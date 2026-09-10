import Testing
import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker
@testable import SwiftStoreSync

@Entity
struct SyncNote {
    var id: UUIDV7 = UUIDV7()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

actor AcknowledgedTransport: SyncTransport {
    nonisolated let remoteChanges: AsyncStream<Void> = AsyncStream { _ in }
    var inbox: [SyncChange] = []
    var queued: [SyncChange] = []
    var acknowledged: [UUIDV7] = []
    var fails = false
    var starts = 0
    var calls = 0
    var pending: [SyncChange] = []
    var rejections = SyncRejectionStore()
    var duringSync: (@Sendable () async throws -> Void)?
    func start(deviceId: UUIDV7) async throws { starts += 1 }
    func stop() async {}
    func enqueue(_ changes: [SyncChange]) async throws { queued.append(contentsOf: changes) }
    func stage(_ changes: [SyncChange]) { inbox.append(contentsOf: changes) }
    func setFailure(_ value: Bool) { fails = value }
    func setPending(_ pending: [SyncChange] = []) { self.pending = pending }
    func reject(_ change: SyncChange, with version: SyncChange) {
        rejections.record(change, serverVersion: version)
        rejections.finishPull()
    }
    func setSyncHook(_ hook: (@Sendable () async throws -> Void)?) { duringSync = hook }
    func syncNow() async throws -> SyncCycleResult {
        calls += 1
        if fails { throw SyncError.invalidPayload("simulated network failure") }
        try await duringSync?()
        return SyncCycleResult(pulled: inbox, pushed: queued.map(\.id), conflicts: [],
            pendingChanges: pending, rejectedKeys: rejections.entries)
    }
    func acknowledge(_ result: SyncCycleResult) async throws {
        rejections.acknowledge(applied: result.pulled, rejectedKeys: result.rejectedKeys)
        let ids = Set(result.pulled.map(\.id))
        inbox.removeAll { ids.contains($0.id) }
        acknowledged.append(contentsOf: ids)
    }
}

@MainActor
final class SyncFixture {
    let directory: URL
    let connection: SQLiteConnection
    let transport = AcknowledgedTransport()
    let manager: SyncManager
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        connection = try SQLiteConnection(path: directory.appendingPathComponent("main.sqlite").path)
        let snapshot = SchemaSnapshot(entities: [SyncNote.self])
        let initial = StoreMigration(id: "001_fixture", target: snapshot) { db in
            for sql in snapshot.creationStatements { try db.execute(sql) }
        }
        try VersionedMigrator(connection: connection, migrations: [initial]).migrate()
        manager = try SyncManager(connection: connection, config: SyncConfig(
            changeLogDbPath: directory.appendingPathComponent("changes.sqlite").path,
            deviceId: UUIDV7(), registeredEntities: [SyncNote.self], transport: transport,
            schemaVersion: 1, tickClock: { 100 }, ntpToleranceMs: 5000))
        try manager.startTracking()
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    func remote(_ note: SyncNote, time: TimeInterval, schema: Int = 1, delete: Bool = false) throws -> SyncChange {
        var row = note
        row.updatedAt = Date(timeIntervalSince1970: time)
        return SyncChange(id: UUIDV7(), entityType: SyncNote.tableName,
            syncKey: SyncKeyEncoder.encode([.blob(note.id.data)]), operation: delete ? .delete : .update,
            payload: delete ? nil : String(decoding: try JSONEncoder().encode(row), as: UTF8.self),
            deviceId: UUIDV7(), logicalClock: Int64(1000000 - time), schemaVersion: schema,
            createdAt: Date(timeIntervalSince1970: time))
    }

}

@Suite("Sync pipeline recovery")
@MainActor
struct SyncPipelineTests {
    @Test("Rejected corrections are acknowledged only after the server version reaches the business table")
    func rejectedCorrectionApplyAcknowledgement() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: {
            NTPVerificationResult(offsetMs: 0, isValid: true, server: "test", rttMs: 1)
        })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let note = SyncNote(title: "server")
            let rejected = try f.remote(note, time: 100)
            let winner = try f.remote(note, time: 200)
            await f.transport.stage([winner])
            await f.transport.reject(rejected, with: winner)
            await f.transport.setPending([rejected])
            _ = try await f.manager.sync()
            #expect(await f.transport.rejections.entries.count == 1)
            #expect(await f.transport.acknowledged.isEmpty)
            await f.transport.setPending()
            let applied = try await f.manager.sync()
            #expect(applied.pulledCount == 1)
            #expect(await f.transport.rejections.entries.isEmpty)
            #expect(await f.transport.acknowledged == [winner.id])
        }
    }

    @Test("Local changes are tracked immediately and clocks do not repeat")
    func trackingAndClocks() throws {
        let f = try SyncFixture()
        defer { f.cleanup() }
        try f.connection.insert(SyncNote(title: "one"))
        try f.connection.insert(SyncNote(title: "two"))
        let changes = try f.manager.allChanges()
        #expect(changes.count == 2)
        #expect(changes[1].logicalClock > changes[0].logicalClock)
        let payload = try #require(changes[0].payload)
        let decoded = try JSONDecoder().decode(SyncNote.self, from: Data(payload.utf8))
        #expect(abs(decoded.createdAt.timeIntervalSinceNow) < 10)
    }

    @Test("Failed network round keeps the staged watermark and retries without duplicate enqueue")
    func retryUpload() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: {
            NTPVerificationResult(offsetMs: 0, isValid: true, server: "test", rttMs: 1)
        })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            try f.connection.insert(SyncNote(title: "offline"))
            await f.transport.setFailure(true)
            await #expect(throws: SyncError.self) { try await f.manager.sync() }
            #expect(f.manager.syncState.lastLocalClock > 0)
            await f.transport.setFailure(false)
            _ = try await f.manager.sync()
            #expect(await f.transport.queued.count == 1)
        }
    }

    @Test("Apply failure and future schema stay unacknowledged")
    func failedApply() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: {
            NTPVerificationResult(offsetMs: 0, isValid: true, server: "test", rttMs: 1)
        })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let note = SyncNote(title: "future")
            let future = try f.remote(note, time: 200, schema: 2)
            let invalid = SyncChange(id: UUIDV7(), entityType: SyncNote.tableName,
                syncKey: SyncKeyEncoder.encode([.blob(UUIDV7().data)]), operation: .insert,
                payload: "not JSON", deviceId: UUIDV7(), logicalClock: 300, createdAt: Date())
            await f.transport.stage([future, invalid])
            let result = try await f.manager.sync()
            #expect(result.pulledCount == 0)
            #expect(result.conflictCount == 1)
            #expect(await f.transport.inbox.count == 2)
            #expect(await f.transport.acknowledged.isEmpty)
        }
    }

    @Test("Committed updates, deletions and recreations apply without being uploaded again")
    func committedLifecycle() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: {
            NTPVerificationResult(offsetMs: 0, isValid: true, server: "test", rttMs: 1)
        })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let note = SyncNote(title: "committed")
            await f.transport.stage([try f.remote(note, time: 200)])
            #expect(try await f.manager.sync().pulledCount == 1)
            #expect(try SyncNote.all(f.connection).first?.title == "committed")
            await f.transport.stage([try f.remote(note, time: 300, delete: true)])
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).isEmpty)
            await f.transport.stage([try f.remote(note, time: 400)])
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).first?.updatedAt.timeIntervalSince1970 == 400)
            #expect(try f.manager.allChanges().isEmpty)
            #expect(await f.transport.inbox.isEmpty)
        }
    }

}

