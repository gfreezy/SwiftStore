import Testing
import Foundation
@testable import SwiftStore

@Suite("Sync Tests")
struct SyncTests {
    @Test("Enable sync and record changes")
    func testSyncEnabled() throws {
        let store = try Store()
        try store.register(TestUser.self)
        try store.migrate()

        store.enableSync(deviceId: "device_A")

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

        let changes = try store.changesSince(clock: 0)
        #expect(changes.count == 1)
        #expect(changes.first?.entityType == "test_user")
        #expect(changes.first?.operation == .insert)
    }

    @Test("Apply remote changes")
    func testApplyChanges() throws {
        let storeA = try Store()
        try storeA.register(TestUser.self)
        try storeA.migrate()
        storeA.enableSync(deviceId: "device_A")

        let user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try storeA.insert(user)

        let changes = try storeA.changesSince(clock: 0)

        // Apply to store B
        let storeB = try Store()
        try storeB.register(TestUser.self)
        try storeB.migrate()
        storeB.enableSync(deviceId: "device_B")

        try storeB.applyChanges(changes)

        let fetchedUser = try storeB.get(TestUser.self, id: user.id)
        #expect(fetchedUser != nil)
        #expect(fetchedUser?.name == "Alice")
    }

    @Test("Hybrid clock")
    func testHybridClock() {
        var clock = HybridClock()

        let tick1 = clock.tick()
        let tick2 = clock.tick()

        #expect(tick2 > tick1)

        let logicalTime = HybridClock.logicalTime(from: tick1)
        #expect(logicalTime > 0)
    }
}
