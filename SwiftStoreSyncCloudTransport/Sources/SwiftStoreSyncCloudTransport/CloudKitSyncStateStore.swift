import Foundation
import CloudKit
import SwiftStoreSync

/// One-time bootstrap flags persisted across app launches.
public struct CloudKitSetupFlags: Codable, Sendable {
    public var didCreateZone: Bool
    public var didSubscribe: Bool

    public init(didCreateZone: Bool = false, didSubscribe: Bool = false) {
        self.didCreateZone = didCreateZone
        self.didSubscribe = didSubscribe
    }
}

/// Persistence for `CloudKitSyncTransport` state. The transport has three
/// pieces of state that must survive app restarts:
///
/// 1. The `CKSyncEngine.State.Serialization` blob — CloudKit's own opaque
///    change-tracking token. Without it, the engine re-fetches everything
///    from scratch on every launch.
/// 2. The pending-push map — local changes handed to `enqueue(_:)` but not
///    yet confirmed saved by CloudKit. Needed because
///    `nextRecordZoneChangeBatch` may fire after a relaunch and needs to
///    re-materialize the full `CKRecord` for pending IDs.
/// 3. Setup flags — whether the CloudKit zone and subscription have been
///    created. One-time bootstrap, persisted so we don't redo it on every
///    launch.
///
/// Implementations must treat decode failures as "no state" (return nil /
/// empty) rather than throwing, so the transport can degrade gracefully.
public protocol CloudKitSyncStateStore: Sendable {
    func loadEngineState() async throws -> CKSyncEngine.State.Serialization?
    func saveEngineState(_ state: CKSyncEngine.State.Serialization) async throws

    func loadPendingPush() async throws -> [String: SyncChange]
    func savePendingPush(_ map: [String: SyncChange]) async throws

    func loadSetupFlags() async throws -> CloudKitSetupFlags
    func saveSetupFlags(_ flags: CloudKitSetupFlags) async throws
}

/// Default file-based `CloudKitSyncStateStore`. Writes three plist files
/// atomically inside the given directory.
///
/// Use this when you don't already have a persistence layer; otherwise
/// implement `CloudKitSyncStateStore` against your own storage (SQLite,
/// UserDefaults, keychain, etc.) to avoid managing a second on-disk state
/// directory.
public actor FileCloudKitSyncStateStore: CloudKitSyncStateStore {
    private let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    private var engineStateURL: URL { directory.appendingPathComponent("engine-state.plist") }
    private var pendingPushURL: URL { directory.appendingPathComponent("pending-push.plist") }
    private var setupFlagsURL: URL { directory.appendingPathComponent("setup-flags.plist") }

    // MARK: - Engine state

    public func loadEngineState() async throws -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: engineStateURL) else { return nil }
        do {
            return try PropertyListDecoder().decode(
                CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            // Graceful fallback: corrupted state triggers a full re-fetch.
            return nil
        }
    }

    public func saveEngineState(_ state: CKSyncEngine.State.Serialization) async throws {
        let data = try PropertyListEncoder().encode(state)
        try data.write(to: engineStateURL, options: .atomic)
    }

    // MARK: - Pending push

    public func loadPendingPush() async throws -> [String: SyncChange] {
        guard let data = try? Data(contentsOf: pendingPushURL) else { return [:] }
        do {
            return try PropertyListDecoder().decode([String: SyncChange].self, from: data)
        } catch {
            return [:]
        }
    }

    public func savePendingPush(_ map: [String: SyncChange]) async throws {
        let data = try PropertyListEncoder().encode(map)
        try data.write(to: pendingPushURL, options: .atomic)
    }

    // MARK: - Setup flags

    public func loadSetupFlags() async throws -> CloudKitSetupFlags {
        guard let data = try? Data(contentsOf: setupFlagsURL) else { return CloudKitSetupFlags() }
        do {
            return try PropertyListDecoder().decode(CloudKitSetupFlags.self, from: data)
        } catch {
            return CloudKitSetupFlags()
        }
    }

    public func saveSetupFlags(_ flags: CloudKitSetupFlags) async throws {
        let data = try PropertyListEncoder().encode(flags)
        try data.write(to: setupFlagsURL, options: .atomic)
    }
}
