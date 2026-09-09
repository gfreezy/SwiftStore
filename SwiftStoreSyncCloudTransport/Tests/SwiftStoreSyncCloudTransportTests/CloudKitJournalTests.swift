import Testing
import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreSync
import SwiftStoreChangeTracker
@testable import SwiftStoreSyncCloudTransport

@Suite("CloudKit durable synchronization")
struct CloudKitJournalTests {
    func change(timestamp: Int64, content: String = "", operation: ChangeOperation = .update) -> SyncChange {
        SyncChange(id: UUIDV7(), entityType: "note", syncKey: Data([1]), operation: operation,
            payload: operation == .delete ? nil : "{\"updatedAt\":\(timestamp),\"content\":\"\(content)\"}", deviceId: UUIDV7(),
            logicalClock: 1000 - timestamp, createdAt: Date(timeIntervalSinceReferenceDate: Double(timestamp)))
    }

    @Test("An old upload acknowledgement cannot erase a newer queued edit")
    func acknowledgementRace() {
        let old = change(timestamp: 1), new = change(timestamp: 2)
        var state = CloudKitSyncJournal()
        state.enqueue([old, new])
        state.prepareUploads()
        state.finishPull()
        state.confirm(name: CloudKitSyncJournal.key(old), sentID: old.id)
        #expect(state.pendingPush.values.first?.id == new.id)
        #expect(state.pushed == [old.id])
        #expect(!state.conflicts.contains { $0.id == old.id })
    }

    @Test("Newest edit wins regardless of delivery order, including deletions")
    func conflicts() {
        let old = change(timestamp: 1), new = change(timestamp: 2, operation: .delete)
        var state = CloudKitSyncJournal()
        state.enqueue([new, old])
        state.prepareUploads()
        state.finishPull()
        state.receive(old)
        state.prepareUploads()
        state.finishPull()
        #expect(state.pendingPush.values.first?.id == new.id)
        #expect(state.inbox.map(\.id) == [old.id])
        #expect(state.result.pendingChanges.map(\.id) == [new.id])
        var other = CloudKitSyncJournal()
        other.enqueue([old])
        other.prepareUploads()
        other.finishPull()
        other.receive(new)
        other.prepareUploads()
        other.finishPull()
        #expect(other.pendingPush.isEmpty)
        #expect(other.inbox.map(\.id) == [new.id])
        #expect(other.conflicts.map(\.id) == [old.id])
    }

