import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker

/// Extension to add makeApplier() to all EntityProtocol types
package extension EntityProtocol {
    static func makeApplier() -> any EntityApplier {
        DefaultEntityApplier<Self>()
    }
}

/// Protocol for applying sync changes to local entities
package protocol EntityApplier: Sendable {
    /// The entity type this applier handles
    static var entityType: String { get }

    /// Apply a change to the local database
    /// - Parameters:
    ///   - change: The change to apply
    ///   - connection: The database connection
    /// - Throws: If the change cannot be applied
    func validate(_ change: SyncChange) throws
    func apply(change: SyncChange, to connection: SQLiteConnection) throws
    /// Snapshot of the current business row for timestamp/content comparison.
    func currentChange(for change: SyncChange, in connection: SQLiteConnection) throws -> SyncChange?
}

/// Default entity applier that uses JSON payload to decode and apply changes
package struct DefaultEntityApplier<T: EntityProtocol & SQLiteCodable & Decodable>: EntityApplier {
    package static var entityType: String { T.tableName }

    package init() {}

    package func validate(_ change: SyncChange) throws {
        let key = SyncKeyEncoder.decode(change.syncKey)
        guard key.count == T.syncKeyColumns.count, !key.contains(.null), !key.isEmpty else {
            throw SyncError.invalidPayload("Invalid record sync key")
        }
        if change.operation != .delete {
            guard let payload = change.payload else { throw SyncError.invalidPayload("Missing payload") }
            let entity = try JSONDecoder().decode(T.self, from: Data(payload.utf8))
            let values = try entity.sqliteEncode()
            guard SyncKeyEncoder.encode(T.syncKeyColumns.map { values[$0] ?? .null }) == change.syncKey else {
                throw SyncError.invalidPayload("Payload sync key does not match its record")
            }
        }
    }

    package func apply(change: SyncChange, to connection: SQLiteConnection) throws {
        switch change.operation {
        case .insert, .update:
            guard let payload = change.payload,
                  let data = payload.data(using: .utf8) else {
                throw SyncError.invalidPayload("Missing or invalid payload for \(change.operation)")
            }

            let decoder = JSONDecoder()
            let entity = try decoder.decode(T.self, from: data)

            let encoded = try entity.sqliteEncode()
            let payloadKey = SyncKeyEncoder.encode(T.syncKeyColumns.map { encoded[$0] ?? .null })
            guard payloadKey == change.syncKey else {
                throw SyncError.invalidPayload("Payload sync key does not match change identity")
            }

            // Find existing record by sync key
            let syncKeyCols = T.syncKeyColumns
            let syncKeyValues = SyncKeyEncoder.decode(change.syncKey)

            if let _ = try findBySyncKey(syncKeyCols: syncKeyCols, syncKeyValues: syncKeyValues, connection: connection) {
                // Update existing record using sync key
                try updateBySyncKey(entity: entity, syncKeyCols: syncKeyCols, syncKeyValues: syncKeyValues, connection: connection)
            } else {
                try connection.insert(entity)
            }

        case .delete:
            // Delete by sync key
            let syncKeyCols = T.syncKeyColumns
            let syncKeyValues = SyncKeyEncoder.decode(change.syncKey)
            try deleteBySyncKey(syncKeyCols: syncKeyCols, syncKeyValues: syncKeyValues, connection: connection)
        }
    }

    package func currentChange(for change: SyncChange, in connection: SQLiteConnection) throws -> SyncChange? {
        guard let entity = try findBySyncKey(syncKeyCols: T.syncKeyColumns,
            syncKeyValues: SyncKeyEncoder.decode(change.syncKey), connection: connection) else { return nil }
        return SyncChange(id: change.id, entityType: change.entityType, syncKey: change.syncKey,
            operation: .update, payload: String(decoding: try JSONEncoder().encode(entity), as: UTF8.self),
            deviceId: change.deviceId, logicalClock: 0, schemaVersion: change.schemaVersion,
            createdAt: change.createdAt)
    }

    /// Find entity by sync key
    private func findBySyncKey(syncKeyCols: [String], syncKeyValues: [SQLiteValue], connection: SQLiteConnection) throws -> T? {
        guard syncKeyCols.count == syncKeyValues.count else {
            throw SyncError.invalidPayload("Sync key column count mismatch")
        }

        // Build WHERE clause: col1 = ? AND col2 = ?
        let whereClause = syncKeyCols.enumerated().map { idx, col in
            "\(col) = ?\(idx + 1)"
        }.joined(separator: " AND ")

        let sql = "SELECT * FROM \(T.tableName) WHERE \(whereClause)"
        let stmt = try connection.prepare(sql)

        // Bind sync key values
        for (idx, value) in syncKeyValues.enumerated() {
            try bindValue(stmt: stmt, index: Int32(idx + 1), value: value)
        }

        guard try stmt.step() else {
            return nil
        }

        return try T.sqliteDecode(from: stmt)
    }

    /// Delete entity by sync key
    private func deleteBySyncKey(syncKeyCols: [String], syncKeyValues: [SQLiteValue], connection: SQLiteConnection) throws {
        guard syncKeyCols.count == syncKeyValues.count else {
            throw SyncError.invalidPayload("Sync key column count mismatch")
        }

        // Build WHERE clause: col1 = ? AND col2 = ?
        let whereClause = syncKeyCols.enumerated().map { idx, col in
            "\(col) = ?\(idx + 1)"
        }.joined(separator: " AND ")

        let sql = "DELETE FROM \(T.tableName) WHERE \(whereClause)"
        let stmt = try connection.prepare(sql)

        // Bind sync key values
        for (idx, value) in syncKeyValues.enumerated() {
            try bindValue(stmt: stmt, index: Int32(idx + 1), value: value)
        }

        try stmt.step()
    }

    /// Update entity by sync key
    private func updateBySyncKey(entity: T, syncKeyCols: [String], syncKeyValues: [SQLiteValue], connection: SQLiteConnection) throws {
        guard syncKeyCols.count == syncKeyValues.count else {
            throw SyncError.invalidPayload("Sync key column count mismatch")
        }

        // Get all columns except sync key columns (for SET clause) and timestamps
        let allColumns = T.columns.map { $0.name }
        let excludedFromSet = Set(syncKeyCols)
        let setColumns = allColumns.filter { !excludedFromSet.contains($0) }
        guard !setColumns.isEmpty else { return }

        // Encode entity to get values
        let values = try entity.sqliteEncode()

        // Build SET clause: col1 = ?, col2 = ?
        let setClause = setColumns.enumerated().map { idx, col in
            "\(col) = ?\(idx + 1)"
        }.joined(separator: ", ")

        // Build WHERE clause: sync_col1 = ?, sync_col2 = ?
        let whereClause = syncKeyCols.enumerated().map { idx, col in
            "\(col) = ?\(setColumns.count + idx + 1)"
        }.joined(separator: " AND ")

        let sql = "UPDATE \(T.tableName) SET \(setClause) WHERE \(whereClause)"
        let stmt = try connection.prepare(sql)

        // Bind SET values
        for (idx, col) in setColumns.enumerated() {
            if let value = values[col] {
                try bindValue(stmt: stmt, index: Int32(idx + 1), value: value)
            } else {
                try stmt.bindNull(Int32(idx + 1))
            }
        }

        // Bind WHERE values (sync key)
        for (idx, value) in syncKeyValues.enumerated() {
            try bindValue(stmt: stmt, index: Int32(setColumns.count + idx + 1), value: value)
        }

        try stmt.step()
    }

    /// Bind SQLiteValue to statement
    private func bindValue(stmt: SQLiteStatementImpl, index: Int32, value: SQLiteValue) throws {
        switch value {
        case .null:
            try stmt.bindNull(index)
        case .integer(let num):
            try stmt.bind(index, num)
        case .real(let num):
            try stmt.bind(index, num)
        case .text(let str):
            try stmt.bind(index, str)
        case .blob(let data):
            try stmt.bind(index, data)
        }
    }

}

