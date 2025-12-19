import Foundation

/// Main store class for database operations
public final class Store: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let migrationManager: MigrationManager
    private let encoder: SQLiteEncoder
    private let decoder: SQLiteDecoder

    // Sync related
    private var syncEnabled: Bool = false
    private var deviceId: String?
    private var clock: HybridClock = HybridClock()
    private let lock = NSLock()

    // Registered entity types
    private var registeredEntities: [String: any EntityProtocol.Type] = [:]
    private var relationEntities: Set<String> = []

    /// Initialize store with database path
    public init(path: String) throws {
        self.connection = try SQLiteConnection(path: path)
        self.migrationManager = MigrationManager(connection: connection)
        self.encoder = SQLiteEncoder()
        self.decoder = SQLiteDecoder()
    }

    /// Initialize store with in-memory database
    public convenience init() throws {
        try self.init(path: ":memory:")
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

        // Record change for sync
        if syncEnabled {
            try recordChange(entity: entity, operation: .insert)
        }
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

        // Record change for sync
        if syncEnabled {
            try recordChange(entity: entity, operation: .update)
        }
    }

    /// Delete an entity
    public func delete<E: EntityProtocol>(_ entity: E) throws {
        try delete(E.self, id: entity.id)
    }

    /// Delete entity by ID
    public func delete<E: EntityProtocol>(_ type: E.Type, id: UUIDV4) throws {
        // Record change before deleting (need to capture the entity first for sync)
        if syncEnabled {
            if let entity = try get(type, id: id) {
                try recordChange(entity: entity, operation: .delete)
            }
        }

        let sql = "DELETE FROM \(E.tableName) WHERE id = ?"
        let stmt = try connection.prepare(sql)
        try stmt.bind(1, id.data)

        try stmt.step()
    }

    // MARK: - Query Execution (Internal)

    func executeQuery<E: EntityProtocol>(sql: String, values: [SQLiteValue], type: E.Type) throws -> [E] {
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

    // MARK: - Transaction Support

    /// Execute a block within a transaction
    public func transaction<T>(_ block: () throws -> T) throws -> T {
        try connection.transaction(block)
    }

    // MARK: - Sync Support

    /// Enable sync with device ID
    public func enableSync(deviceId: String) {
        lock.lock()
        defer { lock.unlock() }

        self.syncEnabled = true
        self.deviceId = deviceId
    }

    /// Disable sync
    public func disableSync() {
        lock.lock()
        defer { lock.unlock() }

        self.syncEnabled = false
        self.deviceId = nil
    }

    /// Get current logical clock value
    public func currentClock() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return clock.current
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
        let checkSQL = "SELECT logical_clock FROM change_log WHERE entity_type = ? AND entity_id = ? ORDER BY logical_clock DESC LIMIT 1"
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
              let dict = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
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
        let sql = "DELETE FROM change_log WHERE logical_clock < ?"
        let stmt = try connection.prepare(sql)
        try stmt.bind(1, clock)
        try stmt.step()
    }

    private func recordChange<E: EntityProtocol>(entity: E, operation: ChangeOperation) throws {
        guard let deviceId = deviceId else { return }

        lock.lock()
        let clockValue = clock.tick()
        lock.unlock()

        var payload: String? = nil
        if operation != .delete {
            payload = try encoder.encodeToJSON(entity)
        }

        let changeLog = ChangeLog(
            entityType: E.tableName,
            entityId: entity.id,
            operation: operation,
            payload: payload,
            deviceId: deviceId,
            logicalClock: clockValue
        )

        // Insert change log directly without triggering another change record
        let values = try encoder.encode(changeLog)
        let columns = values.keys.sorted()
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let columnList = columns.joined(separator: ", ")

        let sql = "INSERT INTO change_log (\(columnList)) VALUES (\(placeholders))"
        let stmt = try connection.prepare(sql)

        for (index, column) in columns.enumerated() {
            if let value = values[column] {
                try value.bind(to: stmt, at: Int32(index + 1))
            }
        }

        try stmt.step()
    }

    // MARK: - Relation Helpers

    /// Check if an entity type is a relation
    public func isRelationEntity(_ tableName: String) -> Bool {
        relationEntities.contains(tableName)
    }

    /// Execute raw SQL (for advanced queries)
    @discardableResult
    public func execute(_ sql: String) throws -> Int {
        try connection.execute(sql)
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
