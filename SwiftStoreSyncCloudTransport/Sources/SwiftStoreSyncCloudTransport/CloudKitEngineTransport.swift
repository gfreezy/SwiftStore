import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreChangeTracker
import SwiftStoreSync

/// Private-database synchronization with a durable outbox and acknowledged inbox.
/// CKSyncEngine's cursor and the data it fetched are saved in one atomic journal.
/// TimestampConflictResolver selects candidates; CloudKit change tags make
/// their commit conditional. SyncManager receives only committed winners.
@available(iOS 17.0, macCatalyst 17.0, *)
actor CloudKitEngineTransport: CloudKitBackend {
    private let config: CloudKitTransportConfig
    private let stateStore: any CloudKitSyncStateStore
    private let delegate = CloudKitSyncEngineDelegate()
    private nonisolated let signal = CloudKitSyncSignal()
    private var engine: CKSyncEngine?
    private var journal = CloudKitSyncJournal()
    private var ntpToleranceMs: Int64
    private var syncing = false
    /// nil allows automatic sync; an explicit cycle freezes change IDs, then uses
    /// an empty set during pull so newly enqueued work cannot prolong this cycle.
    private var uploadSnapshot: Set<UUIDV7>?
    private var cycleFailure: Error?
    /// A persistence/decode/account error suspends the engine until start is retried.
    private var terminalFailure: Error?
    private var assetFiles: [URL] = []

    // Serialize journal writes across actor suspension points, but never hold
    // this lock across engine.fetch/send/cancel (those call back into us).
    private var stateLocked = false
    private var stateWaiters: [CheckedContinuation<Void, Never>] = []

    nonisolated func notifyRemoteChange() { signal.yield() }

    public nonisolated var remoteChanges: AsyncStream<Void> { signal.stream }

    /// Most recent callback failure, including failures from automatic sync.
    public var lastError: Error? { terminalFailure ?? cycleFailure }

    public init(config: CloudKitTransportConfig, stateStore: any CloudKitSyncStateStore) {
        self.ntpToleranceMs = config.ntpToleranceMs
        self.config = config
        self.stateStore = stateStore
    }

    public func configureTimeValidation(toleranceMs: Int64) async throws {
        guard toleranceMs > 0 else { throw NTPError.invalidTolerance }
        await lockState()
        defer { unlockState() }
        ntpToleranceMs = toleranceMs
    }

    public func start(deviceId: UUIDV7) async throws {
        await lockState()
        defer { unlockState() }
        if engine != nil { return }
        try await NTPClient.requireAccurateTime(toleranceMs: ntpToleranceMs)
        let status = try await config.container.accountStatus()
        guard status == .available else {
            throw CloudKitTransportError.notSignedIn("CKAccountStatus: \(status)")
        }
        let accountID = try await config.container.userRecordID().recordName
        journal = try await stateStore.loadJournal() ?? CloudKitSyncJournal()
        if let previous = journal.accountID, previous != accountID {
            throw CloudKitTransportError.accountChanged
        }
        let namespace = [config.container.containerIdentifier ?? "default", config.zoneName, config.recordType].joined(separator: "/")
        if let previous = journal.namespace, previous != namespace {
            throw CloudKitTransportError.stateCorrupt("State directory belongs to a different container/zone/record type")
        }
        journal.namespace = namespace
        journal.accountID = accountID
        try await stateStore.saveJournal(journal)
        // Ensure the configured subscription exists before starting the engine.
        let subscription = CKDatabaseSubscription(subscriptionID: config.subscriptionID)
        let notifications = CKSubscription.NotificationInfo()
        notifications.shouldSendContentAvailable = true
        subscription.notificationInfo = notifications
        _ = try await config.container.privateCloudDatabase.save(subscription)
        terminalFailure = nil
        cycleFailure = nil
        signal.start()
        delegate.transport = self
        var configuration = CKSyncEngine.Configuration(
            database: config.container.privateCloudDatabase,
            stateSerialization: try journal.engineState.map { try PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) },
            delegate: delegate
        )
        // Use the subscription successfully saved above.
        configuration.subscriptionID = config.subscriptionID
        configuration.automaticallySync = config.automaticallySync
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if !journal.didCreateZone { scheduleZone(on: engine) }
        restorePending(on: engine)
        if !journal.inbox.isEmpty { signal.yield() }
    }

    public func stop() async {
        await lockState()
        let previous = engine
        engine = nil
        delegate.transport = nil
        signal.finish()
        let oldAssets = assetFiles
        assetFiles.removeAll()
        unlockState()
        await previous?.cancelOperations()
        for url in oldAssets { try? FileManager.default.removeItem(at: url) }
    }

    public func enqueue(_ changes: [SyncChange]) async throws {
        await lockState()
        defer { unlockState() }
        guard let engine else { throw terminalFailure ?? CloudKitTransportError.notStarted }
        var updated = journal
        updated.enqueue(changes)
        // Persist payloads before publishing pending IDs to the engine.
        try await stateStore.saveJournal(updated)
        journal = updated
        restorePending(on: engine)
    }

    public func acknowledge(_ result: SyncCycleResult) async throws {
        await lockState()
        defer { unlockState() }
        if let terminalFailure { throw terminalFailure }
        var updated = journal
        updated.acknowledge(result)
        try await stateStore.saveJournal(updated)
        journal = updated
    }

    public func syncNow() async throws -> SyncCycleResult {
        guard let engine else { throw terminalFailure ?? CloudKitTransportError.notStarted }
        guard !syncing else { throw SyncError.syncAlreadyInProgress("CloudKit sync is already running") }
        syncing = true
        cycleFailure = nil
        let snapshot = Set((Array(journal.pendingPush.values) + journal.queuedPush).map(\.id))
        uploadSnapshot = snapshot
        defer { syncing = false; uploadSnapshot = nil }
        try await NTPClient.requireAccurateTime(toleranceMs: ntpToleranceMs)
        // A change-tag race can require another send pass. Finish every captured
        // candidate (accepted, rejected, or superseded) before starting fetch.
        repeat {
            try await engine.sendChanges()
            try Task.checkCancellation()
            if let terminalFailure { throw terminalFailure }
            if let cycleFailure { throw CloudKitTransportError.sendFailed(underlying: cycleFailure) }
            guard self.engine === engine else { throw CloudKitTransportError.notStarted }
        } while (Array(journal.pendingPush.values) + journal.queuedPush).contains { snapshot.contains($0.id) }
        uploadSnapshot = []
        try await engine.fetchChanges()
        try Task.checkCancellation()
        if let terminalFailure { throw terminalFailure }
        if let cycleFailure { throw CloudKitTransportError.sendFailed(underlying: cycleFailure) }
        guard self.engine === engine else { throw CloudKitTransportError.notStarted }
        await lockState()
        defer { unlockState() }
        guard self.engine === engine else { throw CloudKitTransportError.notStarted }
        var updated = journal
        updated.finishPull()
        try await stateStore.saveJournal(updated)
        journal = updated
        // The caller acknowledges after local application. Never drain here.
        if !journal.pendingPush.isEmpty || !journal.queuedPush.isEmpty { signal.yield() }
        return journal.result
    }

    func nextFetchOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        engine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        await lockState()
        defer { unlockState() }
        var options = context.options
        do {
            guard self.engine === engine else { throw CloudKitTransportError.notStarted }
            try await NTPClient.requireAccurateTime(toleranceMs: ntpToleranceMs)
            options.scope = .zoneIDs(options.scope.contains(config.zoneID) ? [config.zoneID] : [])
        } catch {
            cycleFailure = error
            options.scope = .zoneIDs([])
        }
        return options
    }

    func nextBatch(
        _ context: CKSyncEngine.SendChangesContext,
        engine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await lockState()
        defer { unlockState() }
        guard self.engine === engine, terminalFailure == nil else { return nil }
        var records: [CKRecord] = []
        do {
            try await NTPClient.requireAccurateTime(toleranceMs: ntpToleranceMs)
            guard self.engine === engine else { return nil }
            var updated = journal
            updated.prepareUploads(eligibleIDs: uploadSnapshot)
            try await stateStore.saveJournal(updated)
            journal = updated
            restorePending(on: engine)
            let pending = engine.state.pendingRecordZoneChanges.filter { item in
                guard context.options.scope.contains(item) else { return false }
                guard let snapshot = uploadSnapshot else { return true }
                switch item {
                case .saveRecord(let id), .deleteRecord(let id):
                    return journal.pendingPush[id.recordName].map { snapshot.contains($0.id) } ?? false
                @unknown default: return false
                }
            }
            for item in pending.prefix(200) {
                let recordID: CKRecord.ID
                switch item {
                case .saveRecord(let id), .deleteRecord(let id): recordID = id
                @unknown default: continue
                }
                guard recordID.zoneID == config.zoneID,
                      let change = journal.pendingPush[recordID.recordName] else {
                    engine.state.remove(pendingRecordZoneChanges: [item])
                    continue
                }
                let record = try change.makeCKRecord(
                    zoneID: config.zoneID, recordType: config.recordType,
                    assetThreshold: config.assetThreshold,
                    // Only reuse tags paired with a known committed version.
                    systemFields: journal.committedVersions[recordID.recordName] == nil
                        ? nil : journal.systemFields[recordID.recordName]
                )
                if let url = (record[SyncChange.RecordField.payloadAsset] as? CKAsset)?.fileURL {
                    assetFiles.append(url)
                }
                records.append(record)
            }
        } catch {
            cycleFailure = error
            return nil
        }
        guard !records.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records, atomicByZone: false)
    }

    func handle(event: CKSyncEngine.Event, engine: CKSyncEngine) async {
        await lockState()
        defer { unlockState() }
        guard self.engine === engine, terminalFailure == nil else { return }
        do {
            var shouldSignal = false
            switch event {
            case .stateUpdate(let update):
                journal.engineState = try PropertyListEncoder().encode(update.stateSerialization)
            case .accountChange(let event):
                switch event.changeType {
                case .signIn(let user) where user.recordName == journal.accountID:
                    break
                default:
                    // Preserve all local work. A different account must use its
                    // own database/state directory; never silently upload old data.
                    throw CloudKitTransportError.accountChanged
                }
            case .fetchedRecordZoneChanges(let event):
                try await NTPClient.requireAccurateTime(toleranceMs: ntpToleranceMs)
                shouldSignal = !event.modifications.isEmpty || !event.deletions.isEmpty
                for modification in event.modifications {
                    let record = modification.record
                    guard record.recordID.zoneID == config.zoneID, record.recordType == config.recordType else { continue }
                    try receive(record, engine: engine)
                }
                if event.deletions.contains(where: {
                    $0.recordID.zoneID == config.zoneID && $0.recordType == config.recordType
                }) {
                    throw CloudKitTransportError.encodingFailed(
                        "Physical record deletion has no timestamp; sync deletions must use tombstone records")
                }
            case .sentRecordZoneChanges(let event):
                shouldSignal = !event.savedRecords.isEmpty || !event.failedRecordSaves.isEmpty
                for record in event.savedRecords {
                    guard let change = SyncChange(ckRecord: record) else {
                        throw CloudKitTransportError.encodingFailed("Malformed saved record")
                    }
                    let name = record.recordID.recordName
                    journal.confirm(name: name, sentID: change.id)
                    try receive(record, engine: engine, fromPull: false)
                    journal.prepareUploads(eligibleIDs: uploadSnapshot)
                    restorePending(on: engine)
                }
                for failed in event.failedRecordSaves {
                    let id = failed.record.recordID
                    switch failed.error.code {
                    case .serverRecordChanged:
                        guard let server = failed.error.serverRecord else { throw failed.error }
                        // Merge the winner and retry local wins with the server's tag.
                        try receive(server, engine: engine, fromPull: false)
                        journal.prepareUploads(eligibleIDs: uploadSnapshot)
                        restorePending(on: engine)
                    case .zoneNotFound:
                        journal.didCreateZone = false
                        journal.systemFields.removeAll()
                        scheduleZone(on: engine)
                        reconcile(id, engine: engine)
                        cycleFailure = failed.error
                    case .unknownItem:
                        journal.systemFields.removeValue(forKey: id.recordName)
                        reconcile(id, engine: engine)
                    default:
                        // Preserve the durable outbox even for non-retryable errors.
                        cycleFailure = failed.error
                    }
                }
                for (_, error) in event.failedRecordDeletes { cycleFailure = error }
            case .sentDatabaseChanges(let event):
                if event.savedZones.contains(where: { $0.zoneID == config.zoneID }) {
                    journal.didCreateZone = true
                }
                for failed in event.failedZoneSaves where failed.zone.zoneID == config.zoneID {
                    cycleFailure = failed.error
                }
            case .fetchedDatabaseChanges(let event):
                if event.deletions.contains(where: { $0.zoneID == config.zoneID }) {
                    // A zone reset invalidates *all* previously acknowledged data.
                    // Stop instead of pretending that only the current outbox is a full backup.
                    throw CloudKitTransportError.zoneDeleted
                }
            case .didFetchRecordZoneChanges(let event):
                if let error = event.error, event.zoneID == config.zoneID {
                    if error.code == .zoneNotFound && !journal.didCreateZone {
                        scheduleZone(on: engine)
                    } else {
                        cycleFailure = error
                    }
                }
            case .didSendChanges:
                cleanAssets()
            default:
                break
            }
            try await stateStore.saveJournal(journal)
            // Background downloads survive until SyncManager applies and acknowledges.
            if shouldSignal && !syncing { signal.yield() }
        } catch {
            terminalFailure = error
            self.engine = nil
            signal.yield()
            // No more cursor updates can persist after a failed download/journal write.
            // Do not await cancellation inside an engine callback.
            let oldAssets = assetFiles
            assetFiles.removeAll()
            Task {
                await engine.cancelOperations()
                for url in oldAssets { try? FileManager.default.removeItem(at: url) }
            }
        }
    }

    private func receive(_ record: CKRecord, engine: CKSyncEngine, fromPull: Bool = true) throws {
        guard let change = SyncChange(ckRecord: record) else {
            throw CloudKitTransportError.encodingFailed("Malformed record \(record.recordID.recordName)")
        }
        if journal.receive(change, fromPull: fromPull) {
            journal.systemFields[record.recordID.recordName] = record.syncSystemFields()
        }
        reconcile(record.recordID, engine: engine)
    }

    private func reconcile(_ id: CKRecord.ID, engine: CKSyncEngine) {
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id), .deleteRecord(id)])
        if journal.pendingPush[id.recordName] != nil || journal.queuedPush.contains(where: { CloudKitSyncJournal.key($0) == id.recordName }) {
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        }
    }

    private func restorePending(on engine: CKSyncEngine) {
        // The journal is authoritative, including when an old state blob still
        // contains physical deletes or when a crash preceded its stateUpdate.
        engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
        engine.state.add(pendingRecordZoneChanges: Set(Array(journal.pendingPush.keys) + journal.queuedPush.map(CloudKitSyncJournal.key)).map {
            .saveRecord(CKRecord.ID(recordName: $0, zoneID: config.zoneID))
        })
    }

    private func scheduleZone(on engine: CKSyncEngine) {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: config.zoneID))])
    }

    private func cleanAssets() {
        for url in assetFiles { try? FileManager.default.removeItem(at: url) }
        assetFiles.removeAll()
    }

    private func lockState() async {
        if stateLocked {
            await withCheckedContinuation { stateWaiters.append($0) }
        } else {
            stateLocked = true
        }
    }

    private func unlockState() {
        if stateWaiters.isEmpty { stateLocked = false }
        else { stateWaiters.removeFirst().resume() }
    }
}
