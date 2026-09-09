import Foundation
import SQLite3
import Testing
import SwiftStoreProtocols

@Suite("SQLite timestamp capability fallback")
struct TimestampCompatibilityTests {
    @Test("Native subsecond epoch takes precedence; null falls back to fractional seconds")
    func capabilitySelection() throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(":memory:", &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for native in [true, false] {
            let flag = native ? UnsafeMutableRawPointer(bitPattern: 1) : nil
            #expect(sqlite3_create_function_v2(db, "unixepoch", 1, SQLITE_UTF8, flag, { context, _, _ in
                if sqlite3_user_data(context) != nil { sqlite3_result_double(context, 123.125) }
                else { sqlite3_result_null(context) }
            }, nil, nil, nil) == SQLITE_OK)
            let before = Date().timeIntervalSince1970
            var stmt: OpaquePointer?
            #expect(sqlite3_prepare_v2(db, "SELECT \(SQLiteTimestampSQL.now)", -1, &stmt, nil) == SQLITE_OK)
            defer { sqlite3_finalize(stmt) }
            #expect(sqlite3_step(stmt) == SQLITE_ROW)
            #expect(sqlite3_column_type(stmt, 0) == SQLITE_FLOAT)
            let result = sqlite3_column_double(stmt, 0)
            if native { #expect(result == 123.125) }
            else {
                #expect(result >= before - 0.001)
                #expect(result <= Date().timeIntervalSince1970 + 0.001)
            }
        }
    }
}
