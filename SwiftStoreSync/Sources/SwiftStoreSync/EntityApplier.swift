import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker

/// Extension to add makeApplier() to all EntityProtocol types
public extension EntityProtocol {
    static func makeApplier() -> any EntityApplier {
        DefaultEntityApplier<Self>()
    }
}

/// Protocol for applying sync changes to local entities
public protocol EntityApplier: Sendable {
    /// The entity type this applier handles
    static var entityType: String { get }

    /// Apply a change to the local database
    /// - Parameters:
    ///   - change: The change to apply
    ///   - connection: The database connection
    /// - Throws: If the change cannot be applied
    func apply(change: SyncChange, to connection: SQLiteConnection) throws
}

/// Default entity applier that uses JSON payload to decode and apply changes
public struct DefaultEntityApplier<T: EntityProtocol & SQLiteCodable & Decodable>: EntityApplier {
    public static var entityType: String { T.tableName }

    public init() {}

    public func apply(change: SyncChange, to connection: SQLiteConnection) throws {
        switch change.operation {
        case .insert, .update:
            guard let payload = change.payload,
                  let data = payload.data(using: .utf8) else {
                throw SyncError.invalidPayload("Missing or invalid payload for \(change.operation)")
            }

            let decoder = JSONDecoder()
            let entity = try decoder.decode(T.self, from: data)

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
        let excludedFromSet = Set(syncKeyCols + ["created_at", "updated_at"])
        let setColumns = allColumns.filter { !excludedFromSet.contains($0) }

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
public final class EntityApplierRegistry: Sendable {
    private let appliers: [String: any EntityApplier]

    public init(_ appliers: [any EntityApplier] = []) {
        self.appliers = Dictionary(uniqueKeysWithValues: appliers.map { (type(of: $0).entityType, $0) })
    }

    /// Number of registered appliers
    public var count: Int { appliers.count }

    /// Create a registry from entity types
    /// Automatically generates DefaultEntityApplier for each type
    public convenience init(entityTypes: [any EntityProtocol.Type]) {
        let appliers = entityTypes.map { $0.makeApplier() }
        self.init(appliers)
    }

    /// Get applier for entity type
    private func applier(for entityType: String) -> (any EntityApplier)? {
        return appliers[entityType]
    }

    /// Apply a change using the appropriate applier
    public func apply(change: SyncChange, to connection: SQLiteConnection) throws {
        guard let applier = applier(for: change.entityType) else {
            throw SyncError.unknownEntityType(change.entityType)
        }
        try applier.apply(change: change, to: connection)
    }
}
