import Testing
import Foundation
@testable import SwiftStoreCore

@Suite("Store Tests")
struct StoreTests {
    @Test("Initialize store")
    func testInitialize() throws {
        let store = try createTestStore()
        // Just verify we can create a store without throwing
        _ = store
    }

    @Test("Register and migrate entities")
    func testMigration() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.register(TestTag.self)
        try store.register(TestUserTags.self)
        try store.migrate()
    }

    @Test("Insert and fetch entity")
    func testInsertAndFetch() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        let fetched = try store.get(TestUser.self, id: user.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "Alice")
        #expect(fetched?.email == "alice@example.com")
        #expect(fetched?.age == 25)
        #expect(fetched?.address.city == "Shanghai")
    }

    @Test("Update entity")
    func testUpdate() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        var user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        user.name = "Alice Updated"
        user.age = 26

        try store.update(user)

        let fetched = try store.get(TestUser.self, id: user.id)
        #expect(fetched?.name == "Alice Updated")
        #expect(fetched?.age == 26)
    }

    @Test("Delete entity")
    func testDelete() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: nil,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)
        try store.delete(user)

        let fetched = try store.get(TestUser.self, id: user.id)
        #expect(fetched == nil)
    }

    @Test("Query with predicates")
    func testQuery() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user1 = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user2 = TestUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: 30,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user1)
        try store.insert(user2)

        let allUsers = try store.fetch(TestUser.self).all()
        #expect(allUsers.count == 2)

        let count = try store.fetch(TestUser.self).count()
        #expect(count == 2)
    }

    @Test("Transaction support")
    func testTransaction() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user1 = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user2 = TestUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: 30,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.transaction {
            try store.insert(user1)
            try store.insert(user2)
        }

        let count = try store.fetch(TestUser.self).count()
        #expect(count == 2)
    }

    @Test("Relation entities")
    func testRelations() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.register(TestTag.self)
        try store.register(TestUserTags.self)
        try store.migrate()

        let user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let tag1 = TestTag(id: UUIDV4(), name: "swift", createdAt: Date(), updatedAt: Date())
        let tag2 = TestTag(id: UUIDV4(), name: "ios", createdAt: Date(), updatedAt: Date())

        try store.insert(user)
        try store.insert(tag1)
        try store.insert(tag2)

        // Create relations
        let relation1 = TestUserTags(
            id: UUIDV4(),
            userId: user.id,
            tagId: tag1.id,
            createdAt: Date(),
            updatedAt: Date()
        )
        let relation2 = TestUserTags(
            id: UUIDV4(),
            userId: user.id,
            tagId: tag2.id,
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(relation1)
        try store.insert(relation2)

        // Query relations
        let userTags = try store.fetch(TestUserTags.self)
            .where(\.userId == user.id)
            .all()

        #expect(userTags.count == 2)
    }
}
