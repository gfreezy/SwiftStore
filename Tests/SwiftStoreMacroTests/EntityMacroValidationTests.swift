import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacros

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
}
