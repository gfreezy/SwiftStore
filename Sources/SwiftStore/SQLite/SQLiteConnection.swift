import Foundation
import SQLite3

/// SQLite database connection wrapper
public final class SQLiteConnection: @unchecked Sendable {
    private var db: OpaquePointer?
    private let path: String
    private let lock = NSLock()

    public init(path: String) throws {
        self.path = path

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)

        guard result == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw StoreError.queryFailed("Failed to open database: \(message)")
        }

        // Enable foreign keys
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close(db)
    }

    /// Execute a SQL statement without returning results
    @discardableResult
    public func execute(_ sql: String) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw StoreError.queryFailed("SQL execution failed: \(message)\nSQL: \(sql)")
        }

        return Int(sqlite3_changes(db))
    }

    /// Prepare a SQL statement
    public func prepare(_ sql: String) throws -> SQLiteStatement {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)

        guard result == SQLITE_OK, let statement = stmt else {
            let message = String(cString: sqlite3_errmsg(db))
            throw StoreError.queryFailed("Failed to prepare statement: \(message)\nSQL: \(sql)")
        }

        return SQLiteStatement(statement: statement)
    }

    /// Get the last insert row id
    public var lastInsertRowId: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return sqlite3_last_insert_rowid(db)
    }

    /// Get the number of changes from the last statement
    public var changes: Int {
        lock.lock()
        defer { lock.unlock() }
        return Int(sqlite3_changes(db))
    }

    /// Begin a transaction
    public func beginTransaction() throws {
        try execute("BEGIN TRANSACTION")
    }

    /// Commit a transaction
    public func commit() throws {
        try execute("COMMIT")
    }

    /// Rollback a transaction
    public func rollback() throws {
        try execute("ROLLBACK")
    }

    /// Execute a block within a transaction
    public func transaction<T>(_ block: () throws -> T) throws -> T {
        try beginTransaction()
        do {
            let result = try block()
            try commit()
            return result
        } catch {
            try? rollback()
            throw error
        }
    }

    /// Check if a table exists
    public func tableExists(_ tableName: String) throws -> Bool {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
        let stmt = try prepare(sql)
        try stmt.bind(1, tableName)

        return try stmt.step()
    }

    /// Get table info
    public func tableInfo(_ tableName: String) throws -> [[String: Any]] {
        let sql = "PRAGMA table_info(\(tableName))"
        let stmt = try prepare(sql)

        var columns: [[String: Any]] = []
        while try stmt.step() {
            var column: [String: Any] = [:]
            column["cid"] = stmt.columnInt(0)
            column["name"] = stmt.columnString(1)
            column["type"] = stmt.columnString(2)
            column["notnull"] = stmt.columnInt(3) == 1
            column["pk"] = stmt.columnInt(5) == 1
            columns.append(column)
        }

        return columns
    }
}
