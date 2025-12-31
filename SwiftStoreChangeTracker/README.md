# SwiftStoreChangeTracker

Change tracking layer for SwiftStore, recording all database changes for synchronization.

## Overview

This package uses SQLite's update hook mechanism to automatically capture database changes (INSERT/UPDATE/DELETE) and writes change records to a separate changelog database. This is the infrastructure for implementing multi-device data synchronization.

## Features

### ChangeTracker

Core class responsible for listening to database changes:

```swift
let tracker = try ChangeTracker(
    connection: mainConnection,
    changeLogDbPath: "changelog.sqlite",
    deviceId: deviceId,
    pendingDeletesTable: "__pending_deletes",
    registeredEntities: [User.self, Post.self],
    tickClock: { clock.tick() },
    schemaVersion: 1
)

// Start tracking
try tracker.start()

// Stop tracking
tracker.stop()
```

### ChangeLog

Change record entity:

```swift
struct ChangeLog {
    let id: UUIDV4
    let entityType: String      // Table name
    let syncKey: Data           // Sync key (binary encoded)
    let operation: ChangeOperation  // insert/update/delete
    let payload: String?        // JSON format entity data
    let deviceId: UUIDV4        // Source device
    let logicalClock: Int64     // Logical clock value
    let schemaVersion: Int      // Schema version
    let createdAt: Date
    let updatedAt: Date
}
```

### HybridClock

Hybrid logical clock implementation for distributed time ordering:

```swift
let clock = HybridClock()
let timestamp = clock.tick()  // Returns monotonically increasing clock value
```

### SyncKeyEncoder

Sync key encoder, encodes multi-field sync keys into compact binary format:

```swift
let encoded = SyncKeyEncoder.encode([.text("value"), .integer(123)])
let decoded = SyncKeyEncoder.decode(encoded)
```

## How It Works

1. SQLite update hook triggers on each INSERT/UPDATE/DELETE
2. ChangeTracker captures the change and extracts entity data
3. Change records are written to a separate changelog database
4. DELETE is captured indirectly via pending_deletes table (since data cannot be read after deletion)

## Supported Platforms

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## Dependencies

- SwiftStoreCore
- SwiftStoreMacros
