import SwiftUI

/// 設定 →「中／英文切換」：單擊 Shift 開關 ＋ 自訂快速鍵（含系統快速鍵衝突偵測／代為停用）。
struct EnglishToggleSection: View {
    @Bindable var store: PrefsStore

    /// 目前設定的快速鍵與系統快速鍵的衝突（nil = 無衝突或未設定）
    @State private var conflict: SystemHotKeys.Conflict?
    /// 剛錄到、正在等使用者決定怎麼處理衝突的快速鍵
    @State private var pending: (shortcut: KeyShortcut, conflict: SystemHotKeys.Conflict)?
    @State private var previous: KeyShortcut?
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("單擊 Shift 切換中／英文；也可以另外指定一組快速鍵（例如 ⌃Space）。")
                .font(Typo.hint).foregroundStyle(.secondary)

            Toggle("單擊 Shift 切換", isOn: $store.shiftToggleEnglish)
                .toggleStyle(.switch)
                .font(Typo.body)

            HStack(spacing: 10) {
                Text("快速鍵").font(Typo.body)
                ShortcutRecorder(shortcut: store.englishToggleShortcut) { recorded($0) }
                    .frame(width: 180, height: 26)
                // 系統快速鍵（⌘Space、⌃Space⋯）會被系統先攔截、錄不到，所以另外給個選單直接挑
                Menu("常用組合") {
                    ForEach(Self.presets, id: \.displayString) { s in
                        Button(s.displayString) { recorded(s) }
                    }
                }
                .fixedSize()
                Button("清除") { store.englishToggleShortcut = nil; conflict = nil}
                    .disabled(store.englishToggleShortcut == nil)
            }

            if let c = conflict, let s = store.englishToggleShortcut {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Typo.warn)
                    Text("\(s.displayString) 目前是系統的「\(c.name)」快速鍵，系統會先攔截、輸入法收不到。")
                        .font(Typo.caption).foregroundStyle(Typo.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    if c.canDisable {
                        Button("停用系統快速鍵") { disable(c, s) }.controlSize(.small)
                    }
                }
            }


            Text("快速鍵以全域方式註冊（無米蝦是目前輸入方式時才生效），在任何 app 都能切、按鍵不會漏進 app。錄製時按下的若是系統快速鍵（例如 ⌘Space），系統會先攔走、錄不到 — 請從「常用組合」挑選，再依提示停用系統那一組。若組合已被 Raycast、Alfred 之類的 app 註冊為全域快速鍵，會被它們搶走，請改用別的組合。沒有 ⌘⌃⌥ 的組合只接受 F 鍵。")
                .font(Typo.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { refreshConflict() }
        .alert("與系統快速鍵衝突", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let p = pending {
                if p.conflict.canDisable {
                    Button("停用系統快速鍵") { disable(p.conflict, p.shortcut) }
                }
                Button("仍然使用") { }
                Button("取消", role: .cancel) { store.englishToggleShortcut = previous; refreshConflict() }
            }
        } message: {
            if let p = pending {
                Text(p.conflict.canDisable
                    ? "\(p.shortcut.displayString) 目前是系統的「\(p.conflict.name)」快速鍵。系統會先攔截這個組合，輸入法收不到。要停用系統的這個快速鍵嗎？"
                    : "\(p.shortcut.displayString) 目前是系統的「\(p.conflict.name)」。系統會先攔截這個組合，輸入法收不到；請到 系統設定 → 鍵盤 → 鍵盤快速鍵 手動停用，或改用別的組合。")
            }
        }
        .alert("停用系統快速鍵", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("好") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    static let presets: [KeyShortcut] = [
        KeyShortcut(keyCode: 49, modifiers: [.control]),            // ⌃Space
        KeyShortcut(keyCode: 49, modifiers: [.option]),             // ⌥Space
        KeyShortcut(keyCode: 49, modifiers: [.command]),            // ⌘Space
        KeyShortcut(keyCode: 49, modifiers: [.control, .shift]),    // ⌃⇧Space
        KeyShortcut(keyCode: 49, modifiers: [.option, .shift]),     // ⌥⇧Space
        KeyShortcut(keyCode: 49, modifiers: [.command, .shift]),    // ⌘⇧Space
        KeyShortcut(keyCode: 49, modifiers: [.control, .option]),   // ⌃⌥Space
        KeyShortcut(keyCode: 49, modifiers: [.command, .option]),   // ⌘⌥Space
        KeyShortcut(keyCode: 105, modifiers: []),                   // F13
        KeyShortcut(keyCode: 107, modifiers: []),                   // F14
        KeyShortcut(keyCode: 113, modifiers: []),                   // F15
    ]

    private func recorded(_ s: KeyShortcut?) {
        previous = store.englishToggleShortcut
        store.englishToggleShortcut = s
        conflict = nil
        guard let s = s, let c = SystemHotKeys.conflict(with: s) else { return }
        conflict = c
        pending = (s, c)
    }

    private func refreshConflict() {
        conflict = store.englishToggleShortcut.flatMap { SystemHotKeys.conflict(with: $0) }
    }

    private func disable(_ c: SystemHotKeys.Conflict, _ s: KeyShortcut) {
        switch SystemHotKeys.disable(c, shortcut: s) {
        case .disabled:
            conflict = nil
        case .needsRelogin:
            resultMessage = "已把系統的「\(c.name)」設為停用，但系統尚未重新讀取設定；登出再登入後生效。"
            refreshConflict()
        case .failed(let why):
            resultMessage = "停用失敗：\(why)。請到 系統設定 → 鍵盤 → 鍵盤快速鍵 手動停用。"
            refreshConflict()
        }
    }
}
