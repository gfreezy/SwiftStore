import Foundation
import SQLite3
import SwiftStoreSQLiteSupport
import OSLog
import SwiftStoreProtocols

/// Row operation reported by SQLite hooks
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
    /// Owned copies of SQLite values, in physical table column order.
    public let oldValues: [SQLiteValue]?
    public let newValues: [SQLiteValue]?
    public let source: SQLiteWriteSource
    public let occurredAt: Date
}

public enum SQLiteWriteSource: Sendable {
    case local
    case remote
}

/// Receives changes after the originating statement finishes, outside SQLite's hook.
public protocol SQLiteUpdateHookHandler: AnyObject {
    /// Called inside SQLite's hook. Must not execute SQL or change this connection.
    func tracksTable(_ tableName: String) -> Bool
    func handleUpdate(_ info: SQLiteUpdateInfo)
    func handleUpdates(_ updates: [SQLiteUpdateInfo]) throws
    func withTrackingTransaction<T>(_ block: () throws -> T) throws -> T
}

public extension SQLiteUpdateHookHandler {
    func tracksTable(_ tableName: String) -> Bool { true }
    func handleUpdates(_ updates: [SQLiteUpdateInfo]) throws {
        for update in updates { handleUpdate(update) }
    }
    func withTrackingTransaction<T>(_ block: () throws -> T) throws -> T {
        try block()
    }
}

/// SQLite database connection wrapper
public final class SQLiteConnection {
    private var db: OpaquePointer?
    private let path: String

    // Update hook support
    private weak var updateHookHandler: SQLiteUpdateHookHandler?
    private var updateHookContext: UnsafeMutableRawPointer?
    private var steppingStatement: SQLiteStatementImpl?
    private weak var activeWriteStatement: SQLiteStatementImpl?
    public private(set) var writeSource: SQLiteWriteSource = .local

