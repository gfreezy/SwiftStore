import XCTest
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacrosImpl

final class EntityMacroComprehensiveTests: XCTestCase {

    /// Comprehensive test covering:
    /// - Properties with default values (count, tags, metadata)
    /// - Optional properties (score, profile)
    /// - Required properties without default (name, settings)
    /// - Embedded struct types (settings, profile, metadata)
    /// - Built-in defaults (id, createdAt, updatedAt)
    func testEntityWithAllPropertyTypes() {
        assertMacroExpansion(
            """
            @Entity
            struct TestEntity {
                let id: UUIDV7
                var name: String
                var count: Int = 0
                var score: Double? = 2.0
                var tags: [String] = []
                var settings: UserSettings
                var profile: Profile?
                var metadata: Metadata = Metadata()
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct TestEntity {
                let id: UUIDV7
                var name: String
                var count: Int = 0
                var score: Double? = 2.0
                var tags: [String] = []
                var settings: UserSettings
                var profile: Profile?
                var metadata: Metadata = Metadata()
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "test_entity"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "count", type: .integer, defaultValue: "0"),
                        ColumnDefinition(name: "score", type: .real, nullable: true, defaultValue: "2.0"),
                        ColumnDefinition(name: "tags", type: .text, defaultValue: "'[]'", isJSONEncoded: true),
                        ColumnDefinition(name: "settings", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "profile", type: .text, nullable: true, isJSONEncoded: true),
                        ColumnDefinition(name: "metadata", type: .text, defaultValue: "'{}'", isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                    result["name"] = try self.name.sqliteEncode()
                    result["count"] = try self.count.sqliteEncode()
                    result["score"] = try self.score.sqliteEncode()
                    result["tags"] = try self.tags.sqliteEncode()
                    result["settings"] = try self.settings.sqliteEncode()
                    result["profile"] = try self.profile.sqliteEncode()
                    result["metadata"] = try self.metadata.sqliteEncode()
                    result["created_at"] = try self.createdAt.sqliteEncode()
                    result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    var _id: UUIDV7
                    do {
                        _id = try UUIDV7(from: statement.columnValue(Int32(0), type: .blob))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.id': %{public}@", String(describing: error))
                        _id = UUIDV7()
                    }
                    let _name = try String(from: statement.columnValue(Int32(1), type: .text))
                    var _count: Int
                    do {
                        _count = try Int(from: statement.columnValue(Int32(2), type: .integer))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.count': %{public}@", String(describing: error))
                        _count = 0
                    }
                    var _score: Optional<Double>
                    do {
                        _score = try Optional<Double>(from: statement.columnValue(Int32(3), type: .real))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.score': %{public}@", String(describing: error))
                        _score = 2.0
                    }
                    var _tags: [String]
                    do {
                        _tags = try [String](from: statement.columnValue(Int32(4), type: .text))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.tags': %{public}@", String(describing: error))
                        _tags = []
                    }
                    let _settings = try UserSettings(from: statement.columnValue(Int32(5), type: .text))
                    let _profile = try Optional<Profile>(from: statement.columnValue(Int32(6), type: .text))
                    var _metadata: Metadata
                    do {
                        _metadata = try Metadata(from: statement.columnValue(Int32(7), type: .text))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.metadata': %{public}@", String(describing: error))
                        _metadata = Metadata()
                    }
                    var _createdAt: Date
                    do {
                        _createdAt = try Date(from: statement.columnValue(Int32(8), type: .real))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.createdAt': %{public}@", String(describing: error))
                        _createdAt = Date()
                    }
                    var _updatedAt: Date
                    do {
                        _updatedAt = try Date(from: statement.columnValue(Int32(9), type: .real))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.updatedAt': %{public}@", String(describing: error))
                        _updatedAt = Date()
                    }
                    return Self(id: _id, name: _name, count: _count, score: _score, tags: _tags, settings: _settings, profile: _profile, metadata: _metadata, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV7 = UUIDV7(),
                    name: String,
                    count: Int = 0,
                    score: Double? = 2.0,
                    tags: [String] = [],
                    settings: UserSettings,
                    profile: Profile?,
                    metadata: Metadata = Metadata(),
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.name = name
                    self.count = count
                    self.score = score
                    self.tags = tags
                    self.settings = settings
                    self.profile = profile
                    self.metadata = metadata
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case count
                    case score
                    case tags
                    case settings
                    case profile
                    case metadata
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    do {
                        self.id = try container.decode(UUIDV7.self, forKey: .id)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.id': %{public}@", String(describing: error))
                        self.id = UUIDV7()
                    }
                    self.name = try container.decode(String.self, forKey: .name)
                    do {
                        self.count = try container.decode(Int.self, forKey: .count)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.count': %{public}@", String(describing: error))
                        self.count = 0
                    }
                    do {
                        self.score = try container.decodeIfPresent(Double.self, forKey: .score)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.score': %{public}@", String(describing: error))
                        self.score = 2.0
                    }
                    do {
                        self.tags = try container.decode([String].self, forKey: .tags)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.tags': %{public}@", String(describing: error))
                        self.tags = []
                    }
                    self.settings = try Self._decodeNested(UserSettings.self, from: container, forKey: .settings)
                    self.profile = try Self._decodeNestedIfPresent(Profile.self, from: container, forKey: .profile)
                    do {
                        self.metadata = try Self._decodeNested(Metadata.self, from: container, forKey: .metadata)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.metadata': %{public}@", String(describing: error))
                        self.metadata = Metadata()
                    }
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.createdAt': %{public}@", String(describing: error))
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'TestEntity.updatedAt': %{public}@", String(describing: error))
                        self.updatedAt = Date()
                    }
                }


                /// Helper to decode nested types with Embedded constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNested<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                    try container.decode(T.self, forKey: key)
                }

                /// Helper to decode optional nested types with Embedded constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNestedIfPresent<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                    try container.decodeIfPresent(T.self, forKey: key)
                }
            }

            extension TestEntity: EntityProtocol {
            }

            extension TestEntity: Identifiable {
            }

            extension TestEntity: Sendable {
            }

            extension TestEntity: Equatable {
            }

            extension TestEntity: Hashable {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - SyncKey Tests

    /// Test Entity with single-field SyncKey
    func testEntityWithSingleFieldSyncKey() {
        assertMacroExpansion(
            """
            @Entity
            struct Customer {
                #SyncKey<Customer>(\\.email)
                var email: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
            }
            """,
            expandedSource: """
            struct Customer {
                var email: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

                public static var tableName: String {
                    "customer"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "email", type: .text, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["email"] = try self.email.sqliteEncode()
                    result["name"] = try self.name.sqliteEncode()
                    result["created_at"] = try self.createdAt.sqliteEncode()
                    result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _email = try String(from: statement.columnValue(Int32(0), type: .text))
                    let _name = try String(from: statement.columnValue(Int32(1), type: .text))
                    var _createdAt: Date
                    do {
                        _createdAt = try Date(from: statement.columnValue(Int32(2), type: .real))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Customer.createdAt': %{public}@", String(describing: error))
                        _createdAt = Date()
                    }
                    var _updatedAt: Date
                    do {
                        _updatedAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Customer.updatedAt': %{public}@", String(describing: error))
                        _updatedAt = Date()
                    }
                    return Self(email: _email, name: _name, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["email"]
                }

                public init(
                    email: String,
                    name: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.email = email
                    self.name = name
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case email
                    case name
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.email = try container.decode(String.self, forKey: .email)
                    self.name = try container.decode(String.self, forKey: .name)
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Customer.createdAt': %{public}@", String(describing: error))
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Customer.updatedAt': %{public}@", String(describing: error))
                        self.updatedAt = Date()
                    }
                }

                public var id: String {
                    email
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_customer_sync_key", columns: ["email"], unique: true)
                    ]
                }
            }

            extension Customer: EntityProtocol {
            }

            extension Customer: Identifiable {
            }

            extension Customer: Sendable {
            }

            extension Customer: Equatable {
            }

            extension Customer: Hashable {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Index Tests

    /// Test Entity with single-field Index
    func testEntityWithSingleIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct Product {
                #Index<Product>(\\.sku)
                var id: UUIDV7 = UUIDV7()
                var sku: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
            }
            """,
            expandedSource: """
            struct Product {
                var id: UUIDV7 = UUIDV7()
                var sku: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

                public static var tableName: String {
                    "product"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "sku", type: .text),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                    result["sku"] = try self.sku.sqliteEncode()
                    result["name"] = try self.name.sqliteEncode()
                    result["created_at"] = try self.createdAt.sqliteEncode()
                    result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    var _id: UUIDV7
                    do {
                        _id = try UUIDV7(from: statement.columnValue(Int32(0), type: .blob))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Product.id': %{public}@", String(describing: error))
                        _id = UUIDV7()
                    }
                    let _sku = try String(from: statement.columnValue(Int32(1), type: .text))
                    let _name = try String(from: statement.columnValue(Int32(2), type: .text))
                    var _createdAt: Date
                    do {
                        _createdAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Product.createdAt': %{public}@", String(describing: error))
                        _createdAt = Date()
                    }
                    var _updatedAt: Date
                    do {
                        _updatedAt = try Date(from: statement.columnValue(Int32(4), type: .real))
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Product.updatedAt': %{public}@", String(describing: error))
                        _updatedAt = Date()
                    }
                    return Self(id: _id, sku: _sku, name: _name, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV7 = UUIDV7(),
                    sku: String,
                    name: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.sku = sku
                    self.name = name
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case sku
                    case name
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    do {
                        self.id = try container.decode(UUIDV7.self, forKey: .id)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Product.id': %{public}@", String(describing: error))
                        self.id = UUIDV7()
                    }
                    self.sku = try container.decode(String.self, forKey: .sku)
                    self.name = try container.decode(String.self, forKey: .name)
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Product.createdAt': %{public}@", String(describing: error))
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        os_log(.error, "SwiftStore: Failed to decode 'Product.updatedAt': %{public}@", String(describing: error))
                        self.updatedAt = Date()
                    }
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_product_sku", columns: ["sku"])
                    ]
                }
            }

            extension Product: EntityProtocol {
            }

            extension Product: Identifiable {
            }

            extension Product: Sendable {
            }

            extension Product: Equatable {
            }

            extension Product: Hashable {
            }
            """,
            macros: testMacros
        )
    }
}
