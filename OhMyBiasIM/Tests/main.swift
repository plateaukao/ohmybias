import Foundation

// Minimal test harness
var passed = 0
var failed = 0

func check(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    if condition { passed += 1 }
    else { failed += 1; print("FAIL [\(file):\(line)] \(msg)") }
}

func checkEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a == b { passed += 1 }
    else { failed += 1; print("FAIL [\(file):\(line)] \(msg) — got \(a), expected \(b)") }
}

// === Tests ===

func testHarness() {
    check(true, "true is true")
    check(!false, "not-false is true")
    checkEqual(1, 1, "1 == 1")
    checkEqual("abc", "abc", "string equality")
}

func testMockDelegateRecords() {
    let mock = MockEngineDelegate()
    mock.engineDidUpdateComposing("abc")
    mock.engineDidShowToast("A")
    mock.engineDidCommit("好")
    mock.engineDidCommitPair("左", "右")
    mock.engineDidClearComposing()
    mock.engineDidDeleteBack()

    checkEqual(mock.composingUpdates.count, 1, "composing update recorded")
    checkEqual(mock.composingUpdates.first!, "abc", "composing value")
    checkEqual(mock.toasts.count, 1, "toast recorded")
    checkEqual(mock.toasts.first!, "A", "toast value")
    checkEqual(mock.commits.count, 1, "commit recorded")
    checkEqual(mock.commits.first!, "好", "commit value")
    checkEqual(mock.commitPairs.count, 1, "commitPair recorded")
    checkEqual(mock.clearCount, 1, "clear recorded")
    checkEqual(mock.deleteBackCount, 1, "deleteBack recorded")
}

func testMockDelegateReset() {
    let mock = MockEngineDelegate()
    mock.engineDidCommit("x")
    mock.engineDidShowToast("t")
    mock.engineDidClearComposing()
    mock.engineDidDeleteBack()
    mock.reset()
    checkEqual(mock.commits.count, 0, "commits cleared after reset")
    checkEqual(mock.toasts.count, 0, "toasts cleared after reset")
    checkEqual(mock.clearCount, 0, "clearCount reset")
    checkEqual(mock.deleteBackCount, 0, "deleteBackCount reset")
}

func testMockDelegateMultipleCalls() {
    let mock = MockEngineDelegate()
    mock.engineDidUpdateComposing("a")
    mock.engineDidUpdateComposing("ab")
    mock.engineDidUpdateComposing("abc")
    checkEqual(mock.composingUpdates.count, 3, "three composing updates")
    checkEqual(mock.composingUpdates.last!, "abc", "last composing value")

    mock.engineDidUpdateCandidates(["好", "號"])
    mock.engineDidUpdateCandidates(["好"])
    checkEqual(mock.candidateUpdates.count, 2, "two candidate updates")
    checkEqual(mock.candidateUpdates.last!.count, 1, "last candidate count")
}

// === Real InputEngine tests ===

func testRealEngineInit() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    check(engine.composing.isEmpty, "composing starts empty")
    check(engine.currentCandidates.isEmpty, "no candidates initially")
    check(!engine.isEnglishMode, "starts in Chinese mode")
    check(!engine.isZhuyinMode, "not in zhuyin mode")
    check(!engine.isPinyinMode, "not in pinyin mode")
}

func testRealToggleEnglish() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.toggleEnglishMode()
    check(engine.isEnglishMode, "English after toggle")
    checkEqual(mock.toasts.last ?? "", "A", "toast should be A")
    engine.toggleEnglishMode()
    check(!engine.isEnglishMode, "Chinese after second toggle")
}

func testRealComposing() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter("a")
    check(!engine.composing.isEmpty, "composing after letter")
    check(mock.composingUpdates.count > 0, "delegate notified")
}

func testRealBackspace() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter("a")
    engine.handleLetter("b")
    let len = engine.composing.count
    engine.handleBackspace()
    check(engine.composing.count < len, "backspace removes char")
}

func testRealEscape() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter("a")
    engine.handleEscape()
    check(engine.composing.isEmpty, "escape clears")
    check(mock.clearCount > 0, "clear notified")
}

