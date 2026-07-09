import Foundation
import SQLite3

public enum SQLiteError: Error, Equatable, CustomStringConvertible {
    case open(String)
    case exec(String)
    case prepare(String)
    case step(String)
    case notFound
    case invalidStatus(String)

    public var description: String {
        switch self {
        case let .open(m), let .exec(m), let .prepare(m), let .step(m):
            return m
        case .notFound:
            return "not found"
        case let .invalidStatus(s):
            return "invalid status: \(s)"
        }
    }
}

/// Thin SQLite3 wrapper (system libsqlite3).
public final class SQLiteDatabase: @unchecked Sendable {
    private var db: OpaquePointer?

    public init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            db = nil
            throw SQLiteError.open(msg)
        }
        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw SQLiteError.exec(message)
        }
    }

    public func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        return stmt!
    }

    public func lastInsertRowId() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    public func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try body(stmt)
    }

    public func scalarInt(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind?(stmt)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_ROW else {
            if rc == SQLITE_DONE { return 0 }
            throw SQLiteError.step(String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_column_int(stmt, 0))
    }

    public func scalarText(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil) throws -> String? {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind?(stmt)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_ROW else { return nil }
        guard let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    public var errorMessage: String {
        String(cString: sqlite3_errmsg(db))
    }
}

// MARK: - Bind helpers

public enum SQLiteBind {
    public static func text(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    public static func int(_ stmt: OpaquePointer, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    public static func double(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    public static func blob(_ stmt: OpaquePointer, _ index: Int32, _ value: Data?) {
        guard let value, !value.isEmpty else {
            sqlite3_bind_null(stmt, index)
            return
        }
        _ = value.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
}

public enum SQLiteColumn {
    public static func text(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    public static func int(_ stmt: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }

    public static func blob(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, index) else { return nil }
        let n = Int(sqlite3_column_bytes(stmt, index))
        guard n > 0 else { return nil }
        return Data(bytes: ptr, count: n)
    }
}
