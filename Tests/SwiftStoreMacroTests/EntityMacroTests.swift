import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacros

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

                public static func sqliteDecode(from statement: SQLiteStatement) throws -> Self {
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

                public static func sqliteDecode(from statement: SQLiteStatement) throws -> Self {
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

                public static func sqliteDecode(from statement: SQLiteStatement) throws -> Self {
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
            """,
            macros: testMacros
        )
    }

    @Test("Entity macro with @RawValue String enum generates rawValue encode/decode")
    func testEntityWithRawValueStringEnum() {
        assertMacroExpansion(
            """
            @Entity
            struct Task {
                let id: UUIDV4
                var title: String
                @RawValue var status: TaskStatus
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Task {
                let id: UUIDV4
                var title: String
                var status: TaskStatus
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "task"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "title", type: .text),
                        ColumnDefinition(name: "status", type: .text),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["title"] = .text(self.title)
                    result["status"] = .text(self.status.rawValue)
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: SQLiteStatement) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _title = statement.columnString(Int32(1)) ?? ""
                    let _status = {
                            guard let rawValue = statement.columnString(Int32(2)),
                                  let value = TaskStatus(rawValue: rawValue) else {
                                throw StoreError.decodingFailed("Failed to decode TaskStatus from column 2")
                            }
                            return value
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
            }

            extension Task: EntityProtocol {
            }

            extension Task: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity macro with @RawValue Integer enum generates rawValue encode/decode")
    func testEntityWithRawValueIntegerEnum() {
        assertMacroExpansion(
            """
            @Entity
            struct Item {
                let id: UUIDV4
                var name: String
                @RawValue(rawType: .integer) var priority: Priority
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Item {
                let id: UUIDV4
                var name: String
                var priority: Priority
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "item"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "priority", type: .integer),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["name"] = .text(self.name)
                    result["priority"] = .integer(Int64(self.priority.rawValue))
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: SQLiteStatement) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _name = statement.columnString(Int32(1)) ?? ""
                    let _priority = {
                            let rawValue = Int(statement.columnInt64(Int32(2)))
                            guard let value = Priority(rawValue: rawValue) else {
                                throw StoreError.decodingFailed("Failed to decode Priority from column 2")
                            }
                            return value
                        }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(4)))
                    return Self(
                        id: _id,
                        name: _name,
                        priority: _priority,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }
            }

            extension Item: EntityProtocol {
            }

            extension Item: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Entity macro with optional @RawValue enum")
    func testEntityWithOptionalRawValueEnum() {
        assertMacroExpansion(
            """
            @Entity
            struct Order {
                let id: UUIDV4
                @RawValue var status: OrderStatus?
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Order {
                let id: UUIDV4
                var status: OrderStatus?
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "order"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "status", type: .text, nullable: true),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = .blob(self.id.data)
                    result["status"] = {
                            if let value = self.status {
                                return .text(value.rawValue)
                            } else {
                                return .null
                            }
                        }()
                    result["created_at"] = .real(self.createdAt.timeIntervalSince1970)
                    result["updated_at"] = .real(self.updatedAt.timeIntervalSince1970)
                    return result
                }

                public static func sqliteDecode(from statement: SQLiteStatement) throws -> Self {
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
                    let _status = {
                            if statement.isNull(Int32(1)) {
                                return nil
                            }
                            return {
                            guard let rawValue = statement.columnString(Int32(1)),
                                  let value = OrderStatus(rawValue: rawValue) else {
                                throw StoreError.decodingFailed("Failed to decode OrderStatus from column 1")
                            }
                            return value
                        }()
                        }()
                    let _createdAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(2)))
                    let _updatedAt = Date(timeIntervalSince1970: statement.columnDouble(Int32(3)))
                    return Self(
                        id: _id,
                        status: _status,
                        createdAt: _createdAt,
                        updatedAt: _updatedAt
                    )
                }
            }

            extension Order: EntityProtocol {
            }

            extension Order: SQLiteCodable {
            }
            """,
            macros: testMacros
        )
    }
}
