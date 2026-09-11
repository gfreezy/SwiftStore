import Foundation
import CloudKit
import SwiftStoreCore
import SwiftStoreSync

/// One immutable changelog window. Both native drivers use exactly this arbitration.
/// Only record IDs enter CKSyncEngine's queue; payloads remain replayable from SQLite.
struct CloudKitUploadWork {
    let batch: CloudUploadBatch
    private let settings: CloudKitOperationsSettings
    private var items: [CKRecord.ID: CloudUploadItem] = [:]
    private(set) var records: [CKRecord.ID: CKRecord] = [:]
    private(set) var decisions: [UUIDV7: CloudUploadDecision] = [:]
    private(set) var assets: Set<URL> = []

    init(batch: CloudUploadBatch, settings: CloudKitOperationsSettings) throws {
        self.batch = batch; self.settings = settings
        for item in batch.items {
            let id = CKRecord.ID(recordName: SyncChange.recordName(entityType: item.change.entityType, syncKey: item.change.syncKey), zoneID: settings.zoneID)
            items[id] = item
            let ms = (item.change.updatedAt.timeIntervalSince1970 * 1000).rounded()
            if let server = item.serverVersion, Double(server.updatedMs) >= ms {
                decisions[item.change.id] = CloudUploadDecision(changeID: item.change.id,
                    outcome: server.changeID == item.change.id ? .committed : .superseded)
            } else {
                try prepare(item, fields: item.serverVersion.flatMap { $0.systemFields.isEmpty ? nil : $0.systemFields })
            }
        }
    }

    var isComplete: Bool { records.isEmpty }
    /// Returns only errors that need retry or repair. Successful sibling records
    /// remain confirmed and can advance the continuous prefix in the same call.
    mutating func receive(_ results: [CKRecord.ID: Result<CKRecord, Error>]) throws -> Error? {
        var failure: Error?
        for (id, result) in results {
            guard let item = items[id], records[id] != nil else { continue }
            switch result {
            case .success(let saved):
                let remote = try Self.decode(saved, settings: settings)
                guard saved.recordID == id, remote.change.id == item.change.id else {
                    throw CloudKitTransportError.encodingFailed("Mismatched CloudKit commit receipt")
                }
                decisions[item.change.id] = CloudUploadDecision(changeID: item.change.id, outcome: .committed, record: remote)
                records.removeValue(forKey: id)
            case .failure(let error):
                guard let ck = error as? CKError else { failure = error; continue }
                switch ck.code {
                case .serverRecordChanged:
                    guard let server = ck.serverRecord, server.recordID == id else {
                        throw CloudKitTransportError.encodingFailed("CloudKit conflict is missing its authoritative record")
                    }
                    let remote = try Self.decode(server, settings: settings)
                    if item.change.isNewer(than: remote.change) {
                        try prepare(item, fields: remote.systemFields)
                    } else {
                        decisions[item.change.id] = CloudUploadDecision(changeID: item.change.id,
                            outcome: remote.change.id == item.change.id ? .committed : .superseded, record: remote)
                        records.removeValue(forKey: id)
                    }
                case .zoneNotFound:
                    failure = CloudKitTransportError.zoneDeleted
                case .unknownItem:
                    // A physical deletion has no business timestamp. Do not resurrect it.
                    failure = CloudKitTransportError.encodingFailed("A CloudKit record was physically removed; reconcile this zone before retrying")
                default: failure = error
                }
            }
        }
        return failure
    }

    mutating private func prepare(_ item: CloudUploadItem, fields: Data?) throws {
        let record = try item.change.makeCKRecord(zoneID: settings.zoneID, recordType: settings.recordType,
            assetThreshold: settings.assetThreshold, systemFields: fields)
        records[record.recordID] = record
        if let url = (record[SyncChange.RecordField.payloadAsset] as? CKAsset)?.fileURL { assets.insert(url) }
    }

    func cleanAssets() { for url in assets { try? FileManager.default.removeItem(at: url) } }

    static func decode(_ record: CKRecord, settings: CloudKitOperationsSettings) throws -> CloudRecord {
        guard record.recordID.zoneID == settings.zoneID, record.recordType == settings.recordType,
              let change = SyncChange(ckRecord: record) else {
            throw CloudKitTransportError.encodingFailed("Invalid CloudKit record identity or payload")
        }
        return CloudRecord(change: change, systemFields: record.syncSystemFields())
    }
}

func cloudRetryDelay(_ error: Error, attempt: Int = 0) -> Double? {
    guard let ck = error as? CKError else { return nil }
    switch ck.code {
    case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited:
        return max(ck.retryAfterSeconds ?? 0, min(60, pow(2, Double(min(attempt, 6)))))
    default: return nil
    }
}
