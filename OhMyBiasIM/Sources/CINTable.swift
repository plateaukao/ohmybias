import Foundation

/// Unified CIN table — mmap binary reader (.bin via CINCompiler) + text .cin fallback.
/// Binary path: liu.bin loaded via mappedIfSafe (zero-copy). Text path: parse .cin into Dict.
///
/// 執行緒安全：所有可變狀態都收在不可變的 `Snapshot` 裡。載入端在區域變數上組好一份完整
/// 快照後，才在鎖內「整份原子替換」；讀取端只在鎖內取出快照參考，之後全部在鎖外操作。
/// 因此背景建表與主執行緒重載不會同時讀寫同一批 Dictionary（舊版會寫壞 heap 而在
/// `activateServer` 裡 SIGTRAP，表現為切輸入法靜默失敗）。
final class CINTable {

    // MARK: - Immutable snapshot

    fileprivate struct Snapshot {
        var binData: Data?
        var entryCount = 0
        var codesOff = 0
        var valsOff = 0
        var stringsOff = 0
        var charsOff = 0
        /// Text fallback + overlay (extras, emoji — small Dict)
        var overlay: [String: [String]] = [:]
        var t2s: [String: String] = [:]
        var s2t: [String: String] = [:]
        var selKeys: [Character] = Array("1234567890")
        var cinName: String = ""
        var maxCodeLength: Int = 4

        var isEmpty: Bool { entryCount == 0 && overlay.isEmpty }
    }

    // MARK: - Shared state (lock-protected)

    private let lock = NSLock()
    private var snap = Snapshot()
    /// 每次替換快照就 +1；快取用它判斷自己是不是還屬於現在這份表。
    private var generation = 0

    private var _reverseTable: [String: [String]]?
    private var _reverseGen = -1
    private var _shortestCodes: [String: Set<String>]?
    private var _shortestGen = -1
    private var _longestCodes: [String: Set<String>]?
    private var _longestGen = -1

