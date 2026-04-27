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
    /// Changes pulled from remote in this cycle. Canonical delivery path.
    public let pulled: [SyncChange]
    /// Identifiers of local changes that were successfully committed to remote.
    public let pushed: [UUIDV7]
    /// Changes rejected by remote as conflicts (for CloudKit: serverRecordChanged only).
    public let conflicts: [SyncChange]

    public init(pulled: [SyncChange], pushed: [UUIDV7], conflicts: [SyncChange]) {
        self.pulled = pulled
        self.pushed = pushed
        self.conflicts = conflicts
    }
}

/// Protocol for a sync transport connecting local change tracking to a remote backend.
///
/// Implementations may be event-driven (e.g., CloudKit's `CKSyncEngine`) or
/// request-response (e.g., REST/WebSocket). The transport owns its own
/// watermark state — callers do not pass a cursor.
public protocol SyncTransport: Sendable {
    /// Signal-only stream that yields when the transport observes remote
    /// activity (push notification, server event, poll tick). Consumers should
    /// treat this as a trigger to call `syncNow()` via `SyncManager.sync()`.
    /// Pulled changes are delivered via `SyncCycleResult.pulled`, not here.
    /// Finishes after `stop()` returns.
    var remoteChanges: AsyncStream<Void> { get }

    /// Activate the transport. Idempotent. Must be called before `enqueue`
    /// or `syncNow`.
    /// - Parameter deviceId: The local device ID; the transport may use it to
    ///   annotate outgoing records or filter incoming ones.
    func start(deviceId: UUIDV7) async throws

    /// Deactivate the transport. Finishes the `remoteChanges` stream.
    /// Idempotent.
    func stop() async

    /// Stage local changes for the next sync cycle. Must not perform network I/O.
    /// Changes staged here are delivered on the next `syncNow()` call.
    func enqueue(_ changes: [SyncChange]) async throws

    /// Run a single fetch + send cycle. The transport is responsible for
    /// tracking its own watermark between calls, so no cursor is required.
    func syncNow() async throws -> SyncCycleResult
}
