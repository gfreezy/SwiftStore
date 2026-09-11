import Foundation
import CloudKit

/// Static configuration for a CloudKit synchronization.
public struct CloudKitSyncConfiguration: Sendable {
    /// The CloudKit container to sync with.
    public let containerIdentifier: String
    package var container: CKContainer { CKContainer(identifier: containerIdentifier) }
    /// Name of the CloudKit record zone used to hold sync changes.
    /// Defaults to `"SwiftStoreSyncChanges"`.
    public let zoneName: String
    /// CloudKit record type for sync change records.
    /// Defaults to `"SwiftStoreSyncChange"`.
    public let recordType: CKRecord.RecordType
    /// Size threshold (in Base64 UTF-8 bytes) above which the complete opaque payload is stored
    /// as a `CKAsset` rather than inline. Defaults to 700_000 (safely under
    /// CloudKit's 1 MB per-record limit).
    public let assetThreshold: Int
    /// Required clock accuracy in milliseconds for direct CloudKit use.
    /// Network failure permits sync; a measured excessive offset still blocks it.
    public let ntpToleranceMs: Int64
    /// Enable CKSyncEngine scheduling on iOS 17+, or the Operations scheduler on iOS 16.
    /// iOS 16 background pushes must be forwarded via handleRemoteNotification.
    public let automaticallySync: Bool
    /// Identifier of the database subscription used for push notifications.
    public let subscriptionID: String

    public init(
        containerIdentifier: String,
        zoneName: String = "SwiftStoreSyncChanges",
        recordType: CKRecord.RecordType = "SwiftStoreSyncChange",
        assetThreshold: Int = 700_000,
        subscriptionID: String = "swiftstore-sync-subscription",
        automaticallySync: Bool = true,
        ntpToleranceMs: Int64 = 5000
    ) {
        self.ntpToleranceMs = ntpToleranceMs
        self.automaticallySync = automaticallySync
        self.containerIdentifier = containerIdentifier
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
