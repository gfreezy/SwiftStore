import Foundation
import SwiftStoreProtocols

/// An owned row in the entity's declared column order. Contains no SQLite
/// pointers, so decoding is safe after the native hook has returned.
public struct SQLiteRowSnapshot: SQLiteStatementProtocol, Sendable {
    public let values: [SQLiteValue]

    public init(values: [SQLiteValue]) { self.values = values }

    public func columnInt64(_ index: Int32) -> Int64 {
        switch values[Int(index)] {
        case .integer(let value): return value
        case .real(let value):
            if value >= Double(Int64.max) { return Int64.max }
            if value <= Double(Int64.min) { return Int64.min }
            return value.isFinite ? Int64(value) : 0
        case .text(let value): return Int64(value) ?? 0
        default: return 0
        }
    }

    public func columnDouble(_ index: Int32) -> Double {
        switch values[Int(index)] {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        case .text(let value): return Double(value) ?? 0
        default: return 0
        }
    }

    public func columnString(_ index: Int32) -> String? {
        switch values[Int(index)] {
        case .text(let value): return value
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        case .blob(let value): return String(data: value, encoding: .utf8)
        case .null: return nil
        }
    }

    public func columnData(_ index: Int32) -> Data? {
        if case .blob(let value) = values[Int(index)] { return value }
        return columnString(index).map { Data($0.utf8) }
    }

    public func isNull(_ index: Int32) -> Bool { values[Int(index)] == .null }
}
