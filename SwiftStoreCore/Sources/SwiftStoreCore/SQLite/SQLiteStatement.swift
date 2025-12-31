import Foundation
import SQLite3
import SwiftStoreProtocols

/// SQLite prepared statement wrapper - concrete implementation
public final class SQLiteStatementImpl: SQLiteStatementProtocol {
    private var statement: OpaquePointer?

    init(statement: OpaquePointer) {
        self.statement = statement
    }

    deinit {
        sqlite3_finalize(statement)
    }

    /// Reset the statement for reuse
    public func reset() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    /// Step through the statement
    @discardableResult
    public func step() throws -> Bool {
        let result = sqlite3_step(statement)

        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            let message = String(cString: sqlite3_errmsg(sqlite3_db_handle(statement)))
            throw StoreError.queryFailed("Step failed: \(message)")
        }
    }

    // MARK: - Binding

    public func bind(_ index: Int32, _ value: Int) throws {
        let result = sqlite3_bind_int64(statement, index, Int64(value))
        guard result == SQLITE_OK else {
            throw StoreError.queryFailed("Failed to bind Int at index \(index)")
        }
    }

    public func bind(_ index: Int32, _ value: Int64) throws {
        let result = sqlite3_bind_int64(statement, index, value)
        guard result == SQLITE_OK else {
            throw StoreError.queryFailed("Failed to bind Int64 at index \(index)")
        }
    }

    public func bind(_ index: Int32, _ value: Double) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else {
            throw StoreError.queryFailed("Failed to bind Double at index \(index)")
        }
    }

    public func bind(_ index: Int32, _ value: String) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard result == SQLITE_OK else {
            throw StoreError.queryFailed("Failed to bind String at index \(index)")
        }
    }

    public func bind(_ index: Int32, _ value: Data) throws {
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else {
            throw StoreError.queryFailed("Failed to bind Data at index \(index)")
        }
    }

    public func bindNull(_ index: Int32) throws {
        let result = sqlite3_bind_null(statement, index)
        guard result == SQLITE_OK else {
            throw StoreError.queryFailed("Failed to bind NULL at index \(index)")
        }
    }

    public func bind(_ index: Int32, _ value: Bool) throws {
        try bind(index, value ? 1 : 0)
    }

    public func bind(_ index: Int32, _ value: UUID) throws {
        try bind(index, value.uuidString)
    }

    public func bind(_ index: Int32, _ value: Date) throws {
        try bind(index, value.timeIntervalSince1970)
    }

    // MARK: - Column Access

    public func columnInt(_ index: Int32) -> Int {
        return Int(sqlite3_column_int64(statement, index))
    }

    public func columnInt64(_ index: Int32) -> Int64 {
        return sqlite3_column_int64(statement, index)
    }

    public func columnDouble(_ index: Int32) -> Double {
        return sqlite3_column_double(statement, index)
    }

    public func columnString(_ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    public func columnData(_ index: Int32) -> Data? {
        guard let blob = sqlite3_column_blob(statement, index) else {
            return nil
        }
        let size = sqlite3_column_bytes(statement, index)
        return Data(bytes: blob, count: Int(size))
    }

    public func columnBool(_ index: Int32) -> Bool {
        return columnInt(index) != 0
    }

    public func columnUUID(_ index: Int32) -> UUID? {
        guard let string = columnString(index) else { return nil }
        return UUID(uuidString: string)
    }

    public func columnDate(_ index: Int32) -> Date {
        return Date(timeIntervalSince1970: columnDouble(index))
    }

    public func isNull(_ index: Int32) -> Bool {
        return sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    public var columnCount: Int32 {
        return sqlite3_column_count(statement)
    }

    public func columnName(_ index: Int32) -> String? {
        guard let name = sqlite3_column_name(statement, index) else {
            return nil
        }
        return String(cString: name)
    }

    /// Get column value as SQLiteValue
    public func sqliteValue(_ index: Int32) -> SQLiteValue {
        let type = sqlite3_column_type(statement, index)
        switch type {
        case SQLITE_INTEGER:
            return .integer(columnInt64(index))
        case SQLITE_FLOAT:
            return .real(columnDouble(index))
        case SQLITE_TEXT:
            return .text(columnString(index) ?? "")
        case SQLITE_BLOB:
            return .blob(columnData(index) ?? Data())
        case SQLITE_NULL:
            return .null
        default:
            return .null
        }
    }
}