    @Test("Background downloads and receipts survive restart until acknowledged")
    func persistenceAndPartialAcknowledgement() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try FileCloudKitSyncStateStore(directory: dir)
        let first = change(timestamp: 1), second = change(timestamp: 2)
        var state = CloudKitSyncJournal()
        state.receive(first)
        state.prepareUploads()
        state.finishPull()
        state.receive(second)
        state.prepareUploads()
        state.finishPull()
        state.confirm(name: CloudKitSyncJournal.key(first), sentID: first.id)
        try await store.saveJournal(state)
        let reopened = try FileCloudKitSyncStateStore(directory: dir)
        var loaded = try #require(try await reopened.loadJournal())
        #expect(loaded.result.pulled.map(\.id) == [second.id])
        loaded.acknowledge(SyncCycleResult(pulled: [first], pushed: [first.id], conflicts: []))
        try await reopened.saveJournal(loaded)
        let final = try #require(try await store.loadJournal())
        #expect(final.inbox.map(\.id) == [second.id])
        #expect(final.pushed.isEmpty)
    }

    @Test("Corrupt durable work reports an error instead of silently dropping data")
    func corruptJournal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try FileCloudKitSyncStateStore(directory: dir)
        try Data("corrupt".utf8).write(to: dir.appendingPathComponent("journal.plist"))
        await #expect(throws: CloudKitTransportError.self) { try await store.loadJournal() }
    }

    @Test("Tombstones round-trip with their deletion time and identity")
    func tombstone() throws {
        let deletion = change(timestamp: 10, operation: .delete)
        let record = try deletion.makeCKRecord(zoneID: CKRecordZone.ID(zoneName: "test"),
            recordType: "Change", assetThreshold: 1_000_000)
        let decoded = try #require(SyncChange(ckRecord: record))
        #expect(decoded.id == deletion.id)
        #expect(decoded.operation == .delete)
        #expect(decoded.updatedAt == deletion.updatedAt)
        #expect(decoded.payload == nil)
        let updated = try change(timestamp: 11).makeCKRecord(zoneID: record.recordID.zoneID,
            recordType: "Change", assetThreshold: 1_000_000, systemFields: record.syncSystemFields())
        #expect(updated.recordID == record.recordID)
    }

    @Test("A downloaded version protects against stale enqueue before local application")
    func fetchBeforeEnqueue() {
        let old = change(timestamp: 10), downloaded = change(timestamp: 20)
        var state = CloudKitSyncJournal()
        state.receive(downloaded)
        state.prepareUploads()
        state.finishPull()
        state.enqueue([old])
        state.prepareUploads()
        state.finishPull()
        #expect(state.pendingPush.isEmpty)
        #expect(state.inbox.map(\.id) == [downloaded.id])
        #expect(state.conflicts.map(\.id) == [old.id])
        let newer = change(timestamp: 30)
        state.enqueue([newer])
        state.prepareUploads()
        state.finishPull()
        #expect(state.pendingPush.values.first?.id == newer.id)
    }

    @Test("Equal timestamps retain the committed version, irrespective of content or deletion")
    func tieBreak() {
        let a = change(timestamp: 1, content: "a"), b = change(timestamp: 1, content: "b")
        #expect(!a.isNewer(than: b))
        #expect(!b.isNewer(than: a))
        let deletion = change(timestamp: 1, operation: .delete)
        for committed in [a, b, deletion] {
            for incoming in [a, b, deletion] where incoming.id != committed.id {
                var state = CloudKitSyncJournal()
                state.receive(committed)
                state.prepareUploads()
                state.finishPull()
                state.acknowledge(state.result)
                state.enqueue([incoming])
                state.prepareUploads()
                state.finishPull()
                #expect(state.pendingPush.isEmpty)
                #expect(state.result.pulled.map(\.id) == [committed.id])
                #expect(state.result.conflicts.map(\.id) == [incoming.id])
            }
        }
    }

    @Test("Schema versions do not override the timestamp policy")
    func schemaIsNotAConflictVersion() {
        let newer = change(timestamp: 20)
        let highSchema = SyncChange(id: UUIDV7(), entityType: newer.entityType, syncKey: newer.syncKey,
            operation: .delete, payload: nil, deviceId: UUIDV7(), logicalClock: Int64.max,
            schemaVersion: 100, createdAt: Date(timeIntervalSinceReferenceDate: 10))
        var state = CloudKitSyncJournal()
        state.enqueue([newer])
        state.prepareUploads()
        state.finishPull()
        state.receive(highSchema)
        state.prepareUploads()
        state.finishPull()
        #expect(state.result.pendingChanges.map(\.id) == [newer.id])
        #expect(state.result.conflicts.isEmpty)
    }

    @Test("Acknowledged winners survive restart and reject late stale uploads")
    func committedVersionAfterRestart() throws {
        let committed = change(timestamp: 20), stale = change(timestamp: 10)
        var state = CloudKitSyncJournal()
        state.receive(committed)
        state.prepareUploads()
        state.finishPull()
        state.acknowledge(state.result)
        #expect(state.inbox.isEmpty)
        var loaded = try PropertyListDecoder().decode(CloudKitSyncJournal.self,
            from: PropertyListEncoder().encode(state))
        loaded.enqueue([stale])
        loaded.prepareUploads()
        loaded.finishPull()
        #expect(loaded.pendingPush.isEmpty)
        #expect(loaded.result.pulled.map(\.id) == [committed.id])
    }

    @Test("Successful uploads deliver the committed winner and late callbacks cannot roll it back")
    func committedUploadAndLateCallback() {
        let first = change(timestamp: 10), next = change(timestamp: 20), latest = change(timestamp: 30)
        var state = CloudKitSyncJournal()
        state.enqueue([first])
        state.prepareUploads()
        state.finishPull()
        state.enqueue([next]) // User edits while the first upload is in flight.
        state.prepareUploads()
        state.finishPull()
        state.confirm(name: CloudKitSyncJournal.key(first), sentID: first.id)
        state.receive(first)
        state.prepareUploads()
        state.finishPull()
        #expect(state.result.pendingChanges.map(\.id) == [next.id])
        #expect(state.result.pulled.map(\.id) == [first.id])
        state.receive(latest)
        state.prepareUploads()
        state.finishPull()
        state.acknowledge(state.result)
        state.confirm(name: CloudKitSyncJournal.key(next), sentID: next.id)
        let acceptedDelivery = state.receive(next)
        #expect(!acceptedDelivery)
        #expect(state.inbox.isEmpty)
        #expect(state.committedVersions[CloudKitSyncJournal.key(latest)]?.id == latest.id)
    }

    @Test("Uncommitted local winners retry without reporting a version-tag race as a rejection")
    func retryIsNotRejection() {
        let local = change(timestamp: 30), remote = change(timestamp: 20)
        var state = CloudKitSyncJournal()
        state.enqueue([local])
        state.prepareUploads()
        state.finishPull()
        state.receive(remote)
        state.prepareUploads()
        state.finishPull()
        #expect(state.result.conflicts.isEmpty)
        #expect(state.result.pendingChanges.map(\.id) == [local.id])
        state.confirm(name: CloudKitSyncJournal.key(local), sentID: local.id)
        state.receive(local)
        state.prepareUploads()
        state.finishPull()
        #expect(state.result.pendingChanges.isEmpty)
        #expect(state.result.pulled.map(\.id) == [local.id])
    }

    @Test("Retrying the same modification uses timestamp rejection, not an ID-based success shortcut")
    func identicalRetryAfterRestart() throws {
        let committed = change(timestamp: 20)
        var state = CloudKitSyncJournal()
        state.receive(committed)
        state.acknowledge(state.result)
        state = try PropertyListDecoder().decode(CloudKitSyncJournal.self,
            from: PropertyListEncoder().encode(state))
        state.enqueue([committed])
        state.prepareUploads()
        #expect(state.pendingPush.isEmpty)
        #expect(state.pushed.isEmpty)
        #expect(state.conflicts.map(\.id) == [committed.id])
        #expect(state.rejections.entries.first?.serverVersion?.id == committed.id)
        #expect(state.result.pulled.isEmpty)
        state.finishPull()
        #expect(state.result.pulled.map(\.id) == [committed.id])
        state.acknowledge(state.result)
        #expect(state.rejections.entries.isEmpty)
    }

    @Test("A frozen upload set excludes edits arriving during send and pull")
    func frozenUploadSnapshot() {
        let first = change(timestamp: 10), later = change(timestamp: 20)
        var state = CloudKitSyncJournal()
        state.enqueue([first])
        let snapshot: Set<UUIDV7> = [first.id]
        state.prepareUploads(eligibleIDs: snapshot)
        state.enqueue([later]) // Same key, while the first upload is in flight.
        state.prepareUploads(eligibleIDs: snapshot)
        #expect(state.pendingPush.values.map(\.id) == [first.id])
        #expect(state.queuedPush.map(\.id) == [later.id])
        state.confirm(name: CloudKitSyncJournal.key(first), sentID: first.id)
        state.receive(first, fromPull: false)
        state.prepareUploads(eligibleIDs: []) // Pull phase cannot send new work.
        state.receive(first)
        state.finishPull()
        #expect(state.pendingPush.isEmpty)
        #expect(state.result.pendingChanges.map(\.id) == [later.id])
        #expect(state.conflicts.isEmpty)
        state.prepareUploads(eligibleIDs: [later.id])
        #expect(state.queuedPush.isEmpty)
        #expect(state.pendingPush.values.map(\.id) == [later.id])
    }

    @Test("Enqueue and pull do not arbitrate uploads; upload preparation produces the rejection")
    func arbitrationOnlyDuringUpload() {
        let local = change(timestamp: 10), remote = change(timestamp: 20)
        var state = CloudKitSyncJournal()
        state.enqueue([local])
        state.receive(remote)
        #expect(state.result.pendingChanges.map(\.id) == [local.id])
        #expect(state.rejections.entries.isEmpty)
        #expect(state.conflicts.isEmpty)
        state.prepareUploads()
        #expect(state.result.pendingChanges.isEmpty)
        #expect(state.rejections.entries.first?.serverVersion?.id == remote.id)
        #expect(state.result.pulled.isEmpty) // Wait for normal pull before using carried content.
        state.finishPull()
        #expect(state.result.pulled.map(\.id) == [remote.id])
    }

    @Test("An upload conflict carries content but normal pull supplies a newer version first")
    func pullBeforeCarriedContent() throws {
        let local = change(timestamp: 10), server = change(timestamp: 20), latest = change(timestamp: 30)
        var state = CloudKitSyncJournal()
        state.enqueue([local])
        state.prepareUploads()
        state.receive(server, fromPull: false) // serverRecordChanged upload response.
        state.prepareUploads()
        #expect(state.inbox.isEmpty)
        #expect(state.rejections.entries.first?.serverVersion?.id == server.id)
        var restored = try PropertyListDecoder().decode(CloudKitSyncJournal.self,
            from: PropertyListEncoder().encode(state))
        restored.receive(latest)
        restored.finishPull()
        #expect(restored.result.pulled.map(\.id) == [latest.id])
        #expect(restored.result.rejectedKeys.first?.serverVersion?.id == latest.id)
        restored.acknowledge(restored.result)
        #expect(restored.rejections.entries.isEmpty)
        #expect(restored.inbox.isEmpty)
    }

    @Test("A newer local candidate retries tag conflicts without becoming rejected")
    func uploadRetryRetainsCandidate() {
        let local = change(timestamp: 30), remote = change(timestamp: 20)
        var state = CloudKitSyncJournal()
        state.enqueue([local])
        state.prepareUploads()
        state.receive(remote, fromPull: false)
        state.prepareUploads()
        #expect(state.result.pendingChanges.map(\.id) == [local.id])
        #expect(state.rejections.entries.isEmpty)
        #expect(state.conflicts.isEmpty)
        #expect(state.inbox.isEmpty)
    }

    @Test("An old apply acknowledgement cannot erase a later rejection of the same winner")
    func rejectionAcknowledgementRace() {
        let remote = change(timestamp: 20), first = change(timestamp: 10), second = change(timestamp: 11)
        var state = CloudKitSyncJournal()
        state.receive(remote)
        state.enqueue([first])
        state.prepareUploads()
        state.finishPull()
        let oldResult = state.result
        state.enqueue([second])
        state.prepareUploads()
        state.finishPull()
        state.acknowledge(oldResult)
        #expect(state.result.rejectedKeys.map(\.changeID) == [second.id])
        #expect(state.result.pulled.map(\.id) == [remote.id])
        state.acknowledge(state.result)
        #expect(state.rejections.entries.isEmpty)
    }

    @Test("Missing update payload is not accepted as a successful download")
    func missingPayload() throws {
        let record = try change(timestamp: 1).makeCKRecord(zoneID: CKRecordZone.ID(zoneName: "test"),
            recordType: "Change", assetThreshold: 1_000_000)
        record[SyncChange.RecordField.payload] = nil
        #expect(SyncChange(ckRecord: record) == nil)
    }

    @Test("Remote notification streams work after stop and restart")
    func restartSignal() async {
        let signal = CloudKitSyncSignal()
        var first = signal.stream.makeAsyncIterator()
        signal.finish()
        #expect(await first.next() == nil)
        signal.start()
        var second = signal.stream.makeAsyncIterator()
        signal.yield()
        #expect(await second.next() != nil)
        signal.finish()
    }
}
