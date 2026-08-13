import Foundation

/// Thin @Observable wrapper over the same UserDefaults keys used by OhMyBiasPrefs.
/// 與輸入法同進程（設定視窗內嵌於 OhMyBiasIM.app），直接用 standard defaults。
@Observable final class PrefsStore {
    @ObservationIgnored private let ud = UserDefaults.standard

    // MARK: - Font sizes

    var fontSize: Double {
        get { access(keyPath: \.fontSize); return ud.object(forKey: "fontSize") as? Double ?? 16.0 }
        set { withMutation(keyPath: \.fontSize) { ud.set(newValue, forKey: "fontSize") }; postChange() }
    }
    var fixedFontSize: Double {
        get { access(keyPath: \.fixedFontSize); return ud.object(forKey: "fixedFontSize") as? Double ?? 18.0 }
        set { withMutation(keyPath: \.fixedFontSize) { ud.set(newValue, forKey: "fixedFontSize") }; postChange() }
    }
    var toastFontSize: Double {
        get { access(keyPath: \.toastFontSize); return ud.object(forKey: "toastFontSize") as? Double ?? 36.0 }
        set { withMutation(keyPath: \.toastFontSize) { ud.set(newValue, forKey: "toastFontSize") }; postChange() }
    }

    // MARK: - Panel

    var fixedAlpha: Double {
        get { access(keyPath: \.fixedAlpha); return ud.object(forKey: "fixedAlpha") as? Double ?? 0.85 }
        set { withMutation(keyPath: \.fixedAlpha) { ud.set(newValue, forKey: "fixedAlpha") }; postChange() }
    }
    var panelPosition: String {
        get { access(keyPath: \.panelPosition); return ud.string(forKey: "panelPosition") ?? "cursor" }
        set { withMutation(keyPath: \.panelPosition) { ud.set(newValue, forKey: "panelPosition") }; postChange() }
    }
    var cursorHorizontal: Bool {
        get { access(keyPath: \.cursorHorizontal); return ud.object(forKey: "cursorHorizontal") as? Bool ?? false }
        set { withMutation(keyPath: \.cursorHorizontal) { ud.set(newValue, forKey: "cursorHorizontal") }; postChange() }
    }
    var fixedAlignment: String {
        get { access(keyPath: \.fixedAlignment); return ud.string(forKey: "fixedAlignment") ?? "center" }
        set { withMutation(keyPath: \.fixedAlignment) { ud.set(newValue, forKey: "fixedAlignment") }; postChange() }
    }
    var fixedYOffset: Double {
        get { access(keyPath: \.fixedYOffset); return ud.object(forKey: "fixedYOffset") as? Double ?? 8.0 }
        set { withMutation(keyPath: \.fixedYOffset) { ud.set(newValue, forKey: "fixedYOffset") }; postChange() }
    }

    // MARK: - Toggles

    var showActivateToast: Bool {
        get { access(keyPath: \.showActivateToast); return ud.object(forKey: "showActivateToast") as? Bool ?? true }
        set { withMutation(keyPath: \.showActivateToast) { ud.set(newValue, forKey: "showActivateToast") }; postChange() }
    }
    var debugMode: Bool {
        get { access(keyPath: \.debugMode); return ud.object(forKey: "debugMode") as? Bool ?? false }
        set { withMutation(keyPath: \.debugMode) { ud.set(newValue, forKey: "debugMode") }; postChange() }
    }
    var highContrast: Bool {
        get { access(keyPath: \.highContrast); return ud.object(forKey: "highContrast") as? Bool ?? false }
        set { withMutation(keyPath: \.highContrast) { ud.set(newValue, forKey: "highContrast") }; postChange() }
    }
    var autoCommit: Bool {
        get { access(keyPath: \.autoCommit); return ud.object(forKey: "autoCommit") as? Bool ?? false }
        set { withMutation(keyPath: \.autoCommit) { ud.set(newValue, forKey: "autoCommit") }; postChange() }
    }
    var showCodeHint: Bool {
        get { access(keyPath: \.showCodeHint); return ud.object(forKey: "showCodeHint") as? Bool ?? false }
        set { withMutation(keyPath: \.showCodeHint) { ud.set(newValue, forKey: "showCodeHint") }; postChange() }
    }
    var zhuyinReverseLookup: Bool {
        get { access(keyPath: \.zhuyinReverseLookup); return ud.object(forKey: "zhuyinReverseLookup") as? Bool ?? true }
        set { withMutation(keyPath: \.zhuyinReverseLookup) { ud.set(newValue, forKey: "zhuyinReverseLookup") }; postChange() }
    }
    var homophoneMultiReading: Bool {
        get { access(keyPath: \.homophoneMultiReading); return ud.object(forKey: "homophoneMultiReading") as? Bool ?? false }
        set { withMutation(keyPath: \.homophoneMultiReading) { ud.set(newValue, forKey: "homophoneMultiReading") }; postChange() }
    }
    var fuzzyMatch: Bool {
        get { access(keyPath: \.fuzzyMatch); return ud.object(forKey: "fuzzyMatch") as? Bool ?? true }
        set { withMutation(keyPath: \.fuzzyMatch) { ud.set(newValue, forKey: "fuzzyMatch") }; postChange() }
    }
    var punctuationPairing: Bool {
        get { access(keyPath: \.punctuationPairing); return ud.object(forKey: "punctuationPairing") as? Bool ?? false }
        set { withMutation(keyPath: \.punctuationPairing) { ud.set(newValue, forKey: "punctuationPairing") }; postChange() }
    }
    var syncFolder: String? {
        get { access(keyPath: \.syncFolder); return ud.string(forKey: "syncFolder") }
        set { withMutation(keyPath: \.syncFolder) { ud.set(newValue, forKey: "syncFolder") }; postChange() }
    }

    // MARK: - Onboarding

    var hasSeenWelcome: Bool {
        get { access(keyPath: \.hasSeenWelcome); return ud.object(forKey: "hasSeenWelcome") as? Bool ?? false }
        set { withMutation(keyPath: \.hasSeenWelcome) { ud.set(newValue, forKey: "hasSeenWelcome") } }
    }

    func postChange() {
        DistributedNotificationCenter.default().post(name: .init("info.plateaukao.ohmybias.prefsChanged"), object: nil)
    }
}