@Suite("Startup sync time validation")
@MainActor
struct MandatorySyncTimeTests {
    @Test("Signed tolerance boundaries are inclusive; extreme offsets fail safely",
        arguments: [Int64.min, -5001, -5000, 0, 5000, 5001, Int64.max])
    func bounds(offset: Int64) async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: {
            NTPVerificationResult(offsetMs: offset, isValid: true, server: "test", rttMs: 1)
        })) {
            if offset >= -5000 && offset <= 5000 {
                try await NTPClient.requireAccurateTime(toleranceMs: 5000)
            } else {
                await #expect(throws: NTPError.self) {
                    try await NTPClient.requireAccurateTime(toleranceMs: 5000)
                }
            }
        }
    }

    @Test("Zero and negative tolerances cannot disable time validation", arguments: [Int64(0), -1])
    func invalidTolerance(value: Int64) async {
        await #expect(throws: NTPError.self) { try await NTPClient.requireAccurateTime(toleranceMs: value) }
    }

    @Test("An out-of-range clock blocks transport startup and sync without advancing queues")
    func badClockBlocksSync() async throws {
        let f = try SyncFixture()
        defer { f.cleanup() }
        try f.connection.insert(SyncNote(title: "local"))
        await f.transport.stage([try f.remote(SyncNote(title: "remote"), time: 100)])
        await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: {
            NTPVerificationResult(offsetMs: 5001, isValid: false, server: "test", rttMs: 1)
        })) {
            await #expect(throws: NTPError.self) { try await f.manager.startTransport() }
            await #expect(throws: NTPError.self) { try await f.manager.sync() }
        }
        #expect(await f.transport.starts == 0)
        #expect(await f.transport.calls == 0)
        #expect(await f.transport.queued.isEmpty)
        #expect(await f.transport.inbox.count == 1)
        #expect(f.manager.syncState.lastLocalClock == 0)
        #expect(try SyncNote.all(f.connection).count == 1)
    }

    @Test("Unavailable startup time allows sync while transport errors still propagate")
    func unavailableTimeAllowsSync() async throws {
        let f = try SyncFixture()
        defer { f.cleanup() }
        try f.connection.insert(SyncNote(title: "offline time source"))
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: { throw NTPError.allServersFailed })) {
            try await f.manager.startTransport()
            await f.transport.setFailure(true)
            await #expect(throws: SyncError.self) { try await f.manager.sync() }
            await f.transport.setFailure(false)
            _ = try await f.manager.sync()
            #expect(await f.transport.starts == 1)
            #expect(await f.transport.queued.count == 1)
        }
    }

    @Test("Transport startup, sync and downloaded batches reuse one startup measurement")
    func reuseStartupMeasurement() async throws {
        let f = try SyncFixture()
        defer { f.cleanup() }
        await f.transport.stage([try f.remote(SyncNote(title: "downloaded"), time: 100)])
        actor Measurements {
            var count = 0
            func next() -> NTPVerificationResult {
                count += 1
                return NTPVerificationResult(offsetMs: count == 1 ? 0 : 6000,
                    isValid: count == 1, server: "test", rttMs: 1)
            }
        }
        let measurements = Measurements()
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: { await measurements.next() })) {
            try await f.manager.startTransport()
            _ = try await f.manager.sync()
            _ = try await f.manager.sync()
        }
        #expect(await measurements.count == 1)
        #expect(try SyncNote.all(f.connection).count == 1)
        #expect(await f.transport.inbox.isEmpty)
        #expect(await f.transport.acknowledged.count == 1)
    }

    @Test("Equal updated_at conflicts preserve the timestamp and restore the local update trigger")
    func equalTimestamp() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: {
            NTPVerificationResult(offsetMs: 0, isValid: true, server: "test", rttMs: 1)
        })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let time = Date(timeIntervalSince1970: 100.125)
            var note = SyncNote(title: "a")
            note.updatedAt = time
            try f.connection.insert(note)
            note.title = "z"
            await f.transport.stage([try f.remote(note, time: 100.125)])
            _ = try await f.manager.sync()
            let applied = try #require(try SyncNote.all(f.connection).first)
            #expect(applied.title == "z")
            #expect(applied.updatedAt == time)
            #expect(try !f.connection.tableExists("__swiftstore_sync_versions"))
            let count: Int64 = try f.connection.queryScalar("SELECT COUNT(*) FROM __swiftstore_sync_tombstones") ?? -1
            #expect(count == 0)
            try f.connection.execute("UPDATE sync_note SET title = 'local again'")
            let updated = try #require(try SyncNote.all(f.connection).first)
            #expect(updated.updatedAt > time)
        }
    }
}

