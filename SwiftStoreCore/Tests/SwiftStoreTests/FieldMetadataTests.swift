import Foundation
import Testing
@testable import SwiftStoreCore

@Embedded
private enum MetadataState: String {
    case queued, uploaded
}

@Embedded
private struct MetadataDetails {
    var cityName: String
}

@Entity(tableName: "metadata_files")
private struct MetadataFile {
    #Index<Self>(\.details.cityName)
    #FullTextIndex<Self>(\.details.cityName)
    var id: UUIDV7 = UUIDV7()
    var originalName: String
    var downloadCount: Int = 0
    var optionalName: String? = nil
    var state: MetadataState = .queued
    var details: MetadataDetails = MetadataDetails(cityName: "Paris")
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayName: String { originalName.uppercased() }
    var computedCount: Int { downloadCount + 1 }
    var computedState: MetadataState { state }
}

@Entity(tableName: "metadata_outbox", sync: false)
private struct MetadataOutbox {
    #SyncKey<Self>(\.relativePath)
    var relativePath: String
    var byteCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Entity(tableName: "metadata_composite")
private struct MetadataComposite {
    #SyncKey<Self>(\.ownerId, \.fileName)
    var ownerId: UUIDV7
    var fileName: String
    var byteCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

// Keep the protocol accessor in a generic context, including under -O.
@inline(never)
private func metadataIDPredicate<E: EntityProtocol & Identifiable>(_ type: E.Type, id: E.ID) -> SwiftStoreCore.Predicate<E>
where E.ID: SQLiteValueComparable {
    \E.id == id
}

@Suite("Field metadata, Debug and Release")
struct FieldMetadataTests {
    @Test func storedColumnsAndGenericIdentityUseDeclaredNames() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MetadataFile.self])
        var file = MetadataFile(originalName: "first", downloadCount: 2)
        try file.save(store.connection)
        file.originalName = "second"
        try file.save(store.connection)

        #expect(try columnName(for: \MetadataFile.originalName) == "original_name")
        #expect(try columnName(for: \MetadataFile.details.cityName) == "details__city_name")
        #expect(try MetadataFile.filter(metadataIDPredicate(MetadataFile.self, id: file.id)).count(store.connection) == 1)
        #expect(try MetadataFile.find(file.id, store.connection)?.originalName == "second")
        #expect(try MetadataFile.filter(\.details.cityName == "Paris").count(store.connection) == 1)
        #expect(try MetadataFile.search("Paris").count(store.connection) == 1)
        file.details.cityName = "London"
        try file.save(store.connection)
        #expect(try MetadataFile.filter(\.details.cityName == "Paris").count(store.connection) == 0)
        #expect(try MetadataFile.filter(\.details.cityName == "London").count(store.connection) == 1)
        #expect(try MetadataFile.search("Paris").count(store.connection) == 0)
        #expect(try MetadataFile.search("London").count(store.connection) == 1)
        #expect(try MetadataFile.filter(\.optionalName == nil).count(store.connection) == 1)
        #expect(try MetadataFile.filter(\.state == .queued).count(store.connection) == 1)
        #expect(try MetadataFile.filter { $0.state.in([.queued]) }.count(store.connection) == 1)

