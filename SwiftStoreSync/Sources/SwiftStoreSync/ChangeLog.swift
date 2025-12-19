import Foundation
import SwiftStoreCore

/// Change operation type
public enum ChangeOperation: String, Codable, Sendable {
    case insert
    case update
    case delete
}

/// Change log entry for sync
public struct ChangeLog: EntityProtocol, SQLiteCodable, Codable, Sendable {
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

    public static var tableName: String { ChangeTracker.changeLogTable }

    public static var columns: [ColumnDefinition] {
        [
            ColumnDefinition(name: "id", type: .blob, primaryKey: true),
            ColumnDefinition(name: "entity_type", type: .text),
            ColumnDefinition(name: "entity_id", type: .blob),
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

    public func sqliteEncode() throws -> [String: SQLiteValue] {
        [
            "id": .blob(id.data),
            "entity_type": .text(entityType),
            "entity_id": .blob(entityId.data),
            "operation": .text(operation.rawValue),
            "payload": payload.map { .text($0) } ?? .null,
            "device_id": .text(deviceId),
            "logical_clock": .integer(logicalClock),
            "created_at": .real(createdAt.timeIntervalSince1970),
            "updated_at": .real(updatedAt.timeIntervalSince1970)
        ]
    }

    public static func sqliteDecode(from stmt: SQLiteStatement) throws -> ChangeLog {
        ChangeLog(
            id: UUIDV4(data: stmt.columnData(0) ?? Data()) ?? UUIDV4(),
            entityType: stmt.columnString(1) ?? "",
            entityId: UUIDV4(data: stmt.columnData(2) ?? Data()) ?? UUIDV4(),
            operation: ChangeOperation(rawValue: stmt.columnString(3) ?? "") ?? .insert,
            payload: stmt.columnString(4),
            deviceId: stmt.columnString(5) ?? "",
            logicalClock: stmt.columnInt64(6),
            createdAt: Date(timeIntervalSince1970: stmt.columnDouble(7)),
            updatedAt: Date(timeIntervalSince1970: stmt.columnDouble(8))
        )
    }
}
