import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreSync

/// One atomic checkpoint: the download cursor must never outlive its inbox.
public struct CloudKitSyncJournal: Codable, Sendable {
    /// Opaque CKSyncEngine serialization, accessed only on iOS 17+.
    public var engineState: Data?
    /// CKFetchRecordZoneChanges cursor for the iOS 16 adapter.
    public var zoneChangeToken: Data?
    public var accountID: String?
    public var namespace: String?
    public var pendingPush: [String: SyncChange] = [:]
    /// enqueue only stages work; comparisons happen when preparing an upload.
    public var queuedPush: [SyncChange] = []
    public var rejections = SyncRejectionStore()
    public var inbox: [SyncChange] = []
    public var pushed: [UUIDV7] = []
    public var conflicts: [SyncChange] = []
    public var systemFields: [String: Data] = [:]
    public var didCreateZone = false
    /// Committed CloudKit versions paired with systemFields, retained after ACK.
    public var committedVersions: [String: SyncChange] = [:]

    public init() {}

    mutating func enqueue(_ changes: [SyncChange]) {
        var ids = Set((queuedPush + Array(pendingPush.values)).map(\.id))
        for change in changes where ids.insert(change.id).inserted { queuedPush.append(change) }
    }

    /// Upload-stage arbitration, also used after a CloudKit change-tag conflict.
    mutating func prepareUploads(eligibleIDs: Set<UUIDV7>? = nil) {
        let eligible = { (change: SyncChange) in eligibleIDs?.contains(change.id) ?? true }
        for change in queuedPush where eligible(change) {
            let name = Self.key(change)
            if let previous = pendingPush[name] {
                if previous.id == change.id { continue }
                if !change.isNewer(than: previous) {
                    reject(change)
                    continue
                }
                reject(previous)
            }
            pendingPush[name] = change
        }
        queuedPush.removeAll(where: eligible)
        for (name, change) in pendingPush where eligible(change) {
            guard let remote = committedVersions[name], !change.isNewer(than: remote) else { continue }
            // Equal timestamps always retain the committed record, even when
            // this is a retry of the same modification. No identity-based shortcut.
            reject(change, serverVersion: remote)
            pendingPush.removeValue(forKey: name)
        }
    }

    /// Receive a committed version, not an unresolved candidate. Returns false
    /// for a delayed older delivery so its system fields cannot replace newer tags.
    @discardableResult
    mutating func receive(_ change: SyncChange, fromPull: Bool = true) -> Bool {
        let name = Self.key(change)
        if let previous = committedVersions[name], previous.isNewer(than: change) { return false }
        committedVersions[name] = change
        // A successful upload may precede its fetch callback. Do not leave an
        // older, previously downloaded inbox entry eligible for local application.
        inbox.removeAll { Self.key($0) == name && change.isNewer(than: $0) }
        if fromPull {
            rejections.receive(change, satisfying: Set(rejections.entries.filter {
                SyncRejectionStore.sameKey($0.change, change)
                    && !($0.serverVersion?.isNewer(than: change) ?? false)
            }.map(\.changeID)))
            deliver(change)
        }
        return true
    }

    /// Normal pull has completed. Reuse the freshest committed content already
    /// supplied by CloudKit for any keys pull did not return; no extra query.
    mutating func finishPull() {
        for entry in rejections.entries {
            let name = Self.key(entry.change)
            // A locally superseded candidate has no final version until its
            // replacement has finished the upload-stage arbitration.
            guard pendingPush[name] == nil,
                  !queuedPush.contains(where: { Self.key($0) == name }),
                  let committed = committedVersions[name] else { continue }
            rejections.receive(committed, satisfying: [entry.changeID])
        }
        rejections.finishPull()
        for entry in rejections.entries where entry.isResolved {
            if let version = entry.serverVersion { deliver(version) }
        }
    }

    private mutating func reject(_ change: SyncChange, serverVersion: SyncChange? = nil) {
        if !conflicts.contains(where: { $0.id == change.id }) { conflicts.append(change) }
        rejections.record(change, serverVersion: serverVersion)
    }

    private mutating func deliver(_ change: SyncChange) {
        if inbox.contains(where: { Self.key($0) == Self.key(change) && $0.isNewer(than: change) }) { return }
        inbox.removeAll { Self.key($0) == Self.key(change) }
        inbox.append(change)
    }

    mutating func confirm(name: String, sentID: UUIDV7) {
        if !pushed.contains(sentID) { pushed.append(sentID) }
        // A superseded candidate may already have been in flight and committed.
        // Report its actual successful receipt rather than both outcomes.
        conflicts.removeAll { $0.id == sentID }
        rejections.remove(changeID: sentID)
        // An acknowledgement for an older upload must not erase a newer edit.
        if pendingPush[name]?.id == sentID { pendingPush.removeValue(forKey: name) }
    }

    mutating func acknowledge(_ result: SyncCycleResult) {
        rejections.acknowledge(applied: result.pulled, rejectedKeys: result.rejectedKeys)
        let pulledIDs = Set(result.pulled.map(\.id))
        let pushedIDs = Set(result.pushed)
        let conflictIDs = Set(result.conflicts.map(\.id))
        let retained = Set(rejections.entries.compactMap { $0.serverVersion?.id })
        inbox.removeAll { pulledIDs.contains($0.id) && !retained.contains($0.id) }
        pushed.removeAll { pushedIDs.contains($0) }
        conflicts.removeAll { conflictIDs.contains($0.id) }
    }

    var result: SyncCycleResult {
        SyncCycleResult(pulled: inbox.filter { !rejections.blocks($0) }, pushed: pushed, conflicts: conflicts,
            pendingChanges: Array(pendingPush.values) + queuedPush, rejectedKeys: rejections.entries)
    }

    static func key(_ change: SyncChange) -> String {
        SyncChange.recordName(entityType: change.entityType, syncKey: change.syncKey)
    }
}
