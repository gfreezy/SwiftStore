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

/// Response from pull operation
public struct PullResponse: Sendable {
    /// Changes from remote since the requested clock
    public let changes: [SyncChange]
    /// The latest server clock value
    public let serverClock: Int64

    public init(changes: [SyncChange], serverClock: Int64) {
        self.changes = changes
        self.serverClock = serverClock
    }
}

/// Response from push operation
public struct PushResponse: Sendable {
    /// Whether the push was successful
    public let success: Bool
    /// The new server clock value after push
    public let serverClock: Int64
    /// Any conflicts that occurred (changes that couldn't be applied)
    public let conflicts: [SyncChange]

    public init(success: Bool, serverClock: Int64, conflicts: [SyncChange] = []) {
        self.success = success
        self.serverClock = serverClock
        self.conflicts = conflicts
    }
}

/// Protocol for remote sync transport
/// Implement this protocol to connect to your sync server (REST API, WebSocket, etc.)
public protocol SyncTransport: Sendable {
    /// Pull changes from remote since the given clock value
    /// - Parameters:
    ///   - sinceClock: The clock value to get changes after
    ///   - deviceId: The local device ID (to exclude own changes if needed)
    /// - Returns: Pull response with remote changes
    func pull(sinceClock: Int64, deviceId: UUIDV7) async throws -> PullResponse

    /// Push local changes to remote
    /// - Parameters:
    ///   - changes: The changes to push
    ///   - deviceId: The local device ID
    /// - Returns: Push response with result
    func push(changes: [SyncChange], deviceId: UUIDV7) async throws -> PushResponse
}