@Suite("Shared backend conflict decision contract")
@MainActor
struct ServerConflictDecisionTests {
    @Test("The server decision replaces local data even when the local comparator would prefer it")
    func serverIsAuthoritative() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: { .init(offsetMs: 0, isValid: true, server: "test", rttMs: 1) })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let time = Date(timeIntervalSince1970: 1000.125)
            let local = SyncNote(title: "z-local", createdAt: time, updatedAt: time)
            try f.connection.insert(local)
            let captured = try #require(f.manager.allChanges().last)
            let serverRow = SyncNote(id: local.id, title: "a-server", createdAt: time, updatedAt: time)
            // A same-device winner must be applied too: it may undo a later rejected edit.
            let winner = SyncChange(id: UUIDV7(), entityType: SyncNote.tableName,
                syncKey: captured.syncKey, operation: .update,
                payload: String(decoding: try JSONEncoder().encode(serverRow), as: UTF8.self),
                deviceId: captured.deviceId, logicalClock: 1, createdAt: time)
            #expect(!winner.isNewer(than: SyncChange(from: captured)))
            await f.transport.setPending()
            await f.transport.stage([winner])
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).first?.title == "a-server")
            #expect(try f.manager.allChanges().count == 1) // Remote apply never re-enters outbox.
        }
    }

    @Test("Unsubmitted local work defers application without acknowledging the server record")
    func pendingProtection() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: { .init(offsetMs: 0, isValid: true, server: "test", rttMs: 1) })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let time = Date(timeIntervalSince1970: 1000.125)
            let local = SyncNote(title: "pending", createdAt: time, updatedAt: time)
            try f.connection.insert(local)
            let captured = SyncChange(from: try #require(f.manager.allChanges().last))
            let serverRow = SyncNote(id: local.id, title: "server", createdAt: time, updatedAt: time)
            let winner = try f.remote(serverRow, time: time.timeIntervalSince1970)
            await f.transport.setPending([captured])
            await f.transport.stage([winner])
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).first?.title == "pending")
            #expect(await f.transport.acknowledged.isEmpty)
            await f.transport.setPending() // The server has now decided the pending upload.
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).first?.title == "server")
            #expect(await f.transport.acknowledged.contains(winner.id))
        }
    }

    @Test("Writes arriving during the request remain protected until the next server round")
    func editsDuringRequest() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: { .init(offsetMs: 0, isValid: true, server: "test", rttMs: 1) })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let local = SyncNote(title: "before")
            try f.connection.insert(local)
            let serverRow = SyncNote(id: local.id, title: "server")
            let winner = try f.remote(serverRow, time: 1000)
            await f.transport.setPending()
            await f.transport.stage([winner])
            await f.transport.setSyncHook {
                try await MainActor.run {
                    _ = try f.connection.execute("UPDATE sync_note SET title = 'during request'")
                }
            }
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).first?.title == "during request")
            #expect(await f.transport.acknowledged.isEmpty)
            await f.transport.setSyncHook(nil)
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).first?.title == "server")
            let uploaded = await f.transport.queued
            let titles = try uploaded.compactMap { change -> String? in
                guard let payload = change.payload else { return nil }
                return try JSONDecoder().decode(SyncNote.self, from: Data(payload.utf8)).title
            }
            #expect(Set(titles) == ["before", "during request"])
        }
    }

    @Test("A retained server row can undo a local deletion without delete-first tie breaking")
    func serverRowAfterLocalDelete() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: { .init(offsetMs: 0, isValid: true, server: "test", rttMs: 1) })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let local = SyncNote(title: "retained")
            try f.connection.insert(local)
            try f.connection.execute("DELETE FROM sync_note")
            let deletion = try #require(f.manager.allChanges().last)
            let winner = try f.remote(local, time: deletion.createdAt.timeIntervalSince1970)
            #expect(!winner.isNewer(than: SyncChange(from: deletion)))
            await f.transport.setPending()
            await f.transport.stage([winner])
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).first?.title == "retained")
            #expect(try f.manager.allChanges().count == 2)
        }
    }

    @Test("Server decisions do not compare timestamps against the local database")
    func noSecondTimestampDecision() async throws {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: { .init(offsetMs: 0, isValid: true, server: "test", rttMs: 1) })) {
            let f = try SyncFixture()
            defer { f.cleanup() }
            let local = SyncNote(title: "local", createdAt: Date(timeIntervalSince1970: 2000), updatedAt: Date(timeIntervalSince1970: 2000))
            try f.connection.insert(local)
            let server = SyncNote(id: local.id, title: "server")
            let winner = try f.remote(server, time: 1000)
            await f.transport.setPending()
            await f.transport.stage([winner])
            _ = try await f.manager.sync()
            #expect(try SyncNote.all(f.connection).first?.title == "server")
            #expect(try SyncNote.all(f.connection).first?.updatedAt.timeIntervalSince1970 == 1000)
        }
    }
}
