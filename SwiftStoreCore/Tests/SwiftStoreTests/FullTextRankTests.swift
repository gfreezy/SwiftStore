import Foundation
import Testing
@testable import SwiftStoreCore

@Entity(tableName: "rank_document")
struct RankDocument {
    #SyncKey<Self>(\.number)
    #FullTextIndex<Self>(\.text)
    var number: Int
    var text: String
    var category: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Suite("Full-text rank ordering")
struct FullTextRankTests {
    private func setup() throws -> SQLiteConnection {
        let db = try SQLiteConnection(path: ":memory:")
        let snapshot = SchemaSnapshot(entities: [RankDocument.self, SearchMembership.self])
        try snapshot.validate()
        for sql in snapshot.creationStatements { try db.execute(sql) }
        // Sparse business rowids deliberately differ from the mapping's sequential FTS IDs.
        for document in [
            RankDocument(number: 100, text: "swift filler filler filler filler", category: "keep"),
            RankDocument(number: 900, text: "swift swift swift", category: "keep"),
            RankDocument(number: 500, text: "swift swift swift", category: "keep"),
            RankDocument(number: 800, text: "swift swift swift swift", category: "omit"),
            RankDocument(number: 200, text: "other", category: "keep"),
        ] { try document.insert(db) }
        try db.execute("UPDATE rank_document SET rowid = number * 10")
        return db
    }

    private func nativeIDs(_ db: SQLiteConnection, expression: String = "swift", category: String? = nil) throws -> [Int] {
        let rows = try db.query("""
            SELECT d.number FROM rank_document AS d
            JOIN __swiftstore_fts_rank_document_map AS m ON m.number = d.number
            JOIN rank_document_fts ON rank_document_fts.rowid = m.fts_id
            WHERE rank_document_fts MATCH ? \(category == nil ? "" : "AND d.category = ?")
            ORDER BY rank_document_fts.rank, d.number DESC
            """, values: [.text(expression)] + (category.map { [.text($0)] } ?? []))
        return rows.map { $0[\RankDocument.number] }
    }

