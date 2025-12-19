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
