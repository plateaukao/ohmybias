import Foundation
import SQLite3

/// `,,PIN` 固定排序儲存：pinned.db 單表 pinned(code, chars)＋記憶體快取。
/// 前身 FreqTracker — 字頻學習（freq/bigram 記錄、排序、decay、JSON 同步）已整組移除，
/// 排序唯一的資料來源就是這裡的固定排序。
final class PinnedStore {
    private var db: OpaquePointer?
    private let path: String
    private let bgQueue = DispatchQueue(label: "info.plateaukao.ohmybias.pinned.bg")

    private var stmtUpsertPinned: OpaquePointer?
    private var stmtDeletePinned: OpaquePointer?
    private var pinnedCache: [String: [String]] = [:]

    private var prefsObserver: Any?

    init() {
        let dir = AppConstants.sharedDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        self.path = dir + "/pinned.db"
        openDB()
        migrateFromFreqDB(dir: dir)
        prefsObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("info.plateaukao.ohmybias.prefsChanged"), object: nil, queue: .main
        ) { [weak self] _ in self?.reloadPinned() }
    }

    deinit {
        sqlite3_finalize(stmtUpsertPinned)
        sqlite3_finalize(stmtDeletePinned)
        sqlite3_close(db)
    }

    // MARK: - DB Setup

    private func openDB() {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            DebugLog.log("PinnedStore sqlite3_open failed: \(path)")
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("CREATE TABLE IF NOT EXISTS pinned(code TEXT PRIMARY KEY, chars TEXT NOT NULL)")
        // 預設固定排序（常見同碼字衝突）
        exec("INSERT OR IGNORE INTO pinned(code,chars) VALUES('hj','手乎')")
        prepare("INSERT OR REPLACE INTO pinned(code,chars) VALUES(?1,?2)", &stmtUpsertPinned)
        prepare("DELETE FROM pinned WHERE code=?1", &stmtDeletePinned)
        loadPinnedCache()
    }

    /// 舊版 freq.db：字頻表已無用，只搬 pinned 資料過來，成功後整個刪除。
    /// 舊檔打不開就先留著（下次啟動再試），不能冒丟固定排序的險。
    private func migrateFromFreqDB(dir: String) {
        let old = dir + "/freq.db"
        guard FileManager.default.fileExists(atPath: old) else { return }
        var odb: OpaquePointer?
        let rc = sqlite3_open_v2(old, &odb, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(odb) }
        guard rc == SQLITE_OK else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(odb, "SELECT code, chars FROM pinned", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let code = String(cString: sqlite3_column_text(stmt, 0))
                let chars = String(cString: sqlite3_column_text(stmt, 1))
                // 舊資料覆蓋新 DB 的預設值（使用者調整過的 hj 順序優先於種子）
                guard let up = stmtUpsertPinned else { continue }
                sqlite3_reset(up)
                sqlite3_bind_text(up, 1, code, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(up, 2, chars, -1, SQLITE_TRANSIENT)
                sqlite3_step(up)
            }
        }
        sqlite3_finalize(stmt)
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: old + suffix)
        }
        loadPinnedCache()
        DebugLog.log("PinnedStore: migrated pinned rows from freq.db and removed it")
    }

    // MARK: - Pinned order

    /// Reload pinned cache from DB (called when prefs change from external app).
    func reloadPinned() {
        bgQueue.sync { loadPinnedCache() }
    }

    /// 先建好新字典再一次換掉 — pinnedCache 每個按鍵都會讀（CandidateRanker），
    /// 不能讓讀取方看到清空到一半的狀態
    private func loadPinnedCache() {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT code, chars FROM pinned", -1, &stmt, nil) == SQLITE_OK else { return }
        var fresh: [String: [String]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let code = String(cString: sqlite3_column_text(stmt, 0))
            let chars = String(cString: sqlite3_column_text(stmt, 1))
            fresh[code] = Array(chars).map(String.init)
        }
        sqlite3_finalize(stmt)
        pinnedCache = fresh
    }

    /// Set pinned order for a code. chars is the ordered list of characters.
    func pin(code: String, chars: [String]) {
        let joined = chars.joined()
        bgQueue.sync {
            guard let stmt = stmtUpsertPinned else { return }
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, code, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, joined, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        pinnedCache[code] = chars
    }

    /// Remove pinned order for a code.
    func unpin(code: String) {
        bgQueue.sync {
            guard let stmt = stmtDeletePinned else { return }
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, code, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        pinnedCache.removeValue(forKey: code)
    }

    /// Get pinned chars for a code (from cache).
    func pinnedChars(forCode code: String) -> [String]? {
        pinnedCache[code]
    }

    // MARK: - SQLite Helpers

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }
    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) { sqlite3_prepare_v2(db, sql, -1, &stmt, nil) }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
