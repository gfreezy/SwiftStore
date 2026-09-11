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