    @Test("Rank matches native FTS, with existing and subsequent orderings breaking ties")
    func ordering() throws {
        let db = try setup()
        let expected = try nativeIDs(db)
        #expect(expected != expected.sorted(by: >))
        let ranked = try RankDocument.search("swift", orderByRank: true).orderDesc(by: \.number)
        #expect(try ranked.select(db, \.number) == expected)
        #expect(try ranked.all(db).map(\.number) == expected)
        #expect(try ranked.first(db)?.number == expected.first)
        #expect(try Query(RankDocument.self).orderDesc(by: \.number)
            .matching("swift", orderByRank: true).select(db, \.number) == expected)
        #expect(try Query(RankDocument.self).search("swift", orderByRank: true)
            .order(by: "number", ascending: false).select(db, \.number) == expected)
        #expect(try RankDocument.matching("swift", orderByRank: true)
            .orderDesc(by: \.number).distinct().select(db, \.number) == expected)
        let plain = try RankDocument.search("swift").orderDesc(by: \.number)
        #expect(try plain.select(db, \.number) == expected.sorted(by: >))
        #expect(try plain.buildSQL().sql == RankDocument.search("swift", orderByRank: false).orderDesc(by: \.number).buildSQL().sql)
        #expect(try db.queryScalar("SELECT count(*) FROM __swiftstore_fts_rank_document_map WHERE number = fts_id", type: Int.self) == 0)
    }

    @Test("Filtering, binding order and pagination; count and aggregates ignore ordering")
    func filteredPagination() throws {
        let db = try setup()
        let expected = try nativeIDs(db, category: "keep")
        let query = try Query(RankDocument.self).filter(\.category == "keep")
            .matching("swift", orderByRank: true).filter(\.number > 0).orderDesc(by: \.number)
        let page = query.limit(1).offset(1)
        #expect(try page.select(db, \.number) == Array(expected.dropFirst().prefix(1)))
        #expect(try page.count(db) == expected.count)
        #expect(try page.exists(db))
        #expect(try !page.isEmpty(db))
        #expect(try page.min(db, \.number) == expected.min())
        #expect(try page.max(\.number, db) == expected.max())
        #expect(try page.sum(db, \.number) == expected.reduce(0, +))
        #expect(try page.avg(db, \.number) == Double(expected.reduce(0, +)) / Double(expected.count))
        #expect(try query.buildSQL().values == [.text("keep"), .text("swift"), .integer(0), .text("swift")])
    }

    @Test("Literal quotes, operators and SQL-like input stay bound; malformed FTS still throws")
    func inputs() throws {
        let db = try setup()
        let text = "quoted \"word\" OR ' SQL --"
        try RankDocument(number: 1200, text: text, category: "special").insert(db)
        #expect(try RankDocument.search(text, orderByRank: true).select(db, \.number) == [1200])
        #expect(try !RankDocument.search(text, orderByRank: true).buildSQL().sql.contains(text))
        #expect(try RankDocument.search("' OR 1=1 --", orderByRank: true).all(db).isEmpty)
        #expect(try RankDocument.search("  \n ", orderByRank: true).all(db).isEmpty)
        #expect(try RankDocument.matching("text: swi* OR other", orderByRank: true)
            .orderDesc(by: \.number).select(db, \.number) == nativeIDs(db, expression: "text: swi* OR other"))
        #expect(throws: (any Error).self) { try RankDocument.matching("\"", orderByRank: true).all(db) }
        #expect(throws: (any Error).self) { try RankDocument.search("swift", index: "missing", orderByRank: true) }
    }

    @Test("UUID identities and JSON fields use configured FTS rank")
    func uuidAndConfiguredRank() throws {
        let db = try SQLiteConnection(path: ":memory:")
        let snapshot = SchemaSnapshot(entities: [SearchArticle.self])
        for sql in snapshot.creationStatements { try db.execute(sql) }
        let titleMatch = SearchArticle(title: "swift swift", details: SearchDetails(body: "other"))
        let bodyMatch = SearchArticle(title: "other", details: SearchDetails(body: "swift swift"))
        try titleMatch.insert(db)
        try bodyMatch.insert(db)
        try db.execute("UPDATE search_article SET rowid = rowid + 1000")
        // Weight the JSON body above the title. Using a hard-coded bm25() would
        // ignore the configured rank function and give these documents equal scores.
        try db.execute("INSERT INTO search_article_fts(search_article_fts, rank) VALUES ('rank', 'bm25(1.0, 10.0)')")
        let rows = try db.query("""
            SELECT a.id FROM search_article AS a
            JOIN __swiftstore_fts_search_article_map AS m ON m.id = a.id
            JOIN search_article_fts ON search_article_fts.rowid = m.fts_id
            WHERE search_article_fts MATCH ? ORDER BY search_article_fts.rank
            """, values: [.text("swift")])
        let expected: [UUIDV7] = rows.map { $0[\SearchArticle.id] }
        #expect(expected == [bodyMatch.id, titleMatch.id])
        #expect(try SearchArticle.search("swift", orderByRank: true).select(db, \.id) == expected)
    }

    @Test("Rank bindings do not leak into batch writes")
    func batchWrites() throws {
        let db = try setup()
        let query = try RankDocument.search("swift", orderByRank: true).limit(1).offset(1)
        #expect(try query.updateAll(db, ["category": .text("updated")]) == 4)
        #expect(try query.filter(\.category == "updated").count(db) == 4)
        #expect(try query.deleteAll(db) == 4)
        #expect(try RankDocument.search("other", orderByRank: true).count(db) == 1)
    }

    @Test("Composite keys, named indexes, and successive rank precedence")
    func compositeAndMultipleIndexes() throws {
        let db = try setup()
        for membership in [
            SearchMembership(team: "a", member: "same", text: "abcdef abcdef abcdef filler"),
            SearchMembership(team: "b", member: "same", text: "abcdef filler filler filler"),
            SearchMembership(team: "a", member: "different", text: "abcdef abcdef filler filler"),
        ] { try membership.insert(db) }
        for index in ["search_membership_fts", "membership_substrings"] {
            let rows = try db.query("""
                SELECT d.team, d.member FROM search_membership AS d
                JOIN __swiftstore_fts_search_membership_map AS m ON m.team = d.team AND m.member = d.member
                JOIN \(index) ON \(index).rowid = m.fts_id
                WHERE \(index) MATCH ? ORDER BY \(index).rank, d.team, d.member
                """, values: [.text("abcdef")])
            let expected = rows.map { ($0[\SearchMembership.team], $0[\SearchMembership.member]) }
            let actual = try SearchMembership.search("abcdef", index: index, orderByRank: true)
                .order(by: \.team).order(by: \.member).all(db)
            #expect(actual.map(\.team) == expected.map(\.0))
            #expect(actual.map(\.member) == expected.map(\.1))
        }
        #expect(throws: (any Error).self) { try SearchMembership.search("abcdef", orderByRank: true) }
        let query = try SearchMembership.matching("abcdef", index: "search_membership_fts", orderByRank: true)
            .matching("filler", index: "membership_substrings", orderByRank: true)
            .order(by: \.team).order(by: \.member)
        let rows = try db.query("""
            SELECT d.team, d.member FROM search_membership AS d
            JOIN __swiftstore_fts_search_membership_map AS m ON m.team = d.team AND m.member = d.member
            JOIN search_membership_fts ON search_membership_fts.rowid = m.fts_id
            JOIN membership_substrings ON membership_substrings.rowid = m.fts_id
            WHERE search_membership_fts MATCH ? AND membership_substrings MATCH ?
            ORDER BY membership_substrings.rank, search_membership_fts.rank, d.team, d.member
            """, values: [.text("abcdef"), .text("filler")])
        let actual = try query.all(db)
        #expect(actual.map(\.team) == rows.map { $0[\SearchMembership.team] })
        #expect(actual.map(\.member) == rows.map { $0[\SearchMembership.member] })
        #expect(try query.buildSQL().values == [.text("abcdef"), .text("filler"), .text("filler"), .text("abcdef")])
    }
}
