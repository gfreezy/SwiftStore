import Foundation
import Testing
import SwiftStoreCore
@testable import SwiftStoreChangeTracker

@Suite("Changelog enum encoding")
struct EnumLogEncodingTests {
    @Test func genericCodecRoundTripsAndSupportsQueries() throws {
        let db = try SQLiteConnection(path: ":memory:")
        try SyncLogStorage.create(in: db)
        let event = ChangeLog(entityType: "thing", syncKey: Data([1]), operation: .insert, payload: nil,
            deviceId: UUIDV7(), logicalClock: 1, schemaVersion: 1)
        try SyncLogStorage.append(event, to: db)
        #expect(try db.queryScalar("SELECT operation FROM __swiftstore_change_log", type: String.self) == "insert")
        #expect(try event.operation.sqliteEncode() == .text("insert"))
        #expect(try ChangeLog.filter { $0.operation == .insert }.all(db).count == 1)
        try SyncLogStorage.create(in: db) // Reopening does not duplicate events.
        let events = try ChangeTrackerReader(connection: db).changes(after: 0)
        #expect(events.map(\.operation) == [.insert])
        #expect(events.map(\.seq) == [1])
        #expect(events.first?.id == event.id)
        #expect(throws: (any Error).self) { try db.execute("UPDATE __swiftstore_change_log SET operation = 'delete'") }
    }
}
