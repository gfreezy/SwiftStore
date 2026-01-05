import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacrosImpl

@Suite("#Index Macro Tests")
struct IndexMacroTests {
    @Test("Entity with #Index generates indexes property")
    func testEntityWithIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                #Index(\\.email, unique: true)

                let id: UUIDV7
                var name: String
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {

                let id: UUIDV7
                var name: String
                var email: String
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
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["name"] = .text(self.name)
                    result["email"] = .text(self.email)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV7(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV7()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _email = statement.columnString(Int32(2)) ?? ""
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        name: _name,
                        email: _email,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_user_email", columns: ["email"], unique: true)
                    ]
                }
            }

            extension User: EntityProtocol {
            }

            extension User: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with multiple #Index markers")
    func testEntityWithMultipleIndexes() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                #Index(\\.email, unique: true)
                #Index(\\.name)

                let id: UUIDV7
                var name: String
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {


                let id: UUIDV7
                var name: String
                var email: String
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
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["name"] = .text(self.name)
                    result["email"] = .text(self.email)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV7(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV7()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _email = statement.columnString(Int32(2)) ?? ""
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        name: _name,
                        email: _email,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_user_email", columns: ["email"], unique: true),
                        IndexDefinition(name: "idx_user_name", columns: ["name"])
                    ]
                }
            }

            extension User: EntityProtocol {
            }

            extension User: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with composite #Index (multiple columns)")
    func testEntityWithCompositeIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                #Index(\\.firstName, \\.lastName, unique: true)

                let id: UUIDV7
                var firstName: String
                var lastName: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {

                let id: UUIDV7
                var firstName: String
                var lastName: String
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "first_name", type: .text),
                        ColumnDefinition(name: "last_name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["first_name"] = .text(self.firstName)
                    result["last_name"] = .text(self.lastName)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV7(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV7()
                    let _firstName = statement.columnString(Int32(1)) ?? ""
                    let _lastName = statement.columnString(Int32(2)) ?? ""
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        firstName: _firstName,
                        lastName: _lastName,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_user_first_name_last_name", columns: ["first_name", "last_name"], unique: true)
                    ]
                }
            }

            extension User: EntityProtocol {
            }

            extension User: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with #Index with custom name")
    func testEntityWithCustomIndexName() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                #Index(\\.email, name: "custom_email_idx")

                let id: UUIDV7
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {

                let id: UUIDV7
                var email: String
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "email", type: .text),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["email"] = .text(self.email)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _id = UUIDV7(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV7()
                    let _email = statement.columnString(Int32(1)) ?? ""
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    return Self(
                        id: _id,
                        email: _email,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "custom_email_idx", columns: ["email"])
                    ]
                }
            }

            extension User: EntityProtocol {
            }

            extension User: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with #Index on nested property generates virtual column")
    func testEntityWithNestedPropertyIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct Profile {
                #Index(\\.settings.theme)

                let id: UUIDV7
                var bio: String
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Profile {

                let id: UUIDV7
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
                        ColumnDefinition(name: "updated_at", type: .real),
                        ColumnDefinition(name: "settings__theme", type: .text, nullable: true, generatedAs: "json_extract(settings, '$.theme')")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["bio"] = .text(self.bio)
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
                    let _id = UUIDV7(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV7()
                    let _bio = statement.columnString(Int32(1)) ?? ""
                    let _settings = try {
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

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_profile_settings__theme", columns: ["settings__theme"])
                    ]
                }
            }

            extension Profile: EntityProtocol {
            }

            extension Profile: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with #Index on multiple nested properties")
    func testEntityWithMultipleNestedPropertyIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct Profile {
                #Index(\\.settings.theme, \\.settings.notifications)

                let id: UUIDV7
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Profile {

                let id: UUIDV7
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "profile"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "settings", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real),
                        ColumnDefinition(name: "settings__theme", type: .text, nullable: true, generatedAs: "json_extract(settings, '$.theme')"),
                        ColumnDefinition(name: "settings__notifications", type: .text, nullable: true, generatedAs: "json_extract(settings, '$.notifications')")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
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
                    let _id = UUIDV7(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV7()
                    let _settings = try {
                        guard let jsonString = statement.columnString(Int32(1)),
                              let jsonData = jsonString.data(using: .utf8) else {
                            throw StoreError.decodingFailed("Failed to decode UserSettings from column 1")
                        }
                        return try JSONDecoder().decode(UserSettings.self, from: jsonData)
                    }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    return Self(
                        id: _id,
                        settings: _settings,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_profile_settings__theme_settings__notifications", columns: ["settings__theme", "settings__notifications"])
                    ]
                }
            }

            extension Profile: EntityProtocol {
            }

            extension Profile: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with #Index mixing nested and regular properties")
    func testEntityWithMixedNestedAndRegularIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct Profile {
                #Index(\\.settings.theme, \\.id)

                let id: UUIDV7
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Profile {

                let id: UUIDV7
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "profile"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "settings", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real),
                        ColumnDefinition(name: "settings__theme", type: .text, nullable: true, generatedAs: "json_extract(settings, '$.theme')")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
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
                    let _id = UUIDV7(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV7()
                    let _settings = try {
                        guard let jsonString = statement.columnString(Int32(1)),
                              let jsonData = jsonString.data(using: .utf8) else {
                            throw StoreError.decodingFailed("Failed to decode UserSettings from column 1")
                        }
                        return try JSONDecoder().decode(UserSettings.self, from: jsonData)
                    }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    return Self(
                        id: _id,
                        settings: _settings,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_profile_settings__theme_id", columns: ["settings__theme", "id"])
                    ]
                }
            }

            extension Profile: EntityProtocol {
            }

            extension Profile: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity with multiple #Index markers with shared nested column")
    func testEntityWithMultipleIndexesSharedNestedColumn() {
        assertMacroExpansion(
            """
            @Entity
            struct Profile {
                #Index(\\.settings.theme, \\.settings.notifications)
                #Index(\\.settings.theme, \\.id)

                let id: UUIDV7
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Profile {


                let id: UUIDV7
                var settings: UserSettings
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "profile"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "settings", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real),
                        ColumnDefinition(name: "settings__theme", type: .text, nullable: true, generatedAs: "json_extract(settings, '$.theme')"),
                        ColumnDefinition(name: "settings__notifications", type: .text, nullable: true, generatedAs: "json_extract(settings, '$.notifications')")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
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
                    let _id = UUIDV7(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV7()
                    let _settings = try {
                        guard let jsonString = statement.columnString(Int32(1)),
                              let jsonData = jsonString.data(using: .utf8) else {
                            throw StoreError.decodingFailed("Failed to decode UserSettings from column 1")
                        }
                        return try JSONDecoder().decode(UserSettings.self, from: jsonData)
                    }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    return Self(
                        id: _id,
                        settings: _settings,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_profile_settings__theme_settings__notifications", columns: ["settings__theme", "settings__notifications"]),
                        IndexDefinition(name: "idx_profile_settings__theme_id", columns: ["settings__theme", "id"])
                    ]
                }
            }

            extension Profile: EntityProtocol {
            }

            extension Profile: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }
}
