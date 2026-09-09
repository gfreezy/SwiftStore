import Foundation
import Testing
import CloudKit
import SwiftStoreCore
import SwiftStoreSync
@testable import SwiftStoreSyncCloudTransport

private actor OperationsMemoryStore: CloudKitSyncStateStore {
    var state: CloudKitSyncJournal?
    var failNext = false
    func loadJournal() -> CloudKitSyncJournal? { state }
    func saveJournal(_ value: CloudKitSyncJournal) throws {
        if failNext { failNext = false; throw CKError(.networkFailure) }
        state = value
    }
    func fail() { failNext = true }
}

private actor OperationsClientStub: CloudKitOperationsClient {
    var account = "test-account"
    var pages: [CloudKitChangesPage] = []
    var fetchedTokens: [Data?] = []
    var saved: [CKRecord] = []
    var conflict: CKRecord?
    var expireOnce = false
    var failFetch = false
    var saveFailure: Error?
    var onSave: (@Sendable () async throws -> Void)?
    var onFetch: (@Sendable () async throws -> Void)?
    var prepared: [Bool] = []

    func accountID() -> String { account }
    func prepareZone(create: Bool) { prepared.append(create) }
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        if let action = onSave { onSave = nil; try await action() }
        saved += records
        if let conflict {
            self.conflict = nil
            return [records[0].recordID: .failure(CKError(.serverRecordChanged,
                userInfo: [CKRecordChangedErrorServerRecordKey: conflict]))]
        }
        return Dictionary(uniqueKeysWithValues: records.map {
            ($0.recordID, saveFailure.map { .failure($0) } ?? .success($0))
        })
    }
    func fetch(since token: Data?) async throws -> CloudKitChangesPage {
        fetchedTokens.append(token)
        if let action = onFetch { onFetch = nil; try await action() }
        if expireOnce { expireOnce = false; throw CKError(.changeTokenExpired) }
        if failFetch { throw CKError(.networkFailure) }
        return pages.isEmpty ? CloudKitChangesPage(records: [], token: Data([99]), moreComing: false) : pages.removeFirst()
    }
    func configure(pages: [CloudKitChangesPage] = [], conflict: CKRecord? = nil,
                   expire: Bool = false, failFetch: Bool = false,
                   onSave: (@Sendable () async throws -> Void)? = nil,
                   onFetch: (@Sendable () async throws -> Void)? = nil) {
        self.pages = pages; self.conflict = conflict; expireOnce = expire; self.failFetch = failFetch
        self.onSave = onSave; self.onFetch = onFetch
    }
    func changeAccount() { account = "different-account" }
}

@Suite("iOS 16 CloudKit operations adapter")
struct CloudKitOperationsTests {
    private let zone = CKRecordZone.ID(zoneName: "test")
    private func change(_ time: Int, key: UInt8 = 1) -> SyncChange {
        SyncChange(id: UUIDV7(), entityType: "note", syncKey: Data([key]), operation: .update,
            payload: "{\"updatedAt\":\(time)}", deviceId: UUIDV7(), logicalClock: Int64(time),
            createdAt: Date(timeIntervalSinceReferenceDate: Double(time)))
    }
    private func record(_ change: SyncChange) throws -> CKRecord {
        try change.makeCKRecord(zoneID: zone, recordType: "Change", assetThreshold: 700_000)
    }
    private func adapter(_ client: OperationsClientStub, _ store: OperationsMemoryStore) -> CloudKitOperationsTransport {
        var settings = CloudKitOperationsSettings(zoneID: zone, recordType: "Change", namespace: "test")
        settings.automaticallySync = false
        return CloudKitOperationsTransport(settings: settings, client: client, stateStore: store, validateTime: { _ in })
    }

    @Test("Upload conflict uses shared timestamp rule and pull supplies the winner")
    func conflictAndPagination() async throws {
        let client = OperationsClientStub(), store = OperationsMemoryStore()
        let transport = adapter(client, store)
        let old = change(10), winner = change(20), another = change(30, key: 2)
        let remote = try record(winner)
        await client.configure(pages: [
            CloudKitChangesPage(records: [remote], token: Data([1]), moreComing: true),
            CloudKitChangesPage(records: [try record(another)], token: Data([2]), moreComing: false)
        ], conflict: remote)
        try await transport.start(deviceId: UUIDV7())
        try await transport.enqueue([old])
        let result = try await transport.syncNow()
        #expect(result.conflicts.map(\.id) == [old.id])
        #expect(Set(result.pulled.map(\.id)) == [winner.id, another.id])
        #expect(result.pendingChanges.isEmpty)
        #expect(await client.fetchedTokens == [nil, Data([1])])
        let persisted = await store.loadJournal()
        #expect(persisted?.zoneChangeToken == Data([2]))
        await transport.stop()
        let restarted = adapter(client, store)
        try await restarted.start(deviceId: UUIDV7())
        #expect(await client.prepared == [true, false])
        let replay = try await restarted.syncNow()
        #expect(Set(replay.pulled.map(\.id)) == [winner.id, another.id])
        try await restarted.acknowledge(replay)
        #expect(await store.loadJournal()?.inbox.isEmpty == true)
    }

