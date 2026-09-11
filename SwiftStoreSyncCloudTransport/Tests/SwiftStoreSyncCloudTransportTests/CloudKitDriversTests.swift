import Foundation
import Testing
import CloudKit
import SwiftStoreCore
import SwiftStoreChangeTracker
@testable import SwiftStoreSync
@testable import SwiftStoreSyncCloudTransport

@Entity
struct DriverNote {
    var id: UUIDV7 = UUIDV7()
    var title: String
    var createdAt: Date = Date(timeIntervalSince1970: 1)
    var updatedAt: Date = Date(timeIntervalSince1970: 1)
}

actor DriverStore: CloudSyncStore {
    let session = UUID()
    private let db: SQLiteConnection
    private let manager: SyncManager
    private let clock = Mutex<Int64>(10_000)
    var failApply = false
    var batchSizes: [Int] = []

    init(path: String = ":memory:") throws {
        db = try SQLiteConnection(path: path)
        if try !db.tableExists(DriverNote.tableName) {
            for sql in SchemaSnapshot(entities: [DriverNote.self]).creationStatements { try db.execute(sql) }
        }
        let clock = clock
        manager = try SyncManager(connection: db, deviceID: UUIDV7(), entities: [DriverNote.self], schemaVersion: 1,
            now: { clock.withLock { $0 } })
        try manager.startTracking()
    }
    func insert(_ title: String) throws -> DriverNote {
        let note = DriverNote(title: title); try db.insert(note)
        return try #require(try DriverNote.filter(\.id == note.id).first(db))
    }
    func edit(_ note: DriverNote, title: String, time: Int64) throws {
        clock.withLock { $0 = time }
        try db.execute("UPDATE driver_note SET title=? WHERE id=?", values: [.text(title), .blob(note.id.data)])
    }
    func rows() throws -> [DriverNote] { try DriverNote.all(db) }
    func logs() throws -> [ChangeLog] { try ChangeTrackerReader(connection: db).changes(after: 0, limit: 10000) }
    func injectApplyFailure() { failApply = true }
    func checkpoint() throws -> Data? { try db.queryScalar("SELECT checkpoint FROM __swiftstore_cloud_state WHERE singleton=1") }
    func seedDeletions(_ count: Int) throws {
        try db.transaction {
            for _ in 0..<count {
                let key = SyncKeyEncoder.encode([.blob(UUIDV7().data)])
                try SyncLogStorage.append(ChangeLog(entityType: DriverNote.tableName, syncKey: key, operation: .delete,
                    payload: nil, deviceId: UUIDV7(), logicalClock: 10_000, schemaVersion: 1,
                    createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 10)), to: db)
            }
        }
    }
    func bindCloudAccount(_ accountID: String, scope: String, driver: CloudDriverKind, session: UUID) throws -> CloudStoreState {
        try manager.bind(accountID: accountID, scope: scope, driver: driver)
    }
    func nextCloudBatch(limit: Int, session: UUID) throws -> CloudUploadBatch? {
        let batch = try manager.nextBatch(limit: limit)
        if let batch { batchSizes.append(batch.events.count) }
        return batch
    }
    func commitCloudBatch(_ batch: CloudUploadBatch, decisions: [CloudUploadDecision], session: UUID) throws -> CloudCommitCounts {
        try manager.commit(batch, incoming: decisions)
    }
    func applyCloudRecords(_ records: [CloudRecord], checkpoint: CloudCheckpoint?, session: UUID) throws -> Int {
        if failApply { failApply = false; throw SyncError.applyFailed("Injected local persistence failure") }
        return try manager.receive(records, checkpoint: checkpoint)
    }
    func saveCloudCheckpoint(_ checkpoint: CloudCheckpoint, session: UUID) throws { try manager.saveCheckpoint(checkpoint) }
    func markCloudZoneCreated(session: UUID) throws { try manager.markZoneCreated() }
    func cloudSyncState(session: UUID) throws -> SyncState { try manager.state() }
}

