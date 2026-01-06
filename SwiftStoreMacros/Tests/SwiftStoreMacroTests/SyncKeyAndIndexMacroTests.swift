import XCTest
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacrosImpl

final class SyncKeyAndIndexMacroTests: XCTestCase {

    // MARK: - SyncKey Tests

    /// Test single-field SyncKey
    func testSingleFieldSyncKey() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                #SyncKey(\\.email)
                var email: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
            }
            """,
            expandedSource: """
            struct User {
                var email: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

                public static var tableName: String {
                    "user"
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
                            _createdAt = Date()
                        }
                        var _updatedAt: Date
                        do {
                            _updatedAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                        } catch {
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
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        self.updatedAt = Date()
                    }
                }

                public var id: String {
                    email
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_user_sync_key", columns: ["email"], unique: true)
                    ]
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

            extension User: Embedded {
            }
            """,
            macros: testMacros
        )
    }

    /// Test composite SyncKey with multiple fields
    func testCompositeSyncKey() {
        assertMacroExpansion(
            """
            @Entity
            struct Employee {
                #SyncKey(\\.companyId, \\.employeeCode)
                var companyId: String
                var employeeCode: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
            }
            """,
            expandedSource: """
            struct Employee {
                var companyId: String
                var employeeCode: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

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
                    result["company_id"] = try self.companyId.sqliteEncode()
                        result["employee_code"] = try self.employeeCode.sqliteEncode()
                        result["name"] = try self.name.sqliteEncode()
                        result["created_at"] = try self.createdAt.sqliteEncode()
                        result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    let _companyId = try String(from: statement.columnValue(Int32(0), type: .text))
                        let _employeeCode = try String(from: statement.columnValue(Int32(1), type: .text))
                        let _name = try String(from: statement.columnValue(Int32(2), type: .text))
                        var _createdAt: Date
                        do {
                            _createdAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                        } catch {
                            _createdAt = Date()
                        }
                        var _updatedAt: Date
                        do {
                            _updatedAt = try Date(from: statement.columnValue(Int32(4), type: .real))
                        } catch {
                            _updatedAt = Date()
                        }
                    return Self(companyId: _companyId, employeeCode: _employeeCode, name: _name, createdAt: _createdAt, updatedAt: _updatedAt)
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
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        self.updatedAt = Date()
                    }
                }

                public struct SyncKeyID: Hashable, Sendable {
                    public let companyId: String
                            public let employeeCode: String
                }

                public var id: SyncKeyID { SyncKeyID(companyId: self.companyId, employeeCode: self.employeeCode) }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_employee_sync_key", columns: ["company_id", "employee_code"], unique: true)
                    ]
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

            extension Employee: Embedded {
            }
            """,
            macros: testMacros
        )
    }

    /// Test that SyncKey and id field are mutually exclusive
    func testSyncKeyAndIdMutuallyExclusive() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidEntity {
                #SyncKey(\\.email)
                var id: UUIDV7 = UUIDV7()
                var email: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
            }
            """,
            expandedSource: """
            struct InvalidEntity {
                var id: UUIDV7 = UUIDV7()
                var email: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
            }

            extension InvalidEntity: EntityProtocol {
            }

            extension InvalidEntity: SQLiteCodable {
            }

            extension InvalidEntity: Identifiable {
            }

            extension InvalidEntity: Sendable {
            }

            extension InvalidEntity: Embedded {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity 'InvalidEntity': #SyncKey and 'id' field are mutually exclusive. Use either #SyncKey or 'id: UUIDV7', not both.", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    // MARK: - Index Tests

    /// Test single-field index
    func testSingleFieldIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                let id: UUIDV7 = UUIDV7()
                var email: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
                #Index(\\.email)
            }
            """,
            expandedSource: """
            struct User {
                let id: UUIDV7 = UUIDV7()
                var email: String
                var name: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

                public static var tableName: String {
                    "user"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "email", type: .text),
                        ColumnDefinition(name: "name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                        result["email"] = try self.email.sqliteEncode()
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
                            _id = UUIDV7()
                        }
                        let _email = try String(from: statement.columnValue(Int32(1), type: .text))
                        let _name = try String(from: statement.columnValue(Int32(2), type: .text))
                        var _createdAt: Date
                        do {
                            _createdAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                        } catch {
                            _createdAt = Date()
                        }
                        var _updatedAt: Date
                        do {
                            _updatedAt = try Date(from: statement.columnValue(Int32(4), type: .real))
                        } catch {
                            _updatedAt = Date()
                        }
                    return Self(id: _id, email: _email, name: _name, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV7 = UUIDV7(),
                    email: String,
                    name: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.email = email
                    self.name = name
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case email
                    case name
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    do {
                        self.id = try container.decode(UUIDV7.self, forKey: .id)
                    } catch {
                        self.id = UUIDV7()
                    }
                    self.email = try container.decode(String.self, forKey: .email)
                    self.name = try container.decode(String.self, forKey: .name)
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        self.updatedAt = Date()
                    }
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_user_email", columns: ["email"])
                    ]
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

            extension User: Embedded {
            }
            """,
            macros: testMacros
        )
    }

    /// Test unique index
    func testUniqueIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                let id: UUIDV7 = UUIDV7()
                var email: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
                #Index(\\.email, unique: true)
            }
            """,
            expandedSource: """
            struct User {
                let id: UUIDV7 = UUIDV7()
                var email: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

                public static var tableName: String {
                    "user"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "email", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                        result["email"] = try self.email.sqliteEncode()
                        result["created_at"] = try self.createdAt.sqliteEncode()
                        result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    var _id: UUIDV7
                        do {
                            _id = try UUIDV7(from: statement.columnValue(Int32(0), type: .blob))
                        } catch {
                            _id = UUIDV7()
                        }
                        let _email = try String(from: statement.columnValue(Int32(1), type: .text))
                        var _createdAt: Date
                        do {
                            _createdAt = try Date(from: statement.columnValue(Int32(2), type: .real))
                        } catch {
                            _createdAt = Date()
                        }
                        var _updatedAt: Date
                        do {
                            _updatedAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                        } catch {
                            _updatedAt = Date()
                        }
                    return Self(id: _id, email: _email, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV7 = UUIDV7(),
                    email: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.email = email
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case email
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    do {
                        self.id = try container.decode(UUIDV7.self, forKey: .id)
                    } catch {
                        self.id = UUIDV7()
                    }
                    self.email = try container.decode(String.self, forKey: .email)
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        self.updatedAt = Date()
                    }
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

            extension User: Identifiable {
            }

            extension User: Sendable {
            }

            extension User: Embedded {
            }
            """,
            macros: testMacros
        )
    }

    /// Test composite index with custom name
    func testCompositeIndexWithCustomName() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                let id: UUIDV7 = UUIDV7()
                var firstName: String
                var lastName: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
                #Index(\\.firstName, \\.lastName, name: "idx_full_name")
            }
            """,
            expandedSource: """
            struct User {
                let id: UUIDV7 = UUIDV7()
                var firstName: String
                var lastName: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

                public static var tableName: String {
                    "user"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "first_name", type: .text),
                        ColumnDefinition(name: "last_name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                        result["first_name"] = try self.firstName.sqliteEncode()
                        result["last_name"] = try self.lastName.sqliteEncode()
                        result["created_at"] = try self.createdAt.sqliteEncode()
                        result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    var _id: UUIDV7
                        do {
                            _id = try UUIDV7(from: statement.columnValue(Int32(0), type: .blob))
                        } catch {
                            _id = UUIDV7()
                        }
                        let _firstName = try String(from: statement.columnValue(Int32(1), type: .text))
                        let _lastName = try String(from: statement.columnValue(Int32(2), type: .text))
                        var _createdAt: Date
                        do {
                            _createdAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                        } catch {
                            _createdAt = Date()
                        }
                        var _updatedAt: Date
                        do {
                            _updatedAt = try Date(from: statement.columnValue(Int32(4), type: .real))
                        } catch {
                            _updatedAt = Date()
                        }
                    return Self(id: _id, firstName: _firstName, lastName: _lastName, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV7 = UUIDV7(),
                    firstName: String,
                    lastName: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.firstName = firstName
                    self.lastName = lastName
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case firstName
                    case lastName
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    do {
                        self.id = try container.decode(UUIDV7.self, forKey: .id)
                    } catch {
                        self.id = UUIDV7()
                    }
                    self.firstName = try container.decode(String.self, forKey: .firstName)
                    self.lastName = try container.decode(String.self, forKey: .lastName)
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        self.updatedAt = Date()
                    }
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_full_name", columns: ["first_name", "last_name"])
                    ]
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

            extension User: Embedded {
            }
            """,
            macros: testMacros
        )
    }

    /// Test nested property index (virtual column)
    func testNestedPropertyIndex() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                let id: UUIDV7 = UUIDV7()
                var settings: Settings
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
                #Index(\\.settings.theme)
            }
            """,
            expandedSource: """
            struct User {
                let id: UUIDV7 = UUIDV7()
                var settings: Settings
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

                public static var tableName: String {
                    "user"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "settings", type: .text, isJSONEncoded: true),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "settings__theme", type: .text, nullable: true, generatedAs: "json_extract(settings, '$.theme')")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                        result["settings"] = try self.settings.sqliteEncode()
                        result["created_at"] = try self.createdAt.sqliteEncode()
                        result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    var _id: UUIDV7
                        do {
                            _id = try UUIDV7(from: statement.columnValue(Int32(0), type: .blob))
                        } catch {
                            _id = UUIDV7()
                        }
                        let _settings = try Settings(from: statement.columnValue(Int32(1), type: .text))
                        var _createdAt: Date
                        do {
                            _createdAt = try Date(from: statement.columnValue(Int32(2), type: .real))
                        } catch {
                            _createdAt = Date()
                        }
                        var _updatedAt: Date
                        do {
                            _updatedAt = try Date(from: statement.columnValue(Int32(3), type: .real))
                        } catch {
                            _updatedAt = Date()
                        }
                    return Self(id: _id, settings: _settings, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV7 = UUIDV7(),
                    settings: Settings,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.settings = settings
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case settings
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    do {
                        self.id = try container.decode(UUIDV7.self, forKey: .id)
                    } catch {
                        self.id = UUIDV7()
                    }
                    self.settings = try Self._decodeNested(Settings.self, from: container, forKey: .settings)
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
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

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_user_settings__theme", columns: ["settings__theme"])
                    ]
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

            extension User: Embedded {
            }
            """,
            macros: testMacros
        )
    }

    /// Test multiple indexes
    func testMultipleIndexes() {
        assertMacroExpansion(
            """
            @Entity
            struct User {
                let id: UUIDV7 = UUIDV7()
                var email: String
                var firstName: String
                var lastName: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()
                #Index(\\.email, unique: true)
                #Index(\\.firstName, \\.lastName)
            }
            """,
            expandedSource: """
            struct User {
                let id: UUIDV7 = UUIDV7()
                var email: String
                var firstName: String
                var lastName: String
                let createdAt: Date = Date()
                let updatedAt: Date = Date()

                public static var tableName: String {
                    "user"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "email", type: .text),
                        ColumnDefinition(name: "first_name", type: .text),
                        ColumnDefinition(name: "last_name", type: .text),
                        ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
                        ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
                    ]
                }

                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["id"] = try self.id.sqliteEncode()
                        result["email"] = try self.email.sqliteEncode()
                        result["first_name"] = try self.firstName.sqliteEncode()
                        result["last_name"] = try self.lastName.sqliteEncode()
                        result["created_at"] = try self.createdAt.sqliteEncode()
                        result["updated_at"] = try self.updatedAt.sqliteEncode()
                    return result
                }

                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self {
                    var _id: UUIDV7
                        do {
                            _id = try UUIDV7(from: statement.columnValue(Int32(0), type: .blob))
                        } catch {
                            _id = UUIDV7()
                        }
                        let _email = try String(from: statement.columnValue(Int32(1), type: .text))
                        let _firstName = try String(from: statement.columnValue(Int32(2), type: .text))
                        let _lastName = try String(from: statement.columnValue(Int32(3), type: .text))
                        var _createdAt: Date
                        do {
                            _createdAt = try Date(from: statement.columnValue(Int32(4), type: .real))
                        } catch {
                            _createdAt = Date()
                        }
                        var _updatedAt: Date
                        do {
                            _updatedAt = try Date(from: statement.columnValue(Int32(5), type: .real))
                        } catch {
                            _updatedAt = Date()
                        }
                    return Self(id: _id, email: _email, firstName: _firstName, lastName: _lastName, createdAt: _createdAt, updatedAt: _updatedAt)
                }

                public static var syncKeyColumns: [String] {
                    ["id"]
                }

                public init(
                    id: UUIDV7 = UUIDV7(),
                    email: String,
                    firstName: String,
                    lastName: String,
                    createdAt: Date = Date(),
                    updatedAt: Date = Date()
                ) {
                    self.id = id
                    self.email = email
                    self.firstName = firstName
                    self.lastName = lastName
                    self.createdAt = createdAt
                    self.updatedAt = updatedAt
                }

                private enum CodingKeys: String, CodingKey {
                    case id
                    case email
                    case firstName
                    case lastName
                    case createdAt
                    case updatedAt
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    do {
                        self.id = try container.decode(UUIDV7.self, forKey: .id)
                    } catch {
                        self.id = UUIDV7()
                    }
                    self.email = try container.decode(String.self, forKey: .email)
                    self.firstName = try container.decode(String.self, forKey: .firstName)
                    self.lastName = try container.decode(String.self, forKey: .lastName)
                    do {
                        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
                    } catch {
                        self.createdAt = Date()
                    }
                    do {
                        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
                    } catch {
                        self.updatedAt = Date()
                    }
                }

                public static var indexes: [IndexDefinition] {
                    [
                        IndexDefinition(name: "idx_user_email", columns: ["email"], unique: true),
                        IndexDefinition(name: "idx_user_first_name_last_name", columns: ["first_name", "last_name"])
                    ]
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

            extension User: Embedded {
            }
            """,
            macros: testMacros
        )
    }
}
