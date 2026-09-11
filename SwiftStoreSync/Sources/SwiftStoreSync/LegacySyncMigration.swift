import Foundation
import SwiftStoreCore
import SwiftStoreChangeTracker

/// One-time, read-only import of an older SwiftStore CloudKit installation.
/// Originals are retained; consistent SQLite backups are made before importing.
public struct LegacySyncMigration: Sendable {
    public let changeLogDatabase: URL
    public let cloudKitJournal: URL
    public let backupDirectory: URL
    public init(changeLogDatabase: URL, cloudKitJournal: URL, backupDirectory: URL) {
        self.changeLogDatabase = changeLogDatabase; self.cloudKitJournal = cloudKitJournal
        self.backupDirectory = backupDirectory
    }
}

private struct LegacyJournal: Decodable {
    struct Rejections: Decodable {
        struct Entry: Decodable { let change: SyncChange; let serverVersion: SyncChange? }
        let entries: [Entry]
    }
    let accountID: String?
    let namespace: String?
    let pendingPush: [String: SyncChange]?
    let queuedPush: [SyncChange]?
    let inbox: [SyncChange]?
    let conflicts: [SyncChange]?
    let committedVersions: [String: SyncChange]?
    let systemFields: [String: Data]?
    let rejections: Rejections?
    let didCreateZone: Bool?
}

package struct LegacySyncImport {
    let migration: LegacySyncMigration
    let scope: String
    let journalData: Data

    package init?(connection: SQLiteConnection, migration: LegacySyncMigration?, scope: String) throws {
        guard let migration else { return nil }
        if try connection.tableExists("__swiftstore_cloud_state") {
            let done: Int64 = try connection.queryScalar("SELECT legacy_imported FROM __swiftstore_cloud_state WHERE singleton=1") ?? 0
            if done != 0 { return nil }
        }
        let data = try Data(contentsOf: migration.cloudKitJournal)
        let journal = try PropertyListDecoder().decode(LegacyJournal.self, from: data)
        guard journal.namespace == scope, let account = journal.accountID, !account.isEmpty else {
            throw SyncError.invalidPayload("Legacy journal does not identify this CloudKit account and zone")
        }
        self.migration = migration; self.scope = scope; journalData = data
        let directory = migration.backupDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try connection.backup(to: directory.appendingPathComponent("business.sqlite").path)
        var options = SQLiteConnection.Options(); options.readonly = true; options.walMode = false
        let legacy = try SQLiteConnection(path: migration.changeLogDatabase.path, options: options)
        try legacy.backup(to: directory.appendingPathComponent("changelog.sqlite").path)
        try data.write(to: directory.appendingPathComponent("journal.plist"), options: .atomic)
    }

    package func run(connection: SQLiteConnection, receive: ([CloudRecord]) throws -> Void) throws {
        let done: Int64 = try connection.queryScalar("SELECT legacy_imported FROM __swiftstore_cloud_state WHERE singleton=1") ?? 0
        guard done == 0 else { return }
        let journal = try PropertyListDecoder().decode(LegacyJournal.self, from: journalData)
        var options = SQLiteConnection.Options(); options.readonly = true; options.walMode = false
        let legacy = try SQLiteConnection(path: migration.changeLogDatabase.path, options: options)
        try connection.transaction {
            if try connection.tableExists("__swiftstore_sync_tombstones") {
                let tombstones = try connection.prepare("SELECT key,deleted_at FROM __swiftstore_sync_tombstones")
                while try tombstones.step() {
                    guard let combined = tombstones.columnString(0), let split = combined.lastIndex(of: ":"),
                          let key = Data(base64Encoded: String(combined[combined.index(after: split)...])) else {
                        throw SyncError.invalidPayload("Invalid legacy tombstone identity")
                    }
                    try SyncLogStorage.remember(entity: String(combined[..<split]), key: key,
                        time: SyncLogStorage.timestamp(tombstones.columnDouble(1)), deleted: true, in: connection)
                }
            }
            func append(_ event: ChangeLog) throws {
                if try !SyncLogStorage.contains(event.id, in: connection) { try SyncLogStorage.append(event, to: connection) }
                try SyncLogStorage.remember(entity: event.entityType, key: event.syncKey,
                    time: SyncLogStorage.timestamp(SyncChange(from: event).updatedAt.timeIntervalSince1970),
                    deleted: event.operation == .delete, in: connection)
            }
            let stmt = try legacy.prepare("""
                SELECT id,0 AS seq,entity_type,sync_key,operation,payload,device_id,logical_clock,schema_version,created_at,updated_at
                FROM change_log ORDER BY logical_clock,created_at,rowid
                """)
            while try stmt.step() {
                let event = try ChangeLog.sqliteDecode(from: stmt)
                try append(event)
            }
            let pending = Array((journal.pendingPush ?? [:]).values) + (journal.queuedPush ?? [])
                + (journal.conflicts ?? []) + (journal.rejections?.entries.map(\.change) ?? [])
            for event in pending {
                if try !SyncLogStorage.contains(event.id, in: connection) {
                    try append(ChangeLog(id: event.id, entityType: event.entityType, syncKey: event.syncKey,
                        operation: event.operation, payload: event.payload, deviceId: event.deviceId, logicalClock: event.logicalClock,
                        schemaVersion: event.schemaVersion, createdAt: event.createdAt, updatedAt: event.createdAt))
                }
            }
            var downloaded = (journal.inbox ?? []) + (journal.rejections?.entries.compactMap(\.serverVersion) ?? [])
            downloaded += Array((journal.committedVersions ?? [:]).values)
            // No legacy cursor is trusted: the first native fetch replays the zone.
            try receive(downloaded.map { CloudRecord(change: $0, systemFields: Data()) })
            try connection.execute("UPDATE __swiftstore_cloud_state SET account_id=?,scope=?,zone_created=?,legacy_imported=1 WHERE singleton=1",
                values: [.text(journal.accountID!), .text(scope), .integer(journal.didCreateZone == true ? 1 : 0)])
        }
    }
}
