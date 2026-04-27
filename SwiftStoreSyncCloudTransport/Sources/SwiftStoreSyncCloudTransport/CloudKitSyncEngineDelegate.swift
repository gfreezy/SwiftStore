import Foundation
import CloudKit
import SwiftStoreSync

/// Non-isolated delegate that bridges `CKSyncEngineDelegate` callbacks into
/// `CloudKitSyncTransport`'s actor isolation.
///
/// Two callbacks have different needs:
///
/// - `handleEvent(_:syncEngine:)` is async, so we dispatch to the actor with
///   `await transport?.handle(event:engine:)`.
/// - `nextRecordZoneChangeBatch(_:syncEngine:)` is called *during*
///   `sendChanges()`. Re-entering the actor with `await` would deadlock,
///   so we look up pending records against a lock-protected snapshot that
///   the transport refreshes on every `enqueue` / state change.
final class CloudKitSyncEngineDelegate: NSObject, CKSyncEngineDelegate, Sendable {
    // Weak references are inherently thread-safe at the ARC level, but the
    // compiler can't verify that for a `Sendable` type — use `nonisolated(unsafe)`.
    nonisolated(unsafe) weak var transport: CloudKitSyncTransport?

    private let snapshotLock = NSLock()
    private nonisolated(unsafe) var _pendingSnapshot: [String: SyncChange] = [:]
    let zoneID: CKRecordZone.ID
    let recordType: CKRecord.RecordType
    let assetThreshold: Int

    init(zoneID: CKRecordZone.ID, recordType: CKRecord.RecordType, assetThreshold: Int) {
        self.zoneID = zoneID
        self.recordType = recordType
        self.assetThreshold = assetThreshold
    }

    /// Replace the in-memory pending-push snapshot used by
    /// `nextRecordZoneChangeBatch`. Called by the transport under actor
    /// isolation whenever the authoritative pending-push map changes.
    func updatePendingSnapshot(_ map: [String: SyncChange]) {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        _pendingSnapshot = map
    }

    private func lookup(_ recordName: String) -> SyncChange? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return _pendingSnapshot[recordName]
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await transport?.handle(event: event, engine: syncEngine)
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter {
            scope.contains($0)
        }
        guard !pendingChanges.isEmpty else { return nil }

        // Synchronous lookup — no await into the actor.
        let zoneID = self.zoneID
        let recordType = self.recordType
        let assetThreshold = self.assetThreshold
        let lookup = self.lookup

        return await CKSyncEngine.RecordZoneChangeBatch(
            pendingChanges: pendingChanges
        ) { recordID in
            guard let change = lookup(recordID.recordName) else { return nil }
            return try? change.makeCKRecord(
                zoneID: zoneID,
                recordType: recordType,
                assetThreshold: assetThreshold
            )
        }
    }
}
