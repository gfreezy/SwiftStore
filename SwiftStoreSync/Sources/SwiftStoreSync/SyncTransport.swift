import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker

/// A change record for sync transmission
public struct SyncChange: Codable, Sendable {
    public let id: UUIDV7
    public let entityType: String
    /// Binary encoded sync key values (using SyncKeyEncoder)
    public let syncKey: Data
    public let operation: ChangeOperation
    public let payload: String?
    public let deviceId: UUIDV7
    public let logicalClock: Int64
    /// Schema version for migration compatibility
    public let schemaVersion: Int
    public let createdAt: Date

    public init(
        id: UUIDV7,
        entityType: String,
        syncKey: Data,
        operation: ChangeOperation,
        payload: String?,
        deviceId: UUIDV7,
        logicalClock: Int64,
        schemaVersion: Int = 1,
        createdAt: Date
    ) {
        self.id = id
        self.entityType = entityType
        self.syncKey = syncKey
        self.operation = operation
        self.payload = payload
        self.deviceId = deviceId
        self.logicalClock = logicalClock
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
    }

    /// Create from ChangeLog
    public init(from changeLog: ChangeLog) {
        self.id = changeLog.id
        self.entityType = changeLog.entityType
        self.syncKey = changeLog.syncKey
        self.operation = changeLog.operation
        self.payload = changeLog.payload
        self.deviceId = changeLog.deviceId
        self.logicalClock = changeLog.logicalClock
        self.schemaVersion = changeLog.schemaVersion
        self.createdAt = changeLog.createdAt
    }
}

/// Result of a single transport sync cycle.
public struct SyncCycleResult: Sendable {
    /// Authoritative committed versions, including winners of this device's uploads.
    /// The transport must coalesce each key to its latest known committed version.
    public let pulled: [SyncChange]
    /// Identifiers of local changes that were successfully committed to remote.
    public let pushed: [UUIDV7]
    /// Local changes rejected or superseded by the backend's timestamp policy.
    public let conflicts: [SyncChange]
    /// Records still waiting for server submission; defer downloaded versions of
    /// these keys without acknowledging them, so local edits remain visible.
    public let pendingChanges: [SyncChange]
    /// Durable corrections, retained until their final server version is applied.
    public let rejectedKeys: [RejectedChange]

    public init(pulled: [SyncChange], pushed: [UUIDV7], conflicts: [SyncChange], pendingChanges: [SyncChange] = [], rejectedKeys: [RejectedChange] = []) {
        self.pulled = pulled
        self.pushed = pushed
        self.conflicts = conflicts
        self.pendingChanges = pendingChanges
        self.rejectedKeys = rejectedKeys
    }
}

/// Protocol for a sync transport connecting local change tracking to a remote backend.
///
/// Implementations may be event-driven (e.g., CloudKit's `CKSyncEngine`) or
/// request-response (e.g., REST/WebSocket). The transport owns its own
/// watermark state — callers do not pass a cursor.
///
/// Both built-in transports implement the same backend contract: greater
/// updatedAt (rounded Unix milliseconds) wins; ties retain the committed version.
/// Conflict resolution belongs behind this interface, never in SyncManager.
/// HTTP delegates to its server; CloudKit uses the timestamp resolver plus
/// CloudKit's change-tag conditional saves. Custom transports must return
/// committed decisions too, not unresolved candidate changes.
public protocol SyncTransport: Sendable {
    /// Signal-only stream that yields when the transport observes remote
    /// activity (push notification, server event, poll tick). Consumers should
    /// treat this as a trigger to call `syncNow()` via `SyncManager.sync()`.
    /// Pulled changes are delivered via `SyncCycleResult.pulled`, not here.
    /// Finishes after `stop()` returns.
    var remoteChanges: AsyncStream<Void> { get }

    /// Set the required accuracy for transports that also sync in the background.
    func configureTimeValidation(toleranceMs: Int64) async throws

    /// Activate the transport. Idempotent. Must be called before `enqueue`
    /// or `syncNow`. The local device ID should remain stable across restarts.
    func start(deviceId: UUIDV7) async throws

    /// Deactivate the transport. Finishes the `remoteChanges` stream.
    /// Idempotent.
    func stop() async

    /// Stage local changes for the next sync cycle. Must not perform network I/O.
    /// Must durably retain work before returning; the caller advances its local
    /// watermark after enqueue succeeds. Delivery occurs in syncNow or background sync.
    func enqueue(_ changes: [SyncChange]) async throws

    /// Run upload arbitration followed by incremental pull/reconciliation.
    /// The transport tracks its own watermark, so no cursor is required.
    /// Resolve rejectedKeys from pull first, then carried content or a key lookup.
    /// Return committed versions, receipts, and all still-pending changes. Retain results until acknowledged;
    /// delayed pages or callbacks must not roll a key back to an older version.
    func syncNow() async throws -> SyncCycleResult

    /// Confirm only changes successfully applied (or intentionally ignored).
    /// Durable transports retain unacknowledged results across cycles/restarts.
    func acknowledge(_ result: SyncCycleResult) async throws
}

public extension SyncChange {
    /// Business rows use their own updatedAt; tombstones use the deletion time.
    /// Older wire records without updatedAt fall back to their change timestamp.
    var updatedAt: Date {
        struct Timestamp: Decodable { let updatedAt: Date }
        guard operation != .delete, let payload,
              let timestamp = try? JSONDecoder().decode(Timestamp.self, from: Data(payload.utf8)) else {
            return createdAt
        }
        return timestamp.updatedAt
    }

    /// Compare using the shared backend policy. Equal timestamps are not newer.
    func isNewer(than other: SyncChange) -> Bool {
        TimestampConflictResolver().shouldReplace(other, with: self)
    }

}

public extension SyncTransport {
    func configureTimeValidation(toleranceMs: Int64) async throws {
        guard toleranceMs > 0 else { throw NTPError.invalidTolerance }
    }

    /// Compatibility default for transports that do not maintain a durable inbox.
    func acknowledge(_ result: SyncCycleResult) async throws {}
}
