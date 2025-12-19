import Foundation

/// Change operation type
public enum ChangeOperation: String, Codable, Sendable {
    case insert
    case update
    case delete
}

/// Change log entry for sync (internal entity, manually implements SQLiteCodable)
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

    public static var tableName: String { "__swiftstore_change_log" }

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

    public func sqliteEncode() throws -> [String: SQLiteValue] {
        [
            "id": .text(id.uuidString),
            "entity_type": .text(entityType),
            "entity_id": .text(entityId.uuidString),
            "operation": .text(operation.rawValue),
            "payload": payload.map { .text($0) } ?? .null,
            "device_id": .text(deviceId),
            "logical_clock": .integer(logicalClock),
            "created_at": .real(createdAt.timeIntervalSince1970),
            "updated_at": .real(updatedAt.timeIntervalSince1970)
        ]
    }

    public static func sqliteDecode(from stmt: SQLiteStatement) throws -> ChangeLog {
        // Build column name to index map
        var columnIndex: [String: Int32] = [:]
        for i in 0..<stmt.columnCount {
            if let name = stmt.columnName(i) {
                columnIndex[name] = i
            }
        }

        guard let idIdx = columnIndex["id"],
              let idStr = stmt.columnString(idIdx),
              let id = UUIDV4(uuidString: idStr) else {
            throw StoreError.decodingFailed("Invalid id")
        }
        guard let entityTypeIdx = columnIndex["entity_type"],
              let entityType = stmt.columnString(entityTypeIdx) else {
            throw StoreError.decodingFailed("Invalid entity_type")
        }
        guard let entityIdIdx = columnIndex["entity_id"],
              let entityIdStr = stmt.columnString(entityIdIdx),
              let entityId = UUIDV4(uuidString: entityIdStr) else {
            throw StoreError.decodingFailed("Invalid entity_id")
        }
        guard let opIdx = columnIndex["operation"],
              let opStr = stmt.columnString(opIdx),
              let operation = ChangeOperation(rawValue: opStr) else {
            throw StoreError.decodingFailed("Invalid operation")
        }

        let payloadIdx = columnIndex["payload"] ?? -1
        let deviceIdIdx = columnIndex["device_id"] ?? -1
        let clockIdx = columnIndex["logical_clock"] ?? -1
        let createdIdx = columnIndex["created_at"] ?? -1
        let updatedIdx = columnIndex["updated_at"] ?? -1

        return ChangeLog(
            id: id,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: payloadIdx >= 0 ? stmt.columnString(payloadIdx) : nil,
            deviceId: deviceIdIdx >= 0 ? (stmt.columnString(deviceIdIdx) ?? "") : "",
            logicalClock: clockIdx >= 0 ? stmt.columnInt64(clockIdx) : 0,
            createdAt: createdIdx >= 0 ? stmt.columnDate(createdIdx) : Date(),
            updatedAt: updatedIdx >= 0 ? stmt.columnDate(updatedIdx) : Date()
        )
    }
}
