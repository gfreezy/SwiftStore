// UUIDV4 is now defined in SwiftStoreProtocols
// This file adds SQLite-specific extensions

import Foundation
import SwiftStoreProtocols

// MARK: - SQLite Support

extension UUIDV4: SQLiteComparable {
    public var sqliteValue: SQLiteValue {
        .blob(data)
    }
}
