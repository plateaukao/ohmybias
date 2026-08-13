import Foundation

/// Protocol to decouple Shared/ engine layer from concrete OhMyBiasPrefs.
/// Inject a test-double to unit-test engines without UserDefaults.
protocol IMEPreferences {
    var autoCommit: Bool { get }
    var fuzzyMatch: Bool { get }
    var showCodeHint: Bool { get }
    var punctuationPairing: Bool { get }
}

/// Bridges the static OhMyBiasPrefs into an instance conforming to IMEPreferences.
final class DefaultPreferences: IMEPreferences {
    static let shared = DefaultPreferences()
    var autoCommit: Bool { OhMyBiasPrefs.autoCommit }
    var fuzzyMatch: Bool { OhMyBiasPrefs.fuzzyMatch }
    var showCodeHint: Bool { OhMyBiasPrefs.showCodeHint }
    var punctuationPairing: Bool { OhMyBiasPrefs.punctuationPairing }
}
