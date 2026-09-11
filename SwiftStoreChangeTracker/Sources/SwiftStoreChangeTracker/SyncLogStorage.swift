import Foundation
import SwiftStoreCore

/// Internal sync tables share the business database and never participate in business migrations.
package enum SyncLogStorage {
    package static func create(in db: SQLiteConnection) throws {
        _ = try db.transaction {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS __swiftstore_change_log (
                    id BLOB NOT NULL UNIQUE,
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    entity_type TEXT NOT NULL,
                    sync_key BLOB NOT NULL,
                    operation TEXT NOT NULL,
                    payload TEXT,
                    device_id BLOB NOT NULL,
                    logical_clock INTEGER NOT NULL,
                    schema_version INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS __swiftstore_log_key ON __swiftstore_change_log(entity_type, sync_key, seq);
                CREATE TRIGGER IF NOT EXISTS __swiftstore_log_no_update BEFORE UPDATE ON __swiftstore_change_log
                BEGIN SELECT RAISE(ABORT, 'The sync changelog is append-only'); END;
                CREATE TRIGGER IF NOT EXISTS __swiftstore_log_no_delete BEFORE DELETE ON __swiftstore_change_log
                BEGIN SELECT RAISE(ABORT, 'The sync changelog is append-only'); END;
                CREATE TRIGGER IF NOT EXISTS __swiftstore_log_no_replace BEFORE INSERT ON __swiftstore_change_log
                WHEN EXISTS (SELECT 1 FROM __swiftstore_change_log WHERE id = NEW.id OR seq = NEW.seq)
                BEGIN SELECT RAISE(ABORT, 'The sync changelog is append-only'); END;
                CREATE TABLE IF NOT EXISTS __swiftstore_sync_bootstrap (entity_type TEXT PRIMARY KEY);
                CREATE TABLE IF NOT EXISTS __swiftstore_record_versions (
                    entity_type TEXT NOT NULL, sync_key BLOB NOT NULL,
                    updated_ms INTEGER NOT NULL, deleted INTEGER NOT NULL,
                    PRIMARY KEY(entity_type, sync_key)
                );
                """)
        }
    }

    package static func append(_ event: ChangeLog, to db: SQLiteConnection) throws {
        let operation = String(decoding: try JSONEncoder().encode(event.operation), as: UTF8.self)
        try db.execute("""
            INSERT INTO __swiftstore_change_log
            (id,entity_type,sync_key,operation,payload,device_id,logical_clock,schema_version,created_at,updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?)
            """, values: [.blob(event.id.data), .text(event.entityType), .blob(event.syncKey), .text(operation),
                event.payload.map(SQLiteValue.text) ?? .null, .blob(event.deviceId.data), .integer(event.logicalClock),
                .integer(Int64(event.schemaVersion)), .real(event.createdAt.timeIntervalSince1970),
                .real(event.updatedAt.timeIntervalSince1970)])
    }

    package static func contains(_ id: UUIDV7, in db: SQLiteConnection) throws -> Bool {
        let count: Int64 = try db.queryScalar("SELECT COUNT(*) FROM __swiftstore_change_log WHERE id = ?", values: [.blob(id.data)]) ?? 0
        return count > 0
    }

    package static func timestamp(_ seconds: Double) throws -> Int64 {
        let ms = (seconds * 1000).rounded()
        guard ms.isFinite, abs(ms) <= 9_007_199_254_740_990 else {
            throw StoreError.invalidPayload("Sync timestamp is outside the supported millisecond range")
        }
        return Int64(ms)
    }

    package static func knownTime(entity: String, key: Data, in db: SQLiteConnection) throws -> Int64? {
        try db.queryScalar("SELECT updated_ms FROM __swiftstore_record_versions WHERE entity_type = ? AND sync_key = ?",
            values: [.text(entity), .blob(key)])
    }

    package static func remember(entity: String, key: Data, time: Int64, deleted: Bool, in db: SQLiteConnection) throws {
        try db.execute("""
            INSERT INTO __swiftstore_record_versions(entity_type,sync_key,updated_ms,deleted) VALUES(?,?,?,?)
            ON CONFLICT(entity_type,sync_key) DO UPDATE SET updated_ms=excluded.updated_ms, deleted=excluded.deleted
            WHERE excluded.updated_ms >= __swiftstore_record_versions.updated_ms
            """, values: [.text(entity), .blob(key), .integer(time), .integer(deleted ? 1 : 0)])
    }
}
