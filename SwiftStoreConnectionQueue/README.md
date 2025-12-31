# SwiftStoreConnectionQueue

SwiftStore 的连接管理层，提供单写多读的连接池实现。

## 概述

此 package 实现了 SQLite 的单写多读（Single Writer Multiple Reader）模式，确保线程安全的同时提供最佳性能。使用 Swift Actor 进行并发控制，配合 SQLite WAL 模式实现读写并行。

## 主要功能

### ConnectionManager

连接池管理器：

```swift
let manager = try ConnectionManager(
    path: "database.sqlite",
    options: .init(),
    maxReadConnections: 4,
    syncConfig: syncConfig  // 可选，启用同步功能
)
```

### 读写操作

```swift
// 写操作（串行执行）
try await manager.write { connection in
    try connection.insert(user)
}

// 读操作（并行执行）
let users = try await manager.read { connection in
    try connection.query { $0.where(\.age > 18) }
}
```

### 同步功能

当提供 `syncConfig` 时，自动启用同步功能：

```swift
// 检查是否启用同步
if await manager.hasSyncEnabled {
    // 执行同步
    let result = try await manager.sync()
    print("Pulled: \(result.pulledCount), Pushed: \(result.pushedCount)")
}

// 获取同步状态
if let state = await manager.syncState {
    print("Last server clock: \(state.lastServerClock)")
}
```

## 架构设计

```
ConnectionManager
├── WritableConnectionActor     # 单一写连接（Actor 串行化）
│   └── SyncManager?            # 可选的同步管理器
└── [ConnectionActor]           # 多个读连接池
    └── isInUse: Mutex<Bool>    # 使用状态标记
```

- 写操作通过 `WritableConnectionActor` 串行执行
- 读操作从连接池获取可用连接并行执行
- WAL 模式允许读写同时进行

## 支持平台

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## 依赖

- SwiftStoreCore
- SwiftStoreSync