    private var current: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return snap
    }

    private func publish(_ s: Snapshot) {
        lock.lock()
        snap = s
        generation &+= 1
        _reverseTable = nil; _reverseGen = -1
        _shortestCodes = nil; _shortestGen = -1
        _longestCodes = nil; _longestGen = -1
        lock.unlock()
    }

    // MARK: - Public scalar accessors

    var t2s: [String: String] { current.t2s }
    var s2t: [String: String] { current.s2t }
    var selKeys: [Character] { current.selKeys }
    var cinName: String { current.cinName }
    var isEmpty: Bool { current.isEmpty }
    var maxCodeLength: Int { current.maxCodeLength }

    /// 不同字的數量。只掃一次碼表把 codepoint 收進 Set，不會像 reverseTable 那樣
    /// 配置整份反查字典（匯入完成的訊息只要這個數字）。
    var distinctCharCount: Int { current.distinctCharCount() }

    // MARK: - Reverse lookup caches
    //
    // 只有注音／同音模式、簡碼（.sp）／長碼（.sl）模式、以及「顯示字碼提示」會用到。
    // 一般打字路徑完全不碰，所以刻意維持 lazy — 不在啟動或切換輸入法時預先建表
    // （那份表是 peak footprint 的主因，多數使用者從來用不到）。

    private var reverseTable: [String: [String]] {
        lock.lock()
        if let cached = _reverseTable, _reverseGen == generation { lock.unlock(); return cached }
        let s = snap, gen = generation
        lock.unlock()
        guard MemoryBudget.canAfford(MemoryBudget.reverseTable) else { return [:] }
        let r = s.buildReverseTable()   // 在鎖外用快照建表，不擋按鍵路徑
        lock.lock()
        if generation == gen { _reverseTable = r; _reverseGen = gen }
        lock.unlock()
        return r
    }

    var shortestCodesTable: [String: Set<String>] {
        lock.lock()
        if let cached = _shortestCodes, _shortestGen == generation { lock.unlock(); return cached }
        let gen = generation
        lock.unlock()
        var r: [String: Set<String>] = [:]
        for (char, codes) in reverseTable {
            let m = codes.min(by: { $0.count < $1.count })?.count ?? 0
            r[char] = Set(codes.filter { $0.count == m })
        }
        lock.lock()
        if generation == gen { _shortestCodes = r; _shortestGen = gen }
        lock.unlock()
        return r
    }

    var longestCodesTable: [String: Set<String>] {
        lock.lock()
        if let cached = _longestCodes, _longestGen == generation { lock.unlock(); return cached }
        let gen = generation
        lock.unlock()
        var r: [String: Set<String>] = [:]
        for (char, codes) in reverseTable {
            let m = codes.max(by: { $0.count < $1.count })?.count ?? 0
            r[char] = Set(codes.filter { $0.count == m })
        }
        lock.lock()
        if generation == gen { _longestCodes = r; _longestGen = gen }
        lock.unlock()
        return r
    }

    func releaseOptionalCaches() {
        lock.lock()
        _reverseTable = nil; _reverseGen = -1
        _shortestCodes = nil; _shortestGen = -1
        _longestCodes = nil; _longestGen = -1
        lock.unlock()
    }

    // MARK: - Load

    func reload() {
        var s = Snapshot()

        // 1. Try mmap binary from shared dir
        let userBin = AppConstants.sharedDir + "/liu.bin"
        if FileManager.default.fileExists(atPath: userBin) {
            Self.loadBin(path: userBin, into: &s)
        }
        // 2. If no .bin, try compiling .cin → .bin on the fly
        if s.entryCount == 0 {
            let cinPath = AppConstants.cinPath
            if FileManager.default.fileExists(atPath: cinPath) {
                CINCompiler.compile(src: cinPath, dst: userBin)
                if FileManager.default.fileExists(atPath: userBin) { Self.loadBin(path: userBin, into: &s) }
                // Compile failed, try text fallback
                if s.entryCount == 0 { Self.parseCINIntoOverlay(path: cinPath, into: &s) }
            }
        }
        // 3. Extras
        Self.loadExtras(into: &s)
        // 4. Char maps
        Self.loadCharMaps(into: &s)
        // 5. maxCodeLength
        Self.computeMaxCodeLength(&s)

        publish(s)
        DebugLog.log("OhMyBiasIM: maxCodeLength = \(s.maxCodeLength)")
    }

    /// Load from a .cin text file (compiles to temp .bin first). For tests and on-the-fly use.
    func load(cinPath: String) {
        let tmp = NSTemporaryDirectory() + "cin_\(UUID().uuidString).bin"
        CINCompiler.compile(src: cinPath, dst: tmp)
        var s = Snapshot()
        do {
            let d = try Data(contentsOf: URL(fileURLWithPath: tmp))
            try? FileManager.default.removeItem(atPath: tmp)
            Self.parseBinData(d, into: &s)
        } catch { DebugLog.log("CINTable load(cinPath:) read tmp: \(error.localizedDescription)") }
        // If compile failed, fall back to text parse
        if s.entryCount == 0 {
            Self.parseCINIntoOverlay(path: cinPath, into: &s)
        }
        Self.computeMaxCodeLength(&s)
        publish(s)
    }

    /// Load from a .cin text file directly (macOS legacy path, also used by reload fallback).
    func load(path: String) {
        var s = Snapshot()
        // Try compile to bin first
        let tmp = NSTemporaryDirectory() + "cin_\(UUID().uuidString).bin"
        CINCompiler.compile(src: path, dst: tmp)
        do {
            let d = try Data(contentsOf: URL(fileURLWithPath: tmp))
            try? FileManager.default.removeItem(atPath: tmp)
            Self.parseBinData(d, into: &s)
        } catch { DebugLog.log("CINTable load(path:) read tmp: \(error.localizedDescription)") }
        if s.entryCount == 0 {
            Self.parseCINIntoOverlay(path: path, into: &s)
        }
        Self.loadCharMaps(into: &s)
        Self.computeMaxCodeLength(&s)
        publish(s)
        DebugLog.log("OhMyBiasIM: Loaded \(s.entryCount) bin entries + \(s.overlay.count) overlay entries from \(path)")
    }

    // MARK: - Binary loading

    private static func loadBin(path: String, into s: inout Snapshot) {
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) }
        catch { DebugLog.log("CINTable loadBin: \(error.localizedDescription)"); return }
        parseBinData(d, into: &s)
    }

    private static func parseBinData(_ d: Data, into s: inout Snapshot) {
        guard d.count >= 128,
              d[0] == 0x43, d[1] == 0x49, d[2] == 0x4E, d[3] == 0x4D else { return }
        parseBinHeader(d, into: &s)
        s.binData = d
    }

    private static func parseBinHeader(_ d: Data, into s: inout Snapshot) {
        s.entryCount = Int(d.u32(4))
        let skLen = Int(d[8])
        if skLen > 0, skLen <= 20, 9 + skLen <= d.count { s.selKeys = (0..<skLen).map { Character(UnicodeScalar(d[9 + $0])) } }
        let cnLen = Int(d.u16(20))
        if cnLen > 0, 22 + cnLen <= d.count, let str = String(data: d[22..<(22+cnLen)], encoding: .utf8) { s.cinName = str }
        s.codesOff = Int(d.u32(96))
        s.valsOff = Int(d.u32(100))
        s.stringsOff = Int(d.u32(104))
        s.charsOff = Int(d.u32(108))
        guard s.codesOff >= 128, s.codesOff < s.valsOff, s.valsOff < s.stringsOff,
              s.stringsOff < s.charsOff, s.charsOff <= d.count else {
            s.entryCount = 0; return
        }
    }

    private static func computeMaxCodeLength(_ s: inout Snapshot) {
        var maxLen = 4
        if let d = s.binData {
            for i in 0..<s.entryCount {
                let len = Int(d.u16(s.codesOff + i * 6 + 4))
                if len > maxLen { maxLen = len }
            }
        }
        for k in s.overlay.keys { if k.count > maxLen { maxLen = k.count } }
        s.maxCodeLength = maxLen
    }

    // MARK: - Text CIN parser (fallback + overlay)

    private static func parseCINIntoOverlay(path: String, into s: inout Snapshot) {
        // 檔案大小限制
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attrs?[.size] as? UInt64 ?? 0
        guard fileSize <= 100_000_000 else {
            DebugLog.log("CIN file too large: \(fileSize) bytes, skipped")
            return
        }
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        var inChardef = false
        var lineCount = 0
        var selKeys = s.selKeys
        var cinName = s.cinName
        var overlay = s.overlay
        let maxLines = 500_000
        content.enumerateLines { line, stop in
            lineCount += 1
            if lineCount > maxLines { stop = true; return }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("%selkey ") {
                let keys = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !keys.isEmpty { selKeys = Array(keys) }; return
            }
            if t.hasPrefix("%cname ") {
                cinName = String(t.dropFirst(7)).trimmingCharacters(in: .whitespaces); return
            }
            if t == "%chardef begin" { inChardef = true; return }
            if t == "%chardef end" { inChardef = false; return }
            guard inChardef else { return }
            let parts: [String]
            if t.contains("\t") { parts = t.split(separator: "\t", maxSplits: 1).map(String.init) }
            else { parts = t.split(separator: " ", maxSplits: 1).map(String.init) }
            guard parts.count == 2 else { return }
            let code = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            overlay[code, default: []].append(value)
        }
        s.selKeys = selKeys
        s.cinName = cinName
        s.overlay = overlay
    }

    // MARK: - Extras + char maps

    private static func loadExtras(into s: inout Snapshot) {
        let dir = AppConstants.tablesDir
        var dirs = [dir]
        if let sync = OhMyBiasPrefs.syncFolder {
            dirs.append((sync as NSString).appendingPathComponent("tables"))
        }
        for d in dirs {
            loadTablesFromDir(d, into: &s)
        }
    }

    private static func loadTablesFromDir(_ dir: String, into s: inout Snapshot) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        var overlay = s.overlay
        for file in files where file.hasSuffix(".txt") {
            let path = dir + "/" + file
            guard let data = FileManager.default.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else { continue }
            content.enumerateLines { line, _ in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") { return }
                let parts = t.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let code = parts[0].lowercased()
                overlay[code, default: []].append(parts[1])
            }
        }
        s.overlay = overlay
    }

    private static func loadCharMaps(into s: inout Snapshot) {
        let sharedDir = AppConstants.sharedDir + "/"
        let bundlePath = (Bundle.main.resourcePath ?? "") + "/"
        for name in ["t2s", "s2t"] {
            let shared = sharedDir + name + ".json"
            let bundled = bundlePath + name + ".json"
            let p = FileManager.default.fileExists(atPath: shared) ? shared : bundled
            guard let data = FileManager.default.contents(atPath: p) else { continue }
            do {
                let map = try JSONDecoder().decode([String: String].self, from: data)
                if name == "t2s" { s.t2s = map } else { s.s2t = map }
            } catch { DebugLog.log("CINTable loadCharMaps \(name): \(error.localizedDescription)") }
        }
    }

    // MARK: - Lookup (public API)

    func lookup(_ code: String) -> [String] { current.lookup(code) }
    func hasPrefix(_ prefix: String) -> Bool { current.hasPrefix(prefix) }
    func validNextKeys(after prefix: String) -> Set<Character> { current.validNextKeys(after: prefix) }
    func wildcardLookup(_ pattern: String) -> [String] { current.wildcardLookup(pattern) }
    func reverseLookup(_ char: String) -> [String] { reverseTable[char] ?? [] }
    func convert(_ char: String, map: [String: String]) -> String { map[char] ?? char }
}

