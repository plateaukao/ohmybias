import Foundation
import Cocoa

/// User preferences stored in UserDefaults
struct OhMyBiasPrefs {
    private static let defaults = UserDefaults.standard

    /// Auto-commit when single candidate and code cannot extend further
    static var autoCommit: Bool {
        get { defaults.object(forKey: "autoCommit") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "autoCommit") }
    }

    /// Candidate panel position: "cursor" (near input) or "fixed" (screen bottom-center)
    static var panelPosition: String {
        get { defaults.string(forKey: "panelPosition") ?? "cursor" }
        set { defaults.set(newValue, forKey: "panelPosition") }
    }

    /// Cursor mode layout: when true, display candidates horizontally instead of vertically
    static var cursorHorizontal: Bool {
        get { defaults.object(forKey: "cursorHorizontal") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "cursorHorizontal") }
    }

    // MARK: - Fixed-mode panel settings

    /// Horizontal alignment: "center", "left", "right", "custom"（拖曳後記住的位置）
    static var fixedAlignment: String {
        get { defaults.string(forKey: "fixedAlignment") ?? "center" }
        set { defaults.set(newValue, forKey: "fixedAlignment") }
    }

    /// Panel opacity 0.3–1.0
    static var fixedAlpha: CGFloat {
        get {
            let v = defaults.object(forKey: "fixedAlpha") as? Double ?? 0.85
            return CGFloat(v)
        }
        set { defaults.set(Double(newValue), forKey: "fixedAlpha") }
    }

    /// Y offset above Dock (points)
    static var fixedYOffset: CGFloat {
        get { CGFloat(defaults.object(forKey: "fixedYOffset") as? Double ?? 8.0) }
        set { defaults.set(Double(newValue), forKey: "fixedYOffset") }
    }

    /// X offset from screen left edge (points); only used when fixedAlignment == "custom"
    static var fixedXOffset: CGFloat {
        get { CGFloat(defaults.object(forKey: "fixedXOffset") as? Double ?? 0.0) }
        set { defaults.set(Double(newValue), forKey: "fixedXOffset") }
    }

    // MARK: - Font size

    /// Candidate panel font size (cursor mode)
    static var fontSize: CGFloat {
        get { CGFloat(defaults.object(forKey: "fontSize") as? Double ?? 16.0) }
        set { defaults.set(Double(newValue), forKey: "fontSize") }
    }

    /// Fixed-mode font size
    static var fixedFontSize: CGFloat {
        get { CGFloat(defaults.object(forKey: "fixedFontSize") as? Double ?? 18.0) }
        set { defaults.set(Double(newValue), forKey: "fixedFontSize") }
    }

    // MARK: - Learning aids

    /// Show Boshiamy code after committing a character
    static var showCodeHint: Bool {
        get { defaults.object(forKey: "showCodeHint") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showCodeHint") }
    }

    /// Zhuyin reverse lookup mode (type zhuyin → see Boshiamy code)
    static var zhuyinReverseLookup: Bool {
        get { defaults.object(forKey: "zhuyinReverseLookup") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "zhuyinReverseLookup") }
    }

    // MARK: - Mode toast

    /// Toast font size
    static var toastFontSize: CGFloat {
        get { CGFloat(defaults.object(forKey: "toastFontSize") as? Double ?? 36.0) }
        set { defaults.set(Double(newValue), forKey: "toastFontSize") }
    }

    /// 切換進 OhMyBias 時顯示模式 toast
    static var showActivateToast: Bool {
        get { defaults.object(forKey: "showActivateToast") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showActivateToast") }
    }

    /// 同音字查詢包含多音字的罕見讀音（如「色」的 ㄕㄜˋ）
    static var homophoneMultiReading: Bool {
        get { defaults.object(forKey: "homophoneMultiReading") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "homophoneMultiReading") }
    }

    /// Fuzzy match: try adjacent-key substitution when no candidates found
    static var fuzzyMatch: Bool {
        get { defaults.object(forKey: "fuzzyMatch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fuzzyMatch") }
    }

    /// 標點配對：打「自動補」（iOS 風格）。關閉則各別輸出（macOS 傳統）。
    static var punctuationPairing: Bool {
        get {
            return defaults.object(forKey: "punctuationPairing") as? Bool ?? false
        }
        set { defaults.set(newValue, forKey: "punctuationPairing") }
    }

    /// 英文直印後自動補空白：無候選字按空白鍵、或按 Enter 送出原碼字母時，尾端加一個空白
    static var englishTrailingSpace: Bool {
        get { defaults.object(forKey: "englishTrailingSpace") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "englishTrailingSpace") }
    }

    // MARK: - 英文模式切換

    /// 單擊 Shift 切換中／英文（預設開）
    static var shiftToggleEnglish: Bool {
        get { defaults.object(forKey: "shiftToggleEnglish") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shiftToggleEnglish") }
    }

    /// 另外指定的中／英切換快速鍵（nil = 未設定）
    static var englishToggleShortcut: KeyShortcut? {
        get { KeyShortcut(dict: defaults.dictionary(forKey: "englishToggleShortcut")) }
        set {
            if let s = newValue { defaults.set(s.dict, forKey: "englishToggleShortcut") }
            else { defaults.removeObject(forKey: "englishToggleShortcut") }
        }
    }

    /// Debug mode: write detailed logs to AppConstants.sharedDir/debug.log
    static var debugMode: Bool {
        get { defaults.object(forKey: "debugMode") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "debugMode") }
    }

    /// 候選字高對比模式：加粗 + 文字陰影
    static var highContrast: Bool {
        get { defaults.object(forKey: "highContrast") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "highContrast") }
    }

    /// 同步資料夾（nil = 不開啟，使用本機 AppConstants.sharedDir）— 同步 tables/*.txt
    static var syncFolder: String? {
        get { defaults.string(forKey: "syncFolder") }
        set { defaults.set(newValue, forKey: "syncFolder") }
    }
}
