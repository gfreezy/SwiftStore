import Foundation
import SwiftStoreCore

/// Change operation type
public enum ChangeOperation: String, Codable, Sendable {
    case insert
    case update
    case delete
}

/// Change log entry for sync
public struct ChangeLog: EntityProtocol, SQLiteCodable, Sendable {
    public let id: UUIDV4
    public var entityType: String
    public var entityId: UUIDV4
    public var operation: ChangeOperation
    public var payload: String?
    public var deviceId: String
    public var logicalClock: Int64
    public let createdAt: Date
    public let updatedAt: Date

    public static var tableName: String { "__swiftstore_change_log" }

    public static var columns: [ColumnDefinition] {
        [
            ColumnDefinition(name: "id", type: .blob, primaryKey: true),
            ColumnDefinition(name: "entity_type", type: .text),
            ColumnDefinition(name: "entity_id", type: .blob),
            ColumnDefinition(name: "operation", type: .text),
            ColumnDefinition(name: "payload", type: .text, nullable: true),
            ColumnDefinition(name: "device_id", type: .text),
            ColumnDefinition(name: "logical_clock", type: .integer),
            ColumnDefinition(name: "created_at", type: .real, defaultValue: "(strftime('%s', 'now'))"),
            ColumnDefinition(name: "updated_at", type: .real, defaultValue: "(strftime('%s', 'now'))")
        ]
    }

    public static var indexes: [IndexDefinition] {
        [
            IndexDefinition(name: "idx___swiftstore_change_log_logical_clock", columns: ["logical_clock"]),
            IndexDefinition(name: "idx___swiftstore_change_log_entity", columns: ["entity_type", "entity_id"])
        ]
    }

    public static var foreignKeys: [ForeignKeyDefinition] { [] }

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

    public func sqliteEncode() throws -> [String: SQLiteValue] {
        var result: [String: SQLiteValue] = [
            "id": .blob(id.data),
            "entity_type": .text(entityType),
            "entity_id": .blob(entityId.data),
            "operation": .text(operation.rawValue),
            "device_id": .text(deviceId),
            "logical_clock": .integer(logicalClock),
            "created_at": .real(createdAt.timeIntervalSince1970),
            "updated_at": .real(updatedAt.timeIntervalSince1970)
        ]
        if let payload = payload {
            result["payload"] = .text(payload)
        } else {
            result["payload"] = .null
        }
        return result
    }

    public static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> ChangeLog {
        let id = UUIDV4(data: statement.columnData(0) ?? Data()) ?? UUIDV4()
        let entityType = statement.columnString(1) ?? ""
        let entityId = UUIDV4(data: statement.columnData(2) ?? Data()) ?? UUIDV4()
        let operationStr = statement.columnString(3) ?? "insert"
        let operation = ChangeOperation(rawValue: operationStr) ?? .insert
        let payload = statement.columnString(4)
        let deviceId = statement.columnString(5) ?? ""
        let logicalClock = statement.columnInt64(6)
        let createdAt = Date(timeIntervalSince1970: statement.columnDouble(7))
        let updatedAt = Date(timeIntervalSince1970: statement.columnDouble(8))

        return ChangeLog(
            id: id,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: payload,
            deviceId: deviceId,
            logicalClock: logicalClock,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

