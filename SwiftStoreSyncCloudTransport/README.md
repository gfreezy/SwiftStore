# CloudKit 同步

SwiftStore 只支持 CloudKit 私有数据库中的自定义 zone。iOS 17+ 使用 CKSyncEngine，iOS 16 使用 CloudKit Operations；宿主使用同一个 ConnectionManager API。

## 接入

为应用开启 iCloud / CloudKit，选择容器。自动远端通知还需要 Push Notifications、Background Modes → Remote notifications 和 `registerForRemoteNotifications()`。

```swift
import SwiftStore

// deviceId 从本机持久存储读取，不能每次启动重新生成。
let manager = try ConnectionManager(
    path: businessDatabaseURL.path,
    entities: [Note.self],
    syncConfig: SyncOptions(
        deviceId: deviceId,
        schemaVersion: 1,
        cloudKit: CloudKitSyncConfiguration(
            containerIdentifier: "iCloud.com.example.app",
            zoneName: "SwiftStoreSyncChanges",
            recordType: "SwiftStoreSyncChange"
        )
    )
)
try await manager.migrate(migrations: try StoreMigrations.all(bundle: .module))
let result = try await manager.sync()
```

`automaticallySync` 默认 true，迁移完成后启动自动同步；本地事务提交也会触发同步。false 表示由宿主调用 `sync()`。多个并发 `sync()` 等待同一次运行。`await manager.stopSync()` 停止网络并使旧回调失效，本地写入继续记录；下一次 `sync()` 恢复。使用 `await manager.lastSyncError` 查看最近的同步错误，`await manager.syncState` 查看账号和连续确认的 `pushCursor`。

`SyncConfiguration(batchSize:)` 限制合并前的原始事件数，范围 1...200，默认 200。每批只保留同一键的最后一条完整快照或删除记录，原日志不变。上传确认数与冲突数按批次裁决项计数，不等于用户编辑次数。

每个本地数据库只能有一个启用同步的 ConnectionManager / writer。应用与扩展不能同时为同一文件启动同步。不同数据库使用不同 zone 和 subscriptionID，避免共享原生引擎队列或互相消费不同 schema 的记录。本地数据库不放进 iCloud Drive。

