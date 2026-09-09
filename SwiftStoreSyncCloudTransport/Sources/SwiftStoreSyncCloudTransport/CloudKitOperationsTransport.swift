import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreSync

/// iOS 16 backend. Only journal mutations hold the state lock; network waits
/// never block enqueue or acknowledgement. A generation fences stopped cycles.
actor CloudKitOperationsTransport: CloudKitBackend {
    private let settings: CloudKitOperationsSettings
    private let client: any CloudKitOperationsClient
    private let stateStore: any CloudKitSyncStateStore
    private let validateTime: @Sendable (Int64) async throws -> Void
    private nonisolated let signal = CloudKitSyncSignal()
    private var journal = CloudKitSyncJournal()
    private var toleranceMs: Int64
    private var running = false
    private var generation = UUID()
    private var activeCycle: UUID?
    private var polling: Task<Void, Never>?
    private var failure: Error?
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(settings: CloudKitOperationsSettings, client: any CloudKitOperationsClient,
         stateStore: any CloudKitSyncStateStore,
         validateTime: @escaping @Sendable (Int64) async throws -> Void = { try await NTPClient.requireAccurateTime(toleranceMs: $0) }) {
        self.settings = settings
        self.client = client
        self.stateStore = stateStore
        self.validateTime = validateTime
        toleranceMs = settings.toleranceMs
    }

    deinit { polling?.cancel() }

    nonisolated var remoteChanges: AsyncStream<Void> { signal.stream }
    nonisolated func notifyRemoteChange() { signal.yield() }
    var lastError: Error? { failure }

    func configureTimeValidation(toleranceMs: Int64) async throws {
        guard toleranceMs > 0 else { throw NTPError.invalidTolerance }
        self.toleranceMs = toleranceMs
    }

    func start(deviceId: UUIDV7) async throws {
        await lock()
        defer { unlock() }
        if running { return }
        try await validateTime(toleranceMs)
        let account = try await client.accountID()
        var loaded = try await stateStore.loadJournal() ?? CloudKitSyncJournal()
        if let previous = loaded.accountID, previous != account { throw CloudKitTransportError.accountChanged }
        if let previous = loaded.namespace, previous != settings.namespace {
            throw CloudKitTransportError.stateCorrupt("State belongs to a different container/zone/record type")
        }
        try await client.prepareZone(create: !loaded.didCreateZone)
        loaded.didCreateZone = true
        loaded.accountID = account
        loaded.namespace = settings.namespace
        try await stateStore.saveJournal(loaded)
        journal = loaded
        generation = UUID()
        running = true
        failure = nil
        signal.start()
        // Foreground fallback for missed pushes. Background delivery is forwarded
        // by the host app; the OS suspends this task along with the app.
        if settings.automaticallySync {
            let signal = signal
            polling = Task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    if !Task.isCancelled { signal.yield() }
                }
            }
        }
        if !journal.inbox.isEmpty || !journal.pendingPush.isEmpty || !journal.queuedPush.isEmpty { signal.yield() }
    }

    func stop() async {
        await lock()
        defer { unlock() }
        running = false
        activeCycle = nil
        generation = UUID()
        polling?.cancel()
        polling = nil
        signal.finish()
    }

    func enqueue(_ changes: [SyncChange]) async throws {
        await lock()
        defer { unlock() }
        guard running else { throw CloudKitTransportError.notStarted }
        var updated = journal
        updated.enqueue(changes)
        try await commit(updated)
    }

    func acknowledge(_ result: SyncCycleResult) async throws {
        await lock()
        defer { unlock() }
        guard running else { throw CloudKitTransportError.notStarted }
        var updated = journal
        updated.acknowledge(result)
        try await commit(updated)
    }

    func syncNow() async throws -> SyncCycleResult {
        guard running else { throw CloudKitTransportError.notStarted }
        guard activeCycle == nil else { throw SyncError.syncAlreadyInProgress("CloudKit sync is already running") }
        let cycle = UUID(), session = generation
        activeCycle = cycle
        failure = nil
        defer { if activeCycle == cycle { activeCycle = nil } }
        do {
            try await checkAccount(session)
            let snapshot = Set((Array(journal.pendingPush.values) + journal.queuedPush).map(\.id))
            var attempts: [UUIDV7: Int] = [:]
            while true {
                let changes = try await prepare(snapshot: snapshot, session: session)
                if changes.isEmpty { break }
                let batch = Array(changes.prefix(200))
                for change in batch {
                    attempts[change.id, default: 0] += 1
                    guard attempts[change.id, default: 0] <= 8 else {
                        throw CloudKitTransportError.sendFailed(underlying: CKError(.serverRecordChanged))
                    }
                }
                try await upload(batch, session: session)
            }
            var resetExpiredToken = false
            while true {
                try await checkAccount(session)
                let cursor = journal.zoneChangeToken
                let page: CloudKitChangesPage
                do { page = try await client.fetch(since: cursor) }
                catch let error as CKError where error.code == .changeTokenExpired && !resetExpiredToken {
                    resetExpiredToken = true
                    try await resetToken(session)
                    continue
                }
                try await checkAccount(session)
                try await apply(page, session: session)
                if !page.moreComing { break }
            }
            await lock()
            defer { unlock() }
            try check(session)
            var updated = journal
            updated.finishPull()
            try await commit(updated)
            if !journal.pendingPush.isEmpty || !journal.queuedPush.isEmpty { signal.yield() }
            return journal.result
        } catch {
            if generation == session { failure = error }
            if let ck = error as? CKError, ck.code == .zoneNotFound || ck.code == .userDeletedZone {
                throw CloudKitTransportError.zoneDeleted
            }
            throw error
        }
    }

    private func check(_ session: UUID) throws {
        try Task.checkCancellation()
        guard running, generation == session else { throw CloudKitTransportError.notStarted }
    }

    private func checkAccount(_ session: UUID) async throws {
        try check(session)
        try await validateTime(toleranceMs)
        let account = try await client.accountID()
        try check(session)
        guard account == journal.accountID else { throw CloudKitTransportError.accountChanged }
    }

    private func prepare(snapshot: Set<UUIDV7>, session: UUID) async throws -> [SyncChange] {
        await lock()
        defer { unlock() }
        try check(session)
        var updated = journal
        updated.prepareUploads(eligibleIDs: snapshot)
        try await commit(updated)
        return journal.pendingPush.values.filter { snapshot.contains($0.id) }
    }

    private func upload(_ changes: [SyncChange], session: UUID) async throws {
        try await checkAccount(session)
        var assets: [URL] = []
        defer { for url in assets { try? FileManager.default.removeItem(at: url) } }
        let records = try changes.map { change in
            let name = CloudKitSyncJournal.key(change)
            let record = try change.makeCKRecord(zoneID: settings.zoneID, recordType: settings.recordType,
                assetThreshold: settings.assetThreshold,
                systemFields: journal.committedVersions[name] == nil ? nil : journal.systemFields[name])
            if let url = (record[SyncChange.RecordField.payloadAsset] as? CKAsset)?.fileURL { assets.append(url) }
            return record
        }
        let results = try await client.save(records)
        try await checkAccount(session)
        await lock()
        defer { unlock() }
        try check(session)
        var updated = journal
        var failed: Error?
        for (change, record) in zip(changes, records) {
            guard let result = results[record.recordID] else {
                failed = CloudKitTransportError.encodingFailed("Missing save result")
                continue
            }
            switch result {
            case .success(let saved):
                guard saved.recordID == record.recordID,
                      let savedChange = SyncChange(ckRecord: saved), savedChange.id == change.id else {
                    throw CloudKitTransportError.encodingFailed("Mismatched saved record")
                }
                updated.confirm(name: record.recordID.recordName, sentID: change.id)
                try receive(saved, into: &updated, fromPull: false)
            case .failure(let error):
                if let ck = error as? CKError, ck.code == .serverRecordChanged, let server = ck.serverRecord {
                    guard server.recordID == record.recordID else {
                        throw CloudKitTransportError.encodingFailed("Mismatched conflict record")
                    }
                    try receive(server, into: &updated, fromPull: false)
                } else if let ck = error as? CKError, ck.code == .unknownItem {
                    // A stale tag must not force the same failing request forever.
                    updated.systemFields.removeValue(forKey: record.recordID.recordName)
                } else { failed = error }
            }
        }
        // Preserve successful per-record receipts even if another save failed.
        try await commit(updated)
        if let failed { throw failed }
    }

    private func apply(_ page: CloudKitChangesPage, session: UUID) async throws {
        await lock()
        defer { unlock() }
        try check(session)
        guard !page.hasPhysicalDeletions else {
            throw CloudKitTransportError.encodingFailed("Physical deletions must use timestamped tombstone records")
        }
        var updated = journal
        for record in page.records where record.recordID.zoneID == settings.zoneID && record.recordType == settings.recordType {
            try receive(record, into: &updated, fromPull: true)
        }
        updated.zoneChangeToken = page.token
        try await commit(updated)
    }

    private func receive(_ record: CKRecord, into state: inout CloudKitSyncJournal, fromPull: Bool) throws {
        guard record.recordID.zoneID == settings.zoneID, record.recordType == settings.recordType,
              let change = SyncChange(ckRecord: record) else {
            throw CloudKitTransportError.encodingFailed("Malformed CloudKit record")
        }
        if state.receive(change, fromPull: fromPull) {
            state.systemFields[record.recordID.recordName] = record.syncSystemFields()
        }
    }

    private func resetToken(_ session: UUID) async throws {
        await lock()
        defer { unlock() }
        try check(session)
        var updated = journal
        updated.zoneChangeToken = nil
        try await commit(updated)
    }

    private func commit(_ updated: CloudKitSyncJournal) async throws {
        try await stateStore.saveJournal(updated)
        journal = updated
    }

    private func lock() async {
        if locked { await withCheckedContinuation { waiters.append($0) } }
        else { locked = true }
    }
    private func unlock() {
        if waiters.isEmpty { locked = false }
        else { waiters.removeFirst().resume() }
    }
}
