import SwiftStoreCore

// Reviewed manual implementation of the generated rename placeholder.
enum Migration_002 {
    static func up(_ db: SQLiteConnection) throws {
        try db.execute("ALTER TABLE person RENAME COLUMN name TO display_name")
        try db.execute("UPDATE person SET display_name = trim(display_name)")
    }
}
