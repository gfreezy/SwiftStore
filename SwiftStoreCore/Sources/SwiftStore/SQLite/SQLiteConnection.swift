import Foundation
import SQLite3
import OSLog
import SwiftStoreProtocols

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
public final class SQLiteConnection {
    private var db: OpaquePointer?
    private let path: String

    // Update hook support
    private weak var updateHookHandler: SQLiteUpdateHookHandler?
    private var updateHookContext: UnsafeMutableRawPointer?

    // Transaction nesting support
    private var transactionDepth: Int = 0
    private var savepointCounter: Int = 0
    private let encoder: SQLiteEncoder = SQLiteEncoder()
    private let decoder: SQLiteDecoder = SQLiteDecoder()

    /// Connection options for performance tuning
    public struct Options: Sendable {
        /// Open database in read-only mode
        public var readonly: Bool = false
        /// Enable WAL mode for better concurrent performance
        public var walMode: Bool = true
        /// Synchronous mode: 0=OFF (fastest, risky), 1=NORMAL (balanced), 2=FULL (safest, slowest)
        public var synchronous: Int = 1
        /// Cache size in KB (negative value means KB, positive means pages)
        public var cacheSize: Int = -2000  // 2MB
        /// Store temp tables in memory
        public var tempStoreMemory: Bool = true
        /// Memory-mapped I/O size in bytes (0 to disable)
        public var mmapSize: Int = 256 * 1024 * 1024  // 256MB
        /// Enable foreign keys
        public var foreignKeys: Bool = true

        public init() {}
    }

    public init(path: String, options: Options = Options()) throws {
        self.path = path

        let flags: Int32
        if options.readonly {
            flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        } else {
            flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        }
        let result = sqlite3_open_v2(path, &db, flags, nil)

        guard result == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw StoreError.queryFailed("Failed to open database: \(message)")
        }

        // Apply performance pragmas
        try applyOptions(options)
    }

    private func applyOptions(_ options: Options) throws {
        // WAL mode for better concurrent read/write performance
        if options.walMode {
            try execute("PRAGMA journal_mode = WAL")
        }

        // Synchronous mode (NORMAL is good balance of safety and speed)
        try execute("PRAGMA synchronous = \(options.synchronous)")

        // Cache size (negative = KB)
        try execute("PRAGMA cache_size = \(options.cacheSize)")

        // Store temp tables in memory
        if options.tempStoreMemory {
            try execute("PRAGMA temp_store = MEMORY")
        }

        // Memory-mapped I/O
        if options.mmapSize > 0 {
            try execute("PRAGMA mmap_size = \(options.mmapSize)")
        }

        // Enable foreign keys
        if options.foreignKeys {
            try execute("PRAGMA foreign_keys = ON")
        }
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
    public func prepare(_ sql: String) throws -> SQLiteStatementImpl {
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)

        guard result == SQLITE_OK, let statement = stmt else {
            let message = String(cString: sqlite3_errmsg(db))
            throw StoreError.queryFailed("Failed to prepare statement: \(message)\nSQL: \(sql)")
        }

        return SQLiteStatementImpl(statement: statement)
    }

    /// Get the last insert row id
    public var lastInsertRowId: Int64 {
        return sqlite3_last_insert_rowid(db)
    }

    /// Get the number of changes from the last statement
    public var changes: Int {
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
            column["dflt_value"] = stmt.columnString(4)
            column["pk"] = stmt.columnInt(5) == 1
            columns.append(column)
        }

        return columns
    }

    /// Get prepared statement for a row by rowid
    public func prepareRowById(_ tableName: String, rowId: Int64) throws -> SQLiteStatementImpl {
        let sql = "SELECT * FROM \(tableName) WHERE rowid = ?"
        let stmt = try prepare(sql)
        try stmt.bind(1, rowId)
        return stmt
    }

    // MARK: - Query Execution

    /// Prepare statement and bind values
    public func prepareAndBind(_ sql: String, values: [SQLiteValue]) throws -> SQLiteStatementImpl {
        let stmt = try prepare(sql)
        for (index, value) in values.enumerated() {
            try value.bind(to: stmt, at: Int32(index + 1))
        }
        return stmt
    }

    /// Execute SQL with values and return affected row count
    @discardableResult
    public func execute(_ sql: String, values: [SQLiteValue]) throws -> Int {
        if values.isEmpty {
            return try execute(sql)
        }
        try prepareAndBind(sql, values: values).step()
        return changes
    }

    /// Execute type-safe SQL
    @discardableResult
    public func execute(_ sql: SQL) throws -> Int {
        try execute(sql.sql, values: sql.values)
    }

    /// Execute SQL and return entities (used by Query builder)
    func executeQuery<E: EntityProtocol>(sql: String, values: [SQLiteValue], type: E.Type) throws -> [E] {
        try decoder.decodeAll(E.self, from: prepareAndBind(sql, values: values))
    }

    /// Query using raw SQL string and return rows
    public func query(_ sql: String, values: [SQLiteValue] = []) throws -> [Row] {
        let stmt = try prepareAndBind(sql, values: values)
        var results: [Row] = []
        let columnCount = stmt.columnCount

        while try stmt.step() {
            var data: [String: SQLiteValue] = [:]
            for i in 0..<columnCount {
                if let name = stmt.columnName(i) {
                    data[name] = stmt.sqliteValue(i)
                }
            }
            results.append(Row(data))
        }
        return results
    }

    /// Query using type-safe SQL
    public func query(_ sql: SQL) throws -> [Row] {
        try query(sql.sql, values: sql.values)
    }

    /// Query single row using raw SQL string
    public func queryOne(_ sql: String, values: [SQLiteValue] = []) throws -> Row? {
        let stmt = try prepareAndBind(sql, values: values)
        let columnCount = stmt.columnCount

        guard try stmt.step() else { return nil }

        var data: [String: SQLiteValue] = [:]
        for i in 0..<columnCount {
            if let name = stmt.columnName(i) {
                data[name] = stmt.sqliteValue(i)
            }
        }
        return Row(data)
    }

    /// Query single row using type-safe SQL
    public func queryOne(_ sql: SQL) throws -> Row? {
        try queryOne(sql.sql, values: sql.values)
    }

    /// Query scalar value using raw SQL string
    public func queryScalar<T>(_ sql: String, values: [SQLiteValue] = [], type: T.Type = T.self) throws -> T? {
        guard let row = try queryOne(sql, values: values),
              let firstValue = row.data.values.first else {
            return nil
        }

        switch firstValue {
        case .integer(let v):
            if T.self == Int.self { return Int(v) as? T }
            if T.self == Int32.self { return Int32(v) as? T }
            return v as? T
        case .real(let v):
            if T.self == Float.self { return Float(v) as? T }
            return v as? T
        case .text(let v): return v as? T
        case .blob(let v): return v as? T
        case .null: return nil
        }
    }

    /// Query scalar value using type-safe SQL
    public func queryScalar<T>(_ sql: SQL, type: T.Type = T.self) throws -> T? {
        try queryScalar(sql.sql, values: sql.values, type: type)
    }

    // MARK: - Entity CRUD Operations

    /// Insert a new entity
    /// Timestamps (created_at, updated_at) are set automatically by DEFAULT values
    public func insert<E: EntityProtocol>(_ entity: E) throws {
        var values = try encoder.encode(entity)
        // Remove timestamps - DEFAULT values will set them
        values.removeValue(forKey: "created_at")
        values.removeValue(forKey: "updated_at")

        let columns = values.keys.sorted()
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let columnList = columns.joined(separator: ", ")

        let sql = "INSERT INTO \(E.tableName) (\(columnList)) VALUES (\(placeholders))"
        let stmt = try prepare(sql)

        for (index, column) in columns.enumerated() {
            if let value = values[column] {
                try value.bind(to: stmt, at: Int32(index + 1))
            }
        }

        try stmt.step()
    }

}

