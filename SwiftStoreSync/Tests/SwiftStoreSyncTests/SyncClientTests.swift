import Testing
import Foundation
@testable import SwiftStoreSync
@testable import SwiftStoreCore
@testable import SwiftStoreChangeTracker

// MARK: - Tests

@Suite("Sync Tests")
struct SyncTests {

    @Test("SyncState serialization")
    func testSyncStateSerialization() throws {
        let state = SyncState(lastServerClock: 100, lastLocalClock: 50)

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncState.self, from: data)

        #expect(decoded.lastServerClock == 100)
        #expect(decoded.lastLocalClock == 50)
    }

    @Test("SyncChange from ChangeLog")
    func testSyncChangeFromChangeLog() {
        // Create a sync key (binary encoded UUIDV7)
        let syncKeyData = SyncKeyEncoder.encode([.blob(UUIDV7().data)])

        let changeLog = ChangeLog(
            entityType: "test_entity",
            syncKey: syncKeyData,
            operation: .insert,
            payload: "{\"name\": \"test\"}",
            deviceId: UUIDV7(),
            logicalClock: 1,
            schemaVersion: 1
        )

        let syncChange = SyncChange(from: changeLog)

        #expect(syncChange.entityType == "test_entity")
        #expect(syncChange.operation == .insert)
        #expect(syncChange.payload == "{\"name\": \"test\"}")
        #expect(syncChange.logicalClock == 1)
    }

    @Test("EntityApplierRegistry empty initialization")
    func testEmptyApplierRegistry() {
        let registry = EntityApplierRegistry()
        // Empty registry should initialize with empty appliers
        #expect(registry.count == 0)
    }

    @Test("SyncConfiguration default values")
    func testSyncConfigurationDefaults() {
        let config = SyncConfiguration()
        #expect(config.batchSize == 50)
        #expect(config.yieldBetweenBatches == true)
    }

    @Test("SyncConfiguration custom values")
    func testSyncConfigurationCustom() {
        let config = SyncConfiguration(batchSize: 100, yieldBetweenBatches: false)
        #expect(config.batchSize == 100)
        #expect(config.yieldBetweenBatches == false)
    }

    @Test("SyncResult initialization")
    func testSyncResultInit() {
        let state = SyncState(lastServerClock: 100, lastLocalClock: 50)
        let result = SyncResult(pulledCount: 10, pushedCount: 5, conflictCount: 2, state: state)

        #expect(result.pulledCount == 10)
        #expect(result.pushedCount == 5)
        #expect(result.conflictCount == 2)
        #expect(result.state.lastServerClock == 100)
        #expect(result.state.lastLocalClock == 50)
    }
}
