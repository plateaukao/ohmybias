import SwiftUI
import AppKit

/// 快速鍵錄製欄：點一下進入錄製，按下組合鍵即完成；Esc 取消、⌫ 清除。
///
/// 用 NSView 而不是 SwiftUI 元件，因為要直接收 keyDown／flagsChanged —
/// 這個 view 不是 NSTextInputClient，按鍵不會經過輸入法，所以在輸入法自己的設定視窗裡也錄得到。
///
/// 按鍵不靠 first responder，而是錄製期間掛一個 local event monitor：設定視窗住在輸入法
/// 進程（LSUIElement／accessory），app 常常不是「作用中」的那個，makeFirstResponder 未必成功，
/// 而 SwiftUI 的 focus 系統也可能把 first responder 收回去。滑鼠同理 — 一般 NSView 在 app
/// 未作用中時第一下點擊只拿來啟用 app、不會送到 mouseDown（NSButton／NSSwitch 則會），
/// 所以 `acceptsFirstMouse` 要回 true，看起來才不會像是「按不下去」。
///
/// 錄製期間把系統快速鍵暫停（`SystemHotKeys.pushAllDisabled`），否則 ⌘Space 按下去是 Spotlight 跳出來。
struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: KeyShortcut?
    /// 錄到合法組合鍵時回呼（nil = 使用者按 ⌫ 清除）
    var onChange: (KeyShortcut?) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onChange = onChange
        v.shortcut = shortcut
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.onChange = onChange
        if v.shortcut != shortcut { v.shortcut = shortcut }
    }

    final class RecorderView: NSView {
        var onChange: ((KeyShortcut?) -> Void)?
        var shortcut: KeyShortcut? { didSet { refresh() } }

        private var isRecording = false { didSet { refresh() } }
        private var heldModifiers: NSEvent.ModifierFlags = [] { didSet { refresh() } }
        private var hotKeyToken: UnsafeMutableRawPointer?
        private var keyMonitor: Any?
        private var mouseMonitor: Any?
        private var resignObserver: NSObjectProtocol?
        private let label = NSTextField(labelWithString: "")

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.borderWidth = 1
            label.alignment = .center
            label.font = .systemFont(ofSize: 13)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            ])
            refresh()
        }
        required init?(coder: NSCoder) { fatalError() }
        deinit { stopRecording() }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        /// 點擊一律算在自己頭上 — 不然 hit-test 會落到裡面的 label（NSTextField），
        /// 它的 acceptsFirstMouse 是 false，app 未作用中時那一下就被吃掉、mouseDown 根本不會來。
        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(convert(point, from: superview)) ? self : nil
        }
        override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 26) }

        override func mouseDown(with event: NSEvent) {
            DebugLog.log("ShortcutRecorder: mouseDown recording=\(isRecording) active=\(NSApp.isActive) key=\(window?.isKeyWindow ?? false)")
            if isRecording { stopRecording(); return }
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)   // 盡量拿；拿不到也沒關係，按鍵走 monitor
            startRecording()
        }

        override func resignFirstResponder() -> Bool {
            // first responder 被收走不代表使用者想停 — 只有點到別處／視窗失焦才停（見 monitor）
            super.resignFirstResponder()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { stopRecording() }
        }

        private func startRecording() {
            guard !isRecording else { return }
            hotKeyToken = SystemHotKeys.pushAllDisabled()
            GlobalHotKey.shared.suspend()   // 不然按下去那一下會被自己的全域 hot key 吞掉
            heldModifiers = []
            isRecording = true
            DebugLog.log("ShortcutRecorder: start active=\(NSApp.isActive) key=\(window?.isKeyWindow ?? false) hotKeyMode=\(SystemHotKeys.currentMode())")
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
                guard let self = self, self.isRecording else { return ev }
                DebugLog.log("ShortcutRecorder: event \(ev.type.rawValue) keyCode=\(ev.keyCode) mods=\(ev.modifierFlags.rawValue)")
                if ev.type == .flagsChanged {
                    self.heldModifiers = ev.modifierFlags.intersection(KeyShortcut.relevantModifiers)
                } else {
                    self.handleKey(ev)
                }
                return nil   // 吞掉，不讓它變成選單快速鍵或打進別的欄位
            }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] ev in
                guard let self = self, self.isRecording else { return ev }
                let inside = ev.window == self.window && self.bounds.contains(self.convert(ev.locationInWindow, from: nil))
                if !inside { self.stopRecording() }
                return ev
            }
            if let w = window {
                resignObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification, object: w, queue: .main
                ) { [weak self] _ in self?.stopRecording() }
            }
        }

        private func stopRecording() {
            guard isRecording else { return }
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
            if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
            if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
            SystemHotKeys.pop(hotKeyToken)
            hotKeyToken = nil
            GlobalHotKey.shared.resume()
            heldModifiers = []
            isRecording = false
        }

        // 保險：萬一 monitor 沒接到（理論上不會），first responder 路徑也能錄
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording, event.type == .keyDown else { return false }
            handleKey(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { super.keyDown(with: event); return }
            handleKey(event)
        }

        override func flagsChanged(with event: NSEvent) {
            guard isRecording else { super.flagsChanged(with: event); return }
            heldModifiers = event.modifierFlags.intersection(KeyShortcut.relevantModifiers)
        }

        private func handleKey(_ event: NSEvent) {
            let s = KeyShortcut(event: event)
            if s.modifiers.isEmpty {
                if s.keyCode == 53 { finish(); return }                          // Esc：取消
                if s.keyCode == 51 || s.keyCode == 117 { onChange?(nil); finish(); return } // ⌫／⌦：清除
            }
            guard s.isAllowed else { NSSound.beep(); return }
            onChange?(s)
            finish()
        }

        private func finish() {
            stopRecording()
            if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }

        private func refresh() {
            if isRecording {
                let mods = KeyShortcut.modifierSymbols(heldModifiers)
                label.stringValue = mods.isEmpty ? "請按組合鍵…（Esc 取消）" : mods
                label.textColor = .secondaryLabelColor
                layer?.borderColor = NSColor.controlAccentColor.cgColor
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            } else if let s = shortcut {
                label.stringValue = s.displayString
                label.textColor = .labelColor
                layer?.borderColor = NSColor.separatorColor.cgColor
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            } else {
                label.stringValue = "點按這裡錄製"
                label.textColor = .secondaryLabelColor
                layer?.borderColor = NSColor.separatorColor.cgColor
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            }
        }
    }
}
