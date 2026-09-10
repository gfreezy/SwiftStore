import SwiftStoreCore

// Review before publishing. Published migrations must never be edited.
enum Migration_002 {
    static func up(_ db: SQLiteConnection) throws {
        try db.execute("DROP TRIGGER \"__swiftstore_update_comment\"")
        try db.execute("CREATE TRIGGER IF NOT EXISTS __swiftstore_update_comment\nAFTER UPDATE ON comment\nFOR EACH ROW\nWHEN NEW.updated_at = OLD.updated_at\nBEGIN\n    UPDATE comment SET updated_at = (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL)))\n    WHERE rowid = NEW.rowid;\nEND")
        try db.execute("DROP TRIGGER \"__swiftstore_update_post\"")
        try db.execute("CREATE TRIGGER IF NOT EXISTS __swiftstore_update_post\nAFTER UPDATE ON post\nFOR EACH ROW\nWHEN NEW.updated_at = OLD.updated_at\nBEGIN\n    UPDATE post SET updated_at = (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL)))\n    WHERE rowid = NEW.rowid;\nEND")
        try db.execute("DROP TRIGGER \"__swiftstore_update_user\"")
        try db.execute("CREATE TRIGGER IF NOT EXISTS __swiftstore_update_user\nAFTER UPDATE ON user\nFOR EACH ROW\nWHEN NEW.updated_at = OLD.updated_at\nBEGIN\n    UPDATE user SET updated_at = (COALESCE(unixepoch(\'subsec\'), CAST(strftime(\'%s\', \'now\') AS REAL) + CAST(substr(strftime(\'%f\', \'now\'), 3) AS REAL)))\n    WHERE rowid = NEW.rowid;\nEND")
        // Add data migration SQL here, or between the schema statements above.
    }
}
