# SwiftStoreSync

SwiftStore 的同步层，提供多设备数据同步功能。

## 概述

此 package 实现了基于变更日志的同步机制，支持与远程服务器进行双向同步。采用 Last-Write-Wins (LWW) 策略解决冲突，通过逻辑时钟保证变更顺序。

## 主要功能

### SyncManager

同步管理器，协调本地变更追踪和远程同步：

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
        ntpToleranceMs: 5000  // NTP 时间校验容差
    )
)

// 执行同步
let result = try await syncManager.sync()
```

### SyncConfig

同步配置：

```swift
SyncConfig(
    changeLogDbPath: String,          // 变更日志数据库路径
    deviceId: UUIDV4,                 // 设备 ID
    pendingDeletesTable: String,      // 待删除表名
    registeredEntities: [EntityProtocol.Type],  // 追踪的实体类型
    tickClock: () -> Int64,           // 时钟函数
    transport: SyncTransport,         // 传输层实现
    syncableEntities: [SyncableEntity.Type],    // 可同步的实体类型
    syncConfiguration: SyncConfiguration,       // 批处理配置
    initialState: SyncState,          // 初始同步状态
    schemaVersion: Int,               // Schema 版本（用于兼容性）
    ntpToleranceMs: Int64?            // NTP 容差（nil 禁用检查）
)
```

### SyncTransport

传输层协议，需要实现与远程服务器的通信：

```swift
public protocol SyncTransport: Sendable {
    func pull(sinceClock: Int64, deviceId: UUIDV4) async throws -> PullResponse
    func push(changes: [SyncChange], deviceId: UUIDV4) async throws -> PushResponse
}
```

### NTPClient

NTP 时间校验客户端，确保设备时间同步：

```swift
let result = try await NTPClient.verifyTime(toleranceMs: 5000)
if !result.isValid {
    // 设备时间偏差过大
}
```

### EntityApplier

实体应用器，将远程变更应用到本地数据库：

```swift
// 自动从 SyncableEntity 类型生成
let registry = EntityApplierRegistry(syncableEntities: [User.self, Post.self])
try registry.apply(change: syncChange, to: connection)
```

## 同步流程

1. **Pull** - 从远程拉取变更
   - 获取 `sinceClock` 之后的所有变更
   - 过滤掉本设备的变更和高版本 schema 变更
   - 批量应用到本地数据库（暂停 ChangeTracker）

2. **Push** - 推送本地变更到远程
   - 读取本地 changelog 中的新变更
   - 发送到远程服务器
   - 更新本地同步状态

## Schema 版本兼容性

- 高版本设备可以处理低版本数据
- 低版本设备会忽略高版本数据
- 通过 `schemaVersion` 字段实现向前兼容

## 支持平台

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## 依赖

- SwiftStoreCore
- SwiftStoreChangeTracker