        _ = try MetadataFile.filter(id: file.id).updateAll(store.connection, [
            Column(\MetadataFile.downloadCount).set(4),
            Column(\MetadataFile.originalName).set("third")
        ])
        #expect(try MetadataFile.filter().sum(store.connection, \.downloadCount) == 4)
        #expect(try MetadataFile.filter().order(by: \.originalName).select(store.connection, \.originalName) == ["third"])
        let sql: SQL = "SELECT \(\MetadataFile.originalName) FROM \(MetadataFile.self) WHERE \(\MetadataFile.id) = \(file.id)"
        #expect(try store.connection.queryScalar(sql, type: String.self) == "third")
        let row = try #require(try store.connection.queryOne(sql))
        #expect(row[\MetadataFile.originalName] == "third")
    }

    @Test func syncKeyAliasSupportsTheSameCRUDAndKeyPathSyntax() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MetadataOutbox.self])
        var item = MetadataOutbox(relativePath: "project/audio.m4a", byteCount: 12)
        try item.save(store.connection)
        item.byteCount = 24
        try item.save(store.connection)
        #expect(try MetadataOutbox.count(store.connection) == 1)
        #expect(try columnName(for: \MetadataOutbox.id) == "relative_path")
        #expect(try MetadataOutbox.filter(\.id == item.id).count(store.connection) == 1)
        #expect(try MetadataOutbox.filter(metadataIDPredicate(MetadataOutbox.self, id: item.id)).count(store.connection) == 1)
        #expect(try MetadataOutbox.filter(ids: [item.id, "absent"]).count(store.connection) == 1)
        #expect(try MetadataOutbox.filter(ids: []).count(store.connection) == 0)
        #expect(try MetadataOutbox.filter(ids: Array(repeating: item.id, count: 1_100)).count(store.connection) == 1)
        #expect(try item.reload(store.connection)?.byteCount == 24)
        #expect(try MetadataOutbox.get(item.id, store.connection).byteCount == 24)
        try item.delete(store.connection)
        #expect(try MetadataOutbox.find(item.id, store.connection) == nil)
    }

    @Test func compositeIdentityBindsEveryKeyComponent() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MetadataComposite.self])
        let owner = UUIDV7()
        var first = MetadataComposite(ownerId: owner, fileName: "a", byteCount: 10)
        let second = MetadataComposite(ownerId: owner, fileName: "b", byteCount: 20)
        try first.save(store.connection)
        try second.save(store.connection)
        first.byteCount = 30
        try first.save(store.connection)
        #expect(try MetadataComposite.count(store.connection) == 2)
        #expect(try MetadataComposite.find(first.id, store.connection)?.byteCount == 30)
        #expect(try MetadataComposite.find(second.id, store.connection)?.byteCount == 20)
        #expect(try MetadataComposite.filter(ids: [first.id, second.id]).count(store.connection) == 2)
        #expect(try MetadataComposite.filter(ids: [first.id, second.id]).filter(\.byteCount == 20).count(store.connection) == 1)
        #expect(try MetadataComposite.filter(\.id.fileName == "b").count(store.connection) == 1)
        try MetadataComposite.delete(first.id, store.connection)
        #expect(try MetadataComposite.count(store.connection) == 1)
        #expect(try MetadataComposite.find(second.id, store.connection) != nil)
    }

    @Test func invalidMappingsFailBeforeSQLAndNeverBecomeBroadWrites() throws {
        let store = try createTestStore()
        try store.migrate(entities: [MetadataFile.self])
        let file = MetadataFile(originalName: "keep")
        try file.save(store.connection)
        let unknown = \MetadataFile.displayName == "KEEP"
        let valid = \MetadataFile.id == file.id
        func rejects(_ body: () throws -> Void) {
            do {
                try body()
                Issue.record("Expected an unmapped-field error")
            } catch StoreError.invalidSchema { }
            catch { Issue.record("Expected invalidSchema, received \(error)") }
        }
        rejects { _ = try MetadataFile.filter(unknown).all(store.connection) }
        rejects { _ = try MetadataFile.filter(!unknown || valid).deleteAll(store.connection) }
        rejects { _ = try MetadataFile.filter(valid && unknown).updateAll(store.connection, ["original_name": .text("lost")]) }
        rejects { _ = try MetadataFile.filter().order(by: \.displayName).count(store.connection) }
        rejects { _ = try MetadataFile.filter().select(store.connection, \.displayName) }
        rejects { _ = try MetadataFile.filter().sum(store.connection, \.computedCount) }
        rejects { _ = try MetadataFile.filter(\.computedState == .queued).count(store.connection) }
        rejects { _ = try MetadataFile.filter().updateAll(store.connection, [Column(\MetadataFile.displayName).set("lost")]) }
        rejects { _ = try MetadataFile.filter().updateAll(store.connection) { $0.computedCount += 1 } }
        rejects { _ = try MetadataFile.filter { $0.displayName.in([]) }.count(store.connection) }
        rejects { _ = try MetadataFile.filter { $0.displayName.notIn([]) }.deleteAll(store.connection) }
        let sql: SQL = "UPDATE \(MetadataFile.self) SET \(\MetadataFile.displayName) = \("lost")"
        rejects { _ = try store.connection.execute(sql) }
        #expect(try MetadataFile.find(file.id, store.connection)?.originalName == "keep")
        #expect(try MetadataFile.count(store.connection) == 1)
    }
}
