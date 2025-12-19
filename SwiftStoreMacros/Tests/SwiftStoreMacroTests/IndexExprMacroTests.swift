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

                let id: UUIDV4
                var name: String
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {

                let id: UUIDV4
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
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
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

                let id: UUIDV4
                var name: String
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {


                let id: UUIDV4
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
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
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

                let id: UUIDV4
                var firstName: String
                var lastName: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {

                let id: UUIDV4
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
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
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

                let id: UUIDV4
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct User {

                let id: UUIDV4
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
                    let _id = UUIDV4(data: statement.columnData(Int32(0)) ?? Data()) ?? UUIDV4()
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
}
