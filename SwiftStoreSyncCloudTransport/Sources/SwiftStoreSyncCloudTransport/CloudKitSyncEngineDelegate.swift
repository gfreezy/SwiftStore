import Foundation
import CloudKit

/// CKSyncEngine suspends while calling its delegate; actors remain reentrant.
/// Only the weak bridge needs a lock. Record selection lives on the transport actor.
@available(iOS 17.0, macCatalyst 17.0, *)
final class CloudKitSyncEngineDelegate: NSObject, CKSyncEngineDelegate, Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) weak var owner: CloudKitEngineTransport?

    var transport: CloudKitEngineTransport? {
        get { lock.withLock { owner } }
        set { lock.withLock { owner = newValue } }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await transport?.handle(event: event, engine: syncEngine)
    }

    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        await transport?.nextFetchOptions(context, engine: syncEngine)
            ?? CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([]))
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await transport?.nextBatch(context, engine: syncEngine)
    }
}
