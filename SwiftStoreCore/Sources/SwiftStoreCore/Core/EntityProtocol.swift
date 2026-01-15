import Foundation
import SwiftStoreProtocols

// Re-export core types from SwiftStoreProtocols
// (These are also @_exported via SwiftStore.swift)

// MARK: - Instance CRUD Extensions for EntityProtocol

public extension EntityProtocol {
    /// Insert this entity into the database
    /// Timestamps (created_at, updated_at) are set automatically by DEFAULT values
    /// - Parameter connection: The database connection
    func insert(_ connection: SQLiteConnection) throws {
        try connection.insert(self)
    }
}

public extension EntityProtocol where Self: Identifiable, Self.ID: SQLiteValueComparable {
    /// Update this entity in the database (only available for entities with id field)
    /// Timestamp (updated_at) is set automatically by trigger
    /// - Parameter connection: The database connection
    func update(_ connection: SQLiteConnection) throws {
        try connection.update(self)
    }

    /// Delete this entity from the database (only available for entities with id field)
    /// - Parameter connection: The database connection
    func delete(_ connection: SQLiteConnection) throws {
        try connection.delete(self)
    }

    /// Save this entity (insert if new, update if exists)
    /// - Parameter connection: The database connection
    func save(_ connection: SQLiteConnection) throws {
        if try Self.filter(id: id).exists(connection) {
            try update(connection)
        } else {
            try insert(connection)
        }
    }

    /// Reload this entity from the database
    /// - Parameter connection: The database connection
    /// - Returns: The reloaded entity, or nil if not found
    func reload(_ connection: SQLiteConnection) throws -> Self? {
        try connection.get(Self.self, id: id)
    }
}

// MARK: - Static CRUD Extensions for EntityProtocol

public extension EntityProtocol where Self: Identifiable, Self.ID: SQLiteValueComparable {
    /// Get entity by ID
    /// - Parameters:
    ///   - id: The entity ID
    ///   - connection: The database connection
    /// - Returns: The entity if found, nil otherwise
    static func find(_ id: Self.ID, _ connection: SQLiteConnection) throws -> Self? {
        try connection.get(Self.self, id: id)
    }

    /// Get entity by ID, throwing if not found
    /// - Parameters:
    ///   - id: The entity ID
    ///   - connection: The database connection
    /// - Returns: The entity
    /// - Throws: StoreError.entityNotFound if not found
    static func get(_ id: Self.ID, _ connection: SQLiteConnection) throws -> Self {
        guard let entity = try find(id, connection) else {
            throw StoreError.entityNotFound(try id.sqliteEncode())
        }
        return entity
    }

    /// Delete entity by ID
    /// - Parameters:
    ///   - id: The entity ID
    ///   - connection: The database connection
    static func delete(_ id: Self.ID, _ connection: SQLiteConnection) throws {
        try connection.delete(Self.self, id: id)
    }
}

public extension EntityProtocol {
    /// Get all entities
    /// - Parameter connection: The database connection
    /// - Returns: Array of all entities
    static func all(_ connection: SQLiteConnection) throws -> [Self] {
        try Query(Self.self).all(connection)
    }

    /// Get count of all entities
    /// - Parameter connection: The database connection
    /// - Returns: Total count
    static func count(_ connection: SQLiteConnection) throws -> Int {
        try Query(Self.self).count(connection)
    }

    /// Check if any entities exist
    /// - Parameter connection: The database connection
    /// - Returns: True if at least one entity exists
    static func exists(_ connection: SQLiteConnection) throws -> Bool {
        try count(connection) > 0
    }

    /// Get the first entity
    /// - Parameter connection: The database connection
    /// - Returns: The first entity, or nil if none exist
    static func first(_ connection: SQLiteConnection) throws -> Self? {
        try Query(Self.self).first(connection)
    }

    /// Delete all entities
    /// - Parameter connection: The database connection
    /// - Returns: Number of deleted entities
    @discardableResult
    static func deleteAll(_ connection: SQLiteConnection) throws -> Int {
        try Query(Self.self).deleteAll(connection)
    }
}

// MARK: - Query Extensions for EntityProtocol

public extension EntityProtocol {
    /// Create a new Query for this entity type
    static func filter() -> Query<Self> {
        Query(Self.self)
    }

    /// Add a WHERE predicate
    static func filter(_ predicate: Predicate<Self>) -> Query<Self> {
        Query(Self.self).filter(predicate)
    }

    /// Add a WHERE predicate using closure with dynamic member lookup
    /// Usage: `TestUser.filter { $0.age >= 25 }`
    static func filter(_ buildPredicate: (Columns<Self>) -> Predicate<Self>) -> Query<Self> {
        Query(Self.self).filter(buildPredicate)
    }
}

// MARK: - Identifiable Entity Extensions

public extension EntityProtocol where Self: Identifiable, Self.ID: SQLiteValueComparable {
    /// Filter by primary key (only available for entities with id field)
    static func filter(id: ID) -> Query<Self> {
        Query(Self.self).filter(id: id)
    }

    /// Filter by multiple primary keys (only available for entities with id field)
    static func filter(ids: [ID]) -> Query<Self> {
        Query(Self.self).filter(ids: ids)
    }
}