    /// Default origin for statements starting in this synchronous scope. Each
    /// statement snapshots it on first step, including all triggers/RETURNING rows.
    /// Never share this NOMUTEX connection concurrently.
    public func withWriteSource<T>(_ source: SQLiteWriteSource, _ block: () throws -> T) rethrows -> T {
        let previous = writeSource
        writeSource = source
        defer { writeSource = previous }
        return try block()
    }

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
            _ = swiftstore_preupdate_register(db, nil, nil)
            updateHookContext?.deallocate()
        }
        sqlite3_close(db)
    }

    // MARK: - Update Hook

    public static var supportsPreUpdateHook: Bool { swiftstore_preupdate_available() != 0 }

    /// The connection owns the pre-update slot. Do not attach SQLite Session
    /// objects to the same handle. Capture failures abort the originating write.
    public func setPreUpdateHook(_ handler: SQLiteUpdateHookHandler?) throws {
        if handler != nil && !Self.supportsPreUpdateHook {
            throw StoreError.queryFailed("Change tracking requires SQLite with SQLITE_ENABLE_PREUPDATE_HOOK")
        }
        activeWriteStatement?.reset()
        if updateHookContext != nil {
            _ = swiftstore_preupdate_register(db, nil, nil)
            updateHookContext?.deallocate()
            updateHookContext = nil
        }
        updateHookHandler = handler
        guard handler != nil else { return }
        let context = UnsafeMutablePointer<Unmanaged<SQLiteConnection>>.allocate(capacity: 1)
        context.initialize(to: Unmanaged.passUnretained(self))
        updateHookContext = UnsafeMutableRawPointer(context)
        _ = swiftstore_preupdate_register(db, { contextPtr, db, operation, dbName, tableName, oldRowId, newRowId in
            guard let contextPtr, let tableName else { return }
            let connection = contextPtr.assumingMemoryBound(to: Unmanaged<SQLiteConnection>.self).pointee.takeUnretainedValue()
            guard let statement = connection.steppingStatement,
                  let source = statement.executionSource, source == .local,
                  dbName.map({ String(cString: $0) }) == "main",
                  let op = SQLiteUpdateOperation(rawValue: operation),
                  statement.captureError == nil else { return }
            let table = String(cString: tableName)
            guard statement.trackingHandler?.tracksTable(table) == true else { return }
            do {
                guard swiftstore_preupdate_blobwrite(db) < 0 else {
                    throw StoreError.queryFailed("Incremental BLOB writes are unsupported by change tracking")
                }
                let count = swiftstore_preupdate_count(db)
                func copyRow(old: Bool) throws -> [SQLiteValue] {
                    try (0..<count).map { column in
                        var value: OpaquePointer?
                        let result = old ? swiftstore_preupdate_old(db, column, &value)
                            : swiftstore_preupdate_new(db, column, &value)
                        guard result == SQLITE_OK, let value else {
                            throw StoreError.queryFailed("Cannot capture column \(column) of \(table): SQLite \(result)")
                        }
                        switch sqlite3_value_type(value) {
                        case SQLITE_INTEGER: return .integer(sqlite3_value_int64(value))
                        case SQLITE_FLOAT: return .real(sqlite3_value_double(value))
                        case SQLITE_TEXT:
                            guard let bytes = sqlite3_value_text(value) else {
                                throw StoreError.queryFailed("Cannot copy SQLite text value")
                            }
                            return .text(String(decoding: UnsafeBufferPointer(start: bytes,
                                count: Int(sqlite3_value_bytes(value))), as: UTF8.self))
                        case SQLITE_BLOB:
                            let size = Int(sqlite3_value_bytes(value))
                            if size == 0 { return .blob(Data()) }
                            guard let bytes = sqlite3_value_blob(value) else {
                                throw StoreError.queryFailed("Cannot copy SQLite blob value")
                            }
                            return .blob(Data(bytes: bytes, count: size))
                        default: return .null
                        }
                    }
                }
                statement.pendingUpdates.append(SQLiteUpdateInfo(operation: op, tableName: table,
                    rowId: op == .delete ? oldRowId : newRowId,
                    oldValues: op == .insert ? nil : try copyRow(old: true),
                    newValues: op == .delete ? nil : try copyRow(old: false),
                    source: source, occurredAt: Date()))
            } catch {
                // A C hook cannot throw. Fail and roll back as soon as step returns.
                statement.captureError = error
            }
        }, updateHookContext)
    }

    /// Execute a SQL statement without returning results
    @discardableResult
    public func execute(_ sql: String) throws -> Int {
        // Prepare each statement separately so snapshots are captured between
        // statements, including scripts that later delete or replace the same row.
        try sql.withCString { start in
            var cursor: UnsafePointer<CChar>? = start
            while let current = cursor, current.pointee != 0 {
                var raw: OpaquePointer?
                var tail: UnsafePointer<CChar>?
                let result = sqlite3_prepare_v2(db, current, -1, &raw, &tail)
                guard result == SQLITE_OK else {
                    throw StoreError.queryFailed("Failed to prepare SQL: \(String(cString: sqlite3_errmsg(db)))")
                }
                cursor = tail
                if let raw {
                    let statement = SQLiteStatementImpl(statement: raw, connection: self)
                    while try statement.step() {}
                }
            }
        }
        return Int(sqlite3_changes(db))
    }

    /// Internal transaction control; these statements cannot produce row hooks.
    private func executeControl(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw StoreError.queryFailed("SQL execution failed: \(message)\nSQL: \(sql)")
        }

    }

    func step(_ statement: SQLiteStatementImpl, pointer: OpaquePointer) throws -> Bool {
        let command = statement.command
        if let active = activeWriteStatement, active !== statement,
           sqlite3_stmt_readonly(pointer) == 0 || ["BEGIN", "COMMIT", "END", "ROLLBACK", "SAVEPOINT", "RELEASE"].contains(command) {
            throw StoreError.queryFailed("Finish or reset the active RETURNING statement before another write")
        }
        if statement.trackingSavepoint == nil, let handler = updateHookHandler,
           sqlite3_stmt_readonly(pointer) == 0,
           ["INSERT", "UPDATE", "DELETE", "REPLACE", "WITH"].contains(command) {
            savepointCounter += 1
            let name = "swiftstore_statement_\(savepointCounter)"
            try executeControl("SAVEPOINT \(name)")
            statement.trackingSavepoint = name
            statement.trackingHandler = handler
            activeWriteStatement = statement
        }
        if statement.executionSource == nil { statement.executionSource = writeSource }
        steppingStatement = statement
        let result = sqlite3_step(pointer)
        steppingStatement = nil
        if let error = statement.captureError {
            statement.reset()
            throw error
        }
        if result == SQLITE_ROW { return true }
        guard result == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            statement.reset()
            throw StoreError.queryFailed("Step failed: \(message)")
        }
        do {
            if let name = statement.trackingSavepoint, let handler = statement.trackingHandler {
                if statement.pendingUpdates.isEmpty {
                    try executeControl("RELEASE SAVEPOINT \(name)")
                } else {
                    try handler.withTrackingTransaction {
                        try handler.handleUpdates(statement.pendingUpdates)
                        try executeControl("RELEASE SAVEPOINT \(name)")
                    }
                }
            }
            statement.pendingUpdates.removeAll()
            statement.executionSource = nil
            statement.trackingSavepoint = nil
            statement.trackingHandler = nil
            if activeWriteStatement === statement { activeWriteStatement = nil }
            return false
        } catch {
            statement.reset()
            throw error
        }
    }

    func cancelTracking(_ statement: SQLiteStatementImpl) {
        if let name = statement.trackingSavepoint {
            do {
                try executeControl("ROLLBACK TO SAVEPOINT \(name)")
                try executeControl("RELEASE SAVEPOINT \(name)")
            } catch {
                SwiftStoreLogger.error("Failed to cancel pending write: \(error)")
            }
        }
        statement.trackingSavepoint = nil
        statement.trackingHandler = nil
        statement.executionSource = nil
        statement.captureError = nil
        statement.pendingUpdates.removeAll()
        if activeWriteStatement === statement { activeWriteStatement = nil }
    }

    /// Prepare a SQL statement
    public func prepare(_ sql: String) throws -> SQLiteStatementImpl {
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)

        guard result == SQLITE_OK, let statement = stmt else {
            let message = String(cString: sqlite3_errmsg(db))
            throw StoreError.queryFailed("Failed to prepare statement: \(message)\nSQL: \(sql)")
        }

        return SQLiteStatementImpl(statement: statement, connection: self)
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
        activeWriteStatement?.reset()
        try execute("ROLLBACK")
    }

    /// Execute a block within a transaction
    /// Uses SAVEPOINT for nested transactions
    public func transaction<T>(_ block: () throws -> T) throws -> T {
        if let handler = updateHookHandler {
            return try handler.withTrackingTransaction { try databaseTransaction(block) }
        }
        return try databaseTransaction(block)
    }

    private func databaseTransaction<T>(_ block: () throws -> T) throws -> T {
        if transactionDepth > 0 {
            // Already in a transaction, use SAVEPOINT
            return try savepoint(block)
        }

        try beginTransaction()
        transactionDepth += 1
        do {
            let result = try block()
            try commit()
            transactionDepth -= 1
            return result
        } catch {
            activeWriteStatement?.reset()
            do {
                try rollback()
            } catch {
                SwiftStoreLogger.error("Failed to rollback transaction: \(error.localizedDescription)")
            }
            transactionDepth -= 1
            throw error
        }
    }

    /// Execute a block within a savepoint (for nested transactions)
    private func savepoint<T>(_ block: () throws -> T) throws -> T {
        savepointCounter += 1
        let savepointName = "sp_\(savepointCounter)"
        try execute("SAVEPOINT \(savepointName)")
        transactionDepth += 1
        do {
            let result = try block()
            try execute("RELEASE SAVEPOINT \(savepointName)")
            transactionDepth -= 1
            return result
        } catch {
            activeWriteStatement?.reset()
            do {
                _ = try execute("ROLLBACK TO SAVEPOINT \(savepointName)")
            } catch {
                SwiftStoreLogger.error("Failed to rollback to savepoint: \(error.localizedDescription)")
            }
            do {
                _ = try execute("RELEASE SAVEPOINT \(savepointName)")
            } catch {
                SwiftStoreLogger.error("Failed to release savepoint: \(error.localizedDescription)")
            }
            transactionDepth -= 1
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
    public func insert<E: EntityProtocol>(_ entity: E) throws {
        let values = try encoder.encode(entity)

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
    func get<E: EntityProtocol & Identifiable>(_ type: E.Type, id: E.ID) throws -> E? where E.ID: SQLiteValueComparable {
        // Use explicit column names from entity definition to ensure correct ordering
        // This is critical for migrations where ALTER TABLE ADD COLUMN appends at the end
        let columnList = E.columns.filter { $0.generatedAs == nil }.map { $0.name }.joined(separator: ", ")
        let sql: SQL = "SELECT \(raw: columnList) FROM \(E.self) WHERE id = \(try id.sqliteEncode())"
        let stmt = try prepareAndBind(sql.sql, values: sql.values)

        guard try stmt.step() else {
            return nil
        }

        return try decoder.decode(E.self, from: stmt)
    }

    /// Update an existing entity (only available for entities with id field)
    /// If updated_at is unchanged, the trigger will set it automatically
    func update<E: EntityProtocol & Identifiable>(_ entity: E) throws where E.ID: SQLiteValueComparable {
        var values = try encoder.encode(entity)
        values.removeValue(forKey: "id")

        let columns = values.keys.sorted()
        let setClause = columns.map { "\($0) = ?" }.joined(separator: ", ")

        let sql = "UPDATE \(E.tableName) SET \(setClause) WHERE id = ?"
        let stmt = try prepare(sql)

        for (index, column) in columns.enumerated() {
            if let value = values[column] {
                try value.bind(to: stmt, at: Int32(index + 1))
            }
        }
        let idValue = try entity.id.sqliteEncode()

        // Bind ID
        try stmt.bind(Int32(columns.count + 1), idValue)

        try stmt.step()

        if changes == 0 {
            throw StoreError.entityNotFound(idValue)
        }
    }

    /// Delete an entity (only available for entities with id field)
    func delete<E: EntityProtocol & Identifiable>(_ entity: E) throws where E.ID: SQLiteValueComparable {
        try delete(E.self, id: entity.id)
    }

    /// Delete entity by ID (only available for entities with id field)
    func delete<E: EntityProtocol & Identifiable>(_ type: E.Type, id: E.ID) throws where E.ID: SQLiteValueComparable {
        let sql: SQL = "DELETE FROM \(E.self) WHERE id = \(try id.sqliteEncode())"
        try execute(sql)
    }
}