/// A deterministic CloudKit service fixture. Conflicts expose a server version;
/// the next request may commit only if that observed version has not changed.
/// Production code still uses CloudKit's native ifServerRecordUnchanged save policy.
actor CloudServiceFixture: CloudKitOperationsClient {
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var inspected: [UUIDV7: UUIDV7] = [:]
    private var feed: [CKRecord] = []
    private var failures: Set<String> = []
    private var account = "account"
    private var lostResponse = false
    private var expire = false
    private var switchDuringPreparation = false
    private var onSave: (@Sendable () async throws -> Void)?
    var saveRequests: [[UUIDV7]] = []
    var fetchedTokens: [Data?] = []
    var zonePreparations: [Bool] = []

    func accountID() -> String { account }
    func prepareZone(create: Bool) {
        zonePreparations.append(create)
        if switchDuringPreparation { switchDuringPreparation = false; account = "other" }
    }
    func switchAccountDuringPreparation() { switchDuringPreparation = true }
    func save(_ incoming: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        saveRequests.append(incoming.compactMap { SyncChange(ckRecord: $0)?.id })
        if let onSave { self.onSave = nil; try await onSave() }
        var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        for record in incoming {
            if failures.contains(record.recordID.recordName) { results[record.recordID] = .failure(CKError(.networkFailure)); continue }
            let candidate = try #require(SyncChange(ckRecord: record))
            if let old = records[record.recordID], let previous = SyncChange(ckRecord: old),
               previous.id == candidate.id || inspected[candidate.id] != previous.id {
                inspected[candidate.id] = previous.id
                results[record.recordID] = .failure(CKError(.serverRecordChanged,
                    userInfo: [CKRecordChangedErrorServerRecordKey: old]))
            } else {
                records[record.recordID] = record; feed.append(record)
                results[record.recordID] = .success(record)
            }
        }
        if lostResponse { lostResponse = false; throw CKError(.networkFailure) }
        return results
    }
    func fetch(since token: Data?) throws -> CloudKitChangesPage {
        fetchedTokens.append(token)
        if expire { expire = false; throw CKError(.changeTokenExpired) }
        let start = token.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? 0
        guard start <= feed.count else { throw CKError(.changeTokenExpired) }
        let end = min(feed.count, start + 200)
        return CloudKitChangesPage(records: Array(feed[start..<end]), token: Data(String(end).utf8), moreComing: end < feed.count)
    }
    func install(_ record: CKRecord) { records[record.recordID] = record; feed.append(record) }
    func fail(_ keys: Set<String>) { failures = keys }
    func loseNextResponse() { lostResponse = true }
    func expireNextToken() { expire = true }
    func switchAccount() { account = "other" }
    func duringSave(_ action: @escaping @Sendable () async throws -> Void) { onSave = action }
    var writeCount: Int { feed.count }
}

@Suite("Shared CloudKit drivers and real SQLite checkpoints")
struct CloudKitDriversTests {
    private let zone = CKRecordZone.ID(zoneName: "test")
    private func driver(_ store: DriverStore, _ service: CloudServiceFixture, batchSize: Int = 200) -> CloudKitOperationsTransport {
        var settings = CloudKitOperationsSettings(zoneID: zone, recordType: "Change", namespace: "scope")
        settings.automaticallySync = false
        return CloudKitOperationsTransport(settings: settings, client: service, store: store, session: store.session, batchSize: batchSize)
    }
    private func accurateTime<T>(_ body: () async throws -> T) async throws -> T {
        try await NTPClient.$testStartupCheck.withValue(NTPStartupCheck(query: {
            .init(offsetMs: 0, isValid: true, server: "fixture", rttMs: 1)
        }), operation: body)
    }
    private func record(_ note: DriverNote, time: Double, title: String, delete: Bool = false) throws -> CKRecord {
        var note = note; note.title = title; note.updatedAt = Date(timeIntervalSince1970: time)
        let change = SyncChange(id: UUIDV7(), entityType: DriverNote.tableName,
            syncKey: SyncKeyEncoder.encode([.blob(note.id.data)]), operation: delete ? .delete : .update,
            payload: delete ? nil : String(decoding: try JSONEncoder().encode(note), as: UTF8.self), deviceId: UUIDV7(),
            logicalClock: 0, createdAt: note.updatedAt)
        return try change.makeCKRecord(zoneID: zone, recordType: "Change", assetThreshold: 700_000)
    }

    @Test("Two clients converge after offline edits, ties and deletion without upload echoes")
    func twoClients() async throws {
        try await accurateTime {
            let service = CloudServiceFixture(), a = try DriverStore(), b = try DriverStore()
            let da = driver(a, service), db = driver(b, service)
            let note = try await a.insert("initial")
            _ = try await da.sync(); _ = try await db.sync()
            #expect(try await b.rows().first?.title == "initial")
            #expect(try await b.logs().isEmpty)
            try await a.edit(note, title: "A offline", time: 30_000)
            try await b.edit(note, title: "B offline", time: 20_000)
            _ = try await db.sync(); _ = try await da.sync(); _ = try await db.sync()
            #expect(try await a.rows().first?.title == "A offline")
            #expect(try await b.rows().first?.title == "A offline")
            await service.install(try record(note, time: 40, title: "", delete: true))
            _ = try await da.sync(); _ = try await db.sync()
            #expect(try await a.rows().isEmpty)
            #expect(try await b.rows().isEmpty)
            #expect(try await a.logs().count == 2)
            #expect(try await b.logs().count == 1)
            await da.stop(); await db.stop()
        }
    }

    @Test("Lost response replays the original change ID and does not write the cloud twice")
    func lostResponse() async throws {
        try await accurateTime {
            let service = CloudServiceFixture(), store = try DriverStore()
            _ = try await store.insert("once")
            let driver = driver(store, service)
            await service.loseNextResponse()
            await #expect(throws: CKError.self) { try await driver.sync() }
            #expect(try await store.cloudSyncState(session: store.session).pushCursor == 0)
            _ = try await driver.sync()
            let requests = await service.saveRequests
            #expect(requests.count == 2 && requests[0] == requests[1])
            #expect(await service.writeCount == 1)
            #expect(try await store.cloudSyncState(session: store.session).pushCursor == 1)
            await driver.stop()
        }
    }

