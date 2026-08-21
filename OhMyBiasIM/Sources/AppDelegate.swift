import Cocoa
import InputMethodKit

class NSManualApplication: NSApplication {
    private let appDelegate = AppDelegate()
    override init() {
        super.init()
        self.delegate = appDelegate
    }
    required init?(coder: NSCoder) { fatalError() }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    static var server = IMKServer()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Input methods still need an activatable policy when showing prefs/open panels.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
        Self.server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
        DebugLog.log("OhMyBiasIM: Server started, connection=\(name ?? "nil")")
        let ver = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        DebugLog.log("OhMyBiasIM: build=\(ver)")
        Self.setUpUserDir()
        Self.observeTableReload()
    }

    /// 偏好設定改了擴充表／匯入 .txt 之後會發這個通知。
    /// 以前沒人收，靠「換 app 時 engine getter 又 reload 一次」矇混過去 —
    /// 那條路已經拿掉了（會跟背景建表打架寫壞 heap），所以在這裡明確接起來。
    private static func observeTableReload() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("info.plateaukao.ohmybias.reloadTables"),
            object: nil, queue: .main
        ) { _ in
            OhMyBiasInputController.reloadTable()
        }
    }

    /// 首次啟動建立使用者資料夾並部署預設檔（pkg 安裝以 root 執行，不碰使用者家目錄，
    /// 所以搬到 app 啟動時做；冪等，已存在就不動）。
    private static func setUpUserDir() {
        let fm = FileManager.default
        let dir = AppConstants.sharedDir  // 取用即建立
        try? fm.createDirectory(atPath: AppConstants.tablesDir, withIntermediateDirectories: true)
        if let res = Bundle.main.resourcePath {
            let capture = dir + "/ohmybias_capture.sh"
            if !fm.fileExists(atPath: capture), fm.fileExists(atPath: res + "/ohmybias_capture.sh") {
                try? fm.copyItem(atPath: res + "/ohmybias_capture.sh", toPath: capture)
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: capture)
            }
            let commands = dir + "/commands.json"
            if !fm.fileExists(atPath: commands), fm.fileExists(atPath: res + "/commands-example.json") {
                try? fm.copyItem(atPath: res + "/commands-example.json", toPath: commands)
            }
        }
    }
}
