# SwiftStoreCore

Core layer for SwiftStore, providing SQLite database connection, query building, and migration functionality.

## Overview

This package is the core implementation of the SwiftStore framework. It wraps SQLite database operations and provides type-safe query APIs and automatic schema migration capabilities.

## Features

### SQLite Connection

```swift
let connection = try SQLiteConnection(path: "database.sqlite")
```

Supported options:
- WAL mode
- Foreign key constraints
- Custom configuration

### CRUD Operations

```swift
// Insert
try user.insert(connection)

// Query
let users = try User.filter { $0.age > 18 }
    .order(by: \.name)
    .limit(10)
    .all(connection)

// Update
try user.update(connection)

// Delete
try user.delete(connection)
```

### Query Builder

Type-safe query building:

```swift
// Condition query
let result = try User.filter { $0.email == "test@example.com" }.all(connection)

// Compound conditions
let result = try User
    .filter { $0.age >= 18 && $0.status == "active" }
    .orderDesc(by: \.createdAt)
    .all(connection)
```

### Schema Migration

Auto migration system supports:
- Adding new tables
- Adding new columns
- Creating indexes
- Delete triggers (for change tracking)

```swift
let migrator = Migrator(connection: connection)
let plan = try migrator.plan(for: [User.self, Post.self])
try migrator.apply(plan)
```

## Module Structure

```
SwiftStoreCore/
├── Core/           # Core types and connection
├── Query/          # Query builder
├── SQLite/         # SQLite wrapper
└── Migration/      # Schema migration
```

## Supported Platforms

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## Dependencies

- SwiftStoreMacros
- SwiftStoreProtocols
