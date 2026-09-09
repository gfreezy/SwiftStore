import Foundation
import Testing
@testable import SwiftStoreCore

@Embedded
struct SearchDetails {
    var body: String?
    var ignored: String = ""
}

@Entity(tableName: "search_article")
struct SearchArticle {
    #FullTextIndex<Self>(\.title, \.details.body)
    var id: UUIDV7 = UUIDV7()
    var title: String
    var details: SearchDetails
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Entity(tableName: "search_membership")
struct SearchMembership {
    #SyncKey<Self>(\.team, \.member)
    #FullTextIndex<Self>(\.text)
    #FullTextIndex<Self>(\.text, name: "membership_substrings", tokenizer: .trigram)
    var team: String
    var member: String
    var text: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Suite("Local mapped FTS5")
struct FullTextTests {
    private enum Failure: Error { case rollback }

    private func setup(path: String = ":memory:") throws -> SQLiteConnection {
        let db = try SQLiteConnection(path: path)
        let snapshot = SchemaSnapshot(entities: [SearchArticle.self])
        try snapshot.validate()
        for sql in snapshot.creationStatements { try db.execute(sql) }
        try snapshot.verify(on: db)
        return db
    }

    private func ids(_ db: SQLiteConnection, _ term: String) throws -> [UUIDV7] {
        try SearchArticle.search(term).all(db).map(\.id)
    }

    private func mappingID(_ db: SQLiteConnection, _ id: UUIDV7) throws -> Int64 {
        try #require(try db.queryScalar("SELECT fts_id FROM __swiftstore_fts_search_article_map WHERE id = ?",
            values: [.blob(id.data)], type: Int64.self))
    }

    private func integrity(_ db: SQLiteConnection) throws {
        try db.execute("INSERT INTO search_article_fts(search_article_fts, rank) VALUES ('integrity-check', 1)")
    }

    @Test("UUID schema and JSON columns stay unchanged; raw and Entity writes maintain the index")
    func lifecycle() throws {
        let db = try setup()
        var article = SearchArticle(title: "Swift guide", details: SearchDetails(body: "database indexing"))
        try article.insert(db)
        let mapping = try mappingID(db, article.id)
        #expect(try ids(db, "database") == [article.id])
        #expect(try ids(db, "Swift") == [article.id])
        #expect(try SearchArticle.matching("details__body: index*").count(db) == 1)
        #expect(try SearchArticle.search("database").filter(\.title == "other").count(db) == 0)
        #expect(try db.queryScalar("SELECT type FROM pragma_table_info('search_article') WHERE pk = 1", type: String.self) == "BLOB")
        #expect(try db.queryScalar("SELECT count(*) FROM pragma_table_info('search_article')", type: Int.self) == 5)

        article.details.body = "transaction rollback"
        try article.update(db)
        #expect(try ids(db, "database").isEmpty)
        #expect(try ids(db, "rollback") == [article.id])
        #expect(try mappingID(db, article.id) == mapping)

        // The timestamp trigger performs a nested UPDATE; it must not index the same terms twice.
        try db.execute("UPDATE search_article SET title = 'Updated title'")
        try db.execute("UPDATE search_article SET details = json_set(details, '$.ignored', 'elsewhere')")
        try db.execute("UPDATE search_article SET updated_at = 1")
        #expect(try ids(db, "Updated") == [article.id])
        #expect(try ids(db, "elsewhere").isEmpty)
        try integrity(db)

        try db.execute("UPDATE search_article SET details = json_set(details, '$.body', NULL)")
        #expect(try ids(db, "rollback").isEmpty)
        try integrity(db)
        try article.delete(db)
        #expect(try ids(db, "Updated").isEmpty)
        #expect(try db.queryScalar("SELECT count(*) FROM __swiftstore_fts_search_article_map", type: Int.self) == 0)
        try integrity(db)
    }

