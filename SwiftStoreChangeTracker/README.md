# SwiftStoreChangeTracker

SwiftStore 的变更追踪层，记录数据库所有变更用于同步。

## 概述

此 package 使用 SQLite 的 update hook 机制自动捕获数据库变更（INSERT/UPDATE/DELETE），将变更记录写入独立的 changelog 数据库。这是实现多设备数据同步的基础设施。

## 主要功能

### ChangeTracker

核心类，负责监听数据库变更：

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

// 开始追踪
try tracker.start()

// 停止追踪
tracker.stop()
```

### ChangeLog

变更记录实体：

```swift
struct ChangeLog {
    let id: UUIDV4
    let entityType: String      // 表名
    let syncKey: Data           // 同步键（二进制编码）
    let operation: ChangeOperation  // insert/update/delete
    let payload: String?        // JSON 格式的实体数据
    let deviceId: UUIDV4        // 来源设备
    let logicalClock: Int64     // 逻辑时钟值
    let schemaVersion: Int      // Schema 版本
    let createdAt: Date
    let updatedAt: Date
}
```

### HybridClock

混合逻辑时钟实现，用于分布式时间排序：

```swift
let clock = HybridClock()
let timestamp = clock.tick()  // 返回单调递增的时钟值
```

### SyncKeyEncoder

同步键编码器，将多字段同步键编码为紧凑的二进制格式：

```swift
let encoded = SyncKeyEncoder.encode([.text("value"), .integer(123)])
let decoded = SyncKeyEncoder.decode(encoded)
```

## 工作原理

1. SQLite update hook 在每次 INSERT/UPDATE/DELETE 时触发
2. ChangeTracker 捕获变更并提取实体数据
3. 变更记录写入独立的 changelog 数据库
4. DELETE 通过 pending_deletes 表间接捕获（因为删除后无法读取数据）

## 支持平台

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## 依赖

- SwiftStoreCore
- SwiftStoreMacros
