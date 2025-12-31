# SwiftStoreSync

Sync layer for SwiftStore, providing multi-device data synchronization functionality.

## Overview

This package implements changelog-based synchronization mechanism, supporting bidirectional sync with remote servers. It uses Last-Write-Wins (LWW) strategy for conflict resolution and logical clocks to ensure change ordering.

## Features

### SyncManager

Sync manager coordinating local change tracking and remote synchronization:

```swift
let syncManager = try SyncManager(
    connection: connection,
    config: SyncConfig(
        changeLogDbPath: "changelog.sqlite",
        deviceId: deviceId,
        registeredEntities: [User.self, Post.self],
        tickClock: { clock.tick() },
        transport: myTransport,
        syncableEntities: [User.self, Post.self],
        schemaVersion: 1,
        ntpToleranceMs: 5000  // NTP time validation tolerance
    )
)

// Perform sync
let result = try await syncManager.sync()
```

### SyncConfig

Sync configuration:

```swift
SyncConfig(
    changeLogDbPath: String,          // Changelog database path
    deviceId: UUIDV4,                 // Device ID
    pendingDeletesTable: String,      // Pending deletes table name
    registeredEntities: [EntityProtocol.Type],  // Entity types to track
    tickClock: () -> Int64,           // Clock function
    transport: SyncTransport,         // Transport layer implementation
    syncableEntities: [SyncableEntity.Type],    // Syncable entity types
    syncConfiguration: SyncConfiguration,       // Batch processing config
    initialState: SyncState,          // Initial sync state
    schemaVersion: Int,               // Schema version (for compatibility)
    ntpToleranceMs: Int64?            // NTP tolerance (nil to disable)
)
```

### SyncTransport

Transport layer protocol, implement to communicate with remote server:

```swift
public protocol SyncTransport: Sendable {
    func pull(sinceClock: Int64, deviceId: UUIDV4) async throws -> PullResponse
    func push(changes: [SyncChange], deviceId: UUIDV4) async throws -> PushResponse
}
```

### NTPClient

NTP time validation client, ensures device time synchronization:

```swift
let result = try await NTPClient.verifyTime(toleranceMs: 5000)
if !result.isValid {
    // Device time offset too large
}
```

### EntityApplier

Entity applier, applies remote changes to local database:

```swift
// Auto-generated from SyncableEntity types
let registry = EntityApplierRegistry(syncableEntities: [User.self, Post.self])
try registry.apply(change: syncChange, to: connection)
```

## Sync Flow

1. **Pull** - Pull changes from remote
   - Get all changes after `sinceClock`
   - Filter out changes from this device and higher schema version changes
   - Apply to local database in batches (pausing ChangeTracker)

2. **Push** - Push local changes to remote
   - Read new changes from local changelog
   - Send to remote server
   - Update local sync state

## Schema Version Compatibility

- Higher version devices can process lower version data
- Lower version devices ignore higher version data
- Implemented via `schemaVersion` field for forward compatibility

## Supported Platforms

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## Dependencies

- SwiftStoreCore
- SwiftStoreChangeTracker
