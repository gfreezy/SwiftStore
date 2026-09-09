import SwiftStoreCore

// Review before publishing. Published migrations must never be edited.
enum Migration_001 {
    static func up(_ db: SQLiteConnection) throws {
        try db.execute("CREATE TABLE person (\n    id BLOB NOT NULL PRIMARY KEY,\n    name TEXT,\n    created_at REAL NOT NULL DEFAULT (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL))),\n    updated_at REAL NOT NULL DEFAULT (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL)))\n)")
        // Add data migration SQL here, or between the schema statements above.
    }
}
