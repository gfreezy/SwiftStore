import Foundation
import SwiftStoreCore

/// Small metadata rows in the business database. No second copy of queued payloads.
final class SyncStatePersistence {
    let connection: SQLiteConnection
    init(connection: SQLiteConnection) throws {
        self.connection = connection
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS __swiftstore_cloud_state (
                singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                database_id TEXT NOT NULL,
                scope TEXT, account_id TEXT, driver TEXT,
                checkpoint BLOB, zone_created INTEGER NOT NULL DEFAULT 0,
                push_seq INTEGER NOT NULL DEFAULT 0 CHECK(push_seq>=0),
                legacy_imported INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS __swiftstore_cloud_versions (
                entity_type TEXT NOT NULL, sync_key BLOB NOT NULL, version BLOB NOT NULL,
                PRIMARY KEY(entity_type,sync_key)
            );
            """)
        try connection.execute("INSERT OR IGNORE INTO __swiftstore_cloud_state(singleton,database_id) VALUES(1,?)",
            values: [.text(UUID().uuidString)])
    }

    func load() throws -> SyncState {
        let stmt = try connection.prepare("SELECT push_seq,account_id FROM __swiftstore_cloud_state WHERE singleton=1")
        guard try stmt.step() else { throw SyncError.invalidPayload("Missing CloudKit checkpoint row") }
        return SyncState(pushCursor: stmt.columnInt64(0), accountID: stmt.columnString(1))
    }

    func bind(account: String, scope: String, driver: CloudDriverKind) throws -> CloudStoreState {
        try connection.transaction {
            let stmt = try connection.prepare("SELECT account_id,scope,driver,checkpoint,zone_created FROM __swiftstore_cloud_state WHERE singleton=1")
            guard try stmt.step(), !account.isEmpty, !scope.isEmpty else { throw SyncError.invalidPayload("Invalid CloudKit scope") }
            if let old = stmt.columnString(0), old != account { throw SyncError.accountChanged }
            if let old = stmt.columnString(1), old != scope { throw SyncError.scopeChanged }
            let checkpoint = stmt.columnString(2) == driver.rawValue ? stmt.columnData(3) : nil
            let created = stmt.columnInt64(4) != 0
            try connection.execute("UPDATE __swiftstore_cloud_state SET account_id=?,scope=?,driver=?,checkpoint=? WHERE singleton=1",
                values: [.text(account), .text(scope), .text(driver.rawValue), checkpoint.map(SQLiteValue.blob) ?? .null])
            return CloudStoreState(state: try load(), checkpoint: CloudCheckpoint(driver: driver, data: checkpoint), didCreateZone: created)
        }
    }

    func saveCheckpoint(_ value: CloudCheckpoint) throws {
        let driver: String? = try connection.queryScalar("SELECT driver FROM __swiftstore_cloud_state WHERE singleton=1")
        guard driver == value.driver.rawValue else { throw SyncError.scopeChanged }
        try connection.execute("UPDATE __swiftstore_cloud_state SET checkpoint=? WHERE singleton=1",
            values: [value.data.map(SQLiteValue.blob) ?? .null])
    }

    func saveCursor(_ seq: Int64) throws {
        try connection.execute("UPDATE __swiftstore_cloud_state SET push_seq=? WHERE singleton=1 AND push_seq<=?",
            values: [.integer(seq), .integer(seq)])
    }

    func version(for identity: CloudIdentity) throws -> CloudRecordVersion? {
        let data: Data? = try connection.queryScalar("SELECT version FROM __swiftstore_cloud_versions WHERE entity_type=? AND sync_key=?",
            values: [.text(identity.entity), .blob(identity.key)])
        return try data.map { try PropertyListDecoder().decode(CloudRecordVersion.self, from: $0) }
    }

    func saveVersion(_ value: CloudRecordVersion) throws {
        if let old = try version(for: value.identity), old.updatedMs > value.updatedMs { return }
        try connection.execute("""
            INSERT INTO __swiftstore_cloud_versions(entity_type,sync_key,version) VALUES(?,?,?)
            ON CONFLICT(entity_type,sync_key) DO UPDATE SET version=excluded.version
            """, values: [.text(value.identity.entity), .blob(value.identity.key), .blob(try PropertyListEncoder().encode(value))])
    }
}
