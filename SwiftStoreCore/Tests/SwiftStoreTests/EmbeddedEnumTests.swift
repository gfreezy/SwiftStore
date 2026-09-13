import Foundation
import Testing
import SwiftStoreCore

@Embedded
private enum EscapedRawStatus: Swift.String {
    case quoted = "\"pending\""
    case escaped = "line\n\"quoted\"\\尾"
}

@Embedded
private enum LargeRawNumber: UInt64 {
    case maximum = 9223372036854775807
}

@Embedded
private enum AssociatedState {
    case message(String)
}

@Embedded
private struct NestedEnumDocument {
    var status: TaskStatus
    var states: [TaskStatus]
}

private typealias RatioRawValue = Swift.Double

@Embedded
private enum Ratio: RatioRawValue { case small = 0.5, large = 10.0 }

@Embedded
private enum ComparableLevel: Int, SQLiteValueComparable, Comparable {
    case low = 2, high = 10
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

@Embedded
private struct BlobRawValue {
    var text: String
    static var sqliteType: SQLiteType { .blob }
    static var sqliteIsJSONEncoded: Bool { false }
    func sqliteEncode() throws -> SQLiteValue { .blob(Data(text.utf8)) }
    init(from value: SQLiteValue) throws { text = String(decoding: try Data(from: value), as: UTF8.self) }
}

@Embedded
private struct BlobRawWrapper: RawRepresentable {
    typealias RawValue = BlobRawValue
    var rawValue: RawValue
}

@Embedded
private struct ComparableJSONDocument: SQLiteValueComparable {
    var count: Int
    var sqliteValue: SQLiteValue { .text("{\"count\":\(count)}") }
}

@Entity(readonly: true)
private struct ProtocolDrivenRow {
    var id: Int
    var ratio: Ratio
    var level: ComparableLevel
    var optionalLevel: ComparableLevel?
}

@Suite("Embedded scalar enum storage and predicates")
struct EmbeddedEnumTests {
    private func database() throws -> SQLiteConnection {
        let db = try SQLiteConnection(path: ":memory:")
        for sql in SchemaSnapshot(entities: [MacroTask.self, MacroOrder.self, MacroItem.self]).creationStatements {
            try db.execute(sql)
        }
        return db
    }

    private func encode<T: SQLiteValueEncodable>(_ value: T) throws -> SQLiteValue {
        try value.sqliteEncode()
    }

    @Test func stringRawValuesUseTheSameScalarForStorageAndQueries() throws {
        let db = try database()
        try db.insert(MacroTask(title: "todo", status: .pending))
        try db.insert(MacroTask(title: "done", status: .completed))
        #expect(try db.queryScalar("SELECT status FROM macro_task WHERE title = 'todo'", type: String.self) == "pending")
        #expect(try encode(TaskStatus.pending) == .text("pending"))
        #expect(TaskStatus.pending.sqliteValue == .text("pending"))
        #expect(try MacroTask.filter { $0.status == .pending }.all(db).map(\.title) == ["todo"])
        #expect(try MacroTask.filter { $0.status != .pending }.all(db).map(\.title) == ["done"])
        #expect(try MacroTask.filter { $0.status ~= [.pending, .completed] }.all(db).count == 2)
        let sql: SQL = "SELECT COUNT(*) FROM macro_task WHERE status = \(TaskStatus.pending)"
        #expect(try db.queryScalar(sql, type: Int.self) == 1)
        #expect(MacroTask.columns.first { $0.name == "status" }?.isJSONEncoded == false)
    }

    @Test func optionalAndIntegerEnumPredicatesMatchStoredValues() throws {
        let db = try database()
        try db.insert(MacroOrder(orderNumber: "present", status: .pending))
        try db.insert(MacroOrder(orderNumber: "missing", status: nil))
        #expect(try MacroOrder.filter { $0.status == TaskStatus.pending }.all(db).count == 1)
        #expect(try MacroOrder.filter { $0.status == nil }.all(db).count == 1)
        #expect(try encode(Optional.some(TaskStatus.pending)) == .text("pending"))
        #expect(try encode(Optional<TaskStatus>.none) == .null)
        try db.insert(MacroItem(name: "high", priority: .high))
        #expect(try MacroItem.filter { $0.priority == .high }.all(db).map(\.name) == ["high"])
        #expect(try encode(Priority.high) == Priority.high.sqliteValue)
        #expect(try encode(LargeRawNumber.maximum) == LargeRawNumber.maximum.sqliteValue)
        #expect(try LargeRawNumber(from: LargeRawNumber.maximum.sqliteValue) == .maximum)
    }