func testRealModeSwitch() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let label = engine.switchToMode("s")
    check(!label.isEmpty, "mode switch returns label")
    let label2 = engine.switchToMode("t")
    check(!label2.isEmpty, "switch back returns label")
}

func testRealCommaCommand() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter(",")
    engine.handleLetter(",")
    check(engine.composing.hasPrefix(","), "comma command active")
    engine.handleEscape()
    check(engine.composing.isEmpty, "escape exits comma command")
}

func testRealEnterCommitsRaw() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleEnter()
    check(mock.commits.count > 0, "enter commits raw text")
}

func testRealZhuyinModeSwitch() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.switchToMode("zh")
    check(engine.isZhuyinMode, "should be in zhuyin mode")
    engine.exitZhuyinMode()
    check(!engine.isZhuyinMode, "should exit zhuyin mode")
}

// === CINTable tests ===

func makeTempCIN() -> String {
    let content = """
    %gen_inp
    %cname Test
    %selkey 1234567890
    %keyname begin
    a a
    b b
    %keyname end
    %chardef begin
    a 好
    a 號
    ab 哈
    abab 帕
    b 不
    %chardef end
    """
    let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).cin"
    try! content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

func loadTestCINTable() -> CINTable {
    let table = CINTable()
    let path = makeTempCIN()
    table.load(cinPath: path)
    try? FileManager.default.removeItem(atPath: path)
    return table
}

func testCINTableLoadAndLookup() {
    let table = loadTestCINTable()
    let a = table.lookup("a")
    check(a.contains("好"), "lookup('a') contains 好")
    check(a.contains("號"), "lookup('a') contains 號")
    let ab = table.lookup("ab")
    check(ab.contains("哈"), "lookup('ab') contains 哈")
    let z = table.lookup("z")
    check(z.isEmpty, "lookup('z') is empty")
}

func testCINTableReverseLookup() {
    let table = loadTestCINTable()
    let r = table.reverseLookup("好")
    check(r.contains("a"), "reverseLookup('好') contains 'a'")
    let empty = table.reverseLookup("不存在")
    check(empty.isEmpty, "reverseLookup('不存在') is empty")
}

func testCINTableWildcard() {
    let table = loadTestCINTable()
    // a* regex becomes ^a.+$ — matches "ab" but not "a" itself
    let results = table.wildcardLookup("a*")
    check(results.contains("哈"), "wildcard 'a*' includes 'ab' entry 哈")
    check(!results.isEmpty, "wildcard 'a*' returns results")
}

func testCINTableHasPrefix() {
    let table = loadTestCINTable()
    check(table.hasPrefix("a"), "hasPrefix('a') is true (ab exists)")
    check(!table.hasPrefix("z"), "hasPrefix('z') is false")
}

func testCINTableValidNextKeys() {
    let table = loadTestCINTable()
    let keys = table.validNextKeys(after: "a")
    check(keys.contains("b"), "validNextKeys(after: 'a') contains 'b'")
}

// === CandidateRanker tests ===

func testRankerModeFiltering() {
    let table = loadTestCINTable()
    let store = PinnedStore()
    let ranker = CandidateRanker()

    // mode .t — no filtering, returns both
    let tResult = ranker.rank(raw: ["好", "號"], code: "a", mode: .t, cinTable: table, pinnedStore: store)
    check(tResult.contains("好"), "mode .t keeps 好")
    check(tResult.contains("號"), "mode .t keeps 號")

    // mode .sp — only chars whose shortest code == "a"
    let spResult = ranker.rank(raw: ["好", "號"], code: "a", mode: .sp, cinTable: table, pinnedStore: store)
    // Both 好 and 號 have shortest code "a" (1 char), so both should remain
    check(spResult.contains("好") || spResult.contains("號"), "mode .sp keeps chars with shortest code 'a'")
}

