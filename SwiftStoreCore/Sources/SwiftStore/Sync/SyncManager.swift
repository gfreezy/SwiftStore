import Foundation

/// Manages sync operations for the store
public final class SyncManager: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let dbPath: String
    private let decoder: SQLiteDecoder

    // Sync state
    private var syncEnabled: Bool = false
    private var deviceId: String?
    private var clock: HybridClock = HybridClock()

    // File-based change queue
    private var changeQueue: ChangeQueue?
    private var changeQueueProcessor: ChangeQueueProcessor?

    // Registered entity types
    private var registeredEntities: [String: any EntityProtocol.Type] = [:]
    private var relationEntities: Set<String> = []

    // System table names
    internal static let changeLogTable = "__swiftstore_change_log"
    internal static let pendingDeletesTable = "__swiftstore_pending_deletes"

    // Tables to exclude from sync
    private let excludedFromSync: Set<String> = [changeLogTable, pendingDeletesTable]

    public init(connection: SQLiteConnection, dbPath: String) {
        self.connection = connection
        self.dbPath = dbPath
        self.decoder = SQLiteDecoder()
    }

    // MARK: - Entity Registration

    /// Register entity types for sync
    public func registerEntities(_ entities: [String: any EntityProtocol.Type], relations: Set<String>) {
        self.registeredEntities = entities
        self.relationEntities = relations
    }

    // MARK: - Sync Control

    /// Check if sync is enabled
    public var isEnabled: Bool { syncEnabled }

    /// Enable sync with device ID
    public func enable(deviceId: String) throws {
        syncEnabled = true
        self.deviceId = deviceId

        // Clear pending_deletes table (stale from previous runs)
        let clearSQL: SQL = "DELETE FROM \(raw: Self.pendingDeletesTable)"
        try connection.execute(clearSQL)

        // Create delete triggers for all registered entities
        try createDeleteTriggers()

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
    public func disable() {
        // Remove update hook first
        connection.setUpdateHook(nil)

        // Drop delete triggers
        dropDeleteTriggers()

        // Flush and stop processor
        changeQueueProcessor?.stop()
        changeQueueProcessor = nil
        changeQueue = nil

        syncEnabled = false
        deviceId = nil
    }

    // MARK: - Delete Triggers

    /// Create BEFORE DELETE triggers for all registered entities
    private func createDeleteTriggers() throws {
        for tableName in registeredEntities.keys {
            let triggerName = "__swiftstore_delete_\(tableName)"
            let sql = """
                CREATE TRIGGER IF NOT EXISTS \(triggerName)
                BEFORE DELETE ON \(tableName)
                FOR EACH ROW
                BEGIN
                    INSERT INTO \(Self.pendingDeletesTable) (table_name, entity_id)
                    VALUES ('\(tableName)', OLD.id);
                END
                """
            try connection.execute(sql)
        }
    }

    /// Drop delete triggers for all registered entities
    private func dropDeleteTriggers() {
        for tableName in registeredEntities.keys {
            let triggerName = "__swiftstore_delete_\(tableName)"
            _ = try? connection.execute("DROP TRIGGER IF EXISTS \(triggerName)")
        }
    }

    /// Flush pending changes to change_log
    public func flushChanges() {
        changeQueueProcessor?.flush()
    }

    /// Get current logical clock value
    public func currentClock() -> Int64 {
        return clock.current
    }

    // MARK: - Time Verification

    /// Verify that local time is within acceptable range of NTP time
    public func verifyTime(
        toleranceMs: Int64 = 5000,
        servers: [String] = NTPClient.defaultServers
    ) async throws -> NTPVerificationResult {
        try await NTPClient.verifyTime(toleranceMs: toleranceMs, servers: servers)
    }

    /// Check if local time is valid before enabling sync
    public func validateTimeForSync(toleranceMs: Int64 = 5000) async throws {
        let result = try await verifyTime(toleranceMs: toleranceMs)
        if !result.isValid {
            throw StoreError.timeOutOfSync(offsetMs: result.offsetMs, toleranceMs: toleranceMs)
        }
    }

    // MARK: - Change Log Operations

    /// Get changes since a given clock value
    public func changesSince(clock: Int64) throws -> [ChangeLog] {
        let sql: SQL = """
            SELECT * FROM \(ChangeLog.self)
            WHERE \(\ChangeLog.logicalClock) > \(clock)
            ORDER BY \(\ChangeLog.logicalClock) ASC
            """
        let stmt = try connection.prepareAndBind(sql.sql, values: sql.values)
        return try decoder.decodeAll(ChangeLog.self, from: stmt)
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

        try connection.transaction {
            for change in sorted {
                // Update local clock
                clock.update(received: change.logicalClock)

                switch change.operation {
                case .insert, .update:
                    try applyUpsert(change)
                case .delete:
                    try applyDelete(change)
                }
            }
        }
    }

    /// Prune old change logs
    public func pruneChanges(before clock: Int64) throws {
        let sql: SQL = "DELETE FROM \(ChangeLog.self) WHERE \(\ChangeLog.logicalClock) < \(clock)"
        try connection.execute(sql)
    }

    // MARK: - Private Helpers

    private func applyUpsert(_ change: ChangeLog) throws {
        guard let payload = change.payload else {
            throw StoreError.invalidPayload("Missing payload for \(change.operation) operation")
        }

        guard let entityType = registeredEntities[change.entityType] else {
            throw StoreError.invalidPayload("Unknown entity type: \(change.entityType)")
        }

        // Check if entity exists and compare clocks
        let checkSQL: SQL = """
            SELECT \(\ChangeLog.logicalClock) FROM \(ChangeLog.self)
            WHERE \(\ChangeLog.entityType) = \(change.entityType) AND \(\ChangeLog.entityId) = \(change.entityId)
            ORDER BY \(\ChangeLog.logicalClock) DESC LIMIT 1
            """
        let localClock = try connection.queryScalar(checkSQL, type: Int64.self) ?? 0
        if change.logicalClock <= localClock {
            // Local data is newer, skip
            return
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
        let sql: SQL = "DELETE FROM \(raw: change.entityType) WHERE id = \(change.entityId)"
        try connection.execute(sql)
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
}

// MARK: - SQLiteUpdateHookHandler

extension SyncManager: SQLiteUpdateHookHandler {
    public func handleUpdate(_ info: SQLiteUpdateInfo) {
        // Skip change_log table
        guard info.tableName != Self.changeLogTable else { return }

        // Skip DELETE operations (we handle deletes via INSERT on pending_deletes)
        guard info.operation != .delete else { return }

        // Skip if sync is not enabled
        guard syncEnabled else { return }

        let clockValue = clock.tick()

        // Handle INSERT on pending_deletes as a DELETE operation
        if info.tableName == Self.pendingDeletesTable {
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
            let stmt = try connection.prepareRowById(Self.pendingDeletesTable, rowId: rowId)
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
