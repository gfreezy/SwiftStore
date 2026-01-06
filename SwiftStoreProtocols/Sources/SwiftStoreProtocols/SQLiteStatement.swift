import Foundation

/// Protocol defining the interface for reading values from a SQLite statement
/// This allows decoupling the protocol definitions from the concrete SQLite implementation
public protocol SQLiteStatementProtocol {
    func columnInt64(_ index: Int32) -> Int64
    func columnDouble(_ index: Int32) -> Double
    func columnString(_ index: Int32) -> String?
    func columnData(_ index: Int32) -> Data?
    func isNull(_ index: Int32) -> Bool
}

extension SQLiteStatementProtocol {
    /// Get column value as SQLiteValue based on the expected SQLite type
    public func columnValue(_ index: Int32, type: SQLiteType) -> SQLiteValue {
        if isNull(index) { return .null }
        switch type {
        case .integer:
            return .integer(columnInt64(index))
        case .real:
            return .real(columnDouble(index))
        case .text:
            return .text(columnString(index) ?? "")
        case .blob:
            return .blob(columnData(index) ?? Data())
        }
    }
}
