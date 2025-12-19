import Foundation

/// Change operation type
public enum ChangeOperation: String, Codable, Sendable {
    case insert
    case update
    case delete
}

/// Change log entry for sync
public struct ChangeLog: EntityProtocol, Sendable {
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
        payload: String?,
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

    public static var tableName: String { "change_log" }

    public static var columns: [ColumnDefinition] {
        [
            ColumnDefinition(name: "id", type: .text, primaryKey: true),
            ColumnDefinition(name: "entity_type", type: .text),
            ColumnDefinition(name: "entity_id", type: .text),
            ColumnDefinition(name: "operation", type: .text),
            ColumnDefinition(name: "payload", type: .text, nullable: true),
            ColumnDefinition(name: "device_id", type: .text),
            ColumnDefinition(name: "logical_clock", type: .integer),
            ColumnDefinition(name: "created_at", type: .real),
            ColumnDefinition(name: "updated_at", type: .real)
        ]
    }

    public static var indexes: [IndexDefinition] {
        [
            IndexDefinition(name: "idx_change_log_clock", columns: ["logical_clock"]),
            IndexDefinition(name: "idx_change_log_entity", columns: ["entity_type", "entity_id"])
        ]
    }
}
