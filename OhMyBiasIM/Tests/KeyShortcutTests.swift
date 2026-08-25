import AppKit

// KeyShortcut：自訂中／英切換快速鍵的解析／顯示／合法性

func testKeyShortcutDictRoundTrip() {
    let s = KeyShortcut(keyCode: 49, modifiers: [.control, .shift])
    let back = KeyShortcut(dict: s.dict)
    checkEqual(back, s, "dict round trip")
    check(KeyShortcut(dict: nil) == nil, "nil dict → nil")
    check(KeyShortcut(dict: ["keyCode": 49]) == nil, "missing modifiers → nil")
    check(KeyShortcut(dict: ["keyCode": -1, "modifiers": 0]) == nil, "negative keyCode → nil")
}

func testKeyShortcutStripsIrrelevantModifiers() {
    let s = KeyShortcut(keyCode: 122, modifiers: [.function, .capsLock, .numericPad, .option])
    checkEqual(s.modifiers, [.option], "only ⌘⌃⌥⇧ kept")
}

func testKeyShortcutDisplay() {
    checkEqual(KeyShortcut(keyCode: 49, modifiers: [.control]).displayString, "⌃Space", "ctrl space")
    checkEqual(KeyShortcut(keyCode: 14, modifiers: [.command, .shift, .option, .control]).displayString,
               "⌃⌥⇧⌘E", "modifier order ⌃⌥⇧⌘")
    checkEqual(KeyShortcut(keyCode: 105, modifiers: []).displayString, "F13", "function key")
    checkEqual(KeyShortcut(keyCode: 18, modifiers: [.option]).displayString, "⌥1", "digit")
    checkEqual(KeyShortcut(keyCode: 200, modifiers: [.command]).displayString, "⌘鍵200", "unknown keyCode fallback")
}

func testKeyShortcutAllowed() {
    check(KeyShortcut(keyCode: 49, modifiers: [.control]).isAllowed, "⌃Space allowed")
    check(KeyShortcut(keyCode: 14, modifiers: [.option, .shift]).isAllowed, "⌥⇧E allowed")
    check(KeyShortcut(keyCode: 105, modifiers: []).isAllowed, "F13 alone allowed")
    check(KeyShortcut(keyCode: 105, modifiers: [.shift]).isAllowed, "⇧F13 allowed")
    check(!KeyShortcut(keyCode: 0, modifiers: []).isAllowed, "plain A not allowed")
    check(!KeyShortcut(keyCode: 0, modifiers: [.shift]).isAllowed, "⇧A not allowed（英文模式是大寫 A）")
    check(!KeyShortcut(keyCode: 49, modifiers: [.shift]).isAllowed, "⇧Space not allowed（全形空白）")
    check(!KeyShortcut(keyCode: 56, modifiers: [.shift]).isAllowed, "modifier key itself not allowed")
    check(!KeyShortcut(keyCode: 55, modifiers: [.command]).isAllowed, "⌘ key itself not allowed")
}

func testKeyShortcutMatchesEvent() {
    let s = KeyShortcut(keyCode: 49, modifiers: [.control])
    func ev(_ kc: UInt16, _ m: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: m, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: kc)!
    }
    check(s.matches(ev(49, [.control])), "exact match")
    check(s.matches(ev(49, [.control, .capsLock])), "capsLock ignored")
    check(!s.matches(ev(49, [.control, .shift])), "extra shift → no match")
    check(!s.matches(ev(49, [])), "no modifiers → no match")
    check(!s.matches(ev(48, [.control])), "different key → no match")
}

func testSystemHotKeysNames() {
    checkEqual(SystemHotKeys.names[64], "顯示 Spotlight 搜尋", "Spotlight id")
    checkEqual(SystemHotKeys.names[60], "選擇上一個輸入方式", "prev input source id")
}