// MARK: - Snapshot readers (pure — 只讀不可變快照，可在任意執行緒呼叫)

fileprivate extension CINTable.Snapshot {

    func distinctCharCount() -> Int {
        var seen = Set<String>()
        if let d = binData {
            for i in 0..<entryCount { for ch in readChars(d, at: i) { seen.insert(ch) } }
        }
        for chars in overlay.values { for c in chars { seen.insert(c) } }
        return seen.count
    }

    func buildReverseTable() -> [String: [String]] {
        var r: [String: [String]] = [:]
        if let d = binData {
            for i in 0..<entryCount {
                let code = readCode(d, at: i)
                for ch in readChars(d, at: i) { r[ch, default: []].append(code) }
            }
        }
        for (code, chars) in overlay { for c in chars { r[c, default: []].append(code) } }
        return r
    }

    // MARK: Binary helpers

    @inline(__always) func readCode(_ d: Data, at i: Int) -> String {
        let off = Int(d.u32(codesOff + i * 6))
        let len = Int(d.u16(codesOff + i * 6 + 4))
        let start = stringsOff + off
        guard start >= 0, start + len <= d.count else { return "" }
        return String(data: d[start..<(start + len)], encoding: .ascii) ?? ""
    }

    @inline(__always) func readChars(_ d: Data, at i: Int) -> [String] {
        let entryOff = valsOff + i * 4
        guard entryOff >= 0, entryOff + 3 <= d.count else { return [] }
        let vOff = Int(d.u16(entryOff))
        let vCnt = Int(d[entryOff + 2])
        guard vCnt > 0 else { return [] }
        // Validate that all values fit within charsOff region
        let firstOff = charsOff + vOff * 4
        let lastOff = charsOff + (vOff + vCnt - 1) * 4 + 4
        guard firstOff >= charsOff, lastOff <= d.count else { return [] }
        var r: [String] = []
        r.reserveCapacity(vCnt)
        for j in 0..<vCnt {
            let off = charsOff + (vOff + j) * 4
            let cp = d.u32(off)
            if let s = Unicode.Scalar(cp) { r.append(String(s)) }
        }
        return r
    }

    func binSearch(_ code: String) -> Int {
        guard let d = binData, entryCount > 0 else { return -1 }
        let target = code.utf8
        var lo = 0, hi = entryCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cmp = compareCode(d, at: mid, with: target)
            if cmp == 0 { return mid }
            else if cmp < 0 { lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return -1
    }

    func lowerBound(_ prefix: String) -> Int {
        guard let d = binData, entryCount > 0 else { return 0 }
        let target = prefix.utf8
        var lo = 0, hi = entryCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if comparePrefixCode(d, at: mid, with: target) < 0 { lo = mid + 1 }
            else { hi = mid }
        }
        return lo
    }

    @inline(__always) func compareCode(_ d: Data, at i: Int, with target: String.UTF8View) -> Int {
        let idxOff = codesOff + i * 6
        guard idxOff >= 0, idxOff + 6 <= d.count else { return -1 }
        let off = stringsOff + Int(d.u32(idxOff))
        let len = Int(d.u16(idxOff + 4))
        guard off >= 0, off + len <= d.count else { return -1 }
        var ti = target.startIndex
        for j in 0..<len {
            if ti == target.endIndex { return 1 }
            let a = d[off + j], b = target[ti]
            if a != b { return Int(a) - Int(b) }
            ti = target.index(after: ti)
        }
        if ti != target.endIndex { return -1 }
        return 0
    }

    @inline(__always) func comparePrefixCode(_ d: Data, at i: Int, with prefix: String.UTF8View) -> Int {
        let idxOff = codesOff + i * 6
        guard idxOff >= 0, idxOff + 6 <= d.count else { return -1 }
        let off = stringsOff + Int(d.u32(idxOff))
        let len = Int(d.u16(idxOff + 4))
        guard off >= 0, off + len <= d.count else { return -1 }
        var ti = prefix.startIndex
        for j in 0..<min(len, prefix.count) {
            if ti == prefix.endIndex { return 0 }
            let a = d[off + j], b = prefix[ti]
            if a != b { return Int(a) - Int(b) }
            ti = prefix.index(after: ti)
        }
        if len < prefix.count { return -1 }
        return 0
    }

    @inline(__always) func codeHasPrefix(_ d: Data, at i: Int, _ prefix: String.UTF8View) -> Bool {
        let idxOff = codesOff + i * 6
        guard idxOff >= 0, idxOff + 6 <= d.count else { return false }
        let off = stringsOff + Int(d.u32(idxOff))
        let len = Int(d.u16(idxOff + 4))
        guard off >= 0, off + len <= d.count else { return false }
        guard len >= prefix.count else { return false }
        var ti = prefix.startIndex
        for j in 0..<prefix.count {
            if d[off + j] != prefix[ti] { return false }
            ti = prefix.index(after: ti)
        }
        return true
    }

    // MARK: Lookup

    func lookup(_ code: String) -> [String] {
        let c = code.lowercased()
        var result: [String] = []
        let idx = binSearch(c)
        if idx >= 0, let d = binData { result = readChars(d, at: idx) }
        if let extra = overlay[c] { result = extra + result }
        return result
    }

    func hasPrefix(_ prefix: String) -> Bool {
        let p = prefix.lowercased()
        // Binary: check via binary search
        if let d = binData {
            let i = lowerBound(p)
            if i < entryCount && codeHasPrefix(d, at: i, p.utf8) { return true }
        }
        // Overlay: scan keys
        return overlay.keys.contains { $0.hasPrefix(p) }
    }

    func validNextKeys(after prefix: String) -> Set<Character> {
        let p = prefix.lowercased()
        var result = Set<Character>()
        let pLen = p.utf8.count
        // Binary: scan from lowerBound
        if let d = binData {
            let start = lowerBound(p)
            for i in start..<entryCount {
                guard codeHasPrefix(d, at: i, p.utf8) else { break }
                let codeLen = Int(d.u16(codesOff + i * 6 + 4))
                if codeLen > pLen {
                    let off = stringsOff + Int(d.u32(codesOff + i * 6))
                    guard off + pLen < d.count else { continue }
                    result.insert(Character(UnicodeScalar(d[off + pLen])))
                }
            }
        }
        // Overlay
        for key in overlay.keys where key.hasPrefix(p) && key.count > p.count {
            result.insert(key[key.index(key.startIndex, offsetBy: p.count)])
        }
        return result
    }

    func wildcardLookup(_ pattern: String) -> [String] {
        let pat = pattern.lowercased()
        guard pat.contains("*") else { return lookup(pat) }
        let regex = "^" + NSRegularExpression.escapedPattern(for: pat)
            .replacingOccurrences(of: "\\*", with: ".+") + "$"
        guard let re = try? NSRegularExpression(pattern: regex) else { return [] }
        let fix = String(pat.prefix(while: { $0 != "*" }))
        var results: [String] = []; var seen = Set<String>()
        // Binary
        if let d = binData {
            let start = fix.isEmpty ? 0 : lowerBound(fix)
            for i in start..<entryCount {
                if !fix.isEmpty && !codeHasPrefix(d, at: i, fix.utf8) { break }
                let code = readCode(d, at: i)
                if re.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil {
                    for c in readChars(d, at: i) where seen.insert(c).inserted { results.append(c) }
                }
            }
        }
        // Overlay
        for (code, chars) in overlay {
            guard fix.isEmpty || code.hasPrefix(fix) else { continue }
            if re.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil {
                for c in chars where seen.insert(c).inserted { results.append(c) }
            }
        }
        return results
    }
}
