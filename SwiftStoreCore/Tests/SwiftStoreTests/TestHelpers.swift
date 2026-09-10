import Foundation
import SwiftStoreProtocols
import SwiftStoreMacros
@testable import SwiftStoreCore

// MARK: - Test Store Helper

/// Test store wrapper that provides connection and migration functionality
struct TestStore {
    let connection: SQLiteConnection
    let dbPath: String

    // Entities used to create this disposable test database.
    private var registeredEntities: [any EntityProtocol.Type] = []

    init(path: String) throws {
        self.dbPath = path
        var options = SQLiteConnection.Options()
        options.walMode = true
        self.connection = try SQLiteConnection(path: path, options: options)
    }

    mutating func register<E: EntityProtocol>(_ type: E.Type) throws {
        registeredEntities.append(type)
    }

    func migrate(entities: [any EntityProtocol.Type]) throws {
        // Live types are safe here: these are disposable fixtures, not historical migrations.
        let snapshot = SchemaSnapshot(entities: entities)
        let initial = StoreMigration(id: "001_fixture", target: snapshot) { db in
            for sql in snapshot.creationStatements { try db.execute(sql) }
        }
        try VersionedMigrator(connection: connection, migrations: [initial]).migrate()
    }

    func migrate() throws {
        try migrate(entities: registeredEntities)
    }

    func fetch<E: EntityProtocol>(_ type: E.Type) -> Query<E> {
        Query(E.self)
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

@Embedded
struct Address: Sendable {
    var street: String = ""
    var city: String = ""
    var zipCode: String = ""
}

// MARK: - Test Entities using @Entity macro

@Entity(tableName: "test_user")
struct TestUser {
    #Index<Self>(\.email, unique: true)
    var id: UUIDV7 = UUIDV7()
    var name: String = ""
    var email: String = ""
    var age: Int?
    var address: Address = Address()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Entity(tableName: "test_tag")
struct TestTag {
    var id: UUIDV7 = UUIDV7()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Entity(tableName: "test_user_tags")
struct TestUserTags {
    #Index<Self>(\.userId, \.tagId, unique: true, name: "idx_test_user_tags_unique")
    var id: UUIDV7 = UUIDV7()
    var userId: UUIDV7 = UUIDV7()
    var tagId: UUIDV7 = UUIDV7()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
