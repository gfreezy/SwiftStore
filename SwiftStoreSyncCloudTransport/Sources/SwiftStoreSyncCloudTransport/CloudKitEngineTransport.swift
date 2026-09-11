import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreSync

/// iOS 17+ driver. SDK state is persisted only after earlier delegate data is applied.
@available(iOS 17.0, macCatalyst 17.0, *)
actor CloudKitEngineTransport: CloudKitDriver {
    private let config: CloudKitSyncConfiguration
    private let settings: CloudKitOperationsSettings
    private let store: any CloudSyncStore
    private let session: UUID
    private let batchSize: Int
    private let delegate = CloudKitSyncEngineDelegate()
    private var engine: CKSyncEngine?
    private var work: CloudKitUploadWork?
    private var account: String?
    private var zoneCreated = false
    private var lastSavedState: Data?
    private var starting: Task<Void, Error>?
    private var active: Task<SyncResult, Error>?
    private var scheduled: Task<Void, Never>?
    private var stopped = false
    private var cycleFailure: Error?
    private var uploadBlocked = false
    private var rescheduleRequested = false
    private(set) var lastError: Error?
    private var totals = CloudCommitCounts()
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(config: CloudKitSyncConfiguration, store: any CloudSyncStore, session: UUID, batchSize: Int) {
        self.config = config; settings = .init(config); self.store = store
        self.session = session; self.batchSize = batchSize
    }

    func sync() async throws -> SyncResult {
        guard !stopped else { throw CancellationError() }
        if let active { return try await active.value }
        uploadBlocked = false
        let task = Task { try await self.runCycle() }
        active = task
        defer { active = nil }
        do { let result = try await task.value; lastError = nil; return result }
        catch { lastError = error; throw error }
    }

    func schedule() {
        guard !stopped, !uploadBlocked else { return }
        if scheduled != nil { rescheduleRequested = true; return }
        scheduled = Task { [weak self] in
            guard let self else { return }
            var attempt = 0
            while !Task.isCancelled {
                do {
                    try await self.ensureStarted(); try await self.stage()
                    if await self.takeReschedule() { continue }
                    break
                } catch {
                    await self.note(error)
                    guard let delay = cloudRetryDelay(error, attempt: attempt) else { break }
                    attempt += 1
                    do { try await Task.sleep(for: .seconds(delay)) } catch { break }
                }
            }
            await self.finishScheduled()
        }
    }
    private func takeReschedule() -> Bool { defer { rescheduleRequested = false }; return rescheduleRequested }
    private func note(_ error: Error) { lastError = error }
    private func finishScheduled() { scheduled = nil }

    private func ensureStarted() async throws {
        if stopped { throw CancellationError() }
        if engine != nil { return }
        if let starting { return try await starting.value }
        let task = Task { try await self.startEngine() }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func startEngine() async throws {
        try await NTPClient.requireAccurateTime(toleranceMs: config.ntpToleranceMs)
        let client = SystemCloudKitOperationsClient(config: config)
        let account = try await client.accountID()
        let saved = try await store.bindCloudAccount(account, scope: settings.namespace, driver: .engine, session: session)
        // A previously existing zone may not be silently recreated after deletion.
        if saved.didCreateZone { try await client.prepareZone(create: false) }
        guard !stopped else { throw CancellationError() }
        self.account = account; zoneCreated = saved.didCreateZone; lastSavedState = saved.checkpoint.data
        var configuration = CKSyncEngine.Configuration(database: config.container.privateCloudDatabase,
            stateSerialization: try saved.checkpoint.data.map {
                try PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            }, delegate: delegate)
        configuration.subscriptionID = config.subscriptionID
        configuration.automaticallySync = config.automaticallySync
        delegate.transport = self
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if !zoneCreated { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: config.zoneID))]) }
    }

    private func runCycle() async throws -> SyncResult {
        cycleFailure = nil
        let before = totals
        try await ensureStarted()
        try await stage()
        guard let engine else { throw lastError ?? CloudKitTransportError.notStarted }
        try await engine.sendChanges()
        try Task.checkCancellation()
        guard self.engine === engine else { throw lastError ?? CancellationError() }
        if let cycleFailure { throw cycleFailure }
        try await engine.fetchChanges()
        try Task.checkCancellation()
        guard self.engine === engine else { throw lastError ?? CancellationError() }
        if let cycleFailure { throw cycleFailure }
        return SyncResult(pulledCount: totals.applied - before.applied, pushedCount: totals.pushed - before.pushed,
            conflictCount: totals.conflicts - before.conflicts, state: try await store.cloudSyncState(session: session))
    }

    private func stage() async throws {
        await lock()
        defer { unlock() }
        guard let engine, !stopped else { throw lastError ?? CancellationError() }
        try await fillBatch(on: engine)
    }

    /// Called with our callback lock held. It never invokes a suspending SDK operation.
    private func fillBatch(on engine: CKSyncEngine) async throws {
        guard !uploadBlocked else { reconcile(on: engine); return }
        while work == nil {
            guard self.engine === engine, !stopped else { throw CancellationError() }
            guard let batch = try await store.nextCloudBatch(limit: batchSize, session: session) else {
                reconcile(on: engine); return
            }
            let candidate = try CloudKitUploadWork(batch: batch, settings: settings)
            work = candidate
            let counts = try await store.commitCloudBatch(batch, decisions: Array(candidate.decisions.values), session: session)
            add(counts)
            if candidate.isComplete || counts.batchComplete { candidate.cleanAssets(); work = nil }
        }
        reconcile(on: engine)
    }

    func nextFetchOptions(_ context: CKSyncEngine.FetchChangesContext, engine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        options.scope = .zoneIDs(self.engine === engine && !stopped && context.options.scope.contains(config.zoneID) ? [config.zoneID] : [])
        return options
    }

    func nextBatch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await lock()
        defer { unlock() }
        guard self.engine === engine, !stopped else { return nil }
        do {
            try await fillBatch(on: engine)
            let records = (work?.records.values.map { $0 } ?? []).filter {
                context.options.scope.contains(CKSyncEngine.PendingRecordZoneChange.saveRecord($0.recordID))
            }
            guard !records.isEmpty else { return nil }
            return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records, atomicByZone: false)
        } catch { cycleFailure = error; lastError = error; uploadBlocked = true; reconcile(on: engine); return nil }
    }

    func handle(event: CKSyncEngine.Event, engine: CKSyncEngine) async {
        await lock()
        defer { unlock() }
        guard self.engine === engine, !stopped else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                let bytes = try PropertyListEncoder().encode(update.stateSerialization)
                if bytes != lastSavedState {
                    try await store.saveCloudCheckpoint(CloudCheckpoint(driver: .engine, data: bytes), session: session)
                    lastSavedState = bytes
                }
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let user) where user.recordName == account: break
                default: throw SyncError.accountChanged
                }
            case .fetchedRecordZoneChanges(let fetched):
                guard !fetched.deletions.contains(where: { $0.recordID.zoneID == config.zoneID && $0.recordType == config.recordType }) else {
                    throw CloudKitTransportError.encodingFailed("Physical deletion has no version; synchronized deletions require tombstones")
                }
                let records = try fetched.modifications.map(\.record)
                    .filter { $0.recordID.zoneID == config.zoneID && $0.recordType == config.recordType }
                    .map { try CloudKitUploadWork.decode($0, settings: settings) }
                // Await the writer commit before returning to the SDK. A following
                // stateUpdate can safely include these downloaded records.
                totals.applied += try await store.applyCloudRecords(records, checkpoint: nil, session: session)
            case .sentRecordZoneChanges(let sent):
                guard var current = work else { return }
                var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]
                for record in sent.savedRecords { results[record.recordID] = .success(record) }
                var retry: Set<CKRecord.ID> = []
                for failed in sent.failedRecordSaves {
                    if failed.error.code == .zoneNotFound, !zoneCreated {
                        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: config.zoneID))])
                        retry.insert(failed.record.recordID)
                    } else {
                        results[failed.record.recordID] = .failure(failed.error)
                        if failed.error.code == .serverRecordChanged { retry.insert(failed.record.recordID) }
                    }
                }
                let failure = try current.receive(results)
                work = current
                let counts = try await store.commitCloudBatch(current.batch, decisions: Array(current.decisions.values), session: session)
                add(counts)
                if let failure {
                    cycleFailure = failure; lastError = failure
                    let code = (failure as? CKError)?.code
                    if cloudRetryDelay(failure) == nil, code != .notAuthenticated, code != .operationCancelled {
                        uploadBlocked = true
                    }
                }
                if current.isComplete || counts.batchComplete {
                    current.cleanAssets(); work = nil
                    try await fillBatch(on: engine)
                } else {
                    reconcile(on: engine, reschedule: retry)
                }
                SwiftStoreLogger.info("CloudKit batch: saved=\(sent.savedRecords.count), failed=\(sent.failedRecordSaves.count), pending=\(work?.records.count ?? 0)")
            case .sentDatabaseChanges(let sent):
                if sent.savedZones.contains(where: { $0.zoneID == config.zoneID }) {
                    try await store.markCloudZoneCreated(session: session); zoneCreated = true
                }
                if let failure = sent.failedZoneSaves.first?.error { cycleFailure = failure; lastError = failure }
            case .fetchedDatabaseChanges(let fetched):
                if fetched.deletions.contains(where: { $0.zoneID == config.zoneID }) { throw CloudKitTransportError.zoneDeleted }
            case .didFetchRecordZoneChanges(let fetched):
                if fetched.zoneID == config.zoneID, let error = fetched.error { cycleFailure = error; lastError = error }
            default: break
            }
        } catch {
            // This serialization may already include the failed page. Ignore ALL
            // subsequent callbacks from this engine and restart from the last DB checkpoint.
            lastError = error; cycleFailure = error
            self.engine = nil; delegate.transport = nil
            let oldWork = work; work = nil
            Task {
                await engine.cancelOperations()
                oldWork?.cleanAssets()
            }
        }
    }

    private func add(_ counts: CloudCommitCounts) {
        totals.pushed += counts.pushed; totals.conflicts += counts.conflicts; totals.applied += counts.applied
    }

    /// At most two SDK mutations per batch, touching only IDs that changed.
    private func reconcile(on engine: CKSyncEngine, reschedule: Set<CKRecord.ID> = []) {
        let desired = Set((uploadBlocked ? [] : work?.records.keys.map { $0 } ?? []).map(CKSyncEngine.PendingRecordZoneChange.saveRecord))
        let existing = Set(engine.state.pendingRecordZoneChanges)
        let remove = existing.subtracting(desired)
        let add = desired.subtracting(existing).union(desired.filter {
            if case .saveRecord(let id) = $0 { return reschedule.contains(id) }; return false
        })
        if !remove.isEmpty { engine.state.remove(pendingRecordZoneChanges: Array(remove)) }
        if !add.isEmpty { engine.state.add(pendingRecordZoneChanges: Array(add)) }
    }

    func stop() async {
        stopped = true; scheduled?.cancel(); starting?.cancel(); active?.cancel()
        await lock()
        let previous = engine; engine = nil; delegate.transport = nil
        let previousWork = work; work = nil
        unlock()
        await previous?.cancelOperations()
        previousWork?.cleanAssets()
    }
    private func lock() async {
        if locked { await withCheckedContinuation { waiters.append($0) } } else { locked = true }
    }
    private func unlock() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }
}
