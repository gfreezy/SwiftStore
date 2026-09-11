# iOS 16 支持

SwiftStore 的最低 iOS 版本为 16。数据库、宏、变更追踪和 CloudKit 同步均可使用。其他平台要求见 [README](../README.md#requirements)。

## 时间字段

Date 字段使用 `REAL` Unix 秒。宏生成的默认值、更新时间触发器和迁移流程共用 `SQLiteTimestampSQL.now`：

```sql
COALESCE(
    unixepoch('subsec'),
    CAST(strftime('%s', 'now') AS REAL)
      + CAST(substr(strftime('%f', 'now'), 3) AS REAL)
)
```

优先使用原生 `subsec`。iOS 16.4 自带 SQLite 3.39.5，原生调用返回 `NULL`，此时使用 `%s` 的 Unix 整秒加上 `%f` 的小数部分。两条路径都返回 `REAL`，不会把一分钟内的秒数当作 Unix 时间。

修改已发布表的时间默认值或触发器时，应通过[版本化迁移](versioned-migrations.md)升级，保留历史时间戳。

## CloudKit

调用入口为 `ConnectionManager` 的 `SyncOptions(cloudKit:)`，应用无需按系统版本选择驱动：

| 系统 | 执行方式 | 下载状态 |
|---|---|---|
| iOS 17+ | CKSyncEngine 原生调度 | SQLite 中保存不透明的 State.Serialization |
| iOS 16 | CloudKit 条件保存与 zone 增量拉取 | SQLite 中保存 CKServerChangeToken |

两者共用同一份追加日志、固定批次合并、时间冲突规则和连续上传游标。没有持久化的 payload outbox / inbox 副本。iOS 16 每页数据与 token 在同一事务提交；iOS 17+ 等待下载数据提交后才返回 delegate，随后保存 SDK 状态。下载失败时丢弃当前引擎后续回调，保留旧检查点用于重放。

iOS 16 升级到 iOS 17 时保留业务数据、日志和 pushCursor，只清空下载状态并全量重拉；不能把 Operations token 当作 CKSyncEngine serialization。

两条路径都利用 CloudKit change tag 条件保存。较新的业务修改才能替换云端记录，时间相等采用云端版本。账号变化、已有 zone 被删除会保留本地数据并报错；普通 token 过期会全量重拉，不把云端缺失行当成删除。

### 通知和前台恢复

iOS 16 通过 CKDatabaseSubscription 接收变更信号。宿主转发 `manager.handleRemoteNotification(userInfo)`，匹配订阅后等待 `manager.sync()` 再结束后台回调。进入前台时也调用 `sync()` 补偿未送达通知；没有常驻轮询。完整接入代码见 [CloudKit 接入](../SwiftStoreSyncCloudTransport/README.md#ios-16-通知与前台恢复)。

### 验证范围

最低部署版本 16.0 的 iOS 目标编译验证 API 可用性。自动测试以真实 SQLite 和模拟 CloudKit 网络接口验证 Operations 路径及共享逻辑；不代表已经在 iOS 16 真机上完成 iCloud、APNs 和后台运行验证。

参考：[CloudKit zone 增量拉取](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation)、[条件保存策略](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged)。