/// Registry for entity appliers
package final class EntityApplierRegistry: Sendable {
    private let appliers: [String: any EntityApplier]

    package init(_ appliers: [any EntityApplier] = []) {
        self.appliers = Dictionary(uniqueKeysWithValues: appliers.map { (type(of: $0).entityType, $0) })
    }

    package func validate(_ change: SyncChange) throws {
        guard let applier = appliers[change.entityType] else { throw SyncError.unknownEntityType(change.entityType) }
        try applier.validate(change)
    }

    /// Number of registered appliers
    package var count: Int { appliers.count }

    /// Create a registry from entity types
    /// Automatically generates DefaultEntityApplier for each type
    package convenience init(entityTypes: [any EntityProtocol.Type]) {
        let appliers = entityTypes.map { $0.makeApplier() }
        self.init(appliers)
    }

    /// Get applier for entity type
    private func applier(for entityType: String) -> (any EntityApplier)? {
        return appliers[entityType]
    }

    package func currentChange(for change: SyncChange, in connection: SQLiteConnection) throws -> SyncChange? {
        guard let applier = applier(for: change.entityType) else {
            throw SyncError.unknownEntityType(change.entityType)
        }
        return try applier.currentChange(for: change, in: connection)
    }

    /// Apply a change using the appropriate applier
    package func apply(change: SyncChange, to connection: SQLiteConnection) throws {
        guard let applier = applier(for: change.entityType) else {
            throw SyncError.unknownEntityType(change.entityType)
        }
        try applier.apply(change: change, to: connection)
    }
}
