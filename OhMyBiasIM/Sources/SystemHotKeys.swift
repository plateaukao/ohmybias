import AppKit
import Carbon

/// 系統「鍵盤快速鍵」（Spotlight、切換輸入方式、指揮中心⋯）的衝突偵測與代為停用。
///
/// 這類快速鍵由系統在 app 之前攔截，輸入法根本收不到那個 keyDown，所以使用者若把
/// 英文切換設成 ⌃Space 之類的組合，必須把系統那邊停掉才有用。
///
/// - 偵測用 Carbon `CopySymbolicHotKeys`：回傳目前**實際生效**的清單（含從未寫進 plist 的預設值）。
/// - 停用要寫 `com.apple.symbolichotkeys` 的 `AppleSymbolicHotKeys.<id>.enabled`，所以還得知道 id：
///   先在 plist 找同鍵位的項目，找不到再對照內建的預設鍵位表。
/// - 寫完跑 `activateSettings -u` 讓系統重讀，再用 Carbon 讀一次確認有沒有真的生效。
enum SystemHotKeys {
    struct Conflict {
        /// `AppleSymbolicHotKeys` 的 key；nil 表示知道有衝突但查不出 id（無法代為停用）
        let id: Int?
        let name: String
        var canDisable: Bool { id != nil }
    }

    private static let domain = "com.apple.symbolichotkeys"
    private static let rootKey = "AppleSymbolicHotKeys"

    // MARK: - 偵測

    /// 這組快速鍵目前是否被某個啟用中的系統快速鍵佔用。
    static func conflict(with s: KeyShortcut) -> Conflict? {
        guard isEnabledInSystem(s) else { return nil }
        if let id = idFromPlist(s) ?? idFromDefaults(s) {
            return Conflict(id: id, name: names[id] ?? "系統快速鍵 #\(id)")
        }
        return Conflict(id: nil, name: "系統快速鍵")
    }

