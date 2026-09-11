import Testing
import Foundation
import CloudKit
@testable import SwiftStoreSyncCloudTransport
import SwiftStoreCore
import SwiftStoreSync

@Suite("Opaque CloudKit record mapping")
struct SyncChangeCKRecordTests {
    let zoneID = CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName)
    let recordType: CKRecord.RecordType = "SwiftStoreSyncChange"

    private func change(payload: String? = #"{"updatedAt":810000000.125,"name":"Alice"}"#,
                        deletion: Bool = false) -> SyncChange {
        SyncChange(id: UUIDV7(), entityType: "user", syncKey: Data([1, 2, 3]),
            operation: deletion ? .delete : .update, payload: deletion ? nil : payload,
            deviceId: UUIDV7(), logicalClock: 42, schemaVersion: 3,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.25))
    }

    @Test("CloudKit exposes only an opaque record key, Unix milliseconds and full Base64 payload")
    func inlineEnvelope() throws {
        let original = change()
        let envelope = try CloudRecordEnvelope(change: original)
        let record = try original.makeCKRecord(zoneID: zoneID, recordType: recordType, assetThreshold: 1_000_000)
        #expect(Set(record.allKeys()) == ["updatedAt", "payload"])
        #expect(record.recordID.recordName == envelope.key)
        #expect(record.recordID.recordName.count == 64)
        #expect(record["updatedAt"] as? Int64 == 1788307200125)
        let payload = try #require(record["payload"] as? String)
        #expect(Data(base64Encoded: payload) == envelope.payload)
        let decoded = try #require(SyncChange(ckRecord: record))
        #expect(decoded.id == original.id)
        #expect(decoded.entityType == original.entityType && decoded.syncKey == original.syncKey)
        #expect(decoded.operation == original.operation && decoded.payload == original.payload)
        #expect(decoded.deviceId == original.deviceId && decoded.logicalClock == original.logicalClock)
        #expect(decoded.schemaVersion == original.schemaVersion && decoded.createdAt == original.createdAt)
    }

    @Test("Opaque keys are stable across edits and bounded even for long composite identities")
    func opaqueIdentity() throws {
        let first = change(), second = change()
        #expect(try CloudRecordEnvelope(change: first).key == CloudRecordEnvelope(change: second).key)
        let long = SyncChange.recordName(entityType: String(repeating: "实体:", count: 300),
            syncKey: Data(repeating: 255, count: 1000))
        #expect(long.count == 64)
        #expect(long.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(SyncChange.recordName(entityType: "ab", syncKey: Data("c".utf8))
            != SyncChange.recordName(entityType: "a", syncKey: Data("bc".utf8)))
    }

    @Test("Large opaque payload uses an asset and clears inline content")
    func assetRoundTrip() throws {
        let original = change(payload: String(repeating: "x", count: 1000))
        let record = try original.makeCKRecord(zoneID: zoneID, recordType: recordType, assetThreshold: 500)
        let url = try #require((record["payloadAsset"] as? CKAsset)?.fileURL)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Set(record.allKeys()) == ["updatedAt", "payloadAsset"])
        #expect(try Data(contentsOf: url) == CloudRecordEnvelope(change: original).payload)
        #expect(SyncChange(ckRecord: record)?.payload == original.payload)
        let small = try change().makeCKRecord(zoneID: zoneID, recordType: recordType,
            assetThreshold: 1_000_000, systemFields: record.syncSystemFields())
        #expect(small.recordID == record.recordID)
        #expect(Set(small.allKeys()) == ["updatedAt", "payload"])
    }

    @Test("Tombstones carry complete client metadata in the same opaque payload")
    func opaqueTombstone() throws {
        let original = change(deletion: true)
        let record = try original.makeCKRecord(zoneID: zoneID, recordType: recordType, assetThreshold: 1_000_000)
        #expect(Set(record.allKeys()) == ["updatedAt", "payload"])
        #expect(record["updatedAt"] as? Int64 == 1_700_000_000_250)
        let decoded = try #require(SyncChange(ckRecord: record))
        #expect(decoded.id == original.id && decoded.operation == .delete && decoded.payload == nil)
        record["payload"] = nil
        #expect(SyncChange(ckRecord: record) == nil)
    }

    @Test("Payload, timestamp, key and system-field mismatches are rejected")
    func tamperedEnvelope() throws {
        let original = change()
        let record = try original.makeCKRecord(zoneID: zoneID, recordType: recordType, assetThreshold: 1_000_000)
        record["updatedAt"] = NSNumber(value: 1)
        #expect(SyncChange(ckRecord: record) == nil)
        let valid = try original.makeCKRecord(zoneID: zoneID, recordType: recordType, assetThreshold: 1_000_000)
        let wrongKey = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: "wrong", zoneID: zoneID))
        for field in valid.allKeys() { wrongKey[field] = valid[field] }
        #expect(SyncChange(ckRecord: wrongKey) == nil)
        #expect(throws: CloudKitTransportError.self) {
            try original.makeCKRecord(zoneID: zoneID, recordType: recordType,
                assetThreshold: 1000, systemFields: wrongKey.syncSystemFields())
        }
        valid["payload"] = "not-base64" as NSString
        #expect(SyncChange(ckRecord: valid) == nil)
        let missingBusinessPayload = try change(payload: nil).makeCKRecord(
            zoneID: zoneID, recordType: recordType, assetThreshold: 1_000_000)
        #expect(SyncChange(ckRecord: missingBusinessPayload) == nil)
    }
}
