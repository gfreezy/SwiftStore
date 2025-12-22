import Foundation
import SwiftStoreCore

/// Handles SQLite update hooks and writes changes directly to a separate changelog database
public final class ChangeTracker: SQLiteUpdateHookHandler {
    private let mainConnection: SQLiteConnection
    private let changeLogConnection: SQLiteConnection
    private let registeredEntities: [String: any EntityProtocol.Type]
    private let deviceId: UUIDV4
    private let pendingDeletesTable: String
    private let tickClock: () -> Int64
    private let schemaVersion: Int

    /// Initialize the change tracker
    /// - Parameters:
    ///   - connection: The main database connection
    ///   - changeLogDbPath: The path to the changelog database
    ///   - deviceId: The device ID
    ///   - pendingDeletesTable: The name of the pending deletes table
    ///   - registeredEntities: The registered entity types to track changes for
    ///   - tickClock: A function to tick the clock
    ///   - schemaVersion: The schema version for migration compatibility
    /// - Throws: An error if the changelog table cannot be migrated
    public init(
        connection: SQLiteConnection,
        changeLogDbPath: String,
        deviceId: UUIDV4,
        pendingDeletesTable: String,
        registeredEntities: [any EntityProtocol.Type],
        tickClock: @escaping () -> Int64,
        schemaVersion: Int = 1
    ) throws {
        self.mainConnection = connection
        self.deviceId = deviceId
        self.pendingDeletesTable = pendingDeletesTable
        // Build lookup dictionary from table name to entity type
        self.registeredEntities = Dictionary(uniqueKeysWithValues: registeredEntities.map { ($0.tableName, $0) })
        self.tickClock = tickClock
        self.schemaVersion = schemaVersion

        // Create separate connection for changelog database
        self.changeLogConnection = try SQLiteConnection(path: changeLogDbPath)

        // Create changelog table using Migrator
        try migrateChangeLogTable()
    }

    private func migrateChangeLogTable() throws {
        let migrator = Migrator(connection: changeLogConnection, trackDeletes: false, createUpdateTrigger: false)
        let plan = try migrator.plan(for: [ChangeLog.self])
        try migrator.apply(plan)
    }

    // MARK: - Lifecycle

    /// Start tracking changes by registering update hook
    public func start() throws {
        // Clear pending deletes table (stale from previous runs)
        let clearSQL: SQL = "DELETE FROM \(raw: pendingDeletesTable)"
        try mainConnection.execute(clearSQL)

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
        let log = ChangeLog(
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: payload,
            deviceId: deviceId,
            logicalClock: clockValue,
            schemaVersion: schemaVersion
        )
        try changeLogConnection.insert(log)
    }
}
