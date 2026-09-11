import Foundation
import CloudKit
import SwiftStoreSync

struct CloudKitOperationsSettings: Sendable {
    var zoneID: CKRecordZone.ID
    var recordType: String
    var namespace: String
    var assetThreshold = 700_000
    var toleranceMs: Int64 = 5000
    var automaticallySync = true

    init(zoneID: CKRecordZone.ID, recordType: String, namespace: String) {
        self.zoneID = zoneID
        self.recordType = recordType
        self.namespace = namespace
    }

    init(_ config: CloudKitSyncConfiguration) {
        zoneID = config.zoneID
        recordType = config.recordType
        namespace = [config.containerIdentifier, config.zoneName, config.recordType].joined(separator: "/")
        assetThreshold = config.assetThreshold
        toleranceMs = config.ntpToleranceMs
        automaticallySync = config.automaticallySync
    }
}

struct CloudKitChangesPage: Sendable {
    var records: [CKRecord]
    var hasPhysicalDeletions: Bool = false
    var token: Data
    var moreComing: Bool
}

/// Network boundary, independently testable without an iCloud account.
protocol CloudKitOperationsClient: Sendable {
    func accountID() async throws -> String
    func prepareZone(create: Bool) async throws
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>]
    func fetch(since token: Data?) async throws -> CloudKitChangesPage
}

struct SystemCloudKitOperationsClient: CloudKitOperationsClient {
    let config: CloudKitSyncConfiguration

    func accountID() async throws -> String {
        let status = try await config.container.accountStatus()
        guard status == .available else {
            throw CloudKitTransportError.notSignedIn("CKAccountStatus: \(status)")
        }
        return try await config.container.userRecordID().recordName
    }

    func prepareZone(create: Bool) async throws {
        let db = config.container.privateCloudDatabase
        if create {
            _ = try await db.save(CKRecordZone(zoneID: config.zoneID))
        } else {
            let results = try await db.recordZones(for: [config.zoneID])
            guard let result = results[config.zoneID] else { throw CloudKitTransportError.zoneDeleted }
            do { _ = try result.get() }
            catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
                throw CloudKitTransportError.zoneDeleted
            }
        }
        let subscription = CKDatabaseSubscription(subscriptionID: config.subscriptionID)
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        _ = try await db.save(subscription)
    }

    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        try await config.container.privateCloudDatabase.modifyRecords(
            saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false).saveResults
    }

    func fetch(since token: Data?) async throws -> CloudKitChangesPage {
        let cursor = try token.map {
            guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) else {
                throw CloudKitTransportError.stateCorrupt("Invalid zone change token")
            }
            return decoded
        }
        let page = try await config.container.privateCloudDatabase.recordZoneChanges(
            inZoneWith: config.zoneID, since: cursor, resultsLimit: 200)
        // Decode/retain every record before advancing its cursor. Individual
        // failures abort the page so none can be skipped on the next fetch.
        let records = try page.modificationResultsByID.values.map { try $0.get().record }
        return CloudKitChangesPage(records: records,
            hasPhysicalDeletions: page.deletions.contains { $0.recordType == config.recordType },
            token: try NSKeyedArchiver.archivedData(withRootObject: page.changeToken, requiringSecureCoding: true),
            moreComing: page.moreComing)
    }
}
