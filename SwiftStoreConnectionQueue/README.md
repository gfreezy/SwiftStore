# SwiftStoreConnectionQueue

Connection management layer for SwiftStore, providing single-writer multiple-reader connection pool implementation.

## Overview

This package implements SQLite's Single Writer Multiple Reader (SWMR) pattern, ensuring thread safety while providing optimal performance. It uses Swift Actors for concurrency control, combined with SQLite WAL mode for concurrent read/write.

## Features

### ConnectionManager

Connection pool manager:

```swift
let manager = try ConnectionManager(
    path: "database.sqlite",
    options: .init(),
    maxReadConnections: 4,
    syncConfig: syncConfig  // Optional, enables sync functionality
)
```

### Read/Write Operations

```swift
// Write operation (serialized)
try await manager.write { connection in
    try user.insert(connection)
}

// Read operation (concurrent)
let users = try await manager.read { connection in
    try User.filter { $0.age > 18 }.all(connection)
}
```

### Sync Functionality

When `syncConfig` is provided, sync functionality is automatically enabled:

```swift
// Check if sync is enabled
if await manager.hasSyncEnabled {
    // Perform sync
    let result = try await manager.sync()
    print("Pulled: \(result.pulledCount), Pushed: \(result.pushedCount)")
}

// Get sync state
if let state = await manager.syncState {
    print("Last server clock: \(state.lastServerClock)")
}
```

## Architecture

```
ConnectionManager
├── WritableConnectionActor     # Single write connection (Actor serialization)
│   └── SyncManager?            # Optional sync manager
└── [ConnectionActor]           # Multiple read connection pool
    └── isInUse: Mutex<Bool>    # Usage status flag
```

- Write operations are serialized through `WritableConnectionActor`
- Read operations acquire available connections from the pool for concurrent execution
- WAL mode allows concurrent read and write

## Supported Platforms

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## Dependencies

- SwiftStoreCore
- SwiftStoreSync
