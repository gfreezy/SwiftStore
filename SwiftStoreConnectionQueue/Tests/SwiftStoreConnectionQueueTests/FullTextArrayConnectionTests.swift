import Foundation
import Testing
import SwiftStoreCore
import SwiftStoreConnectionQueue

@Embedded
private struct PoolSearchItem { var text: String }

@Entity(tableName: "pool_array_search")
private struct PoolArraySearch {
    #FullTextIndex<Self>(.each(\.items, fields: \.text))
    var id: UUIDV7 = UUIDV7()
    var items: [PoolSearchItem]?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Suite("FullText array connection pool")
struct FullTextArrayConnectionTests {
    @Test func everyReaderAndWriterCanEvaluateTheProjection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = SchemaSnapshot(entities: [PoolArraySearch.self])
        let manager = try ConnectionManager(path: directory.appendingPathComponent("store.sqlite").path,
            entities: [PoolArraySearch.self], migrations: [StoreMigration(id: "001_initial", target: snapshot) { db in
                for sql in snapshot.creationStatements { try db.execute(sql) }
            }])
        try await manager.write { db in
            try PoolArraySearch(items: [.init(text: "pooledtext")]).insert(db)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    let text = try await manager.read { db in
                        try db.queryScalar("SELECT items__text FROM __swiftstore_fts_pool_array_search_fts_content", type: String.self)
                    }
                    #expect(text == "pooledtext")
                }
            }
            try await group.waitForAll()
        }
        try await manager.write { db in
            try db.execute("UPDATE pool_array_search SET items = NULL")
            try db.execute("INSERT INTO pool_array_search_fts(pool_array_search_fts) VALUES ('rebuild')")
        }
        let count = try await manager.read { db in try PoolArraySearch.search("pooledtext").count(db) }
        #expect(count == 0)
    }
}