    @Test func delegatedStorageSupportsAliasesRealNumbersAndExplicitComparableConformance() throws {
        let db = try SQLiteConnection(path: ":memory:")
        for sql in SchemaSnapshot(entities: [ProtocolDrivenRow.self]).creationStatements { try db.execute(sql) }
        try db.insert(ProtocolDrivenRow(id: 1, ratio: .small, level: .low, optionalLevel: nil))
        try db.insert(ProtocolDrivenRow(id: 2, ratio: .large, level: .high, optionalLevel: .high))
        #expect(try encode(Ratio.small) == .real(0.5))
        #expect(try encode(ComparableLevel.high) == .integer(10))
        #expect(ProtocolDrivenRow.columns.map(\.type) == [.integer, .real, .integer, .integer])
        #expect(try db.queryScalar("SELECT typeof(level) FROM protocol_driven_row LIMIT 1", type: String.self) == "integer")
        #expect(try ProtocolDrivenRow.filter { $0.ratio > .small }.all(db).map(\.id) == [2])
        #expect(try ProtocolDrivenRow.filter { $0.level >= .high }.all(db).map(\.id) == [2])
        #expect(try ProtocolDrivenRow.filter { $0.level == .low }.all(db).map(\.id) == [1])
        #expect(try ProtocolDrivenRow.filter { $0.level.in([.high]) }.all(db).map(\.id) == [2])
        #expect(try ProtocolDrivenRow.filter { $0.level.between(.low, and: .high) }.all(db).count == 2)
        #expect(try ProtocolDrivenRow.filter { $0.optionalLevel != nil }.all(db).count == 1)
        #expect(try ProtocolDrivenRow.filter { $0.optionalLevel >= .high }.all(db).count == 1)
        #expect(try ProtocolDrivenRow.filter(\ProtocolDrivenRow.level == .low).all(db).count == 1)
        #expect(try ProtocolDrivenRow.filter((\ProtocolDrivenRow.ratio).notIn([.small])).all(db).count == 1)
        #expect(try ProtocolDrivenRow.filter((\ProtocolDrivenRow.level).between(.low, and: .high)).all(db).count == 2)
        let sql: SQL = "SELECT COUNT(*) FROM protocol_driven_row WHERE level = \(ComparableLevel.high) AND ratio = \(Ratio.large)"
        #expect(try db.queryScalar(sql, type: Int.self) == 1)
    }

    @Test func customRawCodecAndJSONMetadataAreIndependentOfComparability() throws {
        let wrapper = BlobRawWrapper(rawValue: BlobRawValue(text: "raw"))
        #expect(try encode(wrapper) == .blob(Data("raw".utf8)))
        #expect(try BlobRawWrapper(from: encode(wrapper)) == wrapper)
        #expect(BlobRawWrapper.sqliteType == .blob)
        #expect(!ColumnDefinition.isJSONEncoded(BlobRawWrapper.self))
        #expect(!ColumnDefinition.isJSONEncoded(Optional<BlobRawWrapper>.self))
        #expect(ColumnDefinition.isJSONEncoded(ComparableJSONDocument.self))
        #expect(ColumnDefinition.isJSONEncoded([Ratio].self))
        #expect(ColumnDefinition.isJSONEncoded([String: Ratio].self))
        #expect(ColumnDefinition.isJSONEncoded(Optional<[Ratio]>.self))
        let document = ComparableJSONDocument(count: 2)
        #expect(try encode(document) == document.sqliteValue)
    }

    @Test func legacyJSONStringsRequireAnExplicitDataMigration() throws {
        #expect(throws: SQLiteValueError.self) { try TaskStatus(from: .text("\"pending\"")) }
        #expect(throws: SQLiteValueError.self) { try TaskStatus(from: .text("unknown")) }
        #expect(throws: SQLiteValueError.self) { try TaskStatus(from: .integer(1)) }
        let db = try database()
        let task = MacroTask(title: "legacy", status: .pending)
        try db.insert(task)
        try db.execute("UPDATE macro_task SET status = ?", values: [.text("\"pending\"")])
        #expect(throws: SQLiteValueError.self) { try MacroTask.all(db) }
        try db.execute("UPDATE macro_task SET status = json_extract(status, '$') WHERE json_valid(status) AND json_type(status) = 'text'")
        #expect(try MacroTask.filter { $0.status == .pending }.all(db).count == 1)
    }

    @Test func escapedValuesAndNestedJSONKeepTheirMeaning() throws {
        for value in [EscapedRawStatus.quoted, .escaped] {
            #expect(try encode(value) == .text(value.rawValue))
            #expect(try EscapedRawStatus(from: encode(value)) == value)
        }
        let nested = NestedEnumDocument(status: .pending, states: [.pending, .completed])
        let encoded = try nested.sqliteEncode()
        #expect(try NestedEnumDocument(from: encoded) == nested)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(nested)) as? [String: Any]
        #expect(json?["status"] as? String == "pending")
        #expect(json?["states"] as? [String] == ["pending", "completed"])
        #expect(try AssociatedState(from: AssociatedState.message("hello").sqliteEncode()) == .message("hello"))
        #expect(ColumnDefinition.isJSONEncoded(AssociatedState.self))
    }
}
