import Foundation
import SwiftStoreProtocols
@testable import SwiftStoreCore

// MARK: - Test Store Helper

/// Test store wrapper that provides connection and migration functionality
struct TestStore {
    let connection: SQLiteConnection
    let migrationManager: MigrationManager
    let dbPath: String

    // Track registered entities for planMigrations
    private var registeredEntities: [any EntityProtocol.Type] = []

    init(path: String) throws {
        self.dbPath = path
        var options = SQLiteConnection.Options()
        options.walMode = true
        self.connection = try SQLiteConnection(path: path, options: options)
        self.migrationManager = MigrationManager(connection: connection)
    }

    mutating func register<E: EntityProtocol>(_ type: E.Type) throws {
        registeredEntities.append(type)
    }

    func migrate(entities: [any EntityProtocol.Type]) throws {
        try migrationManager.createSystemTables()
        for entityType in entities {
            try migrationManager.createTableForAnyType(entityType)
        }
        try migrationManager.createDeleteTriggers(for: entities.map { $0.tableName })
    }

    func migrate() throws {
        try migrate(entities: registeredEntities)
    }

    func fetch<E: EntityProtocol>(_ type: E.Type) -> Query<E> {
        Query(E.self)
    }

    func planMigration<E: EntityProtocol>(for type: E.Type) throws -> MigrationPlan {
        try migrationManager.planMigration(for: type)
    }

    func planMigrations() throws -> MigrationPlan {
        try migrationManager.planMigrations(for: registeredEntities)
    }

    func generateCreateTableSQL<E: EntityProtocol>(for type: E.Type) -> String {
        migrationManager.generateCreateTableSQL(for: type)
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

// MARK: - Manual Entity Implementations (for testing without macros)

struct TestUser: EntityProtocol, SQLiteCodable {
    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    var address: Address
    let createdAt: Date
    let updatedAt: Date

    static var tableName: String { "test_user" }

    static var columns: [ColumnDefinition] {
        [
            ColumnDefinition(name: "id", type: .blob, primaryKey: true),
            ColumnDefinition(name: "name", type: .text),
            ColumnDefinition(name: "email", type: .text),
            ColumnDefinition(name: "age", type: .integer, nullable: true),
            ColumnDefinition(name: "address", type: .text, isJSONEncoded: true),
            ColumnDefinition(name: "created_at", type: .real),
            ColumnDefinition(name: "updated_at", type: .real)
        ]
    }

    static var indexes: [IndexDefinition] {
        [
            IndexDefinition(name: "idx_test_user_email", columns: ["email"], unique: true)
        ]
    }

    func sqliteEncode() throws -> [String: SQLiteValue] {
        var result: [String: SQLiteValue] = [:]
        result["id"] = .blob(id.data)
        result["name"] = .text(name)
        result["email"] = .text(email)
        result["age"] = age.map { .integer(Int64($0)) } ?? .null
        let addressData = try JSONEncoder().encode(address)
        result["address"] = .text(String(data: addressData, encoding: .utf8)!)
        result["created_at"] = .real(createdAt.timeIntervalSince1970)
        result["updated_at"] = .real(updatedAt.timeIntervalSince1970)
        return result
    }

    static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> TestUser {
        let id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
        let name = statement.columnString(Int32(1)) ?? ""
        let email = statement.columnString(Int32(2)) ?? ""
        let age: Int? = statement.isNull(Int32(3)) ? nil : Int(statement.columnInt64(Int32(3)))
        let addressJSON = statement.columnString(Int32(4)) ?? "{}"
        let address = try JSONDecoder().decode(Address.self, from: addressJSON.data(using: .utf8)!)
        let createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(5)))
        let updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(6)))
        return TestUser(id: id, name: name, email: email, age: age, address: address, createdAt: createdAt, updatedAt: updatedAt)
    }
}

struct TestTag: EntityProtocol, SQLiteCodable {
    let id: UUIDV4
    var name: String
    let createdAt: Date
    let updatedAt: Date

    static var tableName: String { "test_tag" }

    static var columns: [ColumnDefinition] {
        [
            ColumnDefinition(name: "id", type: .blob, primaryKey: true),
            ColumnDefinition(name: "name", type: .text),
            ColumnDefinition(name: "created_at", type: .real),
            ColumnDefinition(name: "updated_at", type: .real)
        ]
    }

    func sqliteEncode() throws -> [String: SQLiteValue] {
        var result: [String: SQLiteValue] = [:]
        result["id"] = .blob(id.data)
        result["name"] = .text(name)
        result["created_at"] = .real(createdAt.timeIntervalSince1970)
        result["updated_at"] = .real(updatedAt.timeIntervalSince1970)
        return result
    }

    static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> TestTag {
        let id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
        let name = statement.columnString(Int32(1)) ?? ""
        let createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
        let updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
        return TestTag(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt)
    }
}

struct TestUserTags: EntityProtocol, RelationMarker, SQLiteCodable {
    let id: UUIDV4
    let userId: UUIDV4
    let tagId: UUIDV4
    let createdAt: Date
    let updatedAt: Date

    static var tableName: String { "test_user_tags" }

    static var columns: [ColumnDefinition] {
        [
            ColumnDefinition(name: "id", type: .blob, primaryKey: true),
            ColumnDefinition(name: "user_id", type: .blob),
            ColumnDefinition(name: "tag_id", type: .blob),
            ColumnDefinition(name: "created_at", type: .real),
            ColumnDefinition(name: "updated_at", type: .real)
        ]
    }

    static var foreignKeys: [ForeignKeyDefinition] {
        [
            ForeignKeyDefinition(column: "user_id", referencesTable: "test_user", referencesColumn: "id"),
            ForeignKeyDefinition(column: "tag_id", referencesTable: "test_tag", referencesColumn: "id")
        ]
    }

    static var indexes: [IndexDefinition] {
        [
            IndexDefinition(name: "idx_test_user_tags_unique", columns: ["user_id", "tag_id"], unique: true)
        ]
    }

    typealias FromEntity = TestUser
    typealias ToEntity = TestTag

    static var fromKeyPath: String { "userId" }
    static var toKeyPath: String { "tagId" }
    static var relationType: RelationType { .manyToMany }

    func sqliteEncode() throws -> [String: SQLiteValue] {
        var result: [String: SQLiteValue] = [:]
        result["id"] = .blob(id.data)
        result["user_id"] = .blob(userId.data)
        result["tag_id"] = .blob(tagId.data)
        result["created_at"] = .real(createdAt.timeIntervalSince1970)
        result["updated_at"] = .real(updatedAt.timeIntervalSince1970)
        return result
    }

    static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> TestUserTags {
        let id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
        let userId = UUIDV4(data: statement.columnData(Int32(1)) ?? Data()) ?? UUIDV4()
        let tagId = UUIDV4(data: statement.columnData(Int32(2)) ?? Data()) ?? UUIDV4()
        let createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
        let updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
        return TestUserTags(id: id, userId: userId, tagId: tagId, createdAt: createdAt, updatedAt: updatedAt)
    }
}
