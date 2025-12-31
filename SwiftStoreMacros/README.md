# SwiftStoreMacros

Macro definitions layer for SwiftStore, providing Swift macros for auto-generating entity code.

## Overview

This package uses Swift macro technology to auto-generate boilerplate code required by EntityProtocol, including table names, column definitions, encoding/decoding implementations, etc.

## Macros

### @Entity

Main macro for marking entity structs:

```swift
@Entity
struct User {
    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    let createdAt: Date
    let updatedAt: Date
}

// Custom table name
@Entity(tableName: "users_table")
struct User { ... }
```

Auto-generates:
- `tableName` static property
- `columns` column definition array
- `sqliteEncode()` / `sqliteDecode(from:)` methods
- `init` initializer with default values
- `CodingKeys` enum
- `EntityProtocol` / `SQLiteCodable` / `Identifiable` conformance

### #Index

Define indexes inside entity:

```swift
@Entity
struct User {
    #Index<Self>(\.email, unique: true)           // Unique index
    #Index<Self>(\.firstName, \.lastName)         // Composite index
    #Index<Self>(\.address.city)                  // Nested field index

    let id: UUIDV4
    var email: String
    var firstName: String
    var lastName: String
    var address: Address
    let createdAt: Date
    let updatedAt: Date
}
```

### #SyncKey

Define sync key for multi-device sync scenarios:

```swift
@Entity
struct Employee {
    #SyncKey<Self>(\.companyId, \.employeeCode)  // Composite sync key

    var companyId: UUIDV4
    var employeeCode: String
    var name: String
    let createdAt: Date
    let updatedAt: Date
}
```

Note: `#SyncKey` and `id` field are mutually exclusive.

### @Default

Generate fault-tolerant Decodable conformance for Codable structs:

```swift
@Default
struct UserSettings: Codable {
    var theme: String = "light"   // Uses default if missing
    var fontSize: Int = 14        // Uses default if missing
    var userId: String            // Required field
}
```

## Supported Platforms

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## Dependencies

- swift-syntax 600.0.0+
- SwiftStoreProtocols