// MARK: - Identifiable Entity Extensions

public extension SQLiteConnection {
    /// Get entity by ID (only available for entities with id field)
    func get<E: EntityProtocol & Identifiable>(_ type: E.Type, id: UUIDV4) throws -> E? where E.ID == UUIDV4 {
        let sql: SQL = "SELECT * FROM \(E.self) WHERE id = \(id)"
        let stmt = try prepareAndBind(sql.sql, values: sql.values)

        guard try stmt.step() else {
            return nil
        }

        return try decoder.decode(E.self, from: stmt)
    }

    /// Update an existing entity (only available for entities with id field)
    /// Timestamp (updated_at) is set automatically by trigger
    func update<E: EntityProtocol & Identifiable>(_ entity: E) throws where E.ID == UUIDV4 {
        var values = try encoder.encode(entity)
        // Remove id, created_at, updated_at - trigger will set updated_at
        values.removeValue(forKey: "id")
        values.removeValue(forKey: "created_at")
        values.removeValue(forKey: "updated_at")

        let columns = values.keys.sorted()
        let setClause = columns.map { "\($0) = ?" }.joined(separator: ", ")

        let sql = "UPDATE \(E.tableName) SET \(setClause) WHERE id = ?"
        let stmt = try prepare(sql)

        for (index, column) in columns.enumerated() {
            if let value = values[column] {
                try value.bind(to: stmt, at: Int32(index + 1))
            }
        }

        // Bind ID
        try stmt.bind(Int32(columns.count + 1), entity.id.data)

        try stmt.step()

        if changes == 0 {
            throw StoreError.entityNotFound(entity.id)
        }
    }

    /// Delete an entity (only available for entities with id field)
    func delete<E: EntityProtocol & Identifiable>(_ entity: E) throws where E.ID == UUIDV4 {
        try delete(E.self, id: entity.id)
    }

    /// Delete entity by ID (only available for entities with id field)
    func delete<E: EntityProtocol & Identifiable>(_ type: E.Type, id: UUIDV4) throws where E.ID == UUIDV4 {
        let sql: SQL = "DELETE FROM \(E.self) WHERE id = \(id)"
        try execute(sql)
    }
}
