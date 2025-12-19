import Foundation

/// Main store class for database operations
public final class Store: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let migrationManager: MigrationManager
    private let encoder: SQLiteEncoder
    private let decoder: SQLiteDecoder
    private let dbPath: String

    // Sync related
    private var syncEnabled: Bool = false
    private var deviceId: String?
    private var clock: HybridClock = HybridClock()
    private let lock = NSLock()

    // File-based change queue
    private var changeQueue: ChangeQueue?
    private var changeQueueProcessor: ChangeQueueProcessor?

    // Registered entity types
    private var registeredEntities: [String: any EntityProtocol.Type] = [:]
    private var relationEntities: Set<String> = []

    // System table names (prefixed with __swiftstore_ to indicate internal tables)
    internal static let changeLogTable = "__swiftstore_change_log"
    internal static let pendingDeletesTable = "__swiftstore_pending_deletes"

    // Tables to exclude from sync
    private let excludedFromSync: Set<String> = [Store.changeLogTable, Store.pendingDeletesTable]

    /// Initialize store with database path
    public init(path: String) throws {
        self.dbPath = path
        self.connection = try SQLiteConnection(path: path)
        self.migrationManager = MigrationManager(connection: connection)
        self.encoder = SQLiteEncoder()
        self.decoder = SQLiteDecoder()
    }

    // MARK: - Schema Management

    /// Register an entity type
    public func register<E: EntityProtocol>(_ type: E.Type) throws {
        registeredEntities[E.tableName] = type

        // Check if it's a relation entity
        if type is any RelationMarker.Type {
            relationEntities.insert(E.tableName)
        }
    }

    /// Run migrations for all registered entities
    public func migrate() throws {
        // Create change_log table first if sync might be enabled
        try migrationManager.createTable(for: ChangeLog.self)

        // Create pending_deletes table for sync delete tracking
        try createPendingDeletesTable()

        // Create tables for all registered entities
        // Sort to ensure non-relation entities are created first
        let sortedEntities = registeredEntities.sorted { a, b in
            let aIsRelation = relationEntities.contains(a.key)
            let bIsRelation = relationEntities.contains(b.key)
            if aIsRelation != bIsRelation {
                return !aIsRelation
            }
            return a.key < b.key
        }

        for (_, entityType) in sortedEntities {
            try createTableForEntity(entityType)
        }
    }

    /// Create pending_deletes table for tracking delete operations
    private func createPendingDeletesTable() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS \(Store.pendingDeletesTable) (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                table_name TEXT NOT NULL,
                entity_id BLOB NOT NULL
            )
            """
        try connection.execute(sql)
    }

    private func createTableForEntity(_ type: any EntityProtocol.Type) throws {
        let tableName = type.tableName

        if try connection.tableExists(tableName) {
            return
        }

        var columnDefs: [String] = []

        for column in type.columns {
            columnDefs.append(column.toSQL())
        }

        for fk in type.foreignKeys {
            columnDefs.append(fk.toSQL())
        }

        let sql = "CREATE TABLE \(tableName) (\n    \(columnDefs.joined(separator: ",\n    "))\n)"
        try connection.execute(sql)

        for index in type.indexes {
            let indexSQL = index.toSQL(tableName: tableName)
            try connection.execute(indexSQL)
        }
    }

    // MARK: - CRUD Operations

    /// Insert a new entity
    public func insert<E: EntityProtocol>(_ entity: E) throws {
        // Update timestamps
        let now = Date()

        // Encode entity to SQLite values
        let values = try encoder.encode(entity)

        // Update timestamps in values
        var updatedValues = values
        updatedValues["created_at"] = .real(now.timeIntervalSince1970)
        updatedValues["updated_at"] = .real(now.timeIntervalSince1970)

        let columns = updatedValues.keys.sorted()
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let columnList = columns.joined(separator: ", ")

        let sql = "INSERT INTO \(E.tableName) (\(columnList)) VALUES (\(placeholders))"
        let stmt = try connection.prepare(sql)

        for (index, column) in columns.enumerated() {
            if let value = updatedValues[column] {
                try value.bind(to: stmt, at: Int32(index + 1))
            }
        }

        try stmt.step()
        // Change recording is handled by sqlite3_update_hook
    }

    /// Get entity by ID
    public func get<E: EntityProtocol>(_ type: E.Type, id: UUIDV4) throws -> E? {
        let sql = "SELECT * FROM \(E.tableName) WHERE id = ?"
        let stmt = try connection.prepare(sql)
        try stmt.bind(1, id.data)

        guard try stmt.step() else {
            return nil
        }

        return try decoder.decode(E.self, from: stmt)
    }

    /// Create a query builder for fetching entities
    public func fetch<E: EntityProtocol>(_ type: E.Type) -> Query<E> {
        Query(store: self)
    }

    /// Update an existing entity
    public func update<E: EntityProtocol>(_ entity: E) throws {
        let values = try encoder.encode(entity)

        // Update timestamp
        var updatedValues = values
        updatedValues["updated_at"] = .real(Date().timeIntervalSince1970)

        // Remove id and created_at from update
        var mutableValues = updatedValues
        mutableValues.removeValue(forKey: "id")
        mutableValues.removeValue(forKey: "created_at")

        let columns = mutableValues.keys.sorted()
        let setClause = columns.map { "\($0) = ?" }.joined(separator: ", ")

        let sql = "UPDATE \(E.tableName) SET \(setClause) WHERE id = ?"
        let stmt = try connection.prepare(sql)

        for (index, column) in columns.enumerated() {
            if let value = mutableValues[column] {
                try value.bind(to: stmt, at: Int32(index + 1))
            }
        }

        // Bind ID
        try stmt.bind(Int32(columns.count + 1), entity.id.data)

        try stmt.step()

        if connection.changes == 0 {
            throw StoreError.entityNotFound(entity.id)
        }
        // Change recording is handled by sqlite3_update_hook
    }

    /// Delete an entity
    public func delete<E: EntityProtocol>(_ entity: E) throws {
        try delete(E.self, id: entity.id)
    }

    /// Delete entity by ID
    public func delete<E: EntityProtocol>(_ type: E.Type, id: UUIDV4) throws {
        if syncEnabled {
            // Use transaction: INSERT into pending_deletes triggers hook, then DELETE entity
            try connection.transaction {
                // INSERT into pending_deletes - hook will see this and record delete change
                let insertSQL =
                    "INSERT INTO \(Store.pendingDeletesTable) (table_name, entity_id) VALUES (?, ?)"
                let insertStmt = try connection.prepare(insertSQL)
                try insertStmt.bind(1, E.tableName)
                try insertStmt.bind(2, id.data)
                try insertStmt.step()

                // DELETE from entity table
                let deleteSQL = "DELETE FROM \(E.tableName) WHERE id = ?"
                let deleteStmt = try connection.prepare(deleteSQL)
                try deleteStmt.bind(1, id.data)
                try deleteStmt.step()
            }
        } else {
            // No sync, just delete directly
            let sql = "DELETE FROM \(E.tableName) WHERE id = ?"
            let stmt = try connection.prepare(sql)
            try stmt.bind(1, id.data)
            try stmt.step()
        }
    }

    // MARK: - Query Execution (Internal)

    func executeQuery<E: EntityProtocol>(sql: String, values: [SQLiteValue], type: E.Type) throws
        -> [E]
    {
        let stmt = try connection.prepare(sql)

        for (index, value) in values.enumerated() {
            try value.bind(to: stmt, at: Int32(index + 1))
        }

        return try decoder.decodeAll(E.self, from: stmt)
    }

    func executeCount(sql: String, values: [SQLiteValue]) throws -> Int {
        let stmt = try connection.prepare(sql)

        for (index, value) in values.enumerated() {
            try value.bind(to: stmt, at: Int32(index + 1))
        }

        guard try stmt.step() else {
            return 0
        }

        return stmt.columnInt(0)
    }

    /// Execute an UPDATE or DELETE statement and return affected row count
    func executeUpdate(sql: String, values: [SQLiteValue]) throws -> Int {
        let stmt = try connection.prepare(sql)

        for (index, value) in values.enumerated() {
            try value.bind(to: stmt, at: Int32(index + 1))
        }

        try stmt.step()
        return connection.changes
    }

    // MARK: - Transaction Support

    /// Execute a block within a transaction
    public func transaction<T>(_ block: () throws -> T) throws -> T {
        try connection.transaction(block)
    }

    // MARK: - Sync Support

    /// Enable sync with device ID
    public func enableSync(deviceId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        self.syncEnabled = true
        self.deviceId = deviceId

        // Clear pending_deletes table (stale from previous runs)
        try connection.execute("DELETE FROM \(Store.pendingDeletesTable)")

        // Create file-based change queue
        changeQueue = try ChangeQueue(dbPath: dbPath)

        // Process any remaining entries from previous run
        if let queue = changeQueue, queue.hasPendingChanges {
            changeQueueProcessor = ChangeQueueProcessor(
                queue: queue,
                dbPath: dbPath,
                deviceId: deviceId,
                registeredEntities: registeredEntities
            )
            changeQueueProcessor?.flush()
        }

        // Start processor for new changes
        if changeQueueProcessor == nil, let queue = changeQueue {
            changeQueueProcessor = ChangeQueueProcessor(
                queue: queue,
                dbPath: dbPath,
                deviceId: deviceId,
                registeredEntities: registeredEntities
            )
        }
        changeQueueProcessor?.start()

        // Register update hook for automatic change tracking
        connection.setUpdateHook(self)
    }

    /// Disable sync
    public func disableSync() {
        lock.lock()
        defer { lock.unlock() }

        // Remove update hook first
        connection.setUpdateHook(nil)

        // Flush and stop processor
        changeQueueProcessor?.stop()
        changeQueueProcessor = nil
        changeQueue = nil

        self.syncEnabled = false
        self.deviceId = nil
    }

    /// Flush pending changes to change_log
    public func flushChanges() {
        changeQueueProcessor?.flush()
    }

    /// Get current logical clock value
    public func currentClock() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return clock.current
    }

    /// Verify that local time is within acceptable range of NTP time
    /// - Parameters:
    ///   - toleranceMs: Maximum acceptable offset in milliseconds (default 5 seconds)
    ///   - servers: NTP servers to query
    /// - Returns: NTP verification result
    /// - Throws: NTPError if all servers fail
    public func verifyTime(
        toleranceMs: Int64 = 5000,
        servers: [String] = NTPClient.defaultServers
    ) async throws -> NTPVerificationResult {
        try await NTPClient.verifyTime(toleranceMs: toleranceMs, servers: servers)
    }

    /// Check if local time is valid before enabling sync
    /// This is a convenience method that throws if time is out of sync
    /// - Parameters:
    ///   - toleranceMs: Maximum acceptable offset in milliseconds
    /// - Throws: StoreError.timeOutOfSync if local time differs too much from NTP
    public func validateTimeForSync(toleranceMs: Int64 = 5000) async throws {
        let result = try await verifyTime(toleranceMs: toleranceMs)
        if !result.isValid {
            throw StoreError.timeOutOfSync(offsetMs: result.offsetMs, toleranceMs: toleranceMs)
        }
    }

    /// Get changes since a given clock value
    public func changesSince(clock: Int64) throws -> [ChangeLog] {
        try fetch(ChangeLog.self)
            .where(\.logicalClock > clock)
            .order(by: \.logicalClock, ascending: true)
            .all()
    }

    /// Apply remote changes
    public func applyChanges(_ changes: [ChangeLog]) throws {
        guard syncEnabled else {
            throw StoreError.syncNotEnabled
        }

        // Sort: non-relation entities first, then by clock
        let sorted = changes.sorted { a, b in
            let aIsRelation = relationEntities.contains(a.entityType)
            let bIsRelation = relationEntities.contains(b.entityType)
            if aIsRelation != bIsRelation {
                return !aIsRelation
            }
            return a.logicalClock < b.logicalClock
        }

        try transaction {
            for change in sorted {
                // Update local clock
                lock.lock()
                clock.update(received: change.logicalClock)
                lock.unlock()

                switch change.operation {
                case .insert, .update:
                    try applyUpsert(change)
                case .delete:
                    try applyDelete(change)
                }
            }
        }
    }

    private func applyUpsert(_ change: ChangeLog) throws {
        guard let payload = change.payload else {
            throw StoreError.invalidPayload("Missing payload for \(change.operation) operation")
        }

        guard let entityType = registeredEntities[change.entityType] else {
            throw StoreError.invalidPayload("Unknown entity type: \(change.entityType)")
        }

        // Check if entity exists and compare clocks
        let checkSQL =
            "SELECT logical_clock FROM \(Store.changeLogTable) WHERE entity_type = ? AND entity_id = ? ORDER BY logical_clock DESC LIMIT 1"
        let checkStmt = try connection.prepare(checkSQL)
        try checkStmt.bind(1, change.entityType)
        try checkStmt.bind(2, change.entityId.uuidString)

        if try checkStmt.step() {
            let localClock = checkStmt.columnInt64(0)
            if change.logicalClock <= localClock {
                // Local data is newer, skip
                return
            }
        }

        // Parse payload and upsert
        guard let payloadData = payload.data(using: .utf8),
            let dict = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            throw StoreError.invalidPayload("Invalid JSON payload")
        }

        // Build UPSERT SQL
        let tableName = change.entityType
        let columns = entityType.columns.map { $0.name }
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let columnList = columns.joined(separator: ", ")
        let updateClause = columns.filter { $0 != "id" && $0 != "created_at" }
            .map { "\($0) = excluded.\($0)" }
            .joined(separator: ", ")

        let sql = """
            INSERT INTO \(tableName) (\(columnList))
            VALUES (\(placeholders))
            ON CONFLICT(id) DO UPDATE SET \(updateClause)
            """

        let stmt = try connection.prepare(sql)

        // Bind values from payload
        for (index, columnDef) in entityType.columns.enumerated() {
            let propertyName = columnDef.name.snakeCaseToCamelCase()
            if let value = dict[propertyName] {
                let sqliteValue = try convertToSQLiteValue(value, columnType: columnDef.type)
                try sqliteValue.bind(to: stmt, at: Int32(index + 1))
            } else {
                try stmt.bindNull(Int32(index + 1))
            }
        }

        try stmt.step()
    }

    private func applyDelete(_ change: ChangeLog) throws {
        let sql = "DELETE FROM \(change.entityType) WHERE id = ?"
        let stmt = try connection.prepare(sql)
        try stmt.bind(1, change.entityId.uuidString)
        try stmt.step()
    }

    private func convertToSQLiteValue(_ value: Any, columnType: SQLiteType) throws -> SQLiteValue {
        switch value {
        case is NSNull:
            return .null
        case let string as String:
            // If column is blob and string looks like a UUID, convert to blob
            if columnType == .blob, let uuid = UUIDV4(uuidString: string) {
                return .blob(uuid.data)
            }
            return .text(string)
        case let int as Int:
            return .integer(Int64(int))
        case let int64 as Int64:
            return .integer(int64)
        case let double as Double:
            return .real(double)
        case let bool as Bool:
            return .integer(bool ? 1 : 0)
        case let dict as [String: Any]:
            let data = try JSONSerialization.data(withJSONObject: dict)
            return .text(String(data: data, encoding: .utf8) ?? "{}")
        case let array as [Any]:
            let data = try JSONSerialization.data(withJSONObject: array)
            return .text(String(data: data, encoding: .utf8) ?? "[]")
        default:
            throw StoreError.encodingFailed("Unsupported value type: \(type(of: value))")
        }
    }

    /// Prune old change logs
    public func pruneChanges(before clock: Int64) throws {
        let sql = "DELETE FROM \(Store.changeLogTable) WHERE logical_clock < ?"
        let stmt = try connection.prepare(sql)
        try stmt.bind(1, clock)
        try stmt.step()
    }

    // MARK: - Relation Helpers

    /// Check if an entity type is a relation
    public func isRelationEntity(_ tableName: String) -> Bool {
        relationEntities.contains(tableName)
    }

    // MARK: - Raw SQL Execution

    /// Execute raw SQL without parameters
    @discardableResult
    public func execute(_ sql: String) throws -> Int {
        try connection.execute(sql)
    }

    /// Execute raw SQL with parameters
    @discardableResult
    public func execute(_ sql: String, values: [SQLiteValue]) throws -> Int {
        try executeUpdate(sql: sql, values: values)
    }

    /// Query raw SQL and return rows
    public func query(_ sql: String, values: [SQLiteValue] = []) throws -> [Row] {
        let stmt = try connection.prepare(sql)

        for (index, value) in values.enumerated() {
            try value.bind(to: stmt, at: Int32(index + 1))
        }

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

    /// Query raw SQL and return first row
    public func queryOne(_ sql: String, values: [SQLiteValue] = []) throws -> Row? {
        try query(sql, values: values).first
    }

    /// Query raw SQL and return a single value
    public func queryScalar<T>(_ sql: String, values: [SQLiteValue] = []) throws -> T? {
        guard let row = try queryOne(sql, values: values),
              let firstValue = row.data.values.first else {
            return nil
        }

        switch firstValue {
        case .integer(let v):
            return v as? T
        case .real(let v):
            return v as? T
        case .text(let v):
            return v as? T
        case .blob(let v):
            return v as? T
        case .null:
            return nil
        }
    }

    // MARK: - Migration Dry Run

    /// Generate migration plan for a single entity type without executing (dry run)
    /// - Parameter type: The entity type to generate migration for
    /// - Returns: MigrationPlan containing SQL statements that would be executed
    public func planMigration<E: EntityProtocol>(for type: E.Type) throws -> MigrationPlan {
        try migrationManager.planMigration(for: type)
    }

    /// Generate migration plan for all registered entities without executing (dry run)
    /// - Returns: MigrationPlan containing SQL statements that would be executed
    public func planMigrations() throws -> MigrationPlan {
        let sortedEntities = registeredEntities.sorted { a, b in
            let aIsRelation = relationEntities.contains(a.key)
            let bIsRelation = relationEntities.contains(b.key)
            if aIsRelation != bIsRelation {
                return !aIsRelation
            }
            return a.key < b.key
        }

        let types = sortedEntities.map { $0.value }
        return try migrationManager.planMigrations(for: types)
    }

    /// Generate CREATE TABLE SQL for an entity type
    public func generateCreateTableSQL<E: EntityProtocol>(for type: E.Type) -> String {
        migrationManager.generateCreateTableSQL(for: type)
    }
}

// MARK: - SQLiteUpdateHookHandler

extension Store: SQLiteUpdateHookHandler {
    public func handleUpdate(_ info: SQLiteUpdateInfo) {
        // Skip change_log table
        guard info.tableName != Store.changeLogTable else { return }

        // Skip DELETE operations (we handle deletes via INSERT on pending_deletes)
        guard info.operation != .delete else { return }

        // Skip if sync is not enabled
        lock.lock()
        guard syncEnabled else {
            lock.unlock()
            return
        }
        let clockValue = clock.tick()
        lock.unlock()

        // Handle INSERT on pending_deletes as a DELETE operation
        if info.tableName == Store.pendingDeletesTable {
            handlePendingDeleteInsert(rowId: info.rowId, clockValue: clockValue)
            return
        }

        // Skip if not a registered entity
        guard registeredEntities[info.tableName] != nil else { return }

        // Write to file queue
        let op: PendingChange.Operation = info.operation == .insert ? .insert : .update
        let change = PendingChange(
            op: op,
            table: info.tableName,
            rowId: info.rowId,
            clock: clockValue
        )
        changeQueue?.append(change)
    }

    /// Handle INSERT on pending_deletes table - this signals a delete operation
    private func handlePendingDeleteInsert(rowId: Int64, clockValue: Int64) {
        do {
            // Fetch the pending delete row to get table_name and entity_id
            let stmt = try connection.prepareRowById(Store.pendingDeletesTable, rowId: rowId)
            guard try stmt.step() else { return }

            // Columns: id (0), table_name (1), entity_id (2)
            guard let tableName = stmt.columnString(1),
                let entityIdData = stmt.columnData(2),
                let entityId = UUIDV4(data: entityIdData)
            else { return }

            // Write delete change to file queue
            let change = PendingChange(
                op: .delete,
                table: tableName,
                entityId: entityId.uuidString,
                clock: clockValue
            )
            changeQueue?.append(change)
        } catch {
            print("SwiftStore: Failed to handle pending delete: \(error)")
        }
    }
}
