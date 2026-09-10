# CloudKit 同步

`CloudKitSyncTransport` 在 iOS 17+ 使用 CKSyncEngine，在 iOS 16 使用 CloudKit zone 操作。
两者共用持久化 journal 和[同步后端约定](../docs/sync-backend-contract.md)。

## 接入

在宿主 target 中添加 `SwiftStoreSyncCloudTransport` 产品。下面假设 `User` 及其迁移已定义，
`deviceId` 是应用持久化的本机标识，`dbPath` 指向当前账号的本地数据库：

```swift
import CloudKit
import SwiftStoreConnectionQueue
import SwiftStoreSyncCloudTransport

let stateDirectory = URL.applicationSupportDirectory.appendingPathComponent("cloud-sync-state")
let transport = CloudKitSyncTransport(
    config: CloudKitTransportConfig(
        container: CKContainer(identifier: "iCloud.com.example.MyApp")
    ),
    stateStore: try FileCloudKitSyncStateStore(directory: stateDirectory)
)
let manager = try ConnectionManager(
    path: dbPath,
    entities: [User.self],
    syncConfig: SyncOptions(deviceId: deviceId, transport: transport, schemaVersion: 1)
)
try await manager.migrate(migrations: try StoreMigrations.all())
try await manager.sync()
```

宿主应用需要开启 iCloud / CloudKit、Push Notifications，并注册远端通知；iOS 后台接收还需
Background Modes → Remote notifications。iOS 16 的回调接法见[兼容说明](../docs/ios16-compatibility.md)。

首次同步后，本地写入和远端活动会触发后续同步。回到前台或手动刷新时可调用 `manager.sync()`。
`manager.stopSync()` 暂停网络同步，保留本地追踪和队列；再次调用 `sync()` 恢复。
自动同步的调度不保证即时送达，错误可通过 `await transport.lastError` 查询。

`CloudKitTransportConfig.automaticallySync` 默认为 `true`。关闭它用于手动驱动传输层，
不等于关闭 ConnectionManager 的本地写入同步；完全暂停请使用 `stopSync()`。

## 状态与账号隔离

- 每个账号、容器、zone 和本地数据库使用独立的本地状态目录，不放进 iCloud Drive。
- `journal.plist` 原子保存引擎状态、待上传数据、待确认下载、回执和 CloudKit 记录系统字段。
- 自定义 `CloudKitSyncStateStore` 必须原子实现 `loadJournal()` 和 `saveJournal(_:)`。
- 账号变化或已存在的 zone 被删除时，同步报错并保留本地数据。切换账号时，宿主应选择对应的业务库、日志库和状态目录。
- 不要只删除 journal 来重置同步；业务库、变更日志和同步状态必须配套管理。

`SyncOptions.ntpToleranceMs` 默认为 5000 毫秒，必须为正数；ConnectionManager 将同一阈值传给
transport。直接使用 transport 时在 `CloudKitTransportConfig` 中设置阈值。
每个进程第一次同步时联网校时一次，总等待上限为 3 秒（含 DNS 和服务器回退）；并发请求合并，
所有连接、后端、后台回调和后续批次共享结果。超时或网络失败记录日志后放行，进程内不重试。
成功测得偏差超限时仍保留队列并阻止同步；修复时间后重新启动应用，才会重新联网校验。
无需宿主应用添加启动钩子或额外配置。

## 云端记录

CloudKit 使用与 HTTP 相同的 `SyncRecordEnvelope`。`CKRecord.ID.recordName` 是不透明的
SHA-256 同步键，自定义字段为：

| 字段 | CloudKit 类型 | 内容 |
| --- | --- | --- |
| `updatedAt` | Int64 | Unix 毫秒修改时间 |
| `payload` | String | 完整 SyncChange JSON 的 Base64 |
| `payloadAsset` | Asset | 相同 JSON 的原始字节，与 payload 二选一 |

`assetThreshold` 默认 700,000 字节，按完整 Base64 内容的 UTF-8 大小选择存储方式。
客户端验证内容中的身份和时间与外层一致。

冲突按修改时间处理，严格较新才覆盖，相等保留云端版本。change tag 条件写入保证并发安全；
冲突响应中的服务端版本用于重试或修复本地数据。删除也存为带时间的 tombstone，不能物理删除
CloudKit 记录代替同步删除，也不能在离线设备进度未知时清理 tombstone。

下载内容与游标一起持久化，本地事务应用成功后才确认。应用失败、未知实体或未来 schemaVersion
的数据保持待处理。业务库与独立日志库的跨文件崩溃原子性限制见[变更追踪说明](../docs/preupdate-change-tracking.md)。

## 验证

[双设备测试](../IntegrationTests/TwoDeviceSync/README.md#cloudkit-scope)使用条件保存 fixture
验证冲突、删除、重试和 journal 恢复。它不验证 Apple CloudKit、签名或 APNs。

上线前使用带 CloudKit 权限的宿主应用和两个设备验证前后台同步、离线冲突、进程重启、
大 payload、账号切换和 zone 删除。将记录类型和字段部署到 Production 后再验证 TestFlight 构建。

参考：[Apple CKSyncEngine 示例](https://github.com/apple/sample-cloudkit-sync-engine)。