    /// Carbon：目前生效的系統快速鍵裡有沒有同鍵位且 enabled 的。
    private static func isEnabledInSystem(_ s: KeyShortcut) -> Bool {
        var out: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&out) == noErr,
              let list = out?.takeRetainedValue() as? [[String: Any]] else { return false }
        let wantMods = carbonModifiers(s.modifiers)
        for d in list {
            guard let enabled = d[kHISymbolicHotKeyEnabled] as? Bool, enabled,
                  let kc = (d[kHISymbolicHotKeyCode] as? NSNumber)?.intValue,
                  let mods = (d[kHISymbolicHotKeyModifiers] as? NSNumber)?.intValue else { continue }
            if kc == Int(s.keyCode) && (mods & carbonRelevantMask) == wantMods { return true }
        }
        return false
    }

    private static let carbonRelevantMask = cmdKey | shiftKey | optionKey | controlKey

    private static func carbonModifiers(_ m: NSEvent.ModifierFlags) -> Int {
        var v = 0
        if m.contains(.command) { v |= cmdKey }
        if m.contains(.shift)   { v |= shiftKey }
        if m.contains(.option)  { v |= optionKey }
        if m.contains(.control) { v |= controlKey }
        return v
    }

    /// plist 裡 parameters = (charCode, keyCode, NSEvent flags)；找鍵位相同的項目。
    private static func idFromPlist(_ s: KeyShortcut) -> Int? {
        guard let all = UserDefaults(suiteName: domain)?.dictionary(forKey: rootKey) else { return nil }
        let want = s.modifiers.rawValue
        for (key, raw) in all {
            guard let id = Int(key),
                  let entry = raw as? [String: Any],
                  let value = entry["value"] as? [String: Any],
                  let params = value["parameters"] as? [NSNumber], params.count >= 3 else { continue }
            let kc = params[1].intValue
            let mods = UInt(truncatingIfNeeded: params[2].intValue) & KeyShortcut.relevantModifiers.rawValue
            if kc == Int(s.keyCode) && mods == want { return id }
        }
        return nil
    }

    private static func idFromDefaults(_ s: KeyShortcut) -> Int? {
        defaults.first { $0.keyCode == s.keyCode && $0.modifiers == s.modifiers }?.id
    }

    // MARK: - 停用

    enum DisableResult {
        case disabled          // 已停用且 Carbon 確認生效
        case needsRelogin      // 已寫入設定，但系統尚未重讀（登出再登入才會生效）
        case failed(String)
    }

    /// 把該系統快速鍵設為 enabled = false 並套用。
    static func disable(_ c: Conflict, shortcut s: KeyShortcut) -> DisableResult {
        guard let id = c.id else { return .failed("查不出對應的系統快速鍵編號") }
        guard let ud = UserDefaults(suiteName: domain) else { return .failed("無法開啟 \(domain)") }
        var all = ud.dictionary(forKey: rootKey) ?? [:]
        var entry = all["\(id)"] as? [String: Any] ?? [
            "value": [
                "parameters": [65535, Int(s.keyCode), Int(s.modifiers.rawValue)],
                "type": "standard",
            ] as [String: Any],
        ]
        entry["enabled"] = false
        all["\(id)"] = entry
        ud.set(all, forKey: rootKey)
        ud.synchronize()

        // 讓 SystemUIServer／WindowServer 重讀 symbolic hotkeys（同 System Settings 改完做的事）
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        p.arguments = ["-u"]
        do { try p.run(); p.waitUntilExit() } catch {
            DebugLog.log("SystemHotKeys: activateSettings 執行失敗 \(error)")
        }
        return isEnabledInSystem(s) ? .needsRelogin : .disabled
    }

    // MARK: - 錄製期間暫停系統快速鍵

    /// 錄製時把系統快速鍵全部暫停，否則按 ⌘Space 是 Spotlight 跳出來、錄不到。
    /// 只在本 app 是前景 app 時有效；務必成對呼叫 `pop`。
    static func pushAllDisabled() -> UnsafeMutableRawPointer? {
        PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabled))
    }

    static func currentMode() -> UInt32 { GetSymbolicHotKeyMode() }

    static func pop(_ token: UnsafeMutableRawPointer?) {
        guard let t = token else { return }
        PopSymbolicHotKeyMode(t)
    }

    // MARK: - 已知的系統快速鍵

    /// `AppleSymbolicHotKeys` id → 系統設定裡的名稱（繁中）。未列者顯示「系統快速鍵 #id」。
    static let names: [Int: String] = [
        7: "將焦點移到選單列", 8: "將焦點移到 Dock", 9: "將焦點移到使用中的視窗或下一個視窗",
        10: "將焦點移到視窗工具列", 11: "將焦點移到浮動視窗", 12: "開啟或關閉鍵盤操作",
        13: "更改 Tab 鍵移動焦點的方式", 15: "開啟或關閉縮放", 17: "放大", 19: "縮小",
        21: "反轉顏色", 23: "開啟或關閉影像平滑", 25: "增加對比", 26: "減少對比",
        27: "將焦點移到下一個視窗", 28: "將螢幕的圖片儲存為檔案", 29: "將螢幕的圖片拷貝到剪貼板",
        30: "將所選區域的圖片儲存為檔案", 31: "將所選區域的圖片拷貝到剪貼板",
        32: "指揮中心", 33: "應用程式視窗", 36: "顯示桌面", 51: "將焦點移到視窗抽屜",
        52: "開啟或關閉 Dock 隱藏", 57: "將焦點移到狀態選單", 59: "開啟或關閉旁白",
        60: "選擇上一個輸入方式", 61: "選擇「輸入方式」選單中的下一個輸入方式",
        64: "顯示 Spotlight 搜尋", 65: "顯示 Finder 搜尋視窗",
        79: "向左移動一個空間", 81: "向右移動一個空間", 98: "顯示「輔助說明」選單",
        118: "切換至桌面 1", 119: "切換至桌面 2", 120: "切換至桌面 3", 121: "切換至桌面 4",
        122: "切換至桌面 5", 123: "切換至桌面 6", 124: "切換至桌面 7", 125: "切換至桌面 8",
        126: "切換至桌面 9", 127: "切換至桌面 10",
        160: "顯示啟動台", 162: "顯示通知中心", 163: "顯示輔助使用控制項目",
        164: "開啟或關閉勿擾模式", 184: "截圖與錄製選項", 190: "快速備忘錄",
    ]

    private struct DefaultHotKey { let id: Int; let keyCode: UInt16; let modifiers: NSEvent.ModifierFlags }

    /// 系統預設鍵位（使用者沒改過的話 plist 裡不會有該項目，只能靠這張表對回 id）。
    private static let defaults: [DefaultHotKey] = [
        .init(id: 60, keyCode: 49, modifiers: [.control]),                 // ⌃Space
        .init(id: 61, keyCode: 49, modifiers: [.control, .option]),        // ⌃⌥Space
        .init(id: 64, keyCode: 49, modifiers: [.command]),                 // ⌘Space
        .init(id: 65, keyCode: 49, modifiers: [.command, .option]),        // ⌘⌥Space
        .init(id: 32, keyCode: 126, modifiers: [.control]),                // ⌃↑
        .init(id: 33, keyCode: 125, modifiers: [.control]),                // ⌃↓
        .init(id: 79, keyCode: 123, modifiers: [.control]),                // ⌃←
        .init(id: 81, keyCode: 124, modifiers: [.control]),                // ⌃→
        .init(id: 36, keyCode: 103, modifiers: []),                        // F11
        .init(id: 27, keyCode: 50, modifiers: [.command]),                 // ⌘`
        .init(id: 28, keyCode: 20, modifiers: [.command, .shift]),         // ⌘⇧3
        .init(id: 29, keyCode: 20, modifiers: [.command, .control, .shift]),
        .init(id: 30, keyCode: 21, modifiers: [.command, .shift]),         // ⌘⇧4
        .init(id: 31, keyCode: 21, modifiers: [.command, .control, .shift]),
        .init(id: 184, keyCode: 23, modifiers: [.command, .shift]),        // ⌘⇧5
        .init(id: 98, keyCode: 44, modifiers: [.command, .shift]),         // ⌘⇧/
        .init(id: 52, keyCode: 2, modifiers: [.command, .option]),         // ⌘⌥D
        .init(id: 59, keyCode: 96, modifiers: [.command]),                 // ⌘F5
        .init(id: 163, keyCode: 96, modifiers: [.command, .option]),       // ⌘⌥F5
        .init(id: 12, keyCode: 122, modifiers: [.control]),                // ⌃F1
        .init(id: 7, keyCode: 120, modifiers: [.control]),                 // ⌃F2
        .init(id: 8, keyCode: 99, modifiers: [.control]),                  // ⌃F3
        .init(id: 9, keyCode: 118, modifiers: [.control]),                 // ⌃F4
        .init(id: 10, keyCode: 96, modifiers: [.control]),                 // ⌃F5
        .init(id: 11, keyCode: 97, modifiers: [.control]),                 // ⌃F6
        .init(id: 13, keyCode: 98, modifiers: [.control]),                 // ⌃F7
        .init(id: 57, keyCode: 100, modifiers: [.control]),                // ⌃F8
        .init(id: 15, keyCode: 28, modifiers: [.command, .option]),        // ⌘⌥8
        .init(id: 17, keyCode: 24, modifiers: [.command, .option]),        // ⌘⌥=
        .init(id: 19, keyCode: 27, modifiers: [.command, .option]),        // ⌘⌥-
        .init(id: 21, keyCode: 28, modifiers: [.command, .control, .option]),
        .init(id: 23, keyCode: 42, modifiers: [.command, .option]),        // ⌘⌥\
        .init(id: 118, keyCode: 18, modifiers: [.control]), .init(id: 119, keyCode: 19, modifiers: [.control]),
        .init(id: 120, keyCode: 20, modifiers: [.control]), .init(id: 121, keyCode: 21, modifiers: [.control]),
        .init(id: 122, keyCode: 23, modifiers: [.control]), .init(id: 123, keyCode: 22, modifiers: [.control]),
        .init(id: 124, keyCode: 26, modifiers: [.control]), .init(id: 125, keyCode: 28, modifiers: [.control]),
        .init(id: 126, keyCode: 25, modifiers: [.control]), .init(id: 127, keyCode: 29, modifiers: [.control]),
    ]
}
