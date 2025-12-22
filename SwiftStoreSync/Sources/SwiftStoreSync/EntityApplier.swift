import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker

/// Protocol for entities that can be synced
/// Entities conforming to this protocol can automatically generate their EntityApplier
public protocol SyncableEntity: EntityProtocol, SQLiteCodable, Decodable {
    /// Create an applier for this entity type
    static func makeApplier() -> any EntityApplier
}

/// Default implementation uses DefaultEntityApplier
public extension SyncableEntity {
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

            // Check if entity exists
            let existing = try T.filter(id: change.entityId).first(connection)
            if existing != nil {
                try connection.update(entity)
            } else {
                try connection.insert(entity)
            }

        case .delete:
            let sql: SQL = "DELETE FROM \(raw: T.tableName) WHERE id = \(change.entityId)"
            try connection.execute(sql)
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

    /// Create a registry from syncable entity types
    /// Automatically generates DefaultEntityApplier for each type
    public convenience init(syncableEntities: [any SyncableEntity.Type]) {
        let appliers = syncableEntities.map { $0.makeApplier() }
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
