import Foundation
import CloudKit

/// Static configuration for a `CloudKitSyncTransport`.
public struct CloudKitTransportConfig: Sendable {
    /// The CloudKit container to sync with.
    public let container: CKContainer
    /// Name of the CloudKit record zone used to hold sync changes.
    /// Defaults to `"SwiftStoreSyncChanges"`.
    public let zoneName: String
    /// CloudKit record type for sync change records.
    /// Defaults to `"SwiftStoreSyncChange"`.
    public let recordType: CKRecord.RecordType
    /// Size threshold (in UTF-8 bytes) above which `payload` strings are stored
    /// as a `CKAsset` rather than inline. Defaults to 700_000 (safely under
    /// CloudKit's 1 MB per-record limit).
    public let assetThreshold: Int
    /// Identifier of the `CKDatabaseSubscription` used for push notifications.
    /// Defaults to `"swiftstore-sync-subscription"`.
    public let subscriptionID: String

    public init(
        container: CKContainer,
        zoneName: String = "SwiftStoreSyncChanges",
        recordType: CKRecord.RecordType = "SwiftStoreSyncChange",
        assetThreshold: Int = 700_000,
        subscriptionID: String = "swiftstore-sync-subscription"
    ) {
        self.container = container
        self.zoneName = zoneName
        self.recordType = recordType
        self.assetThreshold = assetThreshold
        self.subscriptionID = subscriptionID
    }

    /// The CKRecordZone.ID used for sync records (in the current user's private DB).
    public var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }
}
