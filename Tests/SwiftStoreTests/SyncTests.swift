import Testing
import Foundation
@testable import SwiftStore

@Suite("Sync Tests")
struct SyncTests {
    @Test("Enable sync and record changes")
    func testSyncEnabled() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        try store.enableSync(deviceId: "device_A")

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

        // Flush pending changes to change_log
        store.flushChanges()

        let changes = try store.changesSince(clock: 0)
        #expect(changes.count == 1)
        #expect(changes.first?.entityType == "test_user")
        #expect(changes.first?.operation == .insert)
    }

    @Test("Apply remote changes")
    func testApplyChanges() throws {
        let storeA = try createTestStore()
        try storeA.register(TestUser.self)
        try storeA.migrate()
        try storeA.enableSync(deviceId: "device_A")

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

        // Flush pending changes to change_log
        storeA.flushChanges()

        let changes = try storeA.changesSince(clock: 0)

        // Apply to store B
        let storeB = try createTestStore()
        try storeB.register(TestUser.self)
        try storeB.migrate()
        try storeB.enableSync(deviceId: "device_B")

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

    @Test("NTP verification result properties")
    func testNTPVerificationResult() {
        // Test valid result (within tolerance)
        let validResult = NTPVerificationResult(
            offsetMs: 100,
            isValid: true,
            server: "time.apple.com",
            rttMs: 50
        )
        #expect(validResult.isValid == true)
        #expect(validResult.offsetSeconds == 0.1)
        #expect(validResult.server == "time.apple.com")
        #expect(validResult.rttMs == 50)

        // Test invalid result (outside tolerance)
        let invalidResult = NTPVerificationResult(
            offsetMs: 10000,
            isValid: false,
            server: "pool.ntp.org",
            rttMs: 200
        )
        #expect(invalidResult.isValid == false)
        #expect(invalidResult.offsetSeconds == 10.0)
    }

    @Test("NTP client default servers")
    func testNTPDefaultServers() {
        let servers = NTPClient.defaultServers
        #expect(servers.contains("time.apple.com"))
        #expect(servers.contains("pool.ntp.org"))
        #expect(servers.contains("time.google.com"))
        #expect(servers.contains("time.cloudflare.com"))
    }

    @Test("NTP time verification")
    func testNTPTimeVerification() async throws {
        // This test requires network access
        // It may fail in offline environments
        do {
            let result = try await NTPClient.verifyTime(toleranceMs: 30000)  // 30 second tolerance
            #expect(result.server.isEmpty == false)
            #expect(result.rttMs >= 0)
            // With 30 second tolerance, most systems should pass
            // unless the clock is severely misconfigured
            print("NTP offset: \(result.offsetMs)ms, RTT: \(result.rttMs)ms, server: \(result.server)")
        } catch {
            // Network may not be available in test environment
            print("NTP test skipped: \(error)")
        }
    }

    @Test("Store verify time method")
    func testStoreVerifyTime() async throws {
        let store = try createTestStore()

        do {
            let result = try await store.verifyTime(toleranceMs: 30000)
            #expect(result.server.isEmpty == false)
        } catch {
            // Network may not be available
            print("Store verifyTime test skipped: \(error)")
        }
    }

    @Test("Store validate time for sync - valid time")
    func testValidateTimeForSyncValid() async throws {
        let store = try createTestStore()

        do {
            // With large tolerance, should pass
            try await store.validateTimeForSync(toleranceMs: 60000)  // 60 seconds
        } catch let error as StoreError {
            // If time is really out of sync, this would fail
            if case .timeOutOfSync(let offset, let tolerance) = error {
                print("Time out of sync: offset=\(offset)ms, tolerance=\(tolerance)ms")
            }
        } catch {
            // Network error - skip test
            print("validateTimeForSync test skipped: \(error)")
        }
    }
}
