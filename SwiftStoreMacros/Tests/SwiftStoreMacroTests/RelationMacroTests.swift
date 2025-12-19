import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftStoreMacrosImpl

@Suite("Relation Macro Tests")
struct RelationMacroTests {
    @Test("ManyToMany macro generates RelationMarker conformance")
    func testManyToManyMacro() {
        assertMacroExpansion(
            """
            @Entity
            @ManyToMany(from: User.self, fromField: \\.id, fromKey: \\.userId,
                        to: Tag.self, toField: \\.id, toKey: \\.tagId)
            struct UserTags {
                let id: UUIDV4
                let userId: UUIDV4
                let tagId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserTags {
                let id: UUIDV4
                let userId: UUIDV4
                let tagId: UUIDV4
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user_tags"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "user_id", type: .blob),
                        ColumnDefinition(name: "tag_id", type: .blob),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public typealias FromEntity = User

                public typealias ToEntity = Tag

                public static var fromKeyPath: String {
                    "userId"
                }

                public static var toKeyPath: String {
                    "tagId"
                }

                public static var relationType: RelationType {
                    .manyToMany
                }
            }

            extension UserTags: EntityProtocol {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Self-referencing ManyToMany with fromName/toName")
    func testSelfReferencingManyToMany() {
        assertMacroExpansion(
            """
            @Entity
            @ManyToMany(from: User.self, fromField: \\.id, fromKey: \\.followerId,
                        to: User.self, toField: \\.id, toKey: \\.followeeId,
                        fromName: "following", toName: "followers")
            struct Friendship {
                let id: UUIDV4
                let followerId: UUIDV4
                let followeeId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct Friendship {
                let id: UUIDV4
                let followerId: UUIDV4
                let followeeId: UUIDV4
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "friendship"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "follower_id", type: .blob),
                        ColumnDefinition(name: "followee_id", type: .blob),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public typealias FromEntity = User

                public typealias ToEntity = User

                public static var fromKeyPath: String {
                    "followerId"
                }

                public static var toKeyPath: String {
                    "followeeId"
                }

                public static var relationType: RelationType {
                    .manyToMany
                }

                public static var fromName: String {
                    "following"
                }

                public static var toName: String {
                    "followers"
                }
            }

            extension Friendship: EntityProtocol {
            }
            """,
            macros: testMacros
        )
    }

    @Test("OneToMany macro")
    func testOneToManyMacro() {
        assertMacroExpansion(
            """
            @Entity
            @OneToMany(from: User.self, fromField: \\.id, fromKey: \\.userId,
                       to: Post.self, toField: \\.id, toKey: \\.postId)
            struct UserPosts {
                let id: UUIDV4
                let userId: UUIDV4
                let postId: UUIDV4
                let createdAt: Date
                let updatedAt: Date
            }
            """,
            expandedSource: """
            struct UserPosts {
                let id: UUIDV4
                let userId: UUIDV4
                let postId: UUIDV4
                let createdAt: Date
                let updatedAt: Date

                public static var tableName: String {
                    "user_posts"
                }

                public static var columns: [ColumnDefinition] {
                    [
                        ColumnDefinition(name: "id", type: .blob, primaryKey: true),
                        ColumnDefinition(name: "user_id", type: .blob),
                        ColumnDefinition(name: "post_id", type: .blob),
                        ColumnDefinition(name: "created_at", type: .real),
                        ColumnDefinition(name: "updated_at", type: .real)
                    ]
                }

                public typealias FromEntity = User

                public typealias ToEntity = Post

                public static var fromKeyPath: String {
                    "userId"
                }

                public static var toKeyPath: String {
                    "postId"
                }

                public static var relationType: RelationType {
                    .oneToMany
                }
            }

            extension UserPosts: EntityProtocol {
            }
            """,
            macros: testMacros
        )
    }
}
