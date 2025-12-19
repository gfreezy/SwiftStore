import Foundation
import SwiftStoreCore

/// Handles SQLite update hooks and writes changes directly to a separate changelog database
public final class ChangeTracker: SQLiteUpdateHookHandler {
    // Table name
    public static let changeLogTable = "__swiftstore_change_log"

    private let mainConnection: SQLiteConnection
    private let changeLogConnection: SQLiteConnection
    private let registeredEntities: [String: any EntityProtocol.Type]
    private let deviceId: String
    private let pendingDeletesTable: String
    private let tickClock: () -> Int64

    public init(
        connection: SQLiteConnection,
        changeLogDbPath: String,
        deviceId: String,
        pendingDeletesTable: String,
        registeredEntities: [String: any EntityProtocol.Type],
        tickClock: @escaping () -> Int64
    ) throws {
        self.mainConnection = connection
        self.deviceId = deviceId
        self.pendingDeletesTable = pendingDeletesTable
        self.registeredEntities = registeredEntities
        self.tickClock = tickClock

        // Create separate connection for changelog database
        self.changeLogConnection = try SQLiteConnection(path: changeLogDbPath)

        // Create changelog table if not exists
        try createChangeLogTable()
    }

    private func createChangeLogTable() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS \(Self.changeLogTable) (
                id BLOB PRIMARY KEY,
                entity_type TEXT NOT NULL,
                entity_id BLOB NOT NULL,
                operation TEXT NOT NULL,
                payload TEXT,
                device_id TEXT NOT NULL,
                logical_clock INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        try changeLogConnection.execute(sql)

        // Create indexes
        try changeLogConnection.execute("""
            CREATE INDEX IF NOT EXISTS idx_change_log_clock
            ON \(Self.changeLogTable) (logical_clock)
            """)
        try changeLogConnection.execute("""
            CREATE INDEX IF NOT EXISTS idx_change_log_entity
            ON \(Self.changeLogTable) (entity_type, entity_id)
            """)
    }

    // MARK: - Lifecycle

    /// Start tracking changes by registering update hook
    public func start() {
        mainConnection.setUpdateHook(self)
    }

    /// Stop tracking changes by removing update hook
    public func stop() {
        mainConnection.setUpdateHook(nil)
    }

    // MARK: - Public Access

    /// Get the changelog database connection for queries
    public var connection: SQLiteConnection { changeLogConnection }

    // MARK: - SQLiteUpdateHookHandler

    public func handleUpdate(_ info: SQLiteUpdateInfo) {
        // Skip change_log table
        guard info.tableName != Self.changeLogTable else { return }

        // Skip DELETE operations (we handle deletes via INSERT on pending_deletes)
        guard info.operation != .delete else { return }

        let clockValue = tickClock()

        // Handle INSERT on pending_deletes as a DELETE operation
        if info.tableName == pendingDeletesTable {
            handlePendingDeleteInsert(rowId: info.rowId, clockValue: clockValue)
            return
        }

        // Skip if not a registered entity
        guard let entityType = registeredEntities[info.tableName] else { return }

        // Get entity data from the row
        do {
            let stmt = try mainConnection.prepareRowById(info.tableName, rowId: info.rowId)
            guard try stmt.step() else { return }

            guard let idData = stmt.columnData(0),
                  let entityId = UUIDV4(data: idData) else { return }

            // Serialize entity to JSON payload
            let payload = try serializeEntity(stmt: stmt, entityType: entityType)

            let operation: ChangeOperation = info.operation == .insert ? .insert : .update
            try insertChangeLog(
                entityType: info.tableName,
                entityId: entityId,
                operation: operation,
                payload: payload,
                clockValue: clockValue
            )
        } catch {
            print("SwiftStore: Failed to record change: \(error)")
        }
    }

    /// Serialize entity row to JSON string
    private func serializeEntity(stmt: SQLiteStatementImpl, entityType: any EntityProtocol.Type) throws -> String {
        var dict: [String: Any] = [:]

        for (index, column) in entityType.columns.enumerated() {
            let columnIndex = Int32(index)
            let propertyName = column.name.snakeCaseToCamelCase()

            switch column.type {
            case .text:
                if let value = stmt.columnString(columnIndex) {
                    dict[propertyName] = value
                }
            case .integer:
                dict[propertyName] = stmt.columnInt64(columnIndex)
            case .real:
                dict[propertyName] = stmt.columnDouble(columnIndex)
            case .blob:
                if let data = stmt.columnData(columnIndex) {
                    // Convert UUIDV4 blob to string
                    if let uuid = UUIDV4(data: data) {
                        dict[propertyName] = uuid.uuidString
                    } else {
                        dict[propertyName] = data.base64EncodedString()
                    }
                }
            }
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    /// Handle INSERT on pending_deletes table - this signals a delete operation
    private func handlePendingDeleteInsert(rowId: Int64, clockValue: Int64) {
        do {
            // Fetch the pending delete row to get table_name and entity_id
            let stmt = try mainConnection.prepareRowById(pendingDeletesTable, rowId: rowId)
            guard try stmt.step() else { return }

            // Columns: id (0), table_name (1), entity_id (2)
            guard let tableName = stmt.columnString(1),
                  let entityIdData = stmt.columnData(2),
                  let entityId = UUIDV4(data: entityIdData)
            else { return }

            // Delete operations don't need payload
            try insertChangeLog(
                entityType: tableName,
                entityId: entityId,
                operation: .delete,
                payload: nil,
                clockValue: clockValue
            )
        } catch {
            print("SwiftStore: Failed to handle pending delete: \(error)")
        }
    }

    /// Insert a change log entry into the changelog database
    private func insertChangeLog(
        entityType: String,
        entityId: UUIDV4,
        operation: ChangeOperation,
        payload: String?,
        clockValue: Int64
    ) throws {
        let now = Date()
        let changeId = UUIDV4()

        let sql = """
            INSERT INTO \(Self.changeLogTable)
            (id, entity_type, entity_id, operation, payload, device_id, logical_clock, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        let stmt = try changeLogConnection.prepare(sql)
        try SQLiteValue.blob(changeId.data).bind(to: stmt, at: 1)
        try SQLiteValue.text(entityType).bind(to: stmt, at: 2)
        try SQLiteValue.blob(entityId.data).bind(to: stmt, at: 3)
        try SQLiteValue.text(operation.rawValue).bind(to: stmt, at: 4)
        if let payload = payload {
            try SQLiteValue.text(payload).bind(to: stmt, at: 5)
        } else {
            try stmt.bindNull(5)
        }
        try SQLiteValue.text(deviceId).bind(to: stmt, at: 6)
        try SQLiteValue.integer(clockValue).bind(to: stmt, at: 7)
        try SQLiteValue.real(now.timeIntervalSince1970).bind(to: stmt, at: 8)
        try SQLiteValue.real(now.timeIntervalSince1970).bind(to: stmt, at: 9)

        try stmt.step()
    }
}
