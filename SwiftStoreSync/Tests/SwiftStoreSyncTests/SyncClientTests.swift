import Testing
import Foundation
@testable import SwiftStoreSync
@testable import SwiftStoreCore
@testable import SwiftStoreChangeTracker

// MARK: - In-memory Transport Mock

actor InMemoryTransport: SyncTransport {
    private var _pending: [SyncChange] = []
    private var _pulledQueue: [SyncChange] = []
    private var _started = false
    private nonisolated let _stream: AsyncStream<Void>
    private nonisolated let _continuation: AsyncStream<Void>.Continuation

    init() {
        let (s, c) = AsyncStream<Void>.makeStream()
        _stream = s
        _continuation = c
    }

    nonisolated var remoteChanges: AsyncStream<Void> { _stream }

    func stage(pulled: [SyncChange]) {
        _pulledQueue.append(contentsOf: pulled)
    }

    var pendingSnapshot: [SyncChange] { _pending }

    func start(deviceId: UUIDV7) async throws {
        _started = true
    }

    func stop() async {
        _continuation.finish()
    }

    func enqueue(_ changes: [SyncChange]) async throws {
        _pending.append(contentsOf: changes)
    }

    func syncNow() async throws -> SyncCycleResult {
        let pushed = _pending.map(\.id)
        let pulled = _pulledQueue
        _pending.removeAll()
        _pulledQueue.removeAll()
        return SyncCycleResult(pulled: pulled, pushed: pushed, conflicts: [])
    }
}

// MARK: - Tests

@Suite("Sync Tests")
struct SyncTests {

    @Test("SyncState serialization")
    func testSyncStateSerialization() throws {
        let state = SyncState(lastLocalClock: 50)

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncState.self, from: data)

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
        let state = SyncState(lastLocalClock: 50)
        let result = SyncResult(pulledCount: 10, pushedCount: 5, conflictCount: 2, state: state)

        #expect(result.pulledCount == 10)
        #expect(result.pushedCount == 5)
        #expect(result.conflictCount == 2)
        #expect(result.state.lastLocalClock == 50)
    }

    @Test("SyncCycleResult initialization")
    func testSyncCycleResult() {
        let id = UUIDV7()
        let cycle = SyncCycleResult(pulled: [], pushed: [id], conflicts: [])
        #expect(cycle.pushed == [id])
        #expect(cycle.pulled.isEmpty)
        #expect(cycle.conflicts.isEmpty)
    }

    @Test("SyncStatePersistence round-trips across instances")
    func testSyncStatePersistenceRoundTrip() throws {
        let path = NSTemporaryDirectory() + "swiftstore_syncstate_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        // First session: write a non-zero state.
        do {
            let conn = try SQLiteConnection(path: path)
            let store = try SyncStatePersistence(connection: conn)
            #expect(try store.load().lastLocalClock == 0)  // fresh DB defaults to 0

            try store.save(SyncState(lastLocalClock: 12345))
            #expect(try store.load().lastLocalClock == 12345)
        }

        // Second session against the same file: state survives.
        do {
            let conn = try SQLiteConnection(path: path)
            let store = try SyncStatePersistence(connection: conn)
            let loaded = try store.load()
            #expect(loaded.lastLocalClock == 12345)

            // Overwrite.
            try store.save(SyncState(lastLocalClock: 67890))
        }

        // Third session: latest write wins.
        do {
            let conn = try SQLiteConnection(path: path)
            let store = try SyncStatePersistence(connection: conn)
            #expect(try store.load().lastLocalClock == 67890)
        }
    }

    @Test("InMemoryTransport round-trip")
    func testInMemoryTransportRoundTrip() async throws {
        let transport = InMemoryTransport()
        try await transport.start(deviceId: UUIDV7())

        let change = SyncChange(
            id: UUIDV7(),
            entityType: "test",
            syncKey: Data([1, 2, 3]),
            operation: .insert,
            payload: "{}",
            deviceId: UUIDV7(),
            logicalClock: 1,
            schemaVersion: 1,
            createdAt: Date()
        )
        try await transport.enqueue([change])
        let pendingBefore = await transport.pendingSnapshot
        #expect(pendingBefore.count == 1)

        let cycle = try await transport.syncNow()
        #expect(cycle.pushed == [change.id])
        let pendingAfter = await transport.pendingSnapshot
        #expect(pendingAfter.isEmpty)

        await transport.stop()
    }
}
