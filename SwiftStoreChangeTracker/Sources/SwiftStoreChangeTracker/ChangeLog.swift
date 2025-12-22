import Foundation
import SwiftStoreCore

/// Change operation type
public enum ChangeOperation: String, Codable, Sendable {
    case insert
    case update
    case delete
}

/// Change log entry for sync
@Entity
public struct ChangeLog {
    public let id: UUIDV4
    public var entityType: String
    public var entityId: UUIDV4
    public var operation: ChangeOperation
    public var payload: String?
    public var deviceId: UUIDV4
    public var logicalClock: Int64
    /// Schema version for migration compatibility
    /// Higher versions can process lower version data, lower versions ignore higher version data
    public var schemaVersion: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUIDV4 = UUIDV4(),
        entityType: String,
        entityId: UUIDV4,
        operation: ChangeOperation,
        payload: String? = nil,
        deviceId: UUIDV4,
        logicalClock: Int64,
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.payload = payload
        self.deviceId = deviceId
        self.logicalClock = logicalClock
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