func testRankerPinnedOrderOnly() {
    let table = loadTestCINTable()
    let store = PinnedStore()
    let ranker = CandidateRanker()
    let code = "_test_pin_\(UUID().uuidString)"

    // 未固定 → 維持字表順序
    let unpinned = ranker.rank(raw: ["好", "號"], code: code, mode: .t, cinTable: table, pinnedStore: store)
    checkEqual(unpinned, ["好", "號"], "無固定排序時維持字表順序")

    // ,,PIN 固定 → 固定字排最前，其餘維持字表順序
    store.pin(code: code, chars: ["號"])
    let pinned = ranker.rank(raw: ["好", "號"], code: code, mode: .t, cinTable: table, pinnedStore: store)
    checkEqual(pinned, ["號", "好"], "固定排序的字排到最前")

    store.unpin(code: code)
    let after = ranker.rank(raw: ["好", "號"], code: code, mode: .t, cinTable: table, pinnedStore: store)
    checkEqual(after, ["好", "號"], "解除固定後回到字表順序")
}

// === Integration tests: full typing flow ===

func testIntegrationTypeAndCommit() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    // Load a test CIN table
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // Type "a" → should have candidates 好/號
    engine.handleLetter("a")
    checkEqual(engine.composing, "a", "composing is 'a'")
    check(engine.currentCandidates.count >= 2, "candidates for 'a'")

    // Space → commit first candidate
    engine.handleSpace()
    check(mock.commits.count > 0, "space commits")
    let committed = mock.commits.first ?? ""
    check(committed == "好" || committed == "號", "committed a valid char")
    check(engine.composing.isEmpty, "composing cleared after commit")
}

func testIntegrationTypeMultiChar() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // Type "ab" → should have candidate 哈
    engine.handleLetter("a")
    engine.handleLetter("b")
    checkEqual(engine.composing, "ab", "composing is 'ab'")
    check(engine.currentCandidates.contains("哈"), "candidates contain 哈")

    // Space → commit
    engine.handleSpace()
    checkEqual(mock.commits.first, "哈", "committed 哈")
}

func testIntegrationBackspaceAndRetype() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleBackspace()
    checkEqual(engine.composing, "a", "backspace removes last char")
    engine.handleLetter("b")
    checkEqual(engine.composing, "ab", "retype after backspace")
    engine.handleSpace()
    checkEqual(mock.commits.first, "哈", "commit after backspace+retype")
}

func testIntegrationEscapeCancels() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    engine.handleLetter("a")
    engine.handleEscape()
    check(engine.composing.isEmpty, "escape clears composing")
    check(engine.currentCandidates.isEmpty, "escape clears candidates")
    checkEqual(mock.commits.count, 0, "escape does not commit")
}

func testIntegrationEnterCommitsRawCode() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleEnter()
    check(mock.commits.contains("ab"), "enter commits raw code 'ab'")
}

func testIntegrationDigitSelect() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    engine.handleLetter("a")
    // "a" has 好 and 號 — select second with digit 2
    if engine.currentCandidates.count >= 2 {
        let second = engine.currentCandidates[1]
        engine.selectCandidate(at: 1)
        check(mock.commits.contains(second), "digit 2 selects second candidate")
    }
}

func testIntegrationCommaCommandMode() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock

    // ,,S → switch to simplified Chinese
    engine.handleLetter(",")
    engine.handleLetter(",")
    engine.handleLetter("s")
    engine.handleSpace()
    check(mock.toasts.count > 0, "comma command shows toast")
}

func testIntegrationQuotePassthrough() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock

    // ' key is no longer intercepted — no engine method to call
    // Just verify engine doesn't have any quote-related side effects
    check(engine.composing.isEmpty, "composing stays empty without quote handler")
    checkEqual(mock.commits.count, 0, "no commits without input")
}

func testIntegrationSequentialCommits() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // Type and commit multiple chars in sequence
    engine.handleLetter("a")
    engine.handleSpace()
    engine.handleLetter("b")
    engine.handleSpace()
    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleSpace()

    check(mock.commits.count == 3, "three sequential commits")
}

func testIntegrationNoCandidateKeepsComposing() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // "z" 無候選字 — 組字串不清空，超過 maxCodeLength(4) 仍可續打
    engine.handleLetter("z")
    check(engine.currentCandidates.isEmpty, "'z' 無候選字")
    for _ in 0..<4 { engine.handleLetter("z") }
    checkEqual(engine.composing, "zzzzz", "無候選字時可打超過 maxCodeLength")
    checkEqual(mock.commits.count, 0, "續打過程不送出任何字")
}

