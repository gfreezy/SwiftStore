import Foundation
import SwiftStoreCore
import SwiftStoreMacros

/// Change operation type
public enum ChangeOperation: String, Codable, Sendable {
    case insert
    case update
    case delete
}

/// Change log entry for sync
@Entity(tableName: "__swiftstore_change_log")
public struct ChangeLog: Codable, Sendable {
    #Index<Self>(\.logicalClock)
    #Index<Self>(\.entityType, \.entityId)

    public let id: UUIDV4
    public var entityType: String
    public var entityId: UUIDV4
    public var operation: ChangeOperation
    public var payload: String?
    public var deviceId: String
    public var logicalClock: Int64
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUIDV4 = UUIDV4(),
        entityType: String,
        entityId: UUIDV4,
        operation: ChangeOperation,
        payload: String? = nil,
        deviceId: String,
        logicalClock: Int64,
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

