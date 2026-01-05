# SwiftStoreProtocols

Protocol definitions layer for SwiftStore, providing base protocols and type definitions that all entities must conform to.

## Overview

This package defines the core protocols for the SwiftStore framework and serves as the foundation dependency. It contains no concrete implementations, only protocol and type definitions.

## Contents

### EntityProtocol

The protocol that all entities must conform to:

```swift
public protocol EntityProtocol: Codable, Sendable {
    var createdAt: Date { get }
    var updatedAt: Date { get }

    static var tableName: String { get }
    static var columns: [ColumnDefinition] { get }
    static var indexes: [IndexDefinition] { get }
    static var syncKeyColumns: [String] { get }
}
```

### SQLiteCodable

SQLite encoding/decoding protocols for converting between entities and SQLite values:

```swift
public protocol SQLiteEncodable {
    func sqliteEncode() throws -> [String: SQLiteValue]
}

public protocol SQLiteDecodable {
    static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self
}

public typealias SQLiteCodable = SQLiteEncodable & SQLiteDecodable
```

### Other Types

- `ColumnDefinition` - Column definition describing database column name and type
- `SQLiteValue` - SQLite value type enumeration
- `SQLiteStatementProtocol` - SQLite statement protocol
- `StoreError` - Error type definitions
- `UUIDV7` - UUID v4 type, stored as 16-byte BLOB

## Supported Platforms

- macOS 14+
- iOS 17+

## Dependencies

No external dependencies.
