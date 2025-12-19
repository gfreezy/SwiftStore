import Foundation
import SQLite3
import OSLog

/// Update operation type from sqlite3_update_hook
public enum SQLiteUpdateOperation: Int32, Sendable {
    case insert = 18  // SQLITE_INSERT
    case update = 23  // SQLITE_UPDATE
    case delete = 9   // SQLITE_DELETE
}

/// Update hook callback information
public struct SQLiteUpdateInfo: Sendable {
    public let operation: SQLiteUpdateOperation
    public let tableName: String
    public let rowId: Int64
}

/// Protocol for handling SQLite update hooks
public protocol SQLiteUpdateHookHandler: AnyObject {
    func handleUpdate(_ info: SQLiteUpdateInfo)
}

/// SQLite database connection wrapper
public final class SQLiteConnection: @unchecked Sendable {
    private var db: OpaquePointer?
    private let path: String
    private let lock = NSLock()

    // Update hook support
    private weak var updateHookHandler: SQLiteUpdateHookHandler?
    private var updateHookContext: UnsafeMutableRawPointer?

    // Transaction nesting support
    private var transactionDepth: Int = 0
    private var savepointCounter: Int = 0

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
        // Remove update hook before closing
        if updateHookContext != nil {
            sqlite3_update_hook(db, nil, nil)
            updateHookContext?.deallocate()
        }
        sqlite3_close(db)
    }

    // MARK: - Update Hook

    /// Set update hook handler for tracking changes
    public func setUpdateHook(_ handler: SQLiteUpdateHookHandler?) {
        lock.lock()
        defer { lock.unlock() }

        // Remove existing hook
        if updateHookContext != nil {
            sqlite3_update_hook(db, nil, nil)
            updateHookContext?.deallocate()
            updateHookContext = nil
        }

        updateHookHandler = handler

        guard handler != nil else { return }

        // Create context that holds a reference to self
        let context = UnsafeMutablePointer<Unmanaged<SQLiteConnection>>.allocate(capacity: 1)
        context.initialize(to: Unmanaged.passUnretained(self))
        updateHookContext = UnsafeMutableRawPointer(context)

        // Set up the C callback
        sqlite3_update_hook(db, { (contextPtr, operation, dbName, tableName, rowId) in
            guard let contextPtr = contextPtr,
                  let tableName = tableName else { return }

            let context = contextPtr.assumingMemoryBound(to: Unmanaged<SQLiteConnection>.self)
            let connection = context.pointee.takeUnretainedValue()

            guard let handler = connection.updateHookHandler,
                  let op = SQLiteUpdateOperation(rawValue: operation) else { return }

            let info = SQLiteUpdateInfo(
                operation: op,
                tableName: String(cString: tableName),
                rowId: rowId
            )

            handler.handleUpdate(info)
        }, updateHookContext)
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
    /// Uses SAVEPOINT for nested transactions
    public func transaction<T>(_ block: () throws -> T) throws -> T {
        if transactionDepth > 0 {
            // Already in a transaction, use SAVEPOINT
            return try savepoint(block)
        }

        transactionDepth += 1
        try beginTransaction()
        do {
            let result = try block()
            try commit()
            transactionDepth -= 1
            return result
        } catch {
            do {
                try rollback()
            } catch {
                os_log("SwiftStore: Failed to rollback transaction: %@", log: .default, type: .error, error.localizedDescription)
            }
            transactionDepth -= 1
            throw error
        }
    }

    /// Execute a block within a savepoint (for nested transactions)
    private func savepoint<T>(_ block: () throws -> T) throws -> T {
        savepointCounter += 1
        let savepointName = "sp_\(savepointCounter)"
        transactionDepth += 1

        try execute("SAVEPOINT \(savepointName)")
        do {
            let result = try block()
            try execute("RELEASE SAVEPOINT \(savepointName)")
            transactionDepth -= 1
            return result
        } catch {
            do {
                _ = try execute("ROLLBACK TO SAVEPOINT \(savepointName)")
            } catch {
                os_log("SwiftStore: Failed to rollback to savepoint: %@", log: .default, type: .error, error.localizedDescription)
            }
            do {
                _ = try execute("RELEASE SAVEPOINT \(savepointName)")
            } catch {
                os_log("SwiftStore: Failed to release savepoint: %@", log: .default, type: .error, error.localizedDescription)
            }
            throw error
        }
    }

    /// Check if currently in a transaction
    public var isInTransaction: Bool {
        transactionDepth > 0
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

    /// Get prepared statement for a row by rowid
    public func prepareRowById(_ tableName: String, rowId: Int64) throws -> SQLiteStatement {
        let sql = "SELECT * FROM \(tableName) WHERE rowid = ?"
        let stmt = try prepare(sql)
        try stmt.bind(1, rowId)
        return stmt
    }
}
