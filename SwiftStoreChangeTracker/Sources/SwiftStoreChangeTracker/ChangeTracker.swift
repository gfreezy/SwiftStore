import Foundation
import SwiftStoreCore
import os.log

/// Captures pre-update row snapshots and persists completed statement changes.
public final class ChangeTracker: SQLiteUpdateHookHandler {
    private let mainConnection: SQLiteConnection
    private let changeLogConnection: SQLiteConnection
    private let registeredEntities: [String: any EntityProtocol.Type]
    private let deviceId: UUIDV7
    private var columnOffsets: [String: [Int]] = [:]
    private let tickClock: () -> Int64
    private let schemaVersion: Int
    private var lastClock: Int64 = 0

    /// Initialize the change tracker
    /// - Parameters:
    ///   - connection: The main database connection
    ///   - changeLogDbPath: The path to the changelog database
    ///   - deviceId: The device ID
    ///   - registeredEntities: The registered entity types to track changes for
    ///   - tickClock: A function to tick the clock
    ///   - schemaVersion: The schema version for migration compatibility
    /// - Throws: An error if the changelog table cannot be migrated
    public init(
        connection: SQLiteConnection,
        changeLogDbPath: String,
        deviceId: UUIDV7,
        registeredEntities: [any EntityProtocol.Type],
        tickClock: @escaping () -> Int64,
        schemaVersion: Int = 1
    ) throws {
        guard SQLiteConnection.supportsPreUpdateHook else {
            throw StoreError.queryFailed("Change tracking requires SQLite with SQLITE_ENABLE_PREUPDATE_HOOK")
        }
        self.mainConnection = connection
        self.deviceId = deviceId
        // Build lookup dictionary from table name to entity type
        self.registeredEntities = Dictionary(
            uniqueKeysWithValues: registeredEntities.map { ($0.tableName, $0) })
        self.tickClock = tickClock
        self.schemaVersion = schemaVersion

        // Create separate connection for changelog database
        self.changeLogConnection = try SQLiteConnection(path: changeLogDbPath)

        // Apply the changelog database's frozen migration history.
        try migrateChangeLogTable()
        lastClock = try ChangeLog.filter(\.deviceId == deviceId).max(\.logicalClock, changeLogConnection) ?? 0
    }

    private func migrateChangeLogTable() throws {
        let runner = VersionedMigrator(connection: changeLogConnection, migrations: try ChangeLogMigrations.all())
        try changeLogConnection.transaction {
            do {
                _ = try runner.pendingMigrationIDs()
            } catch VersionedMigrationError.baselineRequired {
                // Earlier versions created this same schema without migration bookkeeping.
                try runner.adoptBaseline(through: "001_initial")
            }
            try runner.migrate()
        }
    }

    // MARK: - Lifecycle

    /// Call after migration. Resolve physical columns once; migrations may have
    /// appended columns in an order different from the current Swift declaration.
    public func start() throws {
        var offsets: [String: [Int]] = [:]
        for entity in registeredEntities.values {
            let name = entity.tableName.replacingOccurrences(of: "\"", with: "\"\"")
            let stmt = try mainConnection.prepare("PRAGMA table_xinfo(\"\(name)\")")
            var columns: [String: Int] = [:]
            while try stmt.step() {
                if let name = stmt.columnString(1) { columns[name] = Int(stmt.columnInt64(0)) }
            }
            offsets[entity.tableName] = try entity.columns.map { column in
                guard let index = columns[column.name] else {
                    throw StoreError.invalidPayload("Missing tracked column \(entity.tableName).\(column.name)")
                }
                return index
            }
        }
        columnOffsets = offsets
        try mainConnection.setPreUpdateHook(self)
    }

    public func stop() {
        // Removing a hook does not require optional API support when none exists.
        try? mainConnection.setPreUpdateHook(nil)
    }

    // MARK: - Public Access

    /// Get the changelog database connection for queries
    public var connection: SQLiteConnection { changeLogConnection }

    // MARK: - SQLiteUpdateHookHandler

    /// Compatibility entry point. Connection delivery uses the throwing batch API.
    public func handleUpdate(_ info: SQLiteUpdateInfo) {
        do { try handleUpdates([info]) }
        catch { SwiftStoreLogger.error("Failed to record change: \(error)") }
    }

    public func withTrackingTransaction<T>(_ block: () throws -> T) throws -> T {
        try changeLogConnection.transaction(block)
    }

    public func tracksTable(_ tableName: String) -> Bool { registeredEntities[tableName] != nil }

    private struct Identity: Hashable {
        let table: String
        let key: Data
    }
    private struct CapturedChange {
        let identity: Identity
        let operation: ChangeOperation
        let row: SQLiteRowSnapshot?
        let occurredAt: Date
    }

