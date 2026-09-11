import Foundation
import SwiftStoreCore

/// Change operation type
@Embedded
public enum ChangeOperation: String, Sendable {
    case insert
    case update
    case delete
}

/// Immutable local event. `seq` is the database's append order, independent of time.
@Entity(tableName: "__swiftstore_change_log")
public struct ChangeLog {
    public var id: UUIDV7 = UUIDV7()
    public var seq: Int64 = 0
    public var entityType: String
    /// Binary encoded sync key values (using SyncKeyEncoder)
    public var syncKey: Data
    public var operation: ChangeOperation
    public var payload: String?
    public var deviceId: UUIDV7
    public var logicalClock: Int64
    /// Schema version for migration compatibility
    /// Unsupported future schemas block synchronization without losing the event.
    public var schemaVersion: Int
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
}
