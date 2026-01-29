import Foundation
import SwiftStoreCore

/// Change operation type
@Embedded
public enum ChangeOperation: String, Sendable {
    case insert
    case update
    case delete
}

/// Change log entry for sync
@Entity
public struct ChangeLog {
    public var id: UUIDV7 = UUIDV7()
    public var entityType: String
    /// Binary encoded sync key values (using SyncKeyEncoder)
    public var syncKey: Data
    public var operation: ChangeOperation
    public var payload: String?
    public var deviceId: UUIDV7
    public var logicalClock: Int64
    /// Schema version for migration compatibility
    /// Higher versions can process lower version data, lower versions ignore higher version data
    public var schemaVersion: Int
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
}

