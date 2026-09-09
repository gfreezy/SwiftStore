# iOS 16 支持

SwiftStore 的最低 iOS 版本为 16。数据库、宏、变更追踪、HTTP 同步和 CloudKit 同步均可使用；其他平台最低版本保持不变。

## 时间字段

Date 字段仍使用 `REAL` Unix 秒。宏生成的默认值、更新时间触发器和迁移流程共用 `SQLiteTimestampSQL.now`：

```sql
COALESCE(
    unixepoch('subsec'),
    CAST(strftime('%s', 'now') AS REAL)
      + CAST(substr(strftime('%f', 'now'), 3) AS REAL)
)
```

优先使用原生 `subsec`。iOS 16.4 自带 SQLite 3.39.5，原生调用返回 `NULL`，此时使用 `%s` 的 Unix 整秒加上 `%f` 的小数部分。两条路径都返回 `REAL`，不会把一分钟内的秒数当作 Unix 时间。

正式迁移会更新旧的秒级 Date 默认值、单独使用 `unixepoch('subsec')` 的默认值和旧的更新时间触发器。已有行的历史时间戳不变；重新迁移不会重复修改结构。

## CloudKit

调用入口仍为 `CloudKitSyncTransport`，应用无需按系统版本选择类型：

| 系统 | 执行方式 | 状态 |
|---|---|---|
| iOS 17+ | CKSyncEngine | journal 中保存不透明的 engineState |
| iOS 16 | CloudKit 条件保存与 zone 增量拉取 | journal 中保存 zoneChangeToken |

两者共用 `CloudKitSyncJournal`、冲突规则、待上传队列、下载 inbox 和确认逻辑。iOS 16 的保存使用 `ifServerRecordUnchanged`：遇到 change-tag 冲突时读取服务端版本，再由相同的时间规则决定重试还是接受云端版本。先完成本轮上传裁决，再分页拉取；期间新增的本地修改留到下一轮。

每页下载内容与游标在同一次 journal 写入中保存。解析或持久化失败不推进游标；游标过期会从头拉取并保留尚未确认的内容。账号变化和已存在的 zone 被删除会报错，不自动把旧账号数据传到新账号，也不把已删除的 zone 当作空白新库重建。

### iOS 16 远端通知

开启 iCloud / CloudKit、Push Notifications 和 Background Modes → Remote notifications，并调用 `registerForRemoteNotifications()`。

在宿主应用的远端通知处理方法中，将通知转交给 transport。匹配本订阅时，等待同步完成再调用后台完成回调，例如：

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    guard cloudTransport.handleRemoteNotification(userInfo) else {
        completionHandler(.noData)
        return
    }
    Task {
        do {
            _ = try await manager.sync()
            completionHandler(.newData)
        } catch {
            completionHandler(.failed)
        }
    }
}
```

`handleRemoteNotification` 只接受配置中的 subscriptionID。iOS 16 在 `automaticallySync` 开启时每 60 秒发出一次前台同步信号，交给 SyncManager 执行，用于补偿遗漏的推送；应用被系统挂起后不会依赖这个计时器，后台同步由宿主通知回调触发。`stop()` 会停止计时器、结束通知流，并隔离之前尚未返回的请求结果。重新启动会恢复持久化的队列。

## 验证

- 已在 iOS 16.4（20E247）模拟器的 SQLite 3.39.5 上运行真实包代码，验证时间回退、迁移幂等、历史时间戳保留、REAL 默认值、更新时间触发器、pre-update hook、远端写入不回传及事务回滚。
- iOS 16.4 模拟器验证了 CloudKit 适配层的编码、上传、拉取、确认和 journal 持久化，网络端使用注入的模拟实现。
- 自动测试覆盖原生时间函数优先、回退路径、CloudKit 双向冲突、分页、游标过期、失败后重试、并发入队、账号隔离、停止期间的旧请求以及强制时间校验。
- 真实 iCloud 跨设备同步仍需使用宿主应用的 CloudKit container、签名和账号验证；模拟网络测试不包含 APNs 投递或 CloudKit 服务端行为。

参考：[CloudKit zone 增量拉取](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation)、[条件保存策略](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged)。
