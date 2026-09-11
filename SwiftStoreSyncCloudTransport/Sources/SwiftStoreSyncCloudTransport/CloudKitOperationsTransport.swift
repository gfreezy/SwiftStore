import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreSync

/// iOS 16 driver. It persists tokens only with the corresponding applied page.
actor CloudKitOperationsTransport: CloudKitDriver {
    private let settings: CloudKitOperationsSettings
    private let client: any CloudKitOperationsClient
    private let store: any CloudSyncStore
    private let session: UUID
    private let batchSize: Int
    private var active: Task<SyncResult, Error>?
    private var scheduled: Task<Void, Never>?
    private var stopped = false
    private var blocked = false
    private var rescheduleRequested = false
    private(set) var lastError: Error?

    init(settings: CloudKitOperationsSettings, client: any CloudKitOperationsClient,
         store: any CloudSyncStore, session: UUID, batchSize: Int = 200) {
        self.settings = settings; self.client = client; self.store = store
        self.session = session; self.batchSize = batchSize
    }

    func sync() async throws -> SyncResult {
        guard !stopped else { throw CancellationError() }
        if let active { return try await active.value }
        blocked = false
        let task = Task { try await self.runCycle() }
        active = task
        defer { active = nil }
        do { let result = try await task.value; lastError = nil; return result }
        catch { lastError = error; throw error }
    }

    func schedule() {
        guard !stopped, !blocked else { return }
        if scheduled != nil { rescheduleRequested = true; return }
        if active != nil { rescheduleRequested = true }
        scheduled = Task { [weak self] in
            guard let self else { return }
            var attempt = 0
            while !Task.isCancelled {
                do {
                    _ = try await self.sync()
                    if await self.takeReschedule() { continue }
                    break
                }
                catch {
                    guard let delay = cloudRetryDelay(error, attempt: attempt) else {
                        await self.setBlocked(error); break
                    }
                    attempt += 1
                    do { try await Task.sleep(for: .seconds(delay)) } catch { break }
                }
            }
            await self.finishScheduled()
        }
    }
    private func setBlocked(_ error: Error) {
        // Account availability can recover on its notification without a manual retry.
        if case CloudKitTransportError.notSignedIn = error { return }
        if let error = error as? CKError, error.code == .notAuthenticated || error.code == .operationCancelled { return }
        blocked = !(error is CancellationError)
    }
    private func takeReschedule() -> Bool { defer { rescheduleRequested = false }; return rescheduleRequested }
    private func finishScheduled() {
        scheduled = nil
        if rescheduleRequested { rescheduleRequested = false; schedule() }
    }
    func accountChanged() {
        active?.cancel()
        blocked = false
        schedule()
    }
    func stop() { stopped = true; scheduled?.cancel(); active?.cancel(); scheduled = nil }
    private func check() throws { try Task.checkCancellation(); if stopped { throw CancellationError() } }

    private func verifyAccount(_ expected: String) async throws {
        guard try await client.accountID() == expected else { throw SyncError.accountChanged }
        try check()
    }

    private func runCycle() async throws -> SyncResult {
        try await NTPClient.requireAccurateTime(toleranceMs: settings.toleranceMs)
        let account = try await client.accountID()
        try check()
        let initial = try await store.bindCloudAccount(account, scope: settings.namespace, driver: .operations, session: session)
        try await client.prepareZone(create: !initial.didCreateZone)
        try await verifyAccount(account)
        if !initial.didCreateZone { try await store.markCloudZoneCreated(session: session) }
        var pushed = 0, conflicts = 0, applied = 0
        while let batch = try await store.nextCloudBatch(limit: batchSize, session: session) {
            try check()
            var work = try CloudKitUploadWork(batch: batch, settings: settings)
            defer { work.cleanAssets() }
            var counts = try await store.commitCloudBatch(batch, decisions: Array(work.decisions.values), session: session)
            pushed += counts.pushed; conflicts += counts.conflicts; applied += counts.applied
            var conflictsInARow = 0
            while !work.isComplete && !counts.batchComplete {
                try check()
                let records = Array(work.records.values)
                try await verifyAccount(account)
                let results = try await client.save(records)
                try check()
                try await verifyAccount(account)
                let failure = try work.receive(results)
                counts = try await store.commitCloudBatch(batch, decisions: Array(work.decisions.values), session: session)
                pushed += counts.pushed; conflicts += counts.conflicts; applied += counts.applied
                if let failure { throw failure }
                guard records.allSatisfy({ results[$0.recordID] != nil }) else {
                    throw CloudKitTransportError.encodingFailed("CloudKit omitted a per-record save result")
                }
                conflictsInARow += 1
                if !work.isComplete, conflictsInARow >= 5 {
                    throw CKError(.zoneBusy)
                }
            }
        }
        var token = initial.checkpoint.data
        var resetOnce = false
        while true {
            try check()
            let page: CloudKitChangesPage
            do { page = try await client.fetch(since: token) }
            catch let error as CKError where error.code == .changeTokenExpired && !resetOnce {
                resetOnce = true; token = nil
                try await store.saveCloudCheckpoint(CloudCheckpoint(driver: .operations, data: nil), session: session)
                continue
            }
            try check()
            try await verifyAccount(account)
            guard !page.hasPhysicalDeletions else {
                throw CloudKitTransportError.encodingFailed("Physical deletion has no version; synchronized deletions require tombstones")
            }
            let records = try page.records.filter { $0.recordType == settings.recordType }.map {
                try CloudKitUploadWork.decode($0, settings: settings)
            }
            applied += try await store.applyCloudRecords(records,
                checkpoint: CloudCheckpoint(driver: .operations, data: page.token), session: session)
            token = page.token
            if !page.moreComing { break }
        }
        return SyncResult(pulledCount: applied, pushedCount: pushed, conflictCount: conflicts,
            state: try await store.cloudSyncState(session: session))
    }
}
