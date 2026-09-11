import Foundation
import SwiftStoreCore

/// Captures complete local statements and appends their events on the SAME connection,
/// before SQLiteConnection releases the statement savepoint. No second database commit.
public final class ChangeTracker: SQLiteUpdateHookHandler {
    private let mainConnection: SQLiteConnection
    private let registeredEntities: [String: any EntityProtocol.Type]
    private let deviceId: UUIDV7
    private let nowMilliseconds: () -> Int64
    private let schemaVersion: Int
    private var columnOffsets: [String: [Int]] = [:]

    public init(connection: SQLiteConnection, deviceId: UUIDV7,
                registeredEntities: [any EntityProtocol.Type],
                tickClock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
                schemaVersion: Int = 1) throws {
        guard SQLiteConnection.supportsPreUpdateHook else {
            throw StoreError.queryFailed("Change tracking requires SQLite with SQLITE_ENABLE_PREUPDATE_HOOK")
        }
        guard schemaVersion > 0, Set(registeredEntities.map { $0.tableName }).count == registeredEntities.count,
              registeredEntities.allSatisfy({ !$0.tableName.hasPrefix("__swiftstore_") }) else {
            throw StoreError.invalidPayload("Invalid tracked schema or reserved entity name")
        }
        mainConnection = connection
        self.deviceId = deviceId
        self.registeredEntities = Dictionary(uniqueKeysWithValues: registeredEntities.map { ($0.tableName, $0) })
        nowMilliseconds = tickClock
        self.schemaVersion = schemaVersion
        try SyncLogStorage.create(in: connection)
    }

    public var connection: SQLiteConnection { mainConnection }

    public func start() throws {
        var offsets: [String: [Int]] = [:]
        for entity in registeredEntities.values {
            let stmt = try mainConnection.prepare("PRAGMA table_xinfo(\(quote(entity.tableName)))")
            var physical: [String: Int] = [:]
            while try stmt.step() {
                if let name = stmt.columnString(1) { physical[name] = Int(stmt.columnInt64(0)) }
            }
            offsets[entity.tableName] = try entity.columns.map {
                guard let offset = physical[$0.name] else {
                    throw StoreError.invalidPayload("Missing tracked column \(entity.tableName).\($0.name)")
                }
                return offset
            }
        }
        columnOffsets = offsets
        try mainConnection.setPreUpdateHook(self)
    }

    public func stop() { try? mainConnection.setPreUpdateHook(nil) }
    public func tracksTable(_ name: String) -> Bool { registeredEntities[name] != nil }
    public func handleUpdate(_ info: SQLiteUpdateInfo) {
        // SQLiteConnection uses the throwing batch method so failures roll back the write.
    }

    private struct Identity: Hashable { let table: String; let key: Data }
    private struct Captured {
        let identity: Identity
        var old: SQLiteRowSnapshot?
        var row: SQLiteRowSnapshot?
        var operation: ChangeOperation
    }

    public func handleUpdates(_ updates: [SQLiteUpdateInfo]) throws {
        var changes: [Captured] = []
        var positions: [Identity: Int] = [:]
        func record(_ value: Captured) {
            if let index = positions[value.identity] {
                changes[index].row = value.row
                changes[index].operation = changes[index].operation == .insert && value.operation == .update
                    ? .insert : value.operation
            } else {
                positions[value.identity] = changes.count
                changes.append(value)
            }
        }
        func capture(_ updates: [SQLiteUpdateInfo]) throws {
            for info in updates {
                guard let entity = registeredEntities[info.tableName], let offsets = columnOffsets[info.tableName] else { continue }
                func snapshot(_ values: [SQLiteValue]?) throws -> SQLiteRowSnapshot? {
                    guard let values else { return nil }
                    return SQLiteRowSnapshot(values: try offsets.map {
                        guard values.indices.contains($0) else { throw StoreError.invalidPayload("Tracked schema changed; restart tracking") }
                        return values[$0]
                    })
                }
                let old = try snapshot(info.oldValues), row = try snapshot(info.newValues)
                let oldID = try old.map { Identity(table: entity.tableName, key: try key($0, entity)) }
                let newID = try row.map { Identity(table: entity.tableName, key: try key($0, entity)) }
                if let oldID, info.operation == .delete || oldID != newID {
                    record(Captured(identity: oldID, old: old, row: nil, operation: .delete))
                }
                if let newID {
                    record(Captured(identity: newID, old: oldID == newID ? old : nil, row: row,
                        operation: info.operation == .insert || oldID != newID ? .insert : .update))
                }
            }
        }
        try capture(updates.filter { $0.source == .local })
        var assigned: [Identity: Int64] = [:]
        // Timestamp UPDATEs may themselves fire business triggers. Capture every
        // resulting row and settle timestamps before taking the final payloads.
        // A non-converging trigger rolls back the entire originating statement.
        for pass in 0..<32 {
            var corrected = false
            for change in changes {
                guard let entity = registeredEntities[change.identity.table],
                      let index = entity.columns.firstIndex(where: { $0.name == "updated_at" }) else {
                    throw StoreError.invalidPayload("Synchronized entities require updated_at")
                }
                let noOp = change.old.map { old in change.row.map { row in
                    old.values.enumerated().allSatisfy { $0.offset == index || $0.element == row.values[$0.offset] }
                } ?? false } ?? false
                let target: Double
                if noOp {
                    assigned[change.identity] = nil
                    target = change.old!.columnDouble(Int32(index))
                } else {
                    if assigned[change.identity] == nil {
                        let previous = try SyncLogStorage.knownTime(entity: entity.tableName, key: change.identity.key, in: mainConnection)
                        let oldTime = try change.old.map { try SyncLogStorage.timestamp($0.columnDouble(Int32(index))) }
                        let known = max(previous ?? Int64.min, oldTime ?? Int64.min)
                        let now = nowMilliseconds()
                        guard known < 9_007_199_254_740_990, abs(Double(now)) <= 9_007_199_254_740_990 else {
                            throw StoreError.invalidPayload("Cannot advance the local version timestamp")
                        }
                        assigned[change.identity] = max(now, known + 1)
                    }
                    target = Double(assigned[change.identity]!) / 1000
                }
                if let row = change.row, row.columnDouble(Int32(index)) != target {
                    let effects = try mainConnection.captureTrackedMaintenance {
                        try setTime(target, identity: change.identity, entity: entity)
                    }
                    try capture(effects)
                    corrected = true
                }
            }
            if !corrected { break }
            if pass == 31 { throw StoreError.invalidPayload("Timestamp triggers do not converge; local write rolled back") }
        }
        for change in changes {
            guard let time = assigned[change.identity], let entity = registeredEntities[change.identity.table] else { continue }
            let date = Date(timeIntervalSince1970: Double(time) / 1000)
            let payload = try change.row.map { String(decoding: try JSONEncoder().encode(entity.sqliteDecode(from: $0)), as: UTF8.self) }
            try SyncLogStorage.append(ChangeLog(entityType: entity.tableName, syncKey: change.identity.key,
                operation: change.operation, payload: payload, deviceId: deviceId, logicalClock: time,
                schemaVersion: schemaVersion, createdAt: date, updatedAt: date), to: mainConnection)
            try SyncLogStorage.remember(entity: entity.tableName, key: change.identity.key, time: time,
                deleted: change.operation == .delete, in: mainConnection)
        }
    }

