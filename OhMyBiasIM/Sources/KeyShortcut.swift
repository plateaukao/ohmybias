import AppKit

/// 使用者自訂的鍵盤快速鍵：硬體 keyCode ＋ 修飾鍵（⌘⌃⌥⇧），與鍵盤佈局無關。
/// 存在 UserDefaults 時是 `["keyCode": Int, "modifiers": Int]`（modifiers 為 NSEvent.ModifierFlags rawValue）。
struct KeyShortcut: Equatable {
    /// 只認這四個修飾鍵；capsLock／fn／numericPad 一律忽略（F 鍵事件會帶 .function）。
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    /// 從 keyDown 事件取出組合鍵。
    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    init?(dict: [String: Any]?) {
        guard let d = dict,
              let kc = (d["keyCode"] as? NSNumber)?.intValue, kc >= 0, kc <= Int(UInt16.max),
              let m = (d["modifiers"] as? NSNumber)?.uintValue else { return nil }
        self.init(keyCode: UInt16(kc), modifiers: NSEvent.ModifierFlags(rawValue: UInt(m)))
    }

    var dict: [String: Int] {
        ["keyCode": Int(keyCode), "modifiers": Int(modifiers.rawValue)]
    }

    /// keyDown 事件是否就是這組快速鍵（keyCode 相同、四個修飾鍵狀態完全相同）。
    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode &&
            event.modifierFlags.intersection(Self.relevantModifiers) == modifiers
    }

    // MARK: - 合法性

    /// 修飾鍵本身（⌘⇧⇪⌥⌃、右側版本、fn）
    var isModifierKey: Bool { (54...63).contains(keyCode) }

    var isFunctionKey: Bool { Self.functionKeyNames[keyCode] != nil }

    /// 沒有 ⌘／⌃／⌥ 的組合只允許 F 鍵 — 否則會吃掉一般打字（⇧A 在英文模式是大寫 A）。
    var isAllowed: Bool {
        guard !isModifierKey else { return false }
        if isFunctionKey { return true }
        return !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    // MARK: - 顯示

    /// macOS 慣例順序 ⌃⌥⇧⌘ ＋ 鍵名，例如 "⌃Space"、"⌥⇧E"、"F13"。
    var displayString: String {
        Self.modifierSymbols(modifiers) + Self.keyName(keyCode)
    }

    static func modifierSymbols(_ m: NSEvent.ModifierFlags) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option)  { s += "⌥" }
        if m.contains(.shift)   { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s
    }

    static func keyName(_ keyCode: UInt16) -> String {
        if let n = functionKeyNames[keyCode] { return n }
        if let n = specialKeyNames[keyCode] { return n }
        if let n = characterKeyNames[keyCode] { return n }
        return "鍵\(keyCode)"
    }

    private static let functionKeyNames: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
        107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let specialKeyNames: [UInt16: String] = [
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        71: "Clear",
    ]

    private static let characterKeyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 32: "U", 34: "I", 31: "O", 35: "P",
        38: "J", 40: "K", 37: "L", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        43: ",", 47: ".", 41: ";", 44: "/", 39: "'", 33: "[", 30: "]",
        27: "-", 24: "=", 42: "\\", 50: "`",
        // 數字鍵盤
        82: "Pad0", 83: "Pad1", 84: "Pad2", 85: "Pad3", 86: "Pad4", 87: "Pad5",
        88: "Pad6", 89: "Pad7", 91: "Pad8", 92: "Pad9", 65: "Pad.", 67: "Pad*",
        69: "Pad+", 75: "Pad/", 78: "Pad-", 81: "Pad=",
    ]
}
