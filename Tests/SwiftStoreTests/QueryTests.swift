import Testing
import Foundation
@testable import SwiftStore

@Suite("Query Builder Tests")
struct QueryBuilderTests {
    @Test("Order by clause")
    func testOrderBy() throws {
        let store = try Store()
        try store.register(TestUser.self)
        try store.migrate()

        let user1 = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 30,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user2 = TestUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: 25,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date().addingTimeInterval(1),
            updatedAt: Date().addingTimeInterval(1)
        )

        try store.insert(user1)
        try store.insert(user2)

        let ordered = try store.fetch(TestUser.self)
            .order(by: \.name, ascending: true)
            .all()

        #expect(ordered.count == 2)
        #expect(ordered.first?.name == "Alice")
    }

    @Test("Limit and offset")
    func testLimitOffset() throws {
        let store = try Store()
        try store.register(TestUser.self)
        try store.migrate()

        for i in 0..<5 {
            let user = TestUser(
                id: UUIDV4(),
                name: "User\(i)",
                email: "user\(i)@example.com",
                age: 20 + i,
                address: Address(street: "\(i) Main St", city: "City", zipCode: "10000\(i)"),
                createdAt: Date(),
                updatedAt: Date()
            )
            try store.insert(user)
        }

        let limited = try store.fetch(TestUser.self)
            .limit(2)
            .all()

        #expect(limited.count == 2)

        let offsetted = try store.fetch(TestUser.self)
            .limit(2)
            .offset(2)
            .all()

        #expect(offsetted.count == 2)
    }

    @Test("First query")
    func testFirst() throws {
        let store = try Store()
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

        let first = try store.fetch(TestUser.self).first()
        #expect(first != nil)
        #expect(first?.name == "Alice")
    }

    @Test("Exists query")
    func testExists() throws {
        let store = try Store()
        try store.register(TestUser.self)
        try store.migrate()

        let existsBefore = try store.fetch(TestUser.self).exists()
        #expect(existsBefore == false)

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

        let existsAfter = try store.fetch(TestUser.self).exists()
        #expect(existsAfter == true)
    }
}
