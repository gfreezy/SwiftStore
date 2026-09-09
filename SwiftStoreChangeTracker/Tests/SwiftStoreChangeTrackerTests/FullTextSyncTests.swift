import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreChangeTracker

@Entity(tableName: "fts_synced_note")
private struct FTSSyncedNote {
    #FullTextIndex<Self>(\.text)
    var id: UUIDV7 = UUIDV7()
    var text: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Suite("Full-text local sync state")
struct FullTextSyncTests {
    @Test("Remote writes maintain local mappings without syncing derived tables or echoing changes")
    func twoDevices() throws {
        let a = try SQLiteConnection(path: ":memory:")
        let b = try SQLiteConnection(path: ":memory:")
        let snapshot = SchemaSnapshot(entities: [FTSSyncedNote.self])
        for db in [a, b] {
            for sql in snapshot.creationStatements { try db.execute(sql) }
        }
        let trackerA = try ChangeTracker(connection: a, changeLogDbPath: ":memory:", deviceId: UUIDV7(),
            registeredEntities: [FTSSyncedNote.self], tickClock: { 1 })
        let trackerB = try ChangeTracker(connection: b, changeLogDbPath: ":memory:", deviceId: UUIDV7(),
            registeredEntities: [FTSSyncedNote.self], tickClock: { 1 })
        try trackerA.start()
        try trackerB.start()
        // An unrelated local record makes the integer mappings different on device B.
        try FTSSyncedNote(text: "local only").insert(b)
        var note = FTSSyncedNote(text: "shared searchable")
        try note.insert(a)
        let logsA = try ChangeLog.all(trackerA.connection)
        #expect(logsA.count == 1)
        #expect(logsA.allSatisfy { $0.entityType == "fts_synced_note" })
        let payload = try #require(logsA.first?.payload)
        #expect(!payload.contains("fts_id"))
        let received = try JSONDecoder().decode(FTSSyncedNote.self, from: Data(payload.utf8))
        try b.withWriteSource(.remote) { try received.insert(b) }
        let idSQL = "SELECT fts_id FROM __swiftstore_fts_fts_synced_note_map WHERE id = ?"
        let idA = try a.queryScalar(idSQL, values: [.blob(note.id.data)], type: Int.self)
        let idB = try b.queryScalar(idSQL, values: [.blob(note.id.data)], type: Int.self)
        #expect(idA != idB)
        #expect(try Query(FTSSyncedNote.self).search("shared").all(b).map(\.id) == [note.id])
        #expect(try ChangeLog.all(trackerB.connection).count == 1)
        note.text = "updated remotely"
        try note.update(a)
        try b.withWriteSource(.remote) { try note.update(b) }
        #expect(try Query(FTSSyncedNote.self).search("shared").count(b) == 0)
        #expect(try Query(FTSSyncedNote.self).search("remotely").count(b) == 1)
        #expect(try b.queryScalar(idSQL, values: [.blob(note.id.data)], type: Int.self) == idB)
        try b.withWriteSource(.remote) { try note.delete(b) }
        #expect(try Query(FTSSyncedNote.self).search("remotely").count(b) == 0)
        #expect(try b.queryScalar(idSQL, values: [.blob(note.id.data)], type: Int.self) == nil)
        #expect(try ChangeLog.all(trackerB.connection).count == 1)
        #expect(try ChangeLog.all(trackerA.connection).count == 2)
    }
}
