/// No-op stub so test compilation succeeds without the real DebugLog
/// (which depends on OhMyBiasPrefs.debugMode and file I/O).
enum DebugLog {
    static func log(_ msg: String) {}
}
