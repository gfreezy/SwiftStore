import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacrosImpl

@Suite("Entity Macro Tests")
struct EntityMacroTests {
    @Test("Entity macro generates tableName, columns, encode and decode")
    func testEntityMacroExpansion() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                let id: UUIDV4
                var name: String
                var email: String
                var age: Int?
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {
                let id: UUIDV4
                var name: String
                var email: String
                var age: Int?
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "email", type: .text),
                        ColumnDefinition(name: "age", type: .integer, nullable: true),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["name"] = .text(self.name)
                    result["email"] = .text(self.email)
                    result["age"] = {
                            if let value = self.age {
                                return .integer(Int64(value))
                            } else {
                                return .null
                            }
                        }()
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _email = statement.columnString(Int32(2)) ?? ""
                    let _age = {
                            if statement.isNull(Int32(3)) {
                                return nil
                            }
                            return Int(statement.columnInt64(Int32(3)))
                        }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(5)))
                    return Self(
                        id: _id,
                        name: _name,
                        email: _email,
                        age: _age,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }
            }

            extension User: EntityProtocol {
            }

            extension User: SQLiteCodable {
            }

            extension User: Identifiable {
            }

            extension User: Sendable {
            }

            extension User: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity macro with nested Codable type generates JSON encode/decode")
    func testEntityWithNestedType() {
        assertMacroExpansion(
            """
            @Entity
            struct Profile {
                let id: UUIDV4
                var bio: String
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Profile {
                let id: UUIDV4
                var bio: String
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "profile"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "bio", type: .text),
                        ColumnDefinition(name: "settings", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["bio"] = .text(self.bio)
                    result["settings"] = {
                            let jsonData = try JSONEncoder().encode(self.settings)
                            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                                throw StoreError.encodingFailed("Failed to encode \\(self.settings) to JSON")
                            }
                            return .text(jsonString)
                        }()
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _bio = statement.columnString(Int32(1)) ?? ""
                    let _settings = {
                            guard let jsonString = statement.columnString(Int32(2)),
                                  let jsonData = jsonString.data(using: .utf8) else {
                                throw StoreError.decodingFailed("Failed to decode UserSettings from column 2")
                            }
                            return try JSONDecoder().decode(UserSettings.self, from: jsonData)
                        }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        bio: _bio,
                        settings: _settings,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }
            }

            extension Profile: EntityProtocol {
            }

            extension Profile: SQLiteCodable {
            }

            extension Profile: Identifiable {
            }

            extension Profile: Sendable {
            }

            extension Profile: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity macro converts CamelCase to snake_case for table name")
    func testTableNameConversion() {
        assertMacroExpansion(
            """
            @Entity
            struct UserProfile {
                let id: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserProfile {
                let id: UUIDV4
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user_profile"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(1)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    return Self(
                        id: _id,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }
            }

            extension UserProfile: EntityProtocol {
            }

            extension UserProfile: SQLiteCodable {
            }

            extension UserProfile: Identifiable {
            }

            extension UserProfile: Sendable {
            }

            extension UserProfile: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Nested Type Default Constraint Tests

    @Test("Entity with nested struct generates _decodeNested helper with Default constraint")
    func testEntityWithNestedStructGeneratesDefaultConstraintHelper() {
        // This test verifies that when an Entity has a nested struct type,
        // the generated init(from:) uses _decodeNested which requires T: Default & Decodable.
        // If the nested type doesn't have @Default, this will cause a compile error:
        // "Type 'NestedSettings' does not conform to protocol 'Default'"
        assertMacroExpansion(
            """
            @Entity
            struct UserWithSettings {
                let id: UUIDV4
                var name: String
                var settings: NestedSettings
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserWithSettings {
                let id: UUIDV4
                var name: String
                var settings: NestedSettings
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user_with_settings"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "settings", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["name"] = .text(self.name)
                    result["settings"] = try {
                            let jsonData = try JSONEncoder().encode(self.settings)
                            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                                throw StoreError.encodingFailed("Failed to encode \\(self.settings) to JSON")
                            }
                            return .text(jsonString)
                        }()
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _settings = try {
                            guard let jsonString = statement.columnString(Int32(2)),
                                  let jsonData = jsonString.data(using: .utf8) else {
                                throw StoreError.decodingFailed("Failed to decode NestedSettings from column 2")
                            }
                            return try JSONDecoder().decode(NestedSettings.self, from: jsonData)
                        }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        name: _name,
                        settings: _settings,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV4 = UUIDV4(),
                    name: String,
                    settings: NestedSettings,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.name = name
                    self.settings = settings
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case settings
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decodeIfPresent(UUIDV4.self, forKey: .id) ?? UUIDV4()
                    self.name = try container.decode(String.self, forKey: .name)
                    self.settings = try Self._decodeNested(NestedSettings.self, from: container, forKey: .settings)
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
                    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
                }

                /// Helper to decode nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNested<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                    try container.decode(T.self, forKey: key)
                }

                /// Helper to decode optional nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNestedIfPresent<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                    try container.decodeIfPresent(T.self, forKey: key)
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker {
                    _makeDefaultMacroMarker()
                }
            }

            extension UserWithSettings: EntityProtocol {
            }

            extension UserWithSettings: SQLiteCodable {
            }

            extension UserWithSettings: Identifiable {
            }

            extension UserWithSettings: Sendable {
            }

            extension UserWithSettings: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with optional nested struct generates _decodeNestedIfPresent helper with Default constraint")
    func testEntityWithOptionalNestedStructGeneratesDefaultConstraintHelper() {
        // This test verifies that when an Entity has an optional nested struct type,
        // the generated init(from:) uses _decodeNestedIfPresent which requires T: Default & Decodable.
        // If the nested type doesn't have @Default, this will cause a compile error.
        assertMacroExpansion(
            """
            @Entity
            struct UserWithOptionalSettings {
                let id: UUIDV4
                var name: String
                var settings: NestedSettings?
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserWithOptionalSettings {
                let id: UUIDV4
                var name: String
                var settings: NestedSettings?
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user_with_optional_settings"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "settings", type: .text, nullable: true, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["name"] = .text(self.name)
                    result["settings"] = try {
                            if let value = self.settings {
                                return try {
                            let jsonData = try JSONEncoder().encode(value)
                            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                                throw StoreError.encodingFailed("Failed to encode \\(value) to JSON")
                            }
                            return .text(jsonString)
                        }()
                            } else {
                                return .null
                            }
                        }()
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _settings = try {
                            if statement.isNull(Int32(2)) {
                                return Optional<NestedSettings>.none
                            }
                            return try {
                            guard let jsonString = statement.columnString(Int32(2)),
                                  let jsonData = jsonString.data(using: .utf8) else {
                                throw StoreError.decodingFailed("Failed to decode NestedSettings from column 2")
                            }
                            return try JSONDecoder().decode(NestedSettings.self, from: jsonData)
                        }()
                        }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        name: _name,
                        settings: _settings,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV4 = UUIDV4(),
                    name: String,
                    settings: NestedSettings? = nil,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.name = name
                    self.settings = settings
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case settings
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decodeIfPresent(UUIDV4.self, forKey: .id) ?? UUIDV4()
                    self.name = try container.decode(String.self, forKey: .name)
                    self.settings = try Self._decodeNestedIfPresent(NestedSettings.self, from: container, forKey: .settings)
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
                    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
                }

                /// Helper to decode nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNested<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                    try container.decode(T.self, forKey: key)
                }

                /// Helper to decode optional nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNestedIfPresent<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                    try container.decodeIfPresent(T.self, forKey: key)
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker {
                    _makeDefaultMacroMarker()
                }
            }

            extension UserWithOptionalSettings: EntityProtocol {
            }

            extension UserWithOptionalSettings: SQLiteCodable {
            }

            extension UserWithOptionalSettings: Identifiable {
            }

            extension UserWithOptionalSettings: Sendable {
            }

            extension UserWithOptionalSettings: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with nested enum generates _decodeNested helper with Default constraint")
    func testEntityWithNestedEnumGeneratesDefaultConstraintHelper() {
        // This test verifies that when an Entity has a nested enum type,
        // the generated init(from:) uses _decodeNested which requires T: Default & Decodable.
        // If the nested enum doesn't have @Default, this will cause a compile error.
        assertMacroExpansion(
            """
            @Entity
            struct TaskWithStatus {
                let id: UUIDV4
                var title: String
                var status: TaskStatus
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct TaskWithStatus {
                let id: UUIDV4
                var title: String
                var status: TaskStatus
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "task_with_status"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "title", type: .text),
                        ColumnDefinition(name: "status", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["title"] = .text(self.title)
                    result["status"] = try {
                            let jsonData = try JSONEncoder().encode(self.status)
                            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                                throw StoreError.encodingFailed("Failed to encode \\(self.status) to JSON")
                            }
                            return .text(jsonString)
                        }()
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _title = statement.columnString(Int32(1)) ?? ""
                    let _status = try {
                            guard let jsonString = statement.columnString(Int32(2)),
                                  let jsonData = jsonString.data(using: .utf8) else {
                                throw StoreError.decodingFailed("Failed to decode TaskStatus from column 2")
                            }
                            return try JSONDecoder().decode(TaskStatus.self, from: jsonData)
                        }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        title: _title,
                        status: _status,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV4 = UUIDV4(),
                    title: String,
                    status: TaskStatus,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.title = title
                    self.status = status
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case title
                    case status
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decodeIfPresent(UUIDV4.self, forKey: .id) ?? UUIDV4()
                    self.title = try container.decode(String.self, forKey: .title)
                    self.status = try Self._decodeNested(TaskStatus.self, from: container, forKey: .status)
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
                    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
                }

                /// Helper to decode nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNested<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                    try container.decode(T.self, forKey: key)
                }

                /// Helper to decode optional nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNestedIfPresent<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                    try container.decodeIfPresent(T.self, forKey: key)
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker {
                    _makeDefaultMacroMarker()
                }
            }

            extension TaskWithStatus: EntityProtocol {
            }

            extension TaskWithStatus: SQLiteCodable {
            }

            extension TaskWithStatus: Identifiable {
            }

            extension TaskWithStatus: Sendable {
            }

            extension TaskWithStatus: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with nested struct with default value still generates helper with Default constraint")
    func testEntityWithNestedStructWithDefaultValueGeneratesHelper() {
        // Even when a nested struct has a default value, the type must still conform to Default.
        // The helper is still generated to enforce the constraint.
        assertMacroExpansion(
            """
            @Entity
            struct UserWithDefaultSettings {
                let id: UUIDV4
                var name: String
                var settings: NestedSettings = NestedSettings()
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserWithDefaultSettings {
                let id: UUIDV4
                var name: String
                var settings: NestedSettings = NestedSettings()
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user_with_default_settings"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "settings", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["name"] = .text(self.name)
                    result["settings"] = try {
                            let jsonData = try JSONEncoder().encode(self.settings)
                            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                                throw StoreError.encodingFailed("Failed to encode \\(self.settings) to JSON")
                            }
                            return .text(jsonString)
                        }()
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _settings = try {
                            if statement.isNull(Int32(2)) {
                                return NestedSettings()
                            }
                            return try {
                            guard let jsonString = statement.columnString(Int32(2)),
                                  let jsonData = jsonString.data(using: .utf8) else {
                                throw StoreError.decodingFailed("Failed to decode NestedSettings from column 2")
                            }
                            return try JSONDecoder().decode(NestedSettings.self, from: jsonData)
                        }()
                        }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        name: _name,
                        settings: _settings,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV4 = UUIDV4(),
                    name: String,
                    settings: NestedSettings = NestedSettings(),
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.name = name
                    self.settings = settings
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case settings
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decodeIfPresent(UUIDV4.self, forKey: .id) ?? UUIDV4()
                    self.name = try container.decode(String.self, forKey: .name)
                    self.settings = try Self._decodeNestedIfPresent(NestedSettings.self, from: container, forKey: .settings) ?? NestedSettings()
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
                    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
                }

                /// Helper to decode nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNested<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                    try container.decode(T.self, forKey: key)
                }

                /// Helper to decode optional nested types with Default constraint (compile-time validation)
                @inline(__always)
                private static func _decodeNestedIfPresent<T: Default & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                    try container.decodeIfPresent(T.self, forKey: key)
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker {
                    _makeDefaultMacroMarker()
                }
            }

            extension UserWithDefaultSettings: EntityProtocol {
            }

            extension UserWithDefaultSettings: SQLiteCodable {
            }

            extension UserWithDefaultSettings: Identifiable {
            }

            extension UserWithDefaultSettings: Sendable {
            }

            extension UserWithDefaultSettings: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Sendable Conformance Tests

    @Test("Entity macro generates Sendable conformance")
    func testEntityGeneratesSendableConformance() {
        assertMacroExpansion(
            """
            @Entity
            struct SimpleEntity {
                let id: UUIDV4
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct SimpleEntity {
                let id: UUIDV4
                var name: String
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "simple_entity"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["name"] = .text(self.name)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    return Self(
                        id: _id,
                        name: _name,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV4 = UUIDV4(),
                    name: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.name = name
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.id = try container.decodeIfPresent(UUIDV4.self, forKey: .id) ?? UUIDV4()
                    self.name = try container.decode(String.self, forKey: .name)
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
                    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker {
                    _makeDefaultMacroMarker()
                }
            }

            extension SimpleEntity: EntityProtocol {
            }

            extension SimpleEntity: SQLiteCodable {
            }

            extension SimpleEntity: Identifiable {
            }

            extension SimpleEntity: Sendable {
            }

            extension SimpleEntity: Default {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - SyncKey Identifiable Tests

    @Test("Entity with single SyncKey generates id computed property")
    func testEntityWithSingleSyncKeyGeneratesIdProperty() {
        assertMacroExpansion(
            """
            @Entity
            struct UserByEmail {
                #SyncKey<UserByEmail>(\\.email)
                var email: String
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserByEmail {
                var email: String
                var name: String
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user_by_email"
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
                    result["email"] = .text(self.email)
                    result["name"] = .text(self.name)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _email = statement.columnString(Int32(0)) ?? ""
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    return Self(
                        email: _email,
                        name: _name,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
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
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
                    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker {
                    _makeDefaultMacroMarker()
                }

                public var id: String {
                    email
                }
            }

            extension UserByEmail: EntityProtocol {
            }

            extension UserByEmail: SQLiteCodable {
            }

            extension UserByEmail: Identifiable {
            }

            extension UserByEmail: Sendable {
            }

            extension UserByEmail: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with composite SyncKey generates SyncKeyID struct and id property")
    func testEntityWithCompositeSyncKeyGeneratesSyncKeyIDStruct() {
        assertMacroExpansion(
            """
            @Entity
            struct Employee {
                #SyncKey<Employee>(\\.companyId, \\.employeeCode)
                var companyId: String
                var employeeCode: String
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Employee {
                var companyId: String
                var employeeCode: String
                var name: String
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "employee"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "company_id", type: .text),
                        ColumnDefinition(name: "employee_code", type: .text),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["company_id"] = .text(self.companyId)
                    result["employee_code"] = .text(self.employeeCode)
                    result["name"] = .text(self.name)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _companyId = statement.columnString(Int32(0)) ?? ""
                    let _employeeCode = statement.columnString(Int32(1)) ?? ""
                    let _name = statement.columnString(Int32(2)) ?? ""
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        companyId: _companyId,
                        employeeCode: _employeeCode,
                        name: _name,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var syncKeyColumns: [String] {
                    ["company_id", "employee_code"]
                }

                public init(
                    companyId: String,
                    employeeCode: String,
                    name: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.companyId = companyId
                    self.employeeCode = employeeCode
                    self.name = name
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case companyId
                    case employeeCode
                    case name
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.companyId = try container.decode(String.self, forKey: .companyId)
                    self.employeeCode = try container.decode(String.self, forKey: .employeeCode)
                    self.name = try container.decode(String.self, forKey: .name)
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
                    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker {
                    _makeDefaultMacroMarker()
                }

                public struct SyncKeyID: Hashable, Sendable {
                    public let companyId: String
                    public let employeeCode: String
                }

                public var id: SyncKeyID {
                    SyncKeyID(companyId: self.companyId, employeeCode: self.employeeCode)
                }
            }

            extension Employee: EntityProtocol {
            }

            extension Employee: SQLiteCodable {
            }

            extension Employee: Identifiable {
            }

            extension Employee: Sendable {
            }

            extension Employee: Default {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with UUIDV4 SyncKey generates id computed property with UUIDV4 type")
    func testEntityWithUUIDV4SyncKeyGeneratesIdProperty() {
        assertMacroExpansion(
            """
            @Entity
            struct DeviceRecord {
                #SyncKey<DeviceRecord>(\\.deviceId)
                var deviceId: UUIDV4
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct DeviceRecord {
                var deviceId: UUIDV4
                var name: String
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "device_record"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "device_id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["device_id"] = .blob(self.deviceId.data)
                    result["name"] = .text(self.name)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _deviceId = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    return Self(
                        deviceId: _deviceId,
                        name: _name,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var syncKeyColumns: [String] {
                    ["device_id"]
                }

                public init(
                    deviceId: UUIDV4,
                    name: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.deviceId = deviceId
                    self.name = name
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case deviceId
                    case name
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.deviceId = try container.decode(UUIDV4.self, forKey: .deviceId)
                    self.name = try container.decode(String.self, forKey: .name)
                    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
                    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
                }

                @inlinable public static var _defaultMacroMarker: _DefaultMacroMarker {
                    _makeDefaultMacroMarker()
                }

                public var id: UUIDV4 {
                    deviceId
                }
            }

            extension DeviceRecord: EntityProtocol {
            }

            extension DeviceRecord: SQLiteCodable {
            }

            extension DeviceRecord: Identifiable {
            }

            extension DeviceRecord: Sendable {
            }

            extension DeviceRecord: Default {
            }
            """,
            macros: testMacros
        )
    }

}
