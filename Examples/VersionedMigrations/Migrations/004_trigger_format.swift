import SwiftStoreCore

// Review before publishing. Published migrations must never be edited.
enum Migration_004 {
    static func up(_ db: SQLiteConnection) throws {
        try db.execute("DROP TRIGGER \"__swiftstore_update_person\"")
        try db.execute("CREATE TRIGGER IF NOT EXISTS __swiftstore_update_person\nAFTER UPDATE ON person\nFOR EACH ROW\nWHEN NEW.updated_at = OLD.updated_at\nBEGIN\n    UPDATE person SET updated_at = (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL)))\n    WHERE rowid = NEW.rowid;\nEND")
        // Add data migration SQL here, or between the schema statements above.
    }
}
