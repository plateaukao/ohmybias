import AppKit
import Carbon

/// 中／英切換快速鍵的全域註冊（Carbon `RegisterEventHotKey`）。
///
/// 為什麼不靠 `handle(_:client:)` 在 client 送來的 keyDown 裡比對就好：
/// - iTerm2 之類的 app 根本不把 ⌘ 組合交給輸入法（自己當 key equivalent 處理掉）；
/// - Ghostty／Prowl 這類終端機呼叫 `interpretKeyEvents`（沒有回傳值），看輸入法沒插入文字就
///   自己把按鍵重新編碼送進 pty — 我們吞掉 ⌘Space 之後它照樣多送一個空白。
/// 全域 hot key 由系統在按鍵送到前景 app **之前**就攔下交給我們，前景 app 完全看不到那一下，
/// 不需要輔助使用權限（Alfred／Raycast 的 ⌘Space 就是這樣做的）。
///
/// 只在無米蝦是目前輸入方式時註冊（`activateServer`／`deactivateServer`），其他輸入法在用時不搶鍵。
/// 系統快速鍵（Spotlight 等）優先於 Carbon hot key，所以衝突偵測／代為停用仍然需要。
/// 別的 app 用 RegisterEventHotKey 註冊同一組時，兩邊都註冊得成功（不會回 eventHotKeyExistsErr），
/// 只有一邊收得到 — 偵測不了，只能在設定頁提醒。
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// 按下時呼叫（主執行緒）
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var current: KeyShortcut?
    private var suspended = false
    private var isDown = false
    private static let signature: OSType = 0x4F684D42   // "OhMB"

    /// 註冊（或換成）這組快速鍵；nil = 取消註冊。
    func register(_ s: KeyShortcut?) {
        current = s
        applyRegistration()
    }

    /// 錄製期間暫停 — 不然錄製欄按下去那一下會被自己的 hot key 吞掉。
    func suspend() { suspended = true; applyRegistration() }
    func resume() { suspended = false; applyRegistration() }

    private func applyRegistration() {
        unregisterNow()
        guard !suspended, let s = current else { return }
        installHandlerOnce()
        let st = RegisterEventHotKey(UInt32(s.keyCode), Self.carbonModifiers(s.modifiers),
                                     EventHotKeyID(signature: Self.signature, id: 1),
                                     GetApplicationEventTarget(), 0, &hotKeyRef)
        if st != noErr {
            hotKeyRef = nil
            DebugLog.log("GlobalHotKey: RegisterEventHotKey \(s.displayString) 失敗 status=\(st)")
        }
    }

    private func unregisterNow() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        isDown = false
    }

    private func installHandlerOnce() {
        guard handlerRef == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == GlobalHotKey.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                // 按住不放系統會重複送 pressed；只在第一下切換
                if !me.isDown {
                    me.isDown = true
                    DispatchQueue.main.async { me.onPressed?() }
                }
            } else {
                me.isDown = false
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, specs.count, &specs,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    static func carbonModifiers(_ m: NSEvent.ModifierFlags) -> UInt32 {
        var v: UInt32 = 0
        if m.contains(.command) { v |= UInt32(cmdKey) }
        if m.contains(.shift)   { v |= UInt32(shiftKey) }
        if m.contains(.option)  { v |= UInt32(optionKey) }
        if m.contains(.control) { v |= UInt32(controlKey) }
        return v
    }
}
