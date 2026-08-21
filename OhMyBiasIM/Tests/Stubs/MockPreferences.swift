import Foundation

/// 可注入的偏好測試替身 — 讓引擎測試不碰 UserDefaults。
final class MockPreferences: IMEPreferences {
    var autoCommit: Bool
    var fuzzyMatch: Bool
    var showCodeHint: Bool
    var punctuationPairing: Bool
    var englishTrailingSpace: Bool

    init(autoCommit: Bool = false,
         fuzzyMatch: Bool = true,
         showCodeHint: Bool = false,
         punctuationPairing: Bool = false,
         englishTrailingSpace: Bool = false) {
        self.autoCommit = autoCommit
        self.fuzzyMatch = fuzzyMatch
        self.showCodeHint = showCodeHint
        self.punctuationPairing = punctuationPairing
        self.englishTrailingSpace = englishTrailingSpace
    }
}
