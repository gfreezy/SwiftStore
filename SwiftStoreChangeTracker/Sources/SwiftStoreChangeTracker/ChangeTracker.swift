import Foundation
import SwiftStoreCore
import os.log

/// Handles SQLite update hooks and writes changes directly to a separate changelog database
public final class ChangeTracker: SQLiteUpdateHookHandler {
    private let mainConnection: SQLiteConnection
    private let changeLogConnection: SQLiteConnection
    private let registeredEntities: [String: any EntityProtocol.Type]
    private let deviceId: UUIDV7
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
        deviceId: UUIDV7,
        pendingDeletesTable: String,
        registeredEntities: [any EntityProtocol.Type],
        tickClock: @escaping () -> Int64,
        schemaVersion: Int = 1
    ) throws {
        self.mainConnection = connection
        self.deviceId = deviceId
        self.pendingDeletesTable = pendingDeletesTable
        // Build lookup dictionary from table name to entity type
        self.registeredEntities = Dictionary(
            uniqueKeysWithValues: registeredEntities.map { ($0.tableName, $0) })
        self.tickClock = tickClock
        self.schemaVersion = schemaVersion

        // Create separate connection for changelog database
        self.changeLogConnection = try SQLiteConnection(path: changeLogDbPath)

        // Create changelog table using Migrator
        try migrateChangeLogTable()
    }

    private func migrateChangeLogTable() throws {
        let migrator = Migrator(
            connection: changeLogConnection, trackDeletes: false, createUpdateTrigger: false)
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

            // Extract sync key values and encode to binary
            let syncKeyData = try extractSyncKeyData(stmt: stmt, entityType: entityType)

            // Serialize entity to JSON payload
            let payload = try serializeEntity(stmt: stmt, entityType: entityType)

            let operation: ChangeOperation = info.operation == .insert ? .insert : .update
            try insertChangeLog(
                entityType: info.tableName,
                syncKey: syncKeyData,
                operation: operation,
                payload: payload,
                clockValue: clockValue
            )
        } catch {
            SwiftStoreLogger.error("Failed to record change: \(error)")
        }
    }

    /// Extract sync key values from entity row and encode to binary
    private func extractSyncKeyData(stmt: SQLiteStatementImpl, entityType: any EntityProtocol.Type)
        throws -> Data
    {
        let syncKeyCols = entityType.syncKeyColumns
        var values: [SQLiteValue] = []

        for colName in syncKeyCols {
            // Find the column index by name
            guard let colIndex = entityType.columns.firstIndex(where: { $0.name == colName }) else {
                throw StoreError.invalidPayload("Sync key column '\(colName)' not found in entity")
            }

            let column = entityType.columns[colIndex]
            let columnIndex = Int32(colIndex)

            switch column.type {
            case .text:
                if let value = stmt.columnString(columnIndex) {
                    values.append(.text(value))
                } else {
                    values.append(.null)
                }
            case .integer:
                values.append(.integer(stmt.columnInt64(columnIndex)))
            case .real:
                values.append(.real(stmt.columnDouble(columnIndex)))
            case .blob:
                if let data = stmt.columnData(columnIndex) {
                    values.append(.blob(data))
                } else {
                    values.append(.null)
                }
            }
        }

        return SyncKeyEncoder.encode(values)
    }

    /// Serialize entity row to JSON string
    private func serializeEntity(stmt: SQLiteStatementImpl, entityType: any EntityProtocol.Type)
        throws -> String
    {
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
                    // Convert UUIDV7 blob to string
                    if let uuid = UUIDV7(data: data) {
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
        let stmt: SQLiteStatementImpl
        do {
            // Fetch the pending delete row to get table_name and sync_key_json
            stmt = try mainConnection.prepareRowById(pendingDeletesTable, rowId: rowId)
            guard try stmt.step() else { return }
        } catch {
            SwiftStoreLogger.error("Failed to prepare pending delete row, table: \(pendingDeletesTable), id: \(rowId), error: \(error)")
            return
        }

        // Columns: id (0), table_name (1), sync_key_json (2)
        guard let tableName = stmt.columnString(1),
            let syncKeyJson = stmt.columnString(2)
        else { return }

        // Parse JSON and encode to binary
        guard let entityType = registeredEntities[tableName] else { return }
        let syncKeyData: Data
        do {
            syncKeyData = try parseSyncKeyJson(syncKeyJson, entityType: entityType)
        } catch {
            SwiftStoreLogger.error("Failed to parse sync key JSON for table: \(tableName), row id: \(rowId), error: \(error)")
            return
        }

        do {
            // Delete operations don't need payload
            try insertChangeLog(
                entityType: tableName,
                syncKey: syncKeyData,
                operation: .delete,
                payload: nil,
                clockValue: clockValue
            )
        } catch {
            SwiftStoreLogger.error("Failed to insert change log, table: \(tableName), id: \(rowId), error: \(error)")
            return
        }

    }

    /// Parse sync key JSON and encode to binary
    private func parseSyncKeyJson(_ json: String, entityType: any EntityProtocol.Type) throws
        -> Data
    {
        guard let jsonData = json.data(using: .utf8),
            let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            throw StoreError.decodingFailed("Invalid sync key JSON")
        }

        let syncKeyCols = entityType.syncKeyColumns
        var values: [SQLiteValue] = []

        for colName in syncKeyCols {
            // Find column definition to determine type
            guard let column = entityType.columns.first(where: { $0.name == colName }) else {
                throw StoreError.invalidPayload("Sync key column '\(colName)' not found in entity")
            }

            guard let value = dict[colName] else {
                values.append(.null)
                continue
            }

            switch column.type {
            case .text:
                if let str = value as? String {
                    values.append(.text(str))
                } else {
                    values.append(.null)
                }
            case .integer:
                if let num = value as? Int64 {
                    values.append(.integer(num))
                } else if let num = value as? Int {
                    values.append(.integer(Int64(num)))
                } else {
                    values.append(.null)
                }
            case .real:
                if let num = value as? Double {
                    values.append(.real(num))
                } else {
                    values.append(.null)
                }
            case .blob:
                // For blob (UUIDV7), the JSON trigger stores as hex string using hex() function
                if let str = value as? String {
                    // Try to parse as hex string first (from SQLite hex() function)
                    if let data = Data(hexString: str) {
                        values.append(.blob(data))
                    } else if let uuid = UUIDV7(uuidString: str) {
                        // Try to parse as UUID string
                        values.append(.blob(uuid.data))
                    } else if let data = Data(base64Encoded: str) {
                        // Try base64 as fallback
                        values.append(.blob(data))
                    } else {
                        values.append(.null)
                    }
                } else {
                    values.append(.null)
                }
            }
        }

        return SyncKeyEncoder.encode(values)
    }

    /// Insert a change log entry into the changelog database
    private func insertChangeLog(
        entityType: String,
        syncKey: Data,
        operation: ChangeOperation,
        payload: String?,
        clockValue: Int64
    ) throws {
        let log = ChangeLog(
            entityType: entityType,
            syncKey: syncKey,
            operation: operation,
            payload: payload,
            deviceId: deviceId,
            logicalClock: clockValue,
            schemaVersion: schemaVersion
        )
        try changeLogConnection.insert(log)
    }
}

// MARK: - Data Hex String Extension

extension Data {
    /// Initialize Data from a hex string (e.g., "48656C6C6F" -> "Hello")
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex

        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
