import Foundation
import CloudKit
import SwiftStoreSync

protocol CloudKitDriver: Sendable {
    var lastError: Error? { get async }
    func sync() async throws -> SyncResult
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
    package func sync() async throws -> SyncResult { startObserving(); return try await driver.sync() }
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
