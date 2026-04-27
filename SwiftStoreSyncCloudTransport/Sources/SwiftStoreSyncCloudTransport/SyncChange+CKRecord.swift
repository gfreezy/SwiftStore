import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreChangeTracker
import SwiftStoreSync

extension SyncChange {
    enum RecordField {
        static let id = "id"
        static let entityType = "entityType"
        static let syncKey = "syncKey"
        static let operation = "operation"
        static let payload = "payload"
        static let payloadAsset = "payloadAsset"
        static let deviceId = "deviceId"
        static let logicalClock = "logicalClock"
        static let schemaVersion = "schemaVersion"
        static let createdAt = "createdAt"
    }

    /// CloudKit record name derived from (entityType, syncKey). Insert / update /
    /// delete for the same entity collide on the same `CKRecord.ID`, so deletes
    /// can be performed via `CKDatabase.deleteRecord` rather than tombstones.
    ///
    /// The total name stays under CloudKit's 255 ASCII-char limit for every
    /// reasonable entity name + sync key combination (UUID syncKey → 32 hex
    /// chars; composite keys up to ~100 bytes still fit).
    public static func recordName(entityType: String, syncKey: Data) -> String {
        "\(entityType):\(syncKey.cloudTransportHexString)"
    }

    /// Inverse of `recordName(entityType:syncKey:)`. Returns nil on malformed input.
    public static func parseRecordName(_ name: String) -> (entityType: String, syncKey: Data)? {
        guard let colon = name.firstIndex(of: ":") else { return nil }
        let entityType = String(name[..<colon])
        let hex = String(name[name.index(after: colon)...])
        guard let syncKey = Data(cloudTransportHex: hex) else { return nil }
        return (entityType, syncKey)
    }

    /// Build a `CKRecord` representation of this change (for insert / update).
    /// Delete operations do not produce a `CKRecord` — they are applied via
    /// `CKSyncEngine.State.add(pendingRecordZoneChanges: [.deleteRecord(...)])`.
    ///
    /// Large payloads (over `assetThreshold` UTF-8 bytes) are written to a
    /// temporary file and attached as a `CKAsset`.
    public func makeCKRecord(
        zoneID: CKRecordZone.ID,
        recordType: CKRecord.RecordType,
        assetThreshold: Int
    ) throws -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: Self.recordName(entityType: entityType, syncKey: syncKey),
            zoneID: zoneID
        )
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[RecordField.id] = id.description as NSString
        record[RecordField.entityType] = entityType as NSString
        record[RecordField.syncKey] = syncKey as NSData
        record[RecordField.operation] = operation.rawValue as NSString
        record[RecordField.deviceId] = deviceId.description as NSString
        record[RecordField.logicalClock] = NSNumber(value: logicalClock)
        record[RecordField.schemaVersion] = NSNumber(value: Int64(schemaVersion))
        record[RecordField.createdAt] = createdAt as NSDate

        if let payload {
            let utf8Count = payload.utf8.count
            if utf8Count > assetThreshold {
                let url = try Self.writePayloadToTempFile(payload)
                record[RecordField.payloadAsset] = CKAsset(fileURL: url)
                record[RecordField.payload] = nil
            } else {
                record[RecordField.payload] = payload as NSString
                record[RecordField.payloadAsset] = nil
            }
        }

        return record
    }

    /// Attempt to reconstruct a `SyncChange` from a `CKRecord`.
    /// Returns nil if required fields are missing or malformed.
    public init?(ckRecord record: CKRecord) {
        guard let idStr = record[RecordField.id] as? String,
              let id = UUIDV7(uuidString: idStr),
              let entityType = record[RecordField.entityType] as? String,
              let syncKey = record[RecordField.syncKey] as? Data,
              let opStr = record[RecordField.operation] as? String,
              let operation = ChangeOperation(rawValue: opStr),
              let deviceStr = record[RecordField.deviceId] as? String,
              let deviceId = UUIDV7(uuidString: deviceStr),
              let logicalClockValue = record[RecordField.logicalClock] as? Int64,
              let schemaVersionValue = record[RecordField.schemaVersion] as? Int64,
              let createdAt = record[RecordField.createdAt] as? Date
        else {
            return nil
        }

        let payload: String?
        if let inline = record[RecordField.payload] as? String {
            payload = inline
        } else if let asset = record[RecordField.payloadAsset] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url),
                  let str = String(data: data, encoding: .utf8) {
            payload = str
        } else {
            payload = nil
        }

        self.init(
            id: id,
            entityType: entityType,
            syncKey: syncKey,
            operation: operation,
            payload: payload,
            deviceId: deviceId,
            logicalClock: logicalClockValue,
            schemaVersion: Int(schemaVersionValue),
            createdAt: createdAt
        )
    }

    /// Synthesize a `SyncChange.delete` from a `CKRecord.ID` delivered via
    /// `.fetchedRecordZoneChanges.deletions`. CloudKit does not carry the
    /// original logicalClock / deviceId through a record deletion, so
    /// placeholder values are used — the applier only needs `entityType` and
    /// `syncKey` for deletes.
    public static func syntheticDelete(from recordID: CKRecord.ID) -> SyncChange? {
        guard let (entityType, syncKey) = parseRecordName(recordID.recordName) else {
            return nil
        }
        return SyncChange(
            id: UUIDV7(),
            entityType: entityType,
            syncKey: syncKey,
            operation: .delete,
            payload: nil,
            deviceId: UUIDV7(),
            logicalClock: Int64.max,
            schemaVersion: 1,
            createdAt: Date()
        )
    }

    private static func writePayloadToTempFile(_ payload: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStoreSyncCloudTransport", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString + ".payload")
        try payload.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Hex helpers

extension Data {
    var cloudTransportHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(cloudTransportHex hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
