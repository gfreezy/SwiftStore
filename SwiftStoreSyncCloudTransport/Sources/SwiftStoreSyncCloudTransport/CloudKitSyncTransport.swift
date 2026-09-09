import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreSync

protocol CloudKitBackend: SyncTransport {
    var lastError: Error? { get async }
    func notifyRemoteChange()
}

/// Shared durable CloudKit contract: CKSyncEngine on iOS 17+, zone operations on iOS 16.
public final class CloudKitSyncTransport: SyncTransport {
    private let backend: any CloudKitBackend
    private let subscriptionID: String

    public init(config: CloudKitTransportConfig, stateStore: any CloudKitSyncStateStore) {
        subscriptionID = config.subscriptionID
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            backend = CloudKitEngineTransport(config: config, stateStore: stateStore)
        } else {
            backend = CloudKitOperationsTransport(settings: .init(config),
                client: SystemCloudKitOperationsClient(config: config), stateStore: stateStore)
        }
    }

    public var remoteChanges: AsyncStream<Void> { backend.remoteChanges }
    public var lastError: Error? { get async { await backend.lastError } }
    public func configureTimeValidation(toleranceMs: Int64) async throws {
        try await backend.configureTimeValidation(toleranceMs: toleranceMs)
    }
    public func start(deviceId: UUIDV7) async throws { try await backend.start(deviceId: deviceId) }
    public func stop() async { await backend.stop() }
    public func enqueue(_ changes: [SyncChange]) async throws { try await backend.enqueue(changes) }
    public func syncNow() async throws -> SyncCycleResult { try await backend.syncNow() }
    public func acknowledge(_ result: SyncCycleResult) async throws { try await backend.acknowledge(result) }

    /// Forward the app's CloudKit push here, then await manager.sync() before
    /// completing the background notification. Unrelated subscriptions are ignored.
    @discardableResult
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.subscriptionID == subscriptionID else { return false }
        backend.notifyRemoteChange()
        return true
    }
}
