import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacrosImpl

@Suite("Relation Macro Validation Tests")
struct RelationMacroValidationTests {
    @Test("ManyToMany macro rejects missing fromKey field")
    func testManyToManyMissingFromKey() {
        assertMacroExpansion(
            """
            @ManyToMany(from: User.self, fromField: \\.id, fromKey: \\.userId,
                        to: Tag.self, toField: \\.id, toKey: \\.tagId)
            struct UserTags {
                let id: UUIDV4
                let tagId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserTags {
                let id: UUIDV4
                let tagId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Field 'userId' not found in 'UserTags'", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("ManyToMany macro rejects missing toKey field")
    func testManyToManyMissingToKey() {
        assertMacroExpansion(
            """
            @ManyToMany(from: User.self, fromField: \\.id, fromKey: \\.userId,
                        to: Tag.self, toField: \\.id, toKey: \\.tagId)
            struct UserTags {
                let id: UUIDV4
                let userId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserTags {
                let id: UUIDV4
                let userId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Field 'tagId' not found in 'UserTags'", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("OneToMany macro rejects missing fromKey field")
    func testOneToManyMissingFromKey() {
        assertMacroExpansion(
            """
            @OneToMany(from: User.self, fromField: \\.id, fromKey: \\.userId,
                       to: Post.self, toField: \\.id, toKey: \\.postId)
            struct UserPosts {
                let id: UUIDV4
                let postId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserPosts {
                let id: UUIDV4
                let postId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Field 'userId' not found in 'UserPosts'", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("ManyToOne macro rejects missing fromKey field")
    func testManyToOneMissingFromKey() {
        assertMacroExpansion(
            """
            @ManyToOne(from: Post.self, fromField: \\.id, fromKey: \\.postId,
                       to: User.self, toField: \\.id, toKey: \\.userId)
            struct PostAuthor {
                let id: UUIDV4
                let userId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct PostAuthor {
                let id: UUIDV4
                let userId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Field 'postId' not found in 'PostAuthor'", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("OneToOne macro rejects missing fromKey field")
    func testOneToOneMissingFromKey() {
        assertMacroExpansion(
            """
            @OneToOne(from: User.self, fromField: \\.id, fromKey: \\.userId,
                      to: Profile.self, toField: \\.id, toKey: \\.profileId)
            struct UserProfile {
                let id: UUIDV4
                let profileId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserProfile {
                let id: UUIDV4
                let profileId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Field 'userId' not found in 'UserProfile'", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("OneToOne macro rejects missing toKey field")
    func testOneToOneMissingToKey() {
        assertMacroExpansion(
            """
            @OneToOne(from: User.self, fromField: \\.id, fromKey: \\.userId,
                      to: Profile.self, toField: \\.id, toKey: \\.profileId)
            struct UserProfile {
                let id: UUIDV4
                let userId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserProfile {
                let id: UUIDV4
                let userId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Field 'profileId' not found in 'UserProfile'", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }
}
