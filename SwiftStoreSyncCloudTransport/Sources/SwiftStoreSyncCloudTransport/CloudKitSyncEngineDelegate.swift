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

/// The protocol exposes the stream synchronously, including across stop/start.
final class CloudKitSyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var finished = false

    var stream: AsyncStream<Void> { lock.withLock { pair.stream } }
    func start() {
        lock.withLock {
            if finished {
                pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
                finished = false
            }
        }
    }
    func yield() { lock.withLock { _ = pair.continuation.yield(()) } }
    func finish() {
        lock.withLock {
            finished = true
            pair.continuation.finish()
        }
    }
}
