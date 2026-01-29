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
    /// - let properties without defaults (id, createdAt, updatedAt)
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
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
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
                    let _id = try UUIDV7(from: statement.columnValue(Int32(0), type: .blob))
                    let _name = try String(from: statement.columnValue(Int32(1), type: .text))
                    var _count: Int
                    do {
                        _count = try Int(from: statement.columnValue(Int32(2), type: .integer))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'TestEntity.count': \\(error)")
                        _count = 0
                    }
                    var _score: Optional<Double>
                    do {
                        _score = try Optional<Double>(from: statement.columnValue(Int32(3), type: .real))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'TestEntity.score': \\(error)")
                        _score = 2.0
                    }
                    var _tags: [String]
                    do {
                        _tags = try [String](from: statement.columnValue(Int32(4), type: .text))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'TestEntity.tags': \\(error)")
                        _tags = []
                    }
                    let _settings = try UserSettings(from: statement.columnValue(Int32(5), type: .text))
                    let _profile = try Optional<Profile>(from: statement.columnValue(Int32(6), type: .text))
                    var _metadata: Metadata
                    do {
                        _metadata = try Metadata(from: statement.columnValue(Int32(7), type: .text))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'TestEntity.metadata': \\(error)")
                        _metadata = Metadata()
                    }
                    let _createdAt = try Date(from: statement.columnValue(Int32(8), type: .real))
                    let _updatedAt = try Date(from: statement.columnValue(Int32(9), type: .real))
                    return Self(id: _id, name: _name, count: _count, score: _score, tags: _tags, settings: _settings, profile: _profile, metadata: _metadata, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public static var isReadonly: Bool {
                    false
                }

                public init(
                    id: UUIDV7,
                    name: String,
                    count: Int = 0,
                    score: Double? = 2.0,
                    tags: [String] = [],
                    settings: UserSettings,
                    profile: Profile?,
                    metadata: Metadata = Metadata(),
                    createdAt: Date,
                    updatedAt: Date
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
            }

            extension TestEntity: EntityProtocol {
            }

            extension TestEntity: Decodable {
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
                    self.id = try container.decode(UUIDV7.self, forKey: .id)
                    self.name = try container.decode(String.self, forKey: .name)
                    do {
                        self.count = try container.decode(Int.self, forKey: .count)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'TestEntity.count': \\(error)")
                        self.count = 0
                    }
                    do {
                        self.score = try container.decodeIfPresent(Double.self, forKey: .score)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'TestEntity.score': \\(error)")
                        self.score = 2.0
                    }
                    do {
                        self.tags = try container.decode([String].self, forKey: .tags)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'TestEntity.tags': \\(error)")
                        self.tags = []
                    }
                    self.settings = try Self._decodeNested(UserSettings.self, from: container, forKey: .settings)
                    self.profile = try Self._decodeNestedIfPresent(Profile.self, from: container, forKey: .profile)
                    do {
                        self.metadata = try Self._decodeNested(Metadata.self, from: container, forKey: .metadata)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'TestEntity.metadata': \\(error)")
                        self.metadata = Metadata()
                    }
                    self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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

            extension TestEntity: Encodable {
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
                        SwiftStoreLogger.error("Failed to decode 'Customer.createdAt': \\(error)")
                        _createdAt = Date()
                    }
                    var _updatedAt: Date
                    do {
                        _updatedAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Customer.updatedAt': \\(error)")
                        _updatedAt = Date()
                    }
                    return Self(email: _email, name: _name, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["email"]
                }

                public static var isReadonly: Bool {
                    false
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

            extension Customer: Decodable {
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
                        SwiftStoreLogger.error("Failed to decode 'Customer.createdAt': \\(error)")
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Customer.updatedAt': \\(error)")
                        self.updatedAt = Date()
                    }
                }

            }

            extension Customer: Encodable {
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
                        SwiftStoreLogger.error("Failed to decode 'Product.id': \\(error)")
                        _id = UUIDV7()
                    }
                    let _sku = try String(from: statement.columnValue(Int32(1), type: .text))
                    let _name = try String(from: statement.columnValue(Int32(2), type: .text))
                    var _createdAt: Date
                    do {
                        _createdAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Product.createdAt': \\(error)")
                        _createdAt = Date()
                    }
                    var _updatedAt: Date
                    do {
                        _updatedAt = try Date(from: statement.columnValue(Int32(4), type: .real))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Product.updatedAt': \\(error)")
                        _updatedAt = Date()
                    }
                    return Self(id: _id, sku: _sku, name: _name, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public static var isReadonly: Bool {
                    false
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

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_product_sku", columns: ["sku"])
                    ]
                }
            }

            extension Product: EntityProtocol {
            }

            extension Product: Decodable {
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
                        SwiftStoreLogger.error("Failed to decode 'Product.id': \\(error)")
                        self.id = UUIDV7()
                    }
                    self.sku = try container.decode(String.self, forKey: .sku)
                    self.name = try container.decode(String.self, forKey: .name)
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Product.createdAt': \\(error)")
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Product.updatedAt': \\(error)")
                        self.updatedAt = Date()
                    }
                }

            }

            extension Product: Encodable {
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

    // MARK: - Readonly Entity Tests

    /// Test Entity with readonly = true and Int id
    func testReadonlyEntityWithIntId() {
        assertMacroExpansion(
            """
            @Entity(readonly: true)
            struct LocalConfig {
                var id: Int
                var key: String
                var value: String
            }
            """,
            expandedSource: """
            struct LocalConfig {
                var id: Int
                var key: String
                var value: String

                public static var tableName: String {
                    "local_config"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .integer, primaryKey: true),
                        ColumnDefinition(name: "key", type: .text),
                        ColumnDefinition(name: "value", type: .text)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                    result["key"] = try self.key.sqliteEncode()
                    result["value"] = try self.value.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = try Int(from: statement.columnValue(Int32(0), type: .integer))
                    let _key = try String(from: statement.columnValue(Int32(1), type: .text))
                    let _value = try String(from: statement.columnValue(Int32(2), type: .text))
                    return Self(id: _id, key: _key, value: _value)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public static var isReadonly: Bool {
                    true
                }

                public init(
                    id: Int,
                    key: String,
                    value: String
                ) {
                    self.id = id
                    self.key = key
                    self.value = value
                }
            }

            extension LocalConfig: EntityProtocol {
            }

            extension LocalConfig: Decodable {
                private enum CodingKeys: String, CodingKey {
                    case id
                    case key
                    case value
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decode(Int.self, forKey: .id)
                    self.key = try container.decode(String.self, forKey: .key)
                    self.value = try container.decode(String.self, forKey: .value)
                }

            }

            extension LocalConfig: Encodable {
            }

            extension LocalConfig: Identifiable {
            }

            extension LocalConfig: Sendable {
            }

            extension LocalConfig: Equatable {
            }

            extension LocalConfig: Hashable {
            }
            """,
            macros: testMacros
        )
    }

    /// Test Entity with readonly = true and String id
    func testReadonlyEntityWithStringId() {
        assertMacroExpansion(
            """
            @Entity(readonly: true)
            struct CacheEntry {
                var id: String
                var data: String
                var expiresAt: Double?
            }
            """,
            expandedSource: """
            struct CacheEntry {
                var id: String
                var data: String
                var expiresAt: Double?

                public static var tableName: String {
                    "cache_entry"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .text, primaryKey: true),
                        ColumnDefinition(name: "data", type: .text),
                        ColumnDefinition(name: "expires_at", type: .real, nullable: true)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                    result["data"] = try self.data.sqliteEncode()
                    result["expires_at"] = try self.expiresAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = try String(from: statement.columnValue(Int32(0), type: .text))
                    let _data = try String(from: statement.columnValue(Int32(1), type: .text))
                    let _expiresAt = try Optional<Double>(from: statement.columnValue(Int32(2), type: .real))
                    return Self(id: _id, data: _data, expiresAt: _expiresAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public static var isReadonly: Bool {
                    true
                }

                public init(
                    id: String,
                    data: String,
                    expiresAt: Double?
                ) {
                    self.id = id
                    self.data = data
                    self.expiresAt = expiresAt
                }
            }

            extension CacheEntry: EntityProtocol {
            }

            extension CacheEntry: Decodable {
                private enum CodingKeys: String, CodingKey {
                    case id
                    case data
                    case expiresAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decode(String.self, forKey: .id)
                    self.data = try container.decode(String.self, forKey: .data)
                    self.expiresAt = try container.decodeIfPresent(Double.self, forKey: .expiresAt)
                }

            }

            extension CacheEntry: Encodable {
            }

            extension CacheEntry: Identifiable {
            }

            extension CacheEntry: Sendable {
            }

            extension CacheEntry: Equatable {
            }

            extension CacheEntry: Hashable {
            }
            """,
            macros: testMacros
        )
    }

    /// Test Entity with readonly = true with optional timestamps
    func testReadonlyEntityWithOptionalTimestamps() {
        assertMacroExpansion(
            """
            @Entity(readonly: true)
            struct ExternalData {
                var id: Int
                var name: String
                var createdAt: Date?
                var modifiedAt: Date?
            }
            """,
            expandedSource: """
            struct ExternalData {
                var id: Int
                var name: String
                var createdAt: Date?
                var modifiedAt: Date?

                public static var tableName: String {
                    "external_data"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .integer, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, nullable: true),
                        ColumnDefinition(name: "modified_at", type: .real, nullable: true)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                    result["name"] = try self.name.sqliteEncode()
                    result["created_at"] = try self.createdAt.sqliteEncode()
                    result["modified_at"] = try self.modifiedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = try Int(from: statement.columnValue(Int32(0), type: .integer))
                    let _name = try String(from: statement.columnValue(Int32(1), type: .text))
                    let _createdAt = try Optional<Date>(from: statement.columnValue(Int32(2), type: .real))
                    let _modifiedAt = try Optional<Date>(from: statement.columnValue(Int32(3), type: .real))
                    return Self(id: _id, name: _name, createdAt: _createdAt, modifiedAt: _modifiedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public static var isReadonly: Bool {
                    true
                }

                public init(
                    id: Int,
                    name: String,
                    createdAt: Date?,
                    modifiedAt: Date?
                ) {
                    self.id = id
                    self.name = name
                    self.createdAt = createdAt
                    self.modifiedAt = modifiedAt
                }
            }

            extension ExternalData: EntityProtocol {
            }

            extension ExternalData: Decodable {
                private enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case createdAt
                    case modifiedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decode(Int.self, forKey: .id)
                    self.name = try container.decode(String.self, forKey: .name)
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
                    self.modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
                }

            }

            extension ExternalData: Encodable {
            }

            extension ExternalData: Identifiable {
            }

            extension ExternalData: Sendable {
            }

            extension ExternalData: Equatable {
            }

            extension ExternalData: Hashable {
            }
            """,
            macros: testMacros
        )
    }

    /// Test Entity with readonly = true and custom table name
    func testReadonlyEntityWithCustomTableName() {
        assertMacroExpansion(
            """
            @Entity(tableName: "app_settings", readonly: true)
            struct Settings {
                var id: String
                var theme: String = "light"
                var fontSize: Int = 14
            }
            """,
            expandedSource: """
            struct Settings {
                var id: String
                var theme: String = "light"
                var fontSize: Int = 14

                public static var tableName: String {
                    "app_settings"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .text, primaryKey: true),
                        ColumnDefinition(name: "theme", type: .text, defaultValue: "'light'"),
                        ColumnDefinition(name: "font_size", type: .integer, defaultValue: "14")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                    result["theme"] = try self.theme.sqliteEncode()
                    result["font_size"] = try self.fontSize.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = try String(from: statement.columnValue(Int32(0), type: .text))
                    var _theme: String
                    do {
                        _theme = try String(from: statement.columnValue(Int32(1), type: .text))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Settings.theme': \\(error)")
                        _theme = "light"
                    }
                    var _fontSize: Int
                    do {
                        _fontSize = try Int(from: statement.columnValue(Int32(2), type: .integer))
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Settings.fontSize': \\(error)")
                        _fontSize = 14
                    }
                    return Self(id: _id, theme: _theme, fontSize: _fontSize)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public static var isReadonly: Bool {
                    true
                }

                public init(
                    id: String,
                    theme: String = "light",
                    fontSize: Int = 14
                ) {
                    self.id = id
                    self.theme = theme
                    self.fontSize = fontSize
                }
            }

            extension Settings: EntityProtocol {
            }

            extension Settings: Decodable {
                private enum CodingKeys: String, CodingKey {
                    case id
                    case theme
                    case fontSize
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decode(String.self, forKey: .id)
                    do {
                        self.theme = try container.decode(String.self, forKey: .theme)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Settings.theme': \\(error)")
                        self.theme = "light"
                    }
                    do {
                        self.fontSize = try container.decode(Int.self, forKey: .fontSize)
                    } catch {
                        SwiftStoreLogger.error("Failed to decode 'Settings.fontSize': \\(error)")
                        self.fontSize = 14
                    }
                }

            }

            extension Settings: Encodable {
            }

            extension Settings: Identifiable {
            }

            extension Settings: Sendable {
            }

            extension Settings: Equatable {
            }

            extension Settings: Hashable {
            }
            """,
            macros: testMacros
        )
    }

    /// Test standard Entity (readonly = false) still generates isReadonly = false
    func testStandardEntityHasIsReadonlyFalse() {
        assertMacroExpansion(
            """
            @Entity
            struct StandardEntity {
                var id: UUIDV7
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct StandardEntity {
                var id: UUIDV7
                var name: String
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "standard_entity"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                    result["name"] = try self.name.sqliteEncode()
                    result["created_at"] = try self.createdAt.sqliteEncode()
                    result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = try UUIDV7(from: statement.columnValue(Int32(0), type: .blob))
                    let _name = try String(from: statement.columnValue(Int32(1), type: .text))
                    let _createdAt = try Date(from: statement.columnValue(Int32(2), type: .real))
                    let _updatedAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                    return Self(id: _id, name: _name, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public static var isReadonly: Bool {
                    false
                }

                public init(
                    id: UUIDV7,
                    name: String,
                    createdAt: Date,
                    updatedAt: Date
                ) {
                    self.id = id
                    self.name = name
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }
            }

            extension StandardEntity: EntityProtocol {
            }

            extension StandardEntity: Decodable {
                private enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decode(UUIDV7.self, forKey: .id)
                    self.name = try container.decode(String.self, forKey: .name)
                    self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                }

            }

            extension StandardEntity: Encodable {
            }

            extension StandardEntity: Identifiable {
            }

            extension StandardEntity: Sendable {
            }

            extension StandardEntity: Equatable {
            }

            extension StandardEntity: Hashable {
            }
            """,
            macros: testMacros
        )
    }
}
