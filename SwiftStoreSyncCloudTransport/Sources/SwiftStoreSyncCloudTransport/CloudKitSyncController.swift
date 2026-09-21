import Foundation
import CloudKit
import SwiftStoreSync

protocol CloudKitDriver: Sendable {
    var lastError: Error? { get async }
    func sync(progress: SyncProgressHandler?) async throws -> SyncResult
    func schedule() async
    func stop() async
    func accountChanged() async
}

extension CloudKitDriver {
    func accountChanged() async { await schedule() }
}

/// The package's only network integration. No public custom transport or state-store injection.
package actor CloudKitSyncController {
    private let driver: any CloudKitDriver
    private let subscriptionID: String
    private let automaticallySync: Bool
    private var accountObserver: Task<Void, Never>?

    package init(configuration: CloudKitSyncConfiguration, store: any CloudSyncStore, session: UUID, batchSize: Int) {
        subscriptionID = configuration.subscriptionID
        automaticallySync = configuration.automaticallySync
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            driver = CloudKitEngineTransport(config: configuration, store: store, session: session, batchSize: batchSize)
        } else {
            driver = CloudKitOperationsTransport(settings: .init(configuration),
                client: SystemCloudKitOperationsClient(config: configuration), store: store, session: session, batchSize: batchSize)
        }
    }

    package var lastError: Error? { get async { await driver.lastError } }
    package func sync(progress: SyncProgressHandler?) async throws -> SyncResult { startObserving(); return try await driver.sync(progress: progress) }
    package func localChangesAvailable() async {
        guard automaticallySync else { return }
        startObserving()
        await driver.schedule()
    }
    package func handleRemoteNotification(subscriptionID id: String) async -> Bool {
        guard id == subscriptionID else { return false }
        if automaticallySync { await driver.schedule() }
        return true
    }
    private func startObserving() {
        guard accountObserver == nil, automaticallySync else { return }
        let driver = driver
        accountObserver = Task {
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard !Task.isCancelled else { return }
                await driver.accountChanged()
            }
        }
    }
    package func stop() async { accountObserver?.cancel(); accountObserver = nil; await driver.stop() }
    deinit { accountObserver?.cancel() }
}

/// Keeps observers attached to a shared in-flight cycle. Callbacks should only report progress;
/// they must not await another sync on the same connection.
actor SyncProgressObservers {
    private var handlers: [UUID: SyncProgressHandler] = [:]
    private var latest: SyncProgress?
    func add(_ handler: SyncProgressHandler?, replay: Bool) async -> UUID {
        let id = UUID()
        if let handler {
            handlers[id] = handler
            if replay, let latest { await handler(latest) }
        }
        return id
    }
    func remove(_ id: UUID) { handlers[id] = nil }
    func reset() { latest = nil }
    var hasObservers: Bool { !handlers.isEmpty }
    func send(_ value: SyncProgress) async {
        latest = value
        for handler in Array(handlers.values) { await handler(value) }
    }
}
