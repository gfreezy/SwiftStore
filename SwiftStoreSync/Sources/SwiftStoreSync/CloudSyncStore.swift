import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker

public struct SyncState: Codable, Sendable, Equatable {
    /// Continuous confirmed prefix of the local append-only changelog.
    public var pushCursor: Int64
    public var accountID: String?
    public init(pushCursor: Int64 = 0, accountID: String? = nil) {
        self.pushCursor = pushCursor; self.accountID = accountID
    }
}

public struct SyncConfiguration: Sendable {
    /// Maximum number of changelog events read before coalescing within that batch.
    public var batchSize: Int
    public init(batchSize: Int = 200) { self.batchSize = batchSize }
}

public struct SyncResult: Sendable {
    public let pulledCount: Int
    public let pushedCount: Int
    public let conflictCount: Int
    public let state: SyncState
    public init(pulledCount: Int, pushedCount: Int, conflictCount: Int, state: SyncState) {
        self.pulledCount = pulledCount; self.pushedCount = pushedCount
        self.conflictCount = conflictCount; self.state = state
    }
}

/// The two supported implementations both talk to the same CloudKit private zone.
package enum CloudDriverKind: String, Codable, Sendable { case operations, engine }
package struct CloudCheckpoint: Sendable {
    package let driver: CloudDriverKind
    package let data: Data?
    package init(driver: CloudDriverKind, data: Data?) { self.driver = driver; self.data = data }
}
package struct CloudStoreState: Sendable {
    package let state: SyncState
    package let checkpoint: CloudCheckpoint
    package let didCreateZone: Bool
    package init(state: SyncState, checkpoint: CloudCheckpoint, didCreateZone: Bool) {
        self.state = state; self.checkpoint = checkpoint; self.didCreateZone = didCreateZone
    }
}
package struct CloudIdentity: Hashable, Codable, Sendable {
    package let entity: String
    package let key: Data
    package init(_ change: SyncChange) { entity = change.entityType; key = change.syncKey }
    package init(entity: String, key: Data) { self.entity = entity; self.key = key }
}
package struct CloudRecordVersion: Codable, Sendable {
    package let identity: CloudIdentity
    package let changeID: UUIDV7
    package let updatedMs: Int64
    package let deleted: Bool
    package let systemFields: Data
    package init(record: CloudRecord) throws {
        identity = CloudIdentity(record.change); changeID = record.change.id
        updatedMs = try SyncLogStorage.timestamp(record.change.updatedAt.timeIntervalSince1970)
        deleted = record.change.operation == .delete; systemFields = record.systemFields
    }
}
package struct CloudRecord: Sendable {
    package let change: SyncChange
    package let systemFields: Data
    package init(change: SyncChange, systemFields: Data) { self.change = change; self.systemFields = systemFields }
}
package struct CloudUploadItem: Sendable {
    package let change: SyncChange
    package let coveredSequences: [Int64]
    package let serverVersion: CloudRecordVersion?
    package init(change: SyncChange, coveredSequences: [Int64], serverVersion: CloudRecordVersion?) {
        self.change = change; self.coveredSequences = coveredSequences; self.serverVersion = serverVersion
    }
}
package struct CloudUploadBatch: Sendable {
    package let id: UUID
    package let afterSequence: Int64
    package let events: [ChangeLog]
    package let items: [CloudUploadItem]
    package init(afterSequence: Int64, events: [ChangeLog], items: [CloudUploadItem]) {
        id = UUID(); self.afterSequence = afterSequence; self.events = events; self.items = items
    }
}
package enum CloudUploadOutcome: Sendable { case committed, superseded }
package struct CloudUploadDecision: Sendable {
    package let changeID: UUIDV7
    package let outcome: CloudUploadOutcome
    /// nil is allowed only for an authoritative version already applied by this store.
    package let record: CloudRecord?
    package init(changeID: UUIDV7, outcome: CloudUploadOutcome, record: CloudRecord? = nil) {
        self.changeID = changeID; self.outcome = outcome; self.record = record
    }
}
package struct CloudCommitCounts: Sendable {
    package var pushed = 0
    package var conflicts = 0
    package var applied = 0
    package var batchComplete = false
    package init() {}
}

/// Internal writer boundary, not an application-pluggable synchronization backend.
/// Every call is fenced by a session; implementations execute short, non-awaiting DB work.
package protocol CloudSyncStore: Sendable {
    func bindCloudAccount(_ accountID: String, scope: String, driver: CloudDriverKind, session: UUID) async throws -> CloudStoreState
    func nextCloudBatch(limit: Int, session: UUID) async throws -> CloudUploadBatch?
    func commitCloudBatch(_ batch: CloudUploadBatch, decisions: [CloudUploadDecision], session: UUID) async throws -> CloudCommitCounts
    func applyCloudRecords(_ records: [CloudRecord], checkpoint: CloudCheckpoint?, session: UUID) async throws -> Int
    func saveCloudCheckpoint(_ checkpoint: CloudCheckpoint, session: UUID) async throws
    func markCloudZoneCreated(session: UUID) async throws
    func cloudSyncState(session: UUID) async throws -> SyncState
}
