import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreSync

extension SyncChange {
    enum RecordField {
        static let updatedAt = "updatedAt"
        static let payload = "payload"
        static let payloadAsset = "payloadAsset"
    }

    /// The same opaque SHA-256 key as HTTP, used as CloudKit's native record ID.
    public static func recordName(entityType: String, syncKey: Data) -> String {
        SyncRecordEnvelope.key(entityType: entityType, syncKey: syncKey)
    }

    /// CloudKit adds only its native record ID and conditional-save system fields
    /// to the shared key / updatedAt / payload representation.
    public func makeCKRecord(
        zoneID: CKRecordZone.ID,
        recordType: CKRecord.RecordType,
        assetThreshold: Int,
        systemFields: Data? = nil
    ) throws -> CKRecord {
        let envelope = try SyncRecordEnvelope(change: self)
        let recordID = CKRecord.ID(recordName: envelope.key, zoneID: zoneID)
        let record: CKRecord
        if let systemFields {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: systemFields)
            decoder.requiresSecureCoding = true
            defer { decoder.finishDecoding() }
            guard let restored = CKRecord(coder: decoder),
                  restored.recordID == recordID, restored.recordType == recordType else {
                throw CloudKitTransportError.encodingFailed("Mismatched cached record")
            }
            record = restored
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record[RecordField.updatedAt] = NSNumber(value: envelope.updatedAt)
        record[RecordField.payload] = nil
        record[RecordField.payloadAsset] = nil
        let inline = envelope.payload.base64EncodedString()
        if inline.utf8.count > assetThreshold {
            let url = try Self.writePayloadToTempFile(envelope.payload)
            record[RecordField.payloadAsset] = CKAsset(fileURL: url)
        } else {
            record[RecordField.payload] = inline as NSString
        }
        return record
    }

    /// Decode opaque inline/asset bytes, then validate identity and time against
    /// the same shared envelope used by HTTP. Tombstones also require a payload.
    public init?(ckRecord record: CKRecord) {
        guard let updatedAt = record[RecordField.updatedAt] as? Int64 else { return nil }
        let payload: Data
        if let inline = record[RecordField.payload] as? String,
           record[RecordField.payloadAsset] == nil,
           let data = Data(base64Encoded: inline) {
            payload = data
        } else if record[RecordField.payload] == nil,
                  let asset = record[RecordField.payloadAsset] as? CKAsset,
                  let url = asset.fileURL, let data = try? Data(contentsOf: url) {
            payload = data
        } else {
            return nil
        }
        let envelope = SyncRecordEnvelope(key: record.recordID.recordName, updatedAt: updatedAt, payload: payload)
        guard let change = try? envelope.decodeChange() else { return nil }
        self = change
    }

    private static func writePayloadToTempFile(_ payload: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStoreSyncCloudTransport", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString + ".payload")
        try payload.write(to: url, options: .atomic)
        return url
    }
}

extension CKRecord {
    func syncSystemFields() -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        return encoder.encodedData
    }
}