    @Test("Mapping and terms roll back atomically, including nested transactions")
    func rollback() throws {
        let db = try setup()
        var article = SearchArticle(title: "original", details: SearchDetails(body: "stable"))
        try article.insert(db)
        let mapping = try mappingID(db, article.id)
        try db.transaction { () throws -> Void in
            #expect(throws: Failure.self) {
                try db.transaction {
                    article.title = "changed"
                    try article.update(db)
                    try article.delete(db)
                    try SearchArticle(title: "temporary", details: SearchDetails(body: nil)).insert(db)
                    throw Failure.rollback
                }
            }
            #expect(try ids(db, "original") == [article.id])
            #expect(try ids(db, "temporary").isEmpty)
            #expect(try mappingID(db, article.id) == mapping)
        }
        try integrity(db)
    }

    @Test("FTS survives reopening and VACUUM without changing UUID mappings")
    func persistence() throws {
        let path = NSTemporaryDirectory() + "fts-\(UUID().uuidString).sqlite"
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let article = SearchArticle(title: "persistent", details: SearchDetails(body: "searchable"))
        let mapping: Int64
        do {
            let db = try setup(path: path)
            try article.insert(db)
            mapping = try mappingID(db, article.id)
        }
        let reopened = try SQLiteConnection(path: path)
        try reopened.execute("VACUUM")
        #expect(try mappingID(reopened, article.id) == mapping)
        #expect(try ids(reopened, "searchable") == [article.id])
        try SchemaSnapshot(entities: [SearchArticle.self]).verify(on: reopened)
        try integrity(reopened)
    }

    @Test("Literal search escapes operators and quotes; advanced syntax is explicit")
    func queries() throws {
        let db = try setup()
        let one = SearchArticle(title: "one OR two", details: SearchDetails(body: "quoted \"word\""))
        try one.insert(db)
        try SearchArticle(title: "two", details: SearchDetails(body: nil)).insert(db)
        #expect(try ids(db, "one OR two") == [one.id])
        #expect(try ids(db, "quoted \"word\"") == [one.id])
        #expect(try ids(db, "   ").isEmpty)
        #expect(try ids(db, "' OR 1=1 --").isEmpty)
        #expect(try Query(SearchArticle.self).matching("one OR two").count(db) == 2)
        #expect(throws: (any Error).self) { try Query(SearchArticle.self).matching("\"").all(db) }
        #expect(throws: (any Error).self) { try SearchArticle.search("one", index: "missing") }
        #expect(throws: (any Error).self) { try TestTag.search("one") }
    }

    @Test("Composite identities and multiple indexes share one local map")
    func compositeIdentity() throws {
        let db = try SQLiteConnection(path: ":memory:")
        let snapshot = SchemaSnapshot(entities: [SearchMembership.self])
        try snapshot.validate()
        for sql in snapshot.creationStatements { try db.execute(sql) }
        try SearchMembership(team: "a", member: "one", text: "abcdefgh").insert(db)
        try SearchMembership(team: "b", member: "one", text: "other").insert(db)
        #expect(throws: (any Error).self) { try SearchMembership.search("abc") }
        #expect(try SearchMembership.search("cde", index: "membership_substrings").count(db) == 1)
        #expect(try Query(SearchMembership.self).search("abcdefgh", index: "search_membership_fts").all(db).first?.team == "a")
        try db.execute("UPDATE search_membership SET team = 'c', text = 'replacement' WHERE team = 'a'")
        #expect(try Query(SearchMembership.self).search("replacement", index: "search_membership_fts").all(db).first?.team == "c")
        try db.execute("DELETE FROM search_membership")
        #expect(try db.queryScalar("SELECT count(*) FROM __swiftstore_fts_search_membership_map", type: Int.self) == 0)
        try snapshot.verify(on: db)
    }

    @Test("UPSERT preserves mappings; REPLACE cleanup works with recursive triggers enabled")
    func conflictHandling() throws {
        let db = try setup()
        let article = SearchArticle(title: "before", details: SearchDetails(body: "original"))
        try article.insert(db)
        let mapping = try mappingID(db, article.id)
        try db.execute("""
            INSERT INTO search_article(id, title, details) VALUES (?, 'upserted', '{"body":"fresh"}')
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, details = excluded.details
            """, values: [.blob(article.id.data)])
        #expect(try ids(db, "original").isEmpty)
        #expect(try ids(db, "fresh") == [article.id])
        #expect(try mappingID(db, article.id) == mapping)
        try integrity(db)
        try db.execute("PRAGMA recursive_triggers = ON")
        try db.execute("CREATE UNIQUE INDEX unique_search_title ON search_article(title)")
        let replacement = UUIDV7()
        try db.execute("""
            INSERT OR REPLACE INTO search_article(id, title, details) VALUES (?, 'upserted', '{"body":"replacement"}')
            """, values: [.blob(replacement.data)])
        #expect(try ids(db, "fresh").isEmpty)
        #expect(try ids(db, "replacement") == [replacement])
        #expect(try db.queryScalar("SELECT count(*) FROM __swiftstore_fts_search_article_map", type: Int.self) == 1)
        try integrity(db)
    }

    @Test("Schema verification detects changed views and missing triggers")
    func schemaDrift() throws {
        let db = try setup()
        let snapshot = SchemaSnapshot(entities: [SearchArticle.self])
        try db.execute("DROP VIEW __swiftstore_fts_search_article_fts_content")
        try db.execute("CREATE VIEW __swiftstore_fts_search_article_fts_content AS SELECT 0 AS fts_id, '' AS title, '' AS details__body")
        #expect(throws: (any Error).self) { try snapshot.verify(on: db) }
        let other = try setup()
        try other.execute("DROP TRIGGER __swiftstore_fts_search_article_au")
        #expect(throws: (any Error).self) { try snapshot.verify(on: other) }
    }
}
