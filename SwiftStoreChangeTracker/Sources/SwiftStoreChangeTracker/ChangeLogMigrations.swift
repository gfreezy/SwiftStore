import Foundation
import SwiftStoreCore

/// Frozen history for the separate changelog database. Add a new step when its schema changes.
/// Keep historical SQL and snapshots independent of the live ChangeLog entity.
enum ChangeLogMigrations {
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
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "entity_type",
                            "type": "TEXT"
                        },
                        {
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "sync_key",
                            "type": "BLOB"
                        },
                        {
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "operation",
                            "type": "TEXT"
                        },
                        {
                            "isNullable": true,
                            "isPrimaryKey": false,
                            "name": "payload",
                            "type": "TEXT"
                        },
                        {
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "device_id",
                            "type": "BLOB"
                        },
                        {
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "logical_clock",
                            "type": "INTEGER"
                        },
                        {
                            "isNullable": false,
                            "isPrimaryKey": false,
                            "name": "schema_version",
                            "type": "INTEGER"
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
                    "name": "change_log",
                    "sql": "",
                    "triggers": []
                }
            ]
        }
        """#.utf8))
        return [StoreMigration(id: "001_initial", checksum: "18ed5a5084b4aa763083849136f8927cc2e00fb4dc9b96b50965a55b92037842",
            target: target, up: Migration_001.up)]
    }
}

// Review before publishing. Published migrations must never be edited.
private enum Migration_001 {
    static func up(_ db: SQLiteConnection) throws {
        try db.execute("CREATE TABLE change_log (\n    id BLOB NOT NULL PRIMARY KEY,\n    entity_type TEXT NOT NULL,\n    sync_key BLOB NOT NULL,\n    operation TEXT NOT NULL,\n    payload TEXT,\n    device_id BLOB NOT NULL,\n    logical_clock INTEGER NOT NULL,\n    schema_version INTEGER NOT NULL,\n    created_at REAL NOT NULL DEFAULT (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL))),\n    updated_at REAL NOT NULL DEFAULT (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL)))\n)")
        // Add data migration SQL here, or between the schema statements above.
    }
}
