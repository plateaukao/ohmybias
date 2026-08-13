import Foundation

enum AppConstants {
    static var sharedDir: String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return NSHomeDirectory() + "/Library/Application Support/OhMyBias"
        }
        let dir = appSupport.appendingPathComponent("OhMyBias")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    static var cinPath: String { sharedDir + "/liu.cin" }
    static var pinnedPath: String { sharedDir + "/pinned.db" }
    static var tablesDir: String { sharedDir + "/tables" }
}
