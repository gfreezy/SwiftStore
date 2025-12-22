import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacrosImpl

@Suite("Entity Macro Validation Tests")
struct EntityMacroValidationTests {
    @Test("Entity macro rejects missing id field")
    func testMissingIdField() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser' to have a 'id: UUIDV4' field", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects id with wrong type (UUID instead of UUIDV4)")
    func testWrongIdType() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUID
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUID
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser.id' to be of type 'UUIDV4', but found 'UUID'", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects optional id")
    func testOptionalIdField() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUIDV4?
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV4?
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser.id' to be non-optional", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects missing createdAt field")
    func testMissingCreatedAtField() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUIDV4
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV4
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser' to have a 'createdAt: Date' field", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects missing updatedAt field")
    func testMissingUpdatedAtField() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUIDV4
                let createdAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV4
                let createdAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser' to have a 'updatedAt: Date' field", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects wrong createdAt type")
    func testWrongCreatedAtType() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUIDV4
                let createdAt: String
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV4
                let createdAt: String
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser.createdAt' to be of type 'Date', but found 'String'", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects optional createdAt")
    func testOptionalCreatedAtField() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUIDV4
                let createdAt: Date?
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV4
                let createdAt: Date?
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser.createdAt' to be non-optional", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects both #SyncKey and id field")
    func testSyncKeyAndIdMutuallyExclusive() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                #SyncKey<InvalidUser>(\\.email)
                let id: UUIDV4
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV4
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity 'InvalidUser': #SyncKey and 'id' field are mutually exclusive. Use either #SyncKey or 'id: UUIDV4', not both.", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro accepts #SyncKey without id field")
    func testSyncKeyWithoutId() {
        // When using #SyncKey, the entity should not have an id field
        // and the sync key columns become the primary key
        assertMacroExpansion(
            """
            @Entity
            struct SyncableUser {
                #SyncKey<SyncableUser>(\\.email)
                var email: String
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct SyncableUser {
                var email: String
                var name: String
                let createdAt: Date
                let updatedAt: Date
            }

            extension SyncableUser: EntityProtocol {
                public static let tableName = "syncable_user"
                public static let columns: [ColumnDefinition] = [
                    ColumnDefinition(name: "email", type: .text, nullable: false, primaryKey: true, defaultValue: nil, generatedAs: nil),
                    ColumnDefinition(name: "name", type: .text, nullable: false, primaryKey: false, defaultValue: nil, generatedAs: nil),
                    ColumnDefinition(name: "created_at", type: .real, nullable: false, primaryKey: false, defaultValue: nil, generatedAs: nil),
                    ColumnDefinition(name: "updated_at", type: .real, nullable: false, primaryKey: false, defaultValue: nil, generatedAs: nil),
                ]
                public static let indexes: [IndexDefinition] = [
                    IndexDefinition(name: "idx_syncable_user_sync_key", columns: ["email"], unique: true),
                ]
                public static let syncKeyColumns: [String] = ["email"]
            }

            extension SyncableUser: SQLiteCodable {
                public func sqliteEncode() throws -> [String: SQLiteValue] {
                    var result: [String: SQLiteValue] = [:]
                    result["email"] = email
                    result["name"] = name
                    result["created_at"] = createdAt.timeIntervalSince1970
                    result["updated_at"] = updatedAt.timeIntervalSince1970
                    return result
                }
                public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> SyncableUser {
                    return SyncableUser(
                        email: try statement.read(column: "email"),
                        name: try statement.read(column: "name"),
                        createdAt: Date(timeIntervalSince1970: try statement.read(column: "created_at")),
                        updatedAt: Date(timeIntervalSince1970: try statement.read(column: "updated_at"))
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
}