func testIntegrationSpaceCommitsRawWhenNoCandidate() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    for _ in 0..<5 { engine.handleLetter("z") }
    engine.handleSpace()
    checkEqual(mock.commits.first, "zzzzz", "無候選字按空白 → 原樣送出字母")
    check(engine.composing.isEmpty, "送出後組字串清空")
}

func testIntegrationOverflowAutoCommitStillWorks() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // "abab" 有候選（帕），再打一鍵超長 → 自動送出首選、以新鍵重新組字
    for ch in ["a", "b", "a", "b"] { engine.handleLetter(ch) }
    check(engine.currentCandidates.contains("帕"), "'abab' 有候選字")
    engine.handleLetter("a")
    checkEqual(mock.commits.first, "帕", "有候選字時超長仍自動送出首選")
    checkEqual(engine.composing, "a", "超長後以新鍵重新組字")
}

func testEnglishTrailingSpaceOnSpace() {
    let engine = InputEngine(prefs: MockPreferences(englishTrailingSpace: true))
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    for _ in 0..<5 { engine.handleLetter("z") }
    engine.handleSpace()
    checkEqual(mock.commits.first, "zzzzz ", "開啟補空白：無候選字按空白 → 字母＋空白")
}

func testEnglishTrailingSpaceOnEnter() {
    let engine = InputEngine(prefs: MockPreferences(englishTrailingSpace: true))
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // 有候選字時按 Enter 一樣是英文直印 → 補空白
    for ch in ["a", "b"] { engine.handleLetter(ch) }
    engine.handleEnter()
    checkEqual(mock.commits.first, "ab ", "開啟補空白：Enter 送出原碼 → 字母＋空白")
}

func testEnglishTrailingSpaceOffByDefault() {
    let engine = InputEngine(prefs: MockPreferences())
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    for _ in 0..<3 { engine.handleLetter("z") }
    engine.handleSpace()
    checkEqual(mock.commits.first, "zzz", "關閉補空白：維持原樣送出")
}

func testEnglishTrailingSpaceSkipsNonLetters() {
    let engine = InputEngine(prefs: MockPreferences(englishTrailingSpace: true))
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // 含萬用字元／標點的組字串不是英文，不補空白
    engine.handleLetter("z")
    engine.handleWildcard()
    engine.handleSpace()
    checkEqual(mock.commits.first, "z*", "非純英文字母不補空白")
}

// Run all tests
print("Running OhMyBiasIM tests...")
testHarness()
testMockDelegateRecords()
testMockDelegateReset()
testMockDelegateMultipleCalls()
testRealEngineInit()
testRealToggleEnglish()
testRealComposing()
testRealBackspace()
testRealEscape()
testRealModeSwitch()
testRealCommaCommand()
testRealEnterCommitsRaw()
testRealZhuyinModeSwitch()
testCINTableLoadAndLookup()
testCINTableReverseLookup()
testCINTableWildcard()
testCINTableHasPrefix()
testCINTableValidNextKeys()
testRankerModeFiltering()
testRankerPinnedOrderOnly()
testIntegrationTypeAndCommit()
testIntegrationTypeMultiChar()
testIntegrationBackspaceAndRetype()
testIntegrationEscapeCancels()
testIntegrationEnterCommitsRawCode()
testIntegrationDigitSelect()
testIntegrationCommaCommandMode()
testIntegrationQuotePassthrough()
testIntegrationSequentialCommits()
testIntegrationNoCandidateKeepsComposing()
testIntegrationSpaceCommitsRawWhenNoCandidate()
testIntegrationOverflowAutoCommitStillWorks()
testEnglishTrailingSpaceOnSpace()
testEnglishTrailingSpaceOnEnter()
testEnglishTrailingSpaceOffByDefault()
testEnglishTrailingSpaceSkipsNonLetters()
testKeyShortcutDictRoundTrip()
testKeyShortcutStripsIrrelevantModifiers()
testKeyShortcutDisplay()
testKeyShortcutAllowed()
testKeyShortcutMatchesEvent()
testSystemHotKeysNames()

print("\n\(passed) passed, \(failed) failed")
exit(failed > 0 ? 1 : 0)
