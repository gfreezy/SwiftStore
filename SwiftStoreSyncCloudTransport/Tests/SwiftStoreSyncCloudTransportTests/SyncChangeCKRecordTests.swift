import Testing
import Foundation
import CloudKit
@testable import SwiftStoreSyncCloudTransport
import SwiftStoreCore
import SwiftStoreChangeTracker
import SwiftStoreSync

@Suite("SyncChange <-> CKRecord mapping")
struct SyncChangeCKRecordTests {
    let zoneID = CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName)
    let recordType: CKRecord.RecordType = "SwiftStoreSyncChange"

    @Test("insert with small payload round-trips")
    func insertRoundTrip() throws {
        let original = SyncChange(
            id: UUIDV7(),
            entityType: "user",
            syncKey: Data([0x01, 0x02, 0x03]),
            operation: .insert,
            payload: #"{"name":"Alice"}"#,
            deviceId: UUIDV7(),
            logicalClock: 42,
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let record = try original.makeCKRecord(
            zoneID: zoneID, recordType: recordType, assetThreshold: 1_000_000)
        let decoded = try #require(SyncChange(ckRecord: record))

        #expect(decoded.id == original.id)
        #expect(decoded.entityType == original.entityType)
        #expect(decoded.syncKey == original.syncKey)
        #expect(decoded.operation == original.operation)
        #expect(decoded.payload == original.payload)
        #expect(decoded.deviceId == original.deviceId)
        #expect(decoded.logicalClock == original.logicalClock)
        #expect(decoded.schemaVersion == original.schemaVersion)
        #expect(decoded.createdAt.timeIntervalSince1970 == original.createdAt.timeIntervalSince1970)
    }

    @Test("record name round-trips entityType and syncKey")
    func recordNameRoundTrip() {
        let entityType = "user_profile"
        let syncKey = Data([0x01, 0x02, 0x03, 0xFF, 0xAB])
        let name = SyncChange.recordName(entityType: entityType, syncKey: syncKey)
        let parsed = try? #require(SyncChange.parseRecordName(name))
        #expect(parsed?.entityType == entityType)
        #expect(parsed?.syncKey == syncKey)
    }

    @Test("malformed record name returns nil")
    func malformedRecordName() {
        #expect(SyncChange.parseRecordName("no-colon-here") == nil)
        #expect(SyncChange.parseRecordName("user:not-hex-!") == nil)
    }

    @Test("synthetic delete from CKRecord.ID")
    func syntheticDelete() {
        let syncKey = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let name = SyncChange.recordName(entityType: "user", syncKey: syncKey)
        let recordID = CKRecord.ID(recordName: name, zoneID: zoneID)
        let change = try? #require(SyncChange.syntheticDelete(from: recordID))
        #expect(change?.operation == .delete)
        #expect(change?.entityType == "user")
        #expect(change?.syncKey == syncKey)
        #expect(change?.payload == nil)
    }

    @Test("insert CKRecord uses (entityType, syncKey) as recordName")
    func recordNameFromInsert() throws {
        let syncKey = Data([0xAA, 0xBB])
        let change = SyncChange(
            id: UUIDV7(),
            entityType: "user",
            syncKey: syncKey,
            operation: .insert,
            payload: "{}",
            deviceId: UUIDV7(),
            logicalClock: 1,
            schemaVersion: 1,
            createdAt: Date()
        )
        let record = try change.makeCKRecord(
            zoneID: zoneID, recordType: recordType, assetThreshold: 1_000_000)
        let expected = SyncChange.recordName(entityType: "user", syncKey: syncKey)
        #expect(record.recordID.recordName == expected)
    }

    @Test("large payload is written as CKAsset and round-trips")
    func largePayloadAsset() throws {
        let payload = String(repeating: "x", count: 1_000)  // 1 KB
        let original = SyncChange(
            id: UUIDV7(),
            entityType: "user",
            syncKey: Data([0x01]),
            operation: .update,
            payload: payload,
            deviceId: UUIDV7(),
            logicalClock: 1,
            schemaVersion: 1,
            createdAt: Date()
        )

        let record = try original.makeCKRecord(
            zoneID: zoneID, recordType: recordType, assetThreshold: 500)
        #expect(record[SyncChange.RecordField.payloadAsset] as? CKAsset != nil)
        #expect(record[SyncChange.RecordField.payload] as? String == nil)

        let decoded = try #require(SyncChange(ckRecord: record))
        #expect(decoded.payload == payload)
    }

    @Test("malformed record returns nil")
    func malformedRecord() {
        let recordID = CKRecord.ID(recordName: "not-a-uuid", zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        #expect(SyncChange(ckRecord: record) == nil)
    }
}