## iOS 16 通知与前台恢复

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    Task { @MainActor in
        guard manager.handleRemoteNotification(userInfo) else {
            completionHandler(.noData)
            return
        }
        do {
            let result = try await manager.sync()
            completionHandler(result.pulledCount > 0 ? .newData : .noData)
        } catch {
            completionHandler(.failed)
        }
    }
}
```

通知只是一条“可能有变化”的信号，匹配配置的 subscriptionID 后按 zone token 增量拉取。iOS 16 没有常驻轮询计时器；宿主在进入前台、用户刷新时也调用 `sync()`，补偿丢失或合并的后台通知。后台通知不保证送达，也不保证应用始终有运行时间。iOS 17+ 由 CKSyncEngine 安排自动收发。

## 旧版迁移

4.0.0 的同步 API 已调整：移除了 HTTP / 自定义 `SyncTransport`、独立状态存储、enqueue / acknowledge 和手动清除拒绝项等入口。使用上面的 `SyncOptions(cloudKit:)`。业务实体、已发布的业务迁移、云端 recordName 和 payload 格式保持可读。

**已有 CloudKit 安装必须指定旧文件路径。** 暂停旧同步实例，再打开新 manager：

```swift
let migration = LegacySyncMigration(
    changeLogDatabase: oldChangeLogURL,
    cloudKitJournal: oldStateDirectory.appendingPathComponent("journal.plist"),
    backupDirectory: backupDirectory
)
let options = SyncOptions(
    deviceId: deviceId,
    schemaVersion: schemaVersion,
    cloudKit: CloudKitSyncConfiguration(containerIdentifier: containerIdentifier),
    migration: migration
)
```

旧日志默认路径为 `app_changelog.sqlite`（业务库 `app.sqlite`）；自定义路径必须传原值。迁移核对 journal 中原账号及 container/zone/recordType，先为业务库、旧日志（包括 WAL 内容）和 journal 创建一致备份，再导入日志、待上传记录、拒绝候选、下载 inbox、已确认版本和删除时间。完整迁移在一个业务库事务内完成，成功标记和数据一起提交；再次启动不会重复导入。

原 change ID、payload、时间不修改。旧“已入队”水位和旧下载 token 不作为新确认状态使用：保守重放保留的日志，重新拉取 zone。业务库中未被日志或已应用云端版本覆盖的现存行会补一条原时间快照。旧版本跨两个数据库提交时已经丢失、且所有旧文件均无记录的删除，无法凭现存行恢复。

原文件和备份不会自动删除。检测到默认旧日志或旧删除元数据却未提供迁移参数时，初始化报错；使用过自定义日志路径的应用必须主动传入迁移参数。HTTP 后端历史不支持自动转入某个 iCloud 账号。

## 数据与恢复

业务行、追加日志、上传游标、云端版本元数据及下载检查点都在同一个 SQLite 文件。启用同步的 writer 使用 WAL + synchronous=FULL。禁止单独删除内部同步表或更新日志；应整体备份/恢复该数据库。

远端修改时间大于本地则应用，小于则忽略；时间相等且内容不同采用 CloudKit 已提交版本。相同内容不重复写。远端应用保留原时间且不生成新日志。本地真实编辑的版本为 `max(当前时间, 已知版本 + 1ms)`，删除后重新创建同一键也继续递增。

账号改变、已有 zone 消失、物理删除记录、未知实体、未来 schema、损坏 payload 或本地约束失败会保留数据并停止相关进度。修复原因后重试 `sync()`，没有跳过坏事件的入口。账号切换应选择原账号对应的本地数据库，不能把旧库静默绑定到新账号。普通 token 过期会保留业务数据并全量重拉；没有出现在云端的本地行不因此删除。

删除采用带修改时间的逻辑 tombstone，不能用 CloudKit 物理删除代替。当前不自动清理日志或 tombstone。

`ntpToleranceMs` 默认 5000，必须为正数。进程首次同步共享一次 NTP 校验（含回退最多 3 秒）；网络失败允许继续，成功测得时间偏差超过阈值则阻止同步。修正系统时间后重启应用重新校验。

## 云端记录

`CKRecord.ID.recordName` 是实体名与同步键的 SHA-256；CloudKit 自定义字段保持原格式：

| 字段 | CloudKit 类型 | 内容 |
| --- | --- | --- |
| updatedAt | Int64 | 业务修改时间，Unix 毫秒 |
| payload | String | 完整 SyncChange JSON 的 Base64 |
| payloadAsset | Asset | 相同 JSON 原始字节，与 payload 二选一 |

`assetThreshold` 默认 700,000 字节，按 Base64 的 UTF-8 大小选择。CloudKit `modificationDate` 是保存时间，不能代替离线业务编辑时间。两个驱动均使用 change tag 条件保存；发生冲突时，库比较服务端版本，决定保留云端或携带新 tag 重试。

## 验证范围

自动测试使用真实 SQLite、生产共享裁决逻辑和 Operations 驱动，以及模拟 CloudKit 网络接口。覆盖双端离线编辑、删除、丢失响应、部分成功后重启、下载失败回放、token 过期、账号切换和 2,610 条删除的分批同步。Swift 6.3+ 的 macOS 测试还通过独立进程突然退出验证数据与日志的崩溃原子性。

这些测试不包含真实 iCloud、APNs 或 CKSyncEngine 的系统调度。带容器权限的宿主仍需用两个设备验证前后台同步、离线冲突、账号变化和 TestFlight 的 Production schema。

参考：[CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)、[Apple 示例](https://github.com/apple/sample-cloudkit-sync-engine)、[条件保存](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged)。