    /// Runs at SQLITE_DONE. Only decodes owned snapshots: never re-queries a
    /// business row that a later trigger may have deleted or replaced.
    public func handleUpdates(_ updates: [SQLiteUpdateInfo]) throws {
        var changes: [CapturedChange] = []
        var positions: [Identity: Int] = [:]
        func record(_ change: CapturedChange) {
            if let index = positions[change.identity] {
                let previous = changes[index]
                // An AFTER UPDATE timestamp trigger extends the original insert.
                let operation: ChangeOperation = previous.operation == .insert && change.operation == .update
                    ? .insert : change.operation
                changes[index] = CapturedChange(identity: change.identity, operation: operation,
                    row: change.row, occurredAt: change.occurredAt)
            } else {
                positions[change.identity] = changes.count
                changes.append(change)
            }
        }
        for info in updates where info.source == .local {
            guard let entity = registeredEntities[info.tableName],
                  let offsets = columnOffsets[info.tableName] else { continue }
            func row(_ values: [SQLiteValue]?) throws -> SQLiteRowSnapshot? {
                guard let values else { return nil }
                let mapped = try offsets.map { index -> SQLiteValue in
                    guard values.indices.contains(index) else {
                        throw StoreError.invalidPayload("Tracked schema changed; restart tracking after migration")
                    }
                    return values[index]
                }
                return SQLiteRowSnapshot(values: mapped)
            }
            let old = try row(info.oldValues), new = try row(info.newValues)
            func identity(_ row: SQLiteRowSnapshot) throws -> Identity {
                let values = try entity.syncKeyColumns.map { name -> SQLiteValue in
                    guard let index = entity.columns.firstIndex(where: { $0.name == name }) else {
                        throw StoreError.invalidPayload("Unknown sync key column \(name)")
                    }
                    return row.columnValue(Int32(index), type: entity.columns[index].type)
                }
                return Identity(table: info.tableName, key: SyncKeyEncoder.encode(values))
            }
            let oldID = try old.map(identity), newID = try new.map(identity)
            // Updating a sync key removes the old identity and creates the new one.
            if let oldID, info.operation == .delete || oldID != newID {
                record(CapturedChange(identity: oldID, operation: .delete, row: nil, occurredAt: info.occurredAt))
            }
            if let newID, let new {
                record(CapturedChange(identity: newID, operation: info.operation == .insert ? .insert : .update,
                    row: new, occurredAt: info.occurredAt))
            }
        }
        for change in changes {
            guard let entity = registeredEntities[change.identity.table] else { continue }
            lastClock = max(tickClock(), lastClock + 1)
            let payload = try change.row.map { try serializeEntity(stmt: $0, entityType: entity) }
            try insertChangeLog(entityType: change.identity.table, syncKey: change.identity.key,
                operation: change.operation, payload: payload, clockValue: lastClock, occurredAt: change.occurredAt)
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
            guard let column = entityType.columns.first(where: { $0.name == colName }),
                  let columnIndex = (0..<stmt.columnCount).first(where: { stmt.columnName($0) == colName }) else {
                throw StoreError.invalidPayload("Sync key column '\(colName)' not found in entity")
            }


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
    private func serializeEntity(stmt: any SQLiteStatementProtocol, entityType: any EntityProtocol.Type)
        throws -> String
    {
        let entity = try entityType.sqliteDecode(from: stmt)
        return String(decoding: try JSONEncoder().encode(entity), as: UTF8.self)
    }

    /// Capture rows that existed before synchronization was enabled. Remote
    /// rows are protected by a per-entity bootstrap marker on subsequent launches.
    public func captureExistingRows() throws {
        try changeLogConnection.execute("CREATE TABLE IF NOT EXISTS __swiftstore_sync_bootstrap (entity_type TEXT PRIMARY KEY)")
        for entity in registeredEntities.values {
            let captured: Int64 = try changeLogConnection.queryScalar(
                "SELECT COUNT(*) FROM __swiftstore_sync_bootstrap WHERE entity_type = ?",
                values: [.text(entity.tableName)]) ?? 0
            if captured > 0 { continue }
            try changeLogConnection.transaction {
                let table = entity.tableName.replacingOccurrences(of: "\"", with: "\"\"")
                let columns = entity.columns.map { "\"" + $0.name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ", ")
                let stmt = try mainConnection.prepare("SELECT \(columns) FROM \"\(table)\"")
                while try stmt.step() {
                    let key = try extractSyncKeyData(stmt: stmt, entityType: entity)
                    let tracked: Int64 = try changeLogConnection.queryScalar(
                        "SELECT COUNT(*) FROM change_log WHERE entity_type = ? AND sync_key = ?",
                        values: [.text(entity.tableName), .blob(key)]) ?? 0
                    if tracked > 0 { continue }
                    lastClock = max(tickClock(), lastClock + 1)
                    try insertChangeLog(entityType: entity.tableName, syncKey: key,
                        operation: .insert, payload: try serializeEntity(stmt: stmt, entityType: entity),
                        clockValue: lastClock)
                }
                try changeLogConnection.execute("INSERT INTO __swiftstore_sync_bootstrap (entity_type) VALUES (?)",
                    values: [.text(entity.tableName)])
            }
        }
    }

    /// Insert a change log entry into the changelog database
    private func insertChangeLog(
        entityType: String,
        syncKey: Data,
        operation: ChangeOperation,
        payload: String?,
        clockValue: Int64,
        occurredAt: Date = Date()
    ) throws {
        let log = ChangeLog(
            entityType: entityType,
            syncKey: syncKey,
            operation: operation,
            payload: payload,
            deviceId: deviceId,
            logicalClock: clockValue,
            schemaVersion: schemaVersion,
            createdAt: occurredAt,
            updatedAt: occurredAt
        )
        try changeLogConnection.insert(log)
    }
}
