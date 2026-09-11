import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker

/// Synchronous database half of CloudKit sync. Owned by the same actor as the business writer.
/// Drivers await this actor, never hold its SQLite connection across network operations.
package final class SyncManager {
    private let connection: SQLiteConnection
    private let tracker: ChangeTracker
    private let reader: ChangeTrackerReader
    private let persistence: SyncStatePersistence
    private let registry: EntityApplierRegistry
    private let schemaVersion: Int
    private let legacyImport: LegacySyncImport?
    private var activeBatch: CloudUploadBatch?
    private var decisions: [UUIDV7: CloudUploadDecision] = [:]

    package init(connection: SQLiteConnection, deviceID: UUIDV7, entities: [any EntityProtocol.Type],
                 schemaVersion: Int, migration: LegacySyncMigration? = nil, scope: String = "", now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
        legacyImport = try LegacySyncImport(connection: connection, migration: migration, scope: scope)
        self.connection = connection
        self.schemaVersion = schemaVersion
        tracker = try ChangeTracker(connection: connection, deviceId: deviceID, registeredEntities: entities,
            tickClock: now, schemaVersion: schemaVersion)
        reader = ChangeTrackerReader(connection: connection)
        persistence = try SyncStatePersistence(connection: connection)
        registry = EntityApplierRegistry(entityTypes: entities)
    }

    package func startTracking() throws {
        if let legacyImport { try legacyImport.run(connection: connection) { _ = try receive($0, checkpoint: nil) } }
        try tracker.captureExistingRows { entity, key, time in
            guard let known = try persistence.version(for: CloudIdentity(entity: entity, key: key)) else { return false }
            return known.updatedMs == time && !known.deleted
        }
        try tracker.start()
    }
    package func latestSequence() throws -> Int64 { try reader.latestSequence() }
    package func state() throws -> SyncState { try persistence.load() }
    package func abandonBatch() { activeBatch = nil; decisions = [:] }

    package func bind(accountID: String, scope: String, driver: CloudDriverKind) throws -> CloudStoreState {
        try persistence.bind(account: accountID, scope: scope, driver: driver)
    }

    package func nextBatch(limit: Int) throws -> CloudUploadBatch? {
        if let activeBatch { return activeBatch }
        guard (1...200).contains(limit) else { throw SyncError.invalidPayload("CloudKit batch size must be between 1 and 200") }
        let cursor = try state().pushCursor
        let candidates = try reader.changes(after: cursor, limit: limit)
        var events: [ChangeLog] = []
        var latest: [CloudIdentity: SyncChange] = [:]
        var covered: [CloudIdentity: [Int64]] = [:]
        var order: [CloudIdentity] = []
        for event in candidates {
            let change = SyncChange(from: event)
            do { try validate(change) }
            catch {
                if events.isEmpty { throw error }
                break // Confirm the valid prefix before reporting this blocked event.
            }
            let identity = CloudIdentity(change)
            // Imported histories may predate monotonic timestamps. Split the batch
            // before an inversion instead of coalescing away the newer event.
            if let previous = latest[identity], !change.isNewer(than: previous) { break }
            if latest[identity] == nil { order.append(identity) }
            latest[identity] = change
            covered[identity, default: []].append(event.seq)
            events.append(event)
        }
        guard !events.isEmpty else { return nil }
        let items = try order.map {
            CloudUploadItem(change: latest[$0]!, coveredSequences: covered[$0]!, serverVersion: try persistence.version(for: $0))
        }
        let batch = CloudUploadBatch(afterSequence: cursor, events: events, items: items)
        activeBatch = batch
        decisions = [:]
        return batch
    }

    package func commit(_ batch: CloudUploadBatch, incoming: [CloudUploadDecision]) throws -> CloudCommitCounts {
        guard activeBatch?.id == batch.id else { throw CancellationError() }
        let items = Dictionary(uniqueKeysWithValues: batch.items.map { ($0.change.id, $0) })
        var updated = decisions
        for decision in incoming {
            guard let item = items[decision.changeID] else { throw SyncError.invalidPayload("Receipt does not belong to this upload batch") }
            if let record = decision.record {
                try validate(record.change)
                guard CloudIdentity(record.change) == CloudIdentity(item.change) else { throw SyncError.invalidPayload("Receipt key mismatch") }
                let expected = try SyncLogStorage.timestamp(item.change.updatedAt.timeIntervalSince1970)
                let actual = try SyncLogStorage.timestamp(record.change.updatedAt.timeIntervalSince1970)
                guard actual >= expected else { throw SyncError.invalidPayload("Receipt contains an older server version") }
                if decision.outcome == .committed, record.change.id != item.change.id {
                    throw SyncError.invalidPayload("Commit receipt change ID mismatch")
                }
            } else {
                guard let known = try persistence.version(for: CloudIdentity(item.change)),
                      known.updatedMs >= (try SyncLogStorage.timestamp(item.change.updatedAt.timeIntervalSince1970)),
                      decision.outcome == .superseded || known.changeID == item.change.id else {
                    throw SyncError.invalidPayload("Missing authoritative upload result")
                }
            }
            if updated[decision.changeID] == nil { updated[decision.changeID] = decision }
        }
        var counts = CloudCommitCounts()
        try connection.withWriteSource(.remote) {
            try connection.transaction {
                for (id, decision) in updated where decisions[id] == nil {
                    if let record = decision.record { counts.applied += try apply(record) }
                    if decision.outcome == .committed { counts.pushed += 1 } else { counts.conflicts += 1 }
                }
                let finished = Set(batch.items.filter { updated[$0.change.id] != nil }.flatMap(\.coveredSequences))
                var cursor = try state().pushCursor
                for event in batch.events where event.seq > cursor {
                    guard finished.contains(event.seq) else { break }
                    cursor = event.seq
                }
                try persistence.saveCursor(cursor)
            }
        }
        decisions = updated
        if try state().pushCursor >= (batch.events.last?.seq ?? 0) { counts.batchComplete = true; abandonBatch() }
        return counts
    }

    package func receive(_ records: [CloudRecord], checkpoint: CloudCheckpoint?) throws -> Int {
        // Validate the whole page before applying any of it. Future schemas and bad
        // payloads never disappear behind an advanced download checkpoint.
        for record in records { try validate(record.change) }
        return try connection.withWriteSource(.remote) {
            try connection.transaction {
                var applied = 0
                for record in records { applied += try apply(record) }
                if let checkpoint { try persistence.saveCheckpoint(checkpoint) }
                return applied
            }
        }
    }

    package func saveCheckpoint(_ value: CloudCheckpoint) throws { try persistence.saveCheckpoint(value) }
    package func markZoneCreated() throws {
        try connection.execute("UPDATE __swiftstore_cloud_state SET zone_created=1 WHERE singleton=1")
    }

    private func validate(_ change: SyncChange) throws {
        guard change.schemaVersion > 0, change.schemaVersion <= schemaVersion else {
            throw SyncError.invalidPayload("Unsupported schema version \(change.schemaVersion); update the app before continuing sync")
        }
        _ = try SyncLogStorage.timestamp(change.updatedAt.timeIntervalSince1970)
        if change.operation != .delete {
            struct Timestamp: Decodable { let updatedAt: Date }
            guard let payload = change.payload else { throw SyncError.invalidPayload("Missing record payload") }
            _ = try JSONDecoder().decode(Timestamp.self, from: Data(payload.utf8))
        } else if change.payload != nil { throw SyncError.invalidPayload("Deletion must not contain a live payload") }
        try registry.validate(change)
    }

    private func apply(_ record: CloudRecord) throws -> Int {
        let change = record.change
        let version = try CloudRecordVersion(record: record)
        if let previous = try persistence.version(for: version.identity), previous.updatedMs > version.updatedMs { return 0 }
        let row = try registry.currentChange(for: change, in: connection)
        let rowTime = try row.map { try SyncLogStorage.timestamp($0.updatedAt.timeIntervalSince1970) }
        let remembered = try SyncLogStorage.knownTime(entity: change.entityType, key: change.syncKey, in: connection)
        let localTime = max(rowTime ?? Int64.min, remembered ?? Int64.min)
        var applied = 0
        if version.updatedMs >= localTime {
            let unchanged = row.map { sameContent($0, change) } ?? (change.operation == .delete)
            if !unchanged {
                // Preserve equal-time authoritative values despite historical automatic
                // timestamp triggers. Drop/restore only this trigger inside this transaction.
                let name = "__swiftstore_update_" + change.entityType
                let trigger: String? = rowTime == version.updatedMs
                    ? try connection.queryScalar("SELECT sql FROM sqlite_master WHERE type='trigger' AND name=?", values: [.text(name)]) : nil
                if trigger != nil { try connection.execute("DROP TRIGGER \"\(name.replacingOccurrences(of: "\"", with: "\"\""))\"") }
                try registry.apply(change: change, to: connection)
                if let trigger { try connection.execute(trigger) }
                applied = 1
            }
            try SyncLogStorage.remember(entity: change.entityType, key: change.syncKey,
                time: version.updatedMs, deleted: version.deleted, in: connection)
        }
        try persistence.saveVersion(version)
        return applied
    }

    private func sameContent(_ lhs: SyncChange, _ rhs: SyncChange) -> Bool {
        if lhs.operation == .delete || rhs.operation == .delete { return lhs.operation == rhs.operation }
        guard let a = lhs.payload, let b = rhs.payload,
              let left = try? JSONSerialization.jsonObject(with: Data(a.utf8)) as? NSDictionary,
              let right = try? JSONSerialization.jsonObject(with: Data(b.utf8)) as? NSDictionary else { return false }
        return left.isEqual(right)
    }
}
