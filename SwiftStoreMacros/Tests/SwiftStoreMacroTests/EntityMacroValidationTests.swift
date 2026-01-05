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
                DiagnosticSpec(message: "@Entity requires 'InvalidUser' to have a 'id: UUIDV7' field", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects id with wrong type (UUID instead of UUIDV7)")
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
                DiagnosticSpec(message: "@Entity requires 'InvalidUser.id' to be of type 'UUIDV7', but found 'UUID'", line: 1, column: 1)
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
                let id: UUIDV7?
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7?
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
                let id: UUIDV7
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7
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
                let id: UUIDV7
                let createdAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7
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
                let id: UUIDV7
                let createdAt: String
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7
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
                let id: UUIDV7
                let createdAt: Date?
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7
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
                let id: UUIDV7
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7
                var email: String
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity 'InvalidUser': #SyncKey and 'id' field are mutually exclusive. Use either #SyncKey or 'id: UUIDV7', not both.", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects field without type annotation")
    func testMissingTypeAnnotation() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUIDV7
                var name = "default"
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7
                var name = "default"
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser.name' to have an explicit type annotation. Use 'var name: Type = value' instead of 'var name = value'.", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects let field without type annotation")
    func testMissingTypeAnnotationLet() {
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUIDV7
                let status = "active"
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7
                let status = "active"
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser.status' to have an explicit type annotation. Use 'var status: Type = value' instead of 'var status = value'.", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Entity macro rejects multiple fields without type annotations")
    func testMissingTypeAnnotationMultiple() {
        // Note: The macro stops at the first error
        assertMacroExpansion(
            """
            @Entity
            struct InvalidUser {
                let id: UUIDV7
                var name = "default"
                var age = 0
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct InvalidUser {
                let id: UUIDV7
                var name = "default"
                var age = 0
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Entity requires 'InvalidUser.name' to have an explicit type annotation. Use 'var name: Type = value' instead of 'var name = value'.", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }
}