    @Test("Partial batch failure survives restart without losing coalesced coverage")
    func partialRestart() async throws {
        try await accurateTime {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent("store.sqlite").path
            let service = CloudServiceFixture(), store = try DriverStore(path: path)
            let a = try await store.insert("A"), b = try await store.insert("B")
            try await store.edit(a, title: "A2", time: 11_000)
            let name = SyncChange.recordName(entityType: DriverNote.tableName, syncKey: SyncKeyEncoder.encode([.blob(b.id.data)]))
            await service.fail([name])
            let first = driver(store, service)
            await #expect(throws: CKError.self) { try await first.sync() }
            #expect(try await store.cloudSyncState(session: store.session).pushCursor == 1)
            await first.stop(); await service.fail([])
            let restored = try DriverStore(path: path), second = driver(restored, service)
            _ = try await second.sync()
            #expect(try await restored.cloudSyncState(session: restored.session).pushCursor == 3)
            #expect(await service.writeCount == 2)
            #expect(try await restored.logs().count == 3)
            await second.stop()
        }
    }

    @Test("Failed local application retains the token and CloudKit replays the same page")
    func failedPull() async throws {
        try await accurateTime {
            let service = CloudServiceFixture(), store = try DriverStore()
            let remote = try record(DriverNote(title: "remote"), time: 20, title: "remote")
            await service.install(remote); await store.injectApplyFailure()
            let driver = driver(store, service)
            await #expect(throws: SyncError.self) { try await driver.sync() }
            #expect(try await store.checkpoint() == nil)
            _ = try await driver.sync()
            #expect(await service.fetchedTokens == [nil,nil])
            #expect(try await store.rows().count == 1)
            #expect(try await store.logs().isEmpty)
            await driver.stop()
        }
    }

    @Test("Expired tokens refetch safely without deleting local data or echoing records")
    func expiredToken() async throws {
        try await accurateTime {
            let service = CloudServiceFixture(), store = try DriverStore()
            _ = try await store.insert("local")
            let driver = driver(store, service)
            _ = try await driver.sync(); await service.expireNextToken()
            _ = try await driver.sync()
            #expect(await service.fetchedTokens == [nil,Data("1".utf8),nil])
            #expect(try await store.rows().count == 1)
            #expect(try await store.logs().count == 1)
            await driver.stop()
        }
    }

    @Test("Writes during a network request enter a later frozen batch with a new event ID")
    func concurrentWrite() async throws {
        try await accurateTime {
            let service = CloudServiceFixture(), store = try DriverStore()
            let note = try await store.insert("first")
            await service.duringSave { try await store.edit(note, title: "second", time: 20_000) }
            let driver = driver(store, service, batchSize: 1)
            _ = try await driver.sync()
            let events = try await store.logs()
            let requests = await service.saveRequests
            #expect(events.count == 2 && requests.first == [events[0].id])
            #expect(requests.dropFirst().allSatisfy { $0 == [events[1].id] })
            #expect(try await store.rows().first?.title == "second")
            await driver.stop()
        }
    }

    @Test("Thousands of pending deletions are read and confirmed in bounded batches")
    func bulkDeletions() async throws {
        try await accurateTime {
            let service = CloudServiceFixture(), store = try DriverStore()
            try await store.seedDeletions(2610)
            let driver = driver(store, service)
            let started = ContinuousClock.now
            _ = try await driver.sync()
            #expect(try await store.cloudSyncState(session: store.session).pushCursor == 2610)
            #expect(await service.saveRequests.count == 14)
            #expect(await store.batchSizes.allSatisfy { $0 <= 200 })
            #expect(try await store.logs().count == 2610)
            print("CloudKit 2610 tombstones: \(started.duration(to: .now)), 14 upload batches")
            await driver.stop()
        }
    }

    @Test("Account change during zone preparation prevents uploading the original account's data")
    func accountSwitchBeforeUpload() async throws {
        try await accurateTime {
            let service = CloudServiceFixture(), store = try DriverStore()
            _ = try await store.insert("private")
            await service.switchAccountDuringPreparation()
            let driver = driver(store, service)
            await #expect(throws: SyncError.self) { try await driver.sync() }
            #expect(await service.saveRequests.isEmpty)
            #expect(try await store.cloudSyncState(session: store.session).pushCursor == 0)
            await driver.stop()
        }
    }

    @Test("iCloud account switch during upload cannot confirm progress for another account")
    func accountSwitch() async throws {
        try await accurateTime {
            let service = CloudServiceFixture(), store = try DriverStore()
            _ = try await store.insert("private")
            await service.duringSave { await service.switchAccount() }
            let driver = driver(store, service)
            await #expect(throws: SyncError.self) { try await driver.sync() }
            #expect(try await store.cloudSyncState(session: store.session).pushCursor == 0)
            #expect(try await store.logs().count == 1)
            await driver.stop()
        }
    }
}
