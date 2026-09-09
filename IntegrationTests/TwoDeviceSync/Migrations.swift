import Foundation
import SwiftStoreCore

// Frozen schema and SQL for the persistent two-device integration fixture.
enum WorkerMigrations {
    static func all() throws -> [StoreMigration] {
        let target = try SchemaSnapshot.decode(Data(#"""
        {
            "tables": [
                {
                    "columns": [
                        {
                            "isNullable": false,
                            "isPrimaryKey": true,
                            "name": "id",
                            "type": "BLOB"
                        },
                        {
                            "defaultValue": "''",
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "title",
                            "type": "TEXT"
                        },
                        {
                            "defaultValue": "(COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL)))",
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "created_at",
                            "type": "REAL"
                        },
                        {
                            "defaultValue": "(COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL)))",
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "updated_at",
                            "type": "REAL"
                        }
                    ],
                    "foreignKeys": [],
                    "indexes": [],
                    "name": "sync_note",
                    "sql": "",
                    "triggers": [
                        {
                            "body": "    UPDATE sync_note SET updated_at = (COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL)))\n    WHERE rowid = NEW.rowid;",
                            "condition": "NEW.updated_at = OLD.updated_at",
                            "event": "UPDATE",
                            "name": "__swiftstore_update_sync_note",
                            "sql": "CREATE TRIGGER IF NOT EXISTS __swiftstore_update_sync_note\nAFTER UPDATE ON sync_note\nFOR EACH ROW\nWHEN NEW.updated_at = OLD.updated_at\nBEGIN\n        UPDATE sync_note SET updated_at = (COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL)))\n    WHERE rowid = NEW.rowid;\nEND",
                            "timing": "AFTER"
                        }
                    ]
                }
            ]
        }
        """#.utf8))
        return [StoreMigration(id: "001_initial", checksum: "adfdb22994dbca8140c3b6500da25c5b5c2478e6757bcc0e91f8c656b7a2e311",
            target: target, up: Migration_001.up)]
    }
}

// Review before publishing. Published migrations must never be edited.
private enum Migration_001 {
    static func up(_ db: SQLiteConnection) throws {
        try db.execute("CREATE TABLE sync_note (\n    id BLOB NOT NULL PRIMARY KEY,\n    title TEXT NOT NULL DEFAULT \'\',\n    created_at REAL NOT NULL DEFAULT (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL))),\n    updated_at REAL NOT NULL DEFAULT (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL)))\n)")
        try db.execute("CREATE TRIGGER IF NOT EXISTS __swiftstore_update_sync_note\nAFTER UPDATE ON sync_note\nFOR EACH ROW\nWHEN NEW.updated_at = OLD.updated_at\nBEGIN\n        UPDATE sync_note SET updated_at = (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL)))\n    WHERE rowid = NEW.rowid;\nEND")
        // Add data migration SQL here, or between the schema statements above.
    }
}
