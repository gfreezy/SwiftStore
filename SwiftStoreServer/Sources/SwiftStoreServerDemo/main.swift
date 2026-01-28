import Foundation
import SwiftStore
import SwiftStoreServer

// MARK: - Sample Entities

@Entity
struct User {
    let id: UUIDV7
    var name: String
    var email: String
    var age: Int?
    let createdAt: Date
    let updatedAt: Date
}

@Entity
struct Post {
    let id: UUIDV7
    var authorId: UUIDV7
    var title: String
    var content: String
    var status: String
    let createdAt: Date
    let updatedAt: Date
}

@Entity
struct Comment {
    let id: UUIDV7
    var postId: UUIDV7
    var authorId: UUIDV7
    var content: String
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Main

@main
struct SwiftStoreServerDemo {
    static func main() async throws {
        // Create temporary database
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("demo_\(UUID().uuidString).sqlite").path

        print("Database path: \(dbPath)")

        // Create connection manager
        let manager = try ConnectionManager(
            path: dbPath,
            entities: [User.self, Post.self, Comment.self]
        )

        // Run migrations
        try await manager.migrate(dryRun: false)
        print("Database migrated successfully")

        // Insert sample data
        try await manager.write { conn in
            // Create users
            let alice = User(name: "Alice", email: "alice@example.com", age: 28)
            let bob = User(name: "Bob", email: "bob@example.com", age: 32)
            let charlie = User(name: "Charlie", email: "charlie@example.com", age: nil)

            try alice.insert(conn)
            try bob.insert(conn)
            try charlie.insert(conn)

            // Create posts
            let post1 = Post(
                authorId: alice.id,
                title: "Hello SwiftStore",
                content: "This is my first post about SwiftStore!",
                status: "published"
            )
            let post2 = Post(
                authorId: bob.id,
                title: "Swift Macros Guide",
                content: "Learn how to use Swift macros effectively.",
                status: "published"
            )
            let post3 = Post(
                authorId: alice.id,
                title: "Draft Post",
                content: "This is a draft.",
                status: "draft"
            )

            try post1.insert(conn)
            try post2.insert(conn)
            try post3.insert(conn)

            // Create comments
            let comment1 = Comment(
                postId: post1.id,
                authorId: bob.id,
                content: "Great introduction!"
            )
            let comment2 = Comment(
                postId: post1.id,
                authorId: charlie.id,
                content: "Very helpful, thanks!"
            )
            let comment3 = Comment(
                postId: post2.id,
                authorId: alice.id,
                content: "Nice tutorial!"
            )

            try comment1.insert(conn)
            try comment2.insert(conn)
            try comment3.insert(conn)

            print("Sample data inserted: 3 users, 3 posts, 3 comments")
        }

        // Start server
        let server = try await SwiftStoreServer(
            connectionManager: manager,
            configuration: ServerConfiguration(
                host: "127.0.0.1",
                port: 8080
            )
        )

        print("")
        print("========================================")
        print("  SwiftStore Server Demo")
        print("========================================")
        print("")
        print("  Web Admin: http://127.0.0.1:8080/admin")
        print("  API:       http://127.0.0.1:8080/api/health")
        print("")
        print("  Press Ctrl+C to stop")
        print("========================================")
        print("")

        try await server.start()

        // Keep the server running
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // Never resume - run forever until Ctrl+C
        }
    }
}
