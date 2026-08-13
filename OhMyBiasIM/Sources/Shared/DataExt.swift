import Foundation

// MARK: - Data helpers（CINTable 讀 .bin 用）
extension Data {
    func u32(_ off: Int) -> UInt32 {
        guard off >= 0, off + 4 <= count else { return 0 }
        return withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt32.self).littleEndian }
    }
    func u16(_ off: Int) -> UInt16 {
        guard off >= 0, off + 2 <= count else { return 0 }
        return withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt16.self).littleEndian }
    }
}
