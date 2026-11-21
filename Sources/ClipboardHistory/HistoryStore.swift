import Foundation
import SQLite3

struct ClipboardEntry: Identifiable {
    let id: Int64
    let copiedAt: Date
    let textPreview: String?
    let thumbnail: Data?
    let isPinned: Bool
}

struct ClipboardPayload {
    let format: String
    let data: Data
}

struct ClipboardCapture {
    let payload: ClipboardPayload
    let textPreview: String?
    let thumbnail: Data?
}

final class HistoryStore {
    private let database: OpaquePointer
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func defaultURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        .appendingPathComponent("local.clipboard-history", isDirectory: true)
        .appendingPathComponent("History.sqlite")
    }

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw StoreError.database
        }
        database = connection
        try execute("PRAGMA secure_delete = ON")
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func insert(_ captures: [ClipboardCapture], at time: Date) throws {
        try transaction {
            try withStatement("""
                INSERT INTO history(copied_at, format, payload, text_preview, thumbnail)
                VALUES (?, ?, ?, ?, ?)
                """) { statement in
                for capture in captures {
                    try check(sqlite3_bind_double(statement, 1, time.timeIntervalSince1970))
                    try bind(capture.payload.format, to: 2, in: statement)
                    try bind(capture.payload.data, to: 3, in: statement)
                    if let preview = capture.textPreview {
                        try bind(preview, to: 4, in: statement)
                    }
                    if let thumbnail = capture.thumbnail {
                        try bind(thumbnail, to: 5, in: statement)
                    }
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.database }
                    try check(sqlite3_reset(statement))
                    try check(sqlite3_clear_bindings(statement))
                }
            }
        }
    }

    func entries() throws -> [ClipboardEntry] {
        try withStatement("""
            SELECT id, copied_at, text_preview, thumbnail, is_pinned
            FROM history ORDER BY is_pinned DESC, copied_at DESC, id DESC
            """) { statement in
            var entries: [ClipboardEntry] = []
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                entries.append(ClipboardEntry(
                    id: sqlite3_column_int64(statement, 0),
                    copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    textPreview: Self.text(in: statement, at: 2),
                    thumbnail: Self.data(in: statement, at: 3),
                    isPinned: sqlite3_column_int(statement, 4) != 0
                ))
                result = sqlite3_step(statement)
            }
            guard result == SQLITE_DONE else { throw StoreError.database }
            return entries
        }
    }

    func payload(id: Int64, retainingAfter cutoff: Date) throws -> ClipboardPayload? {
        try withStatement("""
            SELECT format, payload FROM history
            WHERE id = ? AND (is_pinned = 1 OR copied_at > ?)
            """) { statement in
            try check(sqlite3_bind_int64(statement, 1, id))
            try check(sqlite3_bind_double(statement, 2, cutoff.timeIntervalSince1970))
            switch sqlite3_step(statement) {
            case SQLITE_DONE:
                return nil
            case SQLITE_ROW:
                guard let format = Self.text(in: statement, at: 0),
                      let data = Self.data(in: statement, at: 1) else { throw StoreError.database }
                return ClipboardPayload(format: format, data: data)
            default:
                throw StoreError.database
            }
        }
    }

    func setPinned(_ pinned: Bool, id: Int64) throws {
        try withStatement("UPDATE history SET is_pinned = ? WHERE id = ?") { statement in
            try check(sqlite3_bind_int(statement, 1, pinned ? 1 : 0))
            try check(sqlite3_bind_int64(statement, 2, id))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.database }
        }
    }

    func delete(id: Int64) throws {
        try withStatement("DELETE FROM history WHERE id = ?") { statement in
            try check(sqlite3_bind_int64(statement, 1, id))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.database }
        }
    }

    func removeExpired(at cutoff: Date) throws -> Bool {
        try withStatement("DELETE FROM history WHERE is_pinned = 0 AND copied_at <= ?") { statement in
            try check(sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.database }
            return sqlite3_changes(database) > 0
        }
    }

    private func migrate() throws {
        try transaction {
            let version = try withStatement("PRAGMA user_version") { statement in
                guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreError.database }
                return sqlite3_column_int(statement, 0)
            }
            guard version == 0 else { return }
            try execute("""
                CREATE TABLE IF NOT EXISTS history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    copied_at REAL NOT NULL,
                    format TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    text_preview TEXT,
                    thumbnail BLOB
                )
                """)
            try execute("""
                ALTER TABLE history ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0
                CHECK (is_pinned IN (0, 1))
                """)
            try execute("CREATE INDEX history_pinned_copied_at ON history(is_pinned, copied_at, id)")
            try execute("DROP INDEX IF EXISTS history_copied_at")
            try execute("PRAGMA user_version = 1")
        }
    }

    private func transaction(_ action: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try action()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(database, sql, nil, nil, nil))
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw StoreError.database }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw StoreError.database }
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        try check(sqlite3_bind_text(statement, index, value, -1, Self.transient))
    }

    private func bind(_ value: Data, to index: Int32, in statement: OpaquePointer) throws {
        try value.withUnsafeBytes { bytes in
            try check(sqlite3_bind_blob64(
                statement, index, bytes.baseAddress, UInt64(bytes.count), Self.transient
            ))
        }
    }

    private static func text(in statement: OpaquePointer, at index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private static func data(in statement: OpaquePointer, at index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private enum StoreError: Error {
        case database
    }
}