    /// Run after business migration and legacy import, before exposing the writer.
    /// Existing timestamps are preserved. Each entity's capture and marker commit together.
    public func captureExistingRows() throws {
        try captureExistingRows(coveredRemotely: { _, _, _ in false })
    }

    package func captureExistingRows(coveredRemotely: (String, Data, Int64) throws -> Bool) throws {
        try mainConnection.transaction {
            for entity in registeredEntities.values.sorted(by: { $0.tableName < $1.tableName }) {
                let captured: Int64 = try mainConnection.queryScalar(
                    "SELECT COUNT(*) FROM __swiftstore_sync_bootstrap WHERE entity_type = ?", values: [.text(entity.tableName)]) ?? 0
                guard captured == 0 else { continue }
                let columns = entity.columns.map { quote($0.name) }.joined(separator: ",")
                let stmt = try mainConnection.prepare("SELECT \(columns) FROM \(quote(entity.tableName))")
                while try stmt.step() {
                    let row = SQLiteRowSnapshot(values: entity.columns.enumerated().map {
                        stmt.columnValue(Int32($0.offset), type: $0.element.type)
                    })
                    let syncKey = try key(row, entity)
                    guard let index = entity.columns.firstIndex(where: { $0.name == "updated_at" }) else {
                        throw StoreError.invalidPayload("Synchronized entities require updated_at")
                    }
                    let time = try SyncLogStorage.timestamp(row.columnDouble(Int32(index)))
                    let date = Date(timeIntervalSince1970: Double(time) / 1000)
                    let payload = String(decoding: try JSONEncoder().encode(entity.sqliteDecode(from: row)), as: UTF8.self)
                    if try coveredRemotely(entity.tableName, syncKey, time) { continue }
                    let previous: String? = try mainConnection.queryScalar(
                        "SELECT payload FROM __swiftstore_change_log WHERE entity_type=? AND sync_key=? ORDER BY seq DESC LIMIT 1",
                        values: [.text(entity.tableName), .blob(syncKey)])
                    if let previous,
                       let a = try JSONSerialization.jsonObject(with: Data(previous.utf8)) as? NSDictionary,
                       let b = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? NSDictionary, a.isEqual(b) { continue }
                    try SyncLogStorage.append(ChangeLog(entityType: entity.tableName, syncKey: syncKey, operation: .insert,
                        payload: payload, deviceId: deviceId, logicalClock: time, schemaVersion: schemaVersion,
                        createdAt: date, updatedAt: date), to: mainConnection)
                    try SyncLogStorage.remember(entity: entity.tableName, key: syncKey, time: time, deleted: false, in: mainConnection)
                }
                try mainConnection.execute("INSERT INTO __swiftstore_sync_bootstrap(entity_type) VALUES(?)", values: [.text(entity.tableName)])
            }
        }
    }

    private func key(_ row: SQLiteRowSnapshot, _ entity: any EntityProtocol.Type) throws -> Data {
        try SyncKeyEncoder.encode(entity.syncKeyColumns.map { name in
            guard let index = entity.columns.firstIndex(where: { $0.name == name }) else {
                throw StoreError.invalidPayload("Unknown sync key column \(name)")
            }
            return row.values[index]
        })
    }

    private func setTime(_ value: Double, identity: Identity, entity: any EntityProtocol.Type) throws {
        let values = SyncKeyEncoder.decode(identity.key)
        guard values.count == entity.syncKeyColumns.count else { throw StoreError.invalidPayload("Invalid sync key") }
        let predicate = entity.syncKeyColumns.map { "\(quote($0)) = ?" }.joined(separator: " AND ")
        try mainConnection.execute("UPDATE \(quote(entity.tableName)) SET updated_at = ? WHERE \(predicate) AND updated_at != ?",
            values: [.real(value)] + values + [.real(value)])
    }

    private func quote(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
