import AppKit
import SwiftUI

/// 設定視窗 — 內嵌於輸入法進程（無獨立設定 app）。
/// 注意：關閉視窗只是隱藏，絕不可 terminate（會殺掉輸入法本體）。
final class PrefsWindow {
    static let shared = PrefsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "OhMyBias 設定"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ContentView(store: PrefsStore()))
            w.center()
            window = w
            installEditMenu()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Edit 選單讓文字欄支援 Cmd+C/V/X/A；不加 app 選單（避免 Cmd+Q 結束輸入法）。
    private func installEditMenu() {
        guard NSApp.mainMenu == nil else { return }
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let mainMenu = NSMenu()
        for m in [editMenu, windowMenu] {
            let item = NSMenuItem(title: m.title, action: nil, keyEquivalent: "")
            item.submenu = m
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
    }
}