    @Test("New local work during an upload is retained for the next cycle")
    func concurrentEnqueue() async throws {
        let client = OperationsClientStub(), store = OperationsMemoryStore()
        let transport = adapter(client, store)
        let first = change(10), next = change(20)
        try await transport.start(deviceId: UUIDV7())
        try await transport.enqueue([first])
        await client.configure(onSave: { try await transport.enqueue([next]) })
        let result = try await transport.syncNow()
        #expect(result.pushed == [first.id])
        #expect(result.pendingChanges.map(\.id) == [next.id])
        #expect(await client.saved.count == 1)
        let second = try await transport.syncNow()
        #expect(second.pushed.contains(next.id))
        #expect(second.pendingChanges.isEmpty)
    }

    @Test("Newer local edits retry a conditional-save conflict before fetching")
    func localWinnerRetries() async throws {
        let client = OperationsClientStub(), store = OperationsMemoryStore()
        let transport = adapter(client, store)
        let local = change(20), older = change(10)
        try await transport.start(deviceId: UUIDV7())
        try await transport.enqueue([local])
        await client.configure(conflict: try record(older))
        let result = try await transport.syncNow()
        #expect(await client.saved.count == 2)
        #expect(result.pushed == [local.id])
        #expect(result.conflicts.isEmpty)
        #expect(result.pendingChanges.isEmpty)
        #expect(await store.loadJournal()?.committedVersions[CloudKitSyncJournal.key(local)]?.id == local.id)
    }

    @Test("Time validation failure retains staged work without sending")
    func timeValidation() async throws {
        let client = OperationsClientStub(), store = OperationsMemoryStore()
        var settings = CloudKitOperationsSettings(zoneID: zone, recordType: "Change", namespace: "test")
        settings.automaticallySync = false
        let calls = Mutex(0)
        let transport = CloudKitOperationsTransport(settings: settings, client: client, stateStore: store,
            validateTime: { _ in
                let count = calls.withLock { $0 += 1; return $0 }
                if count > 1 { throw CKError(.networkFailure) }
            })
        try await transport.start(deviceId: UUIDV7())
        let local = change(20)
        try await transport.enqueue([local])
        await #expect(throws: (any Error).self) { try await transport.syncNow() }
        #expect(await client.saved.isEmpty)
        #expect(await store.loadJournal()?.queuedPush.map(\.id) == [local.id])
    }

    @Test("Malformed download and persistence failure never advance the page token")
    func failedPage() async throws {
        for corrupt in [false, true] {
            let client = OperationsClientStub(), store = OperationsMemoryStore()
            let transport = adapter(client, store)
            let remote = try record(change(10))
            if corrupt { remote[SyncChange.RecordField.payload] = nil }
            try await transport.start(deviceId: UUIDV7())
            await client.configure(pages: [CloudKitChangesPage(records: [remote], token: Data([1]), moreComing: false)],
                onFetch: { if !corrupt { await store.fail() } })
            await #expect(throws: (any Error).self) { try await transport.syncNow() }
            #expect(await store.loadJournal()?.zoneChangeToken == nil)
            #expect(await store.loadJournal()?.inbox.isEmpty == true)
        }
    }

    @Test("Expired tokens refetch from nil without discarding unacknowledged data")
    func expiredToken() async throws {
        let client = OperationsClientStub(), store = OperationsMemoryStore()
        let transport = adapter(client, store)
        let remote = try record(change(10))
        try await transport.start(deviceId: UUIDV7())
        await client.configure(pages: [CloudKitChangesPage(records: [remote], token: Data([1]), moreComing: false)])
        _ = try await transport.syncNow()
        await client.configure(expire: true)
        let result = try await transport.syncNow()
        #expect(result.pulled.count == 1)
        #expect(await client.fetchedTokens == [nil, Data([1]), nil])
    }

    @Test("Account changes and stopped in-flight downloads cannot overwrite durable state")
    func sessionFence() async throws {
        let client = OperationsClientStub(), store = OperationsMemoryStore()
        let transport = adapter(client, store)
        try await transport.start(deviceId: UUIDV7())
        await client.configure(onFetch: { await transport.stop() })
        await #expect(throws: (any Error).self) { try await transport.syncNow() }
        #expect(await store.loadJournal()?.zoneChangeToken == nil)
        try await transport.start(deviceId: UUIDV7())
        await client.changeAccount()
        await #expect(throws: (any Error).self) { try await transport.syncNow() }
        #expect(await store.loadJournal()?.accountID == "test-account")
        #expect(await client.saved.isEmpty)
    }

    @Test("Upload receipts survive a failed pull and are delivered on retry")
    func uploadThenNetworkFailure() async throws {
        let client = OperationsClientStub(), store = OperationsMemoryStore()
        let transport = adapter(client, store)
        let local = change(10)
        try await transport.start(deviceId: UUIDV7())
        try await transport.enqueue([local])
        await client.configure(failFetch: true)
        await #expect(throws: (any Error).self) { try await transport.syncNow() }
        #expect(await store.loadJournal()?.pushed == [local.id])
        await client.configure()
        let result = try await transport.syncNow()
        #expect(result.pushed == [local.id])
        #expect(await client.saved.count == 1)
    }
}
