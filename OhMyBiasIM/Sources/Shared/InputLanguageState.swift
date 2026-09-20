import Foundation

/// 由平台層注入所有 client 引擎；只有中／英文選擇共用，組字仍各自保存。
final class InputLanguageState {
    private let lock = NSLock()
    private var english = false

    var isEnglishMode: Bool {
        lock.lock(); defer { lock.unlock() }
        return english
    }

    func toggle() {
        lock.lock(); defer { lock.unlock() }
        english.toggle()
    }
}
