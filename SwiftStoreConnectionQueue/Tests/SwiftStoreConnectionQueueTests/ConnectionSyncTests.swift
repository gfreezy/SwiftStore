import Testing
import Foundation
import SwiftStoreCore
@testable import SwiftStoreSync
@testable import SwiftStoreConnectionQueue

@Entity
struct ConnectionSyncNote {
    var id: UUIDV7 = UUIDV7()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

private actor RecordingSyncTransport: SyncTransport {
    nonisolated let remoteChanges = AsyncStream<Void> { _ in }
    var changes: [SyncChange] = []
    var calls = 0
    var stops = 0
    func start(deviceId: UUIDV7) async throws {}
    func stop() async { stops += 1 }
    func enqueue(_ changes: [SyncChange]) async throws { self.changes.append(contentsOf: changes) }
    func syncNow() async throws -> SyncCycleResult {
        calls += 1
        return SyncCycleResult(pulled: [], pushed: changes.map(\.id), conflicts: [])
    }
}

@Suite("ConnectionManager synchronization")
struct ConnectionSyncTests {
    private func history() -> [StoreMigration] {
        let schema = SchemaSnapshot(entities: [ConnectionSyncNote.self])
        return [StoreMigration(id: "001_initial", target: schema) { db in
            for sql in schema.creationStatements { try db.execute(sql) }
        }]
    }

    @Test("Migration starts tracking, rollback is excluded, and later writes automatically sync")
    func automaticSync() async throws {
        try await NTPClient.$testTimeQuery.withValue({
            NTPVerificationResult(offsetMs: 0, isValid: true, server: "test", rttMs: 1)
        }) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let transport = RecordingSyncTransport()
            let manager = try ConnectionManager(path: dir.appendingPathComponent("main.sqlite").path,
                entities: [ConnectionSyncNote.self], syncConfig: SyncOptions(
                    deviceId: UUIDV7(), transport: transport, schemaVersion: 1,
                    tickClock: { 10 }, ntpToleranceMs: 5000))
            try await manager.migrate(migrations: history())
            let hasLegacyTable = try await manager.read { try $0.tableExists("__swiftstore_pending_deletes") }
            #expect(!hasLegacyTable)
            try await manager.write { try $0.insert(ConnectionSyncNote(title: "first")) }
            enum Rollback: Error { case requested }
            await #expect(throws: Rollback.self) {
                try await manager.write { connection in
                    try connection.insert(ConnectionSyncNote(title: "rolled back"))
                    throw Rollback.requested
                }
            }
            _ = try await manager.sync()
            #expect(await transport.changes.count == 1)
            try await manager.write { try $0.insert(ConnectionSyncNote(title: "automatic")) }
            for _ in 0..<200 {
                if await transport.changes.count == 2 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(await transport.changes.count == 2)
            await manager.stopSync()
            try await manager.write { try $0.insert(ConnectionSyncNote(title: "while stopped")) }
            #expect(await transport.changes.count == 2)
            _ = try await manager.sync()
            #expect(await transport.changes.count == 3)
            await manager.stopSync()
        }
    }

    @Test("Enabling sync reuses the local schema and uploads preexisting rows once")
    func existingRows() async throws {
        try await NTPClient.$testTimeQuery.withValue({
            NTPVerificationResult(offsetMs: 0, isValid: true, server: "test", rttMs: 1)
        }) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = dir.appendingPathComponent("main.sqlite").path
            let local = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self])
            try await local.migrate(migrations: history())
            try await local.write { try $0.insert(ConnectionSyncNote(title: "before sync")) }
            let transport = RecordingSyncTransport()
            let deviceID = UUIDV7()
            let manager = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self],
                syncConfig: SyncOptions(deviceId: deviceID, transport: transport,
                    schemaVersion: 1, ntpToleranceMs: 5000))
            try await manager.migrate(migrations: history())
            _ = try await manager.sync()
            #expect(try await manager.read {
                try $0.queryScalar("SELECT COUNT(*) FROM __swiftstore_migrations", type: Int.self)
            } == 1)
            #expect(await transport.changes.count == 1)
            await manager.stopSync()
            let restarted = try ConnectionManager(path: path, entities: [ConnectionSyncNote.self],
                syncConfig: SyncOptions(deviceId: deviceID, transport: transport,
                    schemaVersion: 1, ntpToleranceMs: 5000))
            try await restarted.migrate(migrations: history())
            _ = try await restarted.sync()
            #expect(await transport.changes.count == 1)
            await restarted.stopSync()
        }
    }
}
