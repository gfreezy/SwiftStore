import Foundation
import SwiftStoreProtocols
import SwiftStoreMacros
@testable import SwiftStoreCore

// MARK: - Test Store Helper

/// Test store wrapper that provides connection and migration functionality
struct TestStore {
    let connection: SQLiteConnection
    let migrator: Migrator
    let dbPath: String

    // Track registered entities for planMigrations
    private var registeredEntities: [any EntityProtocol.Type] = []

    init(path: String, trackDeletes: Bool = false) throws {
        self.dbPath = path
        var options = SQLiteConnection.Options()
        options.walMode = true
        self.connection = try SQLiteConnection(path: path, options: options)
        self.migrator = Migrator(connection: connection, trackDeletes: trackDeletes)
    }

    mutating func register<E: EntityProtocol>(_ type: E.Type) throws {
        registeredEntities.append(type)
    }

    func migrate(entities: [any EntityProtocol.Type]) throws {
        let plan = try migrator.plan(for: entities)
        try migrator.apply(plan)
    }

    func migrate() throws {
        try migrate(entities: registeredEntities)
    }

    func fetch<E: EntityProtocol>(_ type: E.Type) -> Query<E> {
        Query(E.self)
    }

    func planMigration<E: EntityProtocol>(for type: E.Type) throws -> MigrationPlan {
        try migrator.plan(for: [type])
    }

    func planMigrations() throws -> MigrationPlan {
        try migrator.plan(for: registeredEntities)
    }
}

/// Create a temporary store for testing
/// The database file is automatically created in the temp directory
func createTestStore() throws -> TestStore {
    let tempPath = NSTemporaryDirectory() + "swiftstore_test_\(UUID().uuidString).sqlite"
    return try TestStore(path: tempPath)
}

func createTestConnectionAndMigrate() throws -> SQLiteConnection {
    let tempPath = NSTemporaryDirectory() + "swiftstore_test_\(UUID().uuidString).sqlite"
    return try SQLiteConnection(path: tempPath)
}

// MARK: - Test Helper Types

struct Address: Codable, Sendable {
    var street: String
    var city: String
    var zipCode: String
}

// MARK: - Test Entities using @Entity macro

@Entity(tableName: "test_user")
struct TestUser {
    #Index<Self>(\.email, unique: true)
    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    var address: Address
    let createdAt: Date
    let updatedAt: Date
}

@Entity(tableName: "test_tag")
struct TestTag {
    let id: UUIDV4
    var name: String
    let createdAt: Date
    let updatedAt: Date
}

@Entity(tableName: "test_user_tags")
struct TestUserTags {
    #Index<Self>(\.userId, \.tagId, unique: true, name: "idx_test_user_tags_unique")
    let id: UUIDV4
    let userId: UUIDV4
    let tagId: UUIDV4
    let createdAt: Date
    let updatedAt: Date
}
