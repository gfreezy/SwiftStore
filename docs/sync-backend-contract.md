# 同步后端约定

自定义 transport 实现 `SyncTransport`，负责持久化传输状态和冲突裁决。
SyncManager 应用 transport 返回的已提交版本，不重复裁决业务时间。

## 记录与冲突

`SyncRecordEnvelope` 统一编码 HTTP 和 CloudKit 的记录：

| 字段 | 含义 |
| --- | --- |
| `key` | 实体名长度前缀、实体名和 syncKey 的 SHA-256；固定 64 位十六进制字符串 |
| `updatedAt` | Unix 毫秒 Int64；业务记录取更新时间，删除取删除时间 |
| `payload` | 完整 SyncChange JSON 字节，包含修改 ID、实体、操作和业务内容 |

传入时间严格大于已提交时间才覆盖，相等保留已提交版本。这是整条记录的覆盖，
不按设备、schemaVersion、修改 ID 或删除类型打破平局。时间校验默认容差为 ±5 秒。每个应用进程在第一次同步时联网校验一次，
所有数据库、同步层和后端共享结果，并发调用合并；后续调用不再联网。
首次校验总等待上限为 3 秒，包含 DNS 解析和服务器回退。网络失败或超时记录日志后放行，
该结果同样缓存到进程退出，不在每轮同步重试。成功测得偏差超限时仍阻止同步，
各调用方按自己的正数 `ntpToleranceMs` 判断缓存偏差；修复系统时间后需重新启动应用再校验。
缓存不写入磁盘，新进程会重新检查。`stop()`、重新创建连接或切换数据库不会重置缓存。

| 环节 | HTTP | CloudKit |
| --- | --- | --- |
| 冲突裁决 | 服务器事务内比较时间并追加 sequence | 适配器比较时间，通过 change tag 条件保存 |
| 下载进度 | 服务端 sequence cursor | CKSyncEngine 状态或 iOS 16 zone token |
| 拒绝项修复 | 正常 pull，缺失时按 key 补查 | 正常 fetch，缺失时使用冲突响应携带的版本 |
| 记录存储 | payload 为 Base64 | recordName 为 key；payload 用 Base64 或 CKAsset |

CloudKit 的 `serverRecordChanged` 只表示条件写入失败。若本地时间仍较新，应使用服务器返回的
版本信息重试；否则记录业务拒绝。普通 fetch 不裁决待上传修改。

## 生命周期

```swift
var remoteChanges: AsyncStream<Void> { get }
func configureTimeValidation(toleranceMs: Int64) async throws
func start(deviceId: UUIDV7) async throws
func stop() async
func enqueue(_ changes: [SyncChange]) async throws
func syncNow() async throws -> SyncCycleResult
func acknowledge(_ result: SyncCycleResult) async throws
```

- `remoteChanges` 只发送同步信号，下载内容通过 `syncNow()` 返回。
- `start` 和 `stop` 应幂等；停止时结束通知流，重新启动时恢复队列并提供新的流。
- `enqueue` 不执行网络请求，返回成功前必须持久化。SyncManager 随后推进本地上传游标。
- 每轮固定待上传列表，全部完成裁决后才下载。期间新增的修改留到下一轮。
- 上传批次确认、下载内容和游标分别持久化；后续失败不能撤销已确认的上传或丢失下载。
- `acknowledge` 只清除明确确认的结果。自定义持久化 transport 必须实现它，不能依赖空的默认实现。

## 返回结果与确认

`SyncCycleResult` 的字段约定：

| 字段 | 内容 |
| --- | --- |
| `pulled` | 每个 key 最新已知的已提交版本，包括本机上传的服务端版本 |
| `pushed` | 已提交本地修改的 ID |
| `conflicts` | 被拒绝或取代的本地修改，用于上传处理统计 |
| `pendingChanges` | 全部尚未提交的本地修改 |
| `rejectedKeys` | 尚待本地应用的持久化修复任务 |

HTTP 的拒绝按本批 key 关联本地修改，重试也可能计入 conflicts。它不代表每次都发生了内容冲突。

`RejectedChange` 关联被拒绝的修改、可选 `serverVersion` 和 `isResolved`。
两端的 `SyncRejectionStore` 保存这些记录，不负责选择赢家：transport 先验证投递顺序，
再用 pull 或补查内容解决拒绝项。HTTP 用 sequence 下界，CloudKit 用已知记录版本及系统字段，
阻止迟到的历史内容回退数据。

有服务器内容不代表已经应用。上传回执可以先确认，拒绝任务必须等对应版本在本地应用成功后
才能清除；旧 ACK 必须匹配拒绝修改 ID 和已应用版本 ID，不能清除后来的任务。

SyncManager 以 remote 来源事务落库。对仍有待上传修改或网络期间新增本地日志的 key，暂缓应用和确认。
应用失败、未知实体或未来 schemaVersion 保留待处理结果，修复或升级后重试。

HTTP 服务端的精确消息格式、分页和重试规则见 [HTTP 接口](http-sync-server-api.md)；
CloudKit 的账号隔离及宿主接入见 [CloudKit 文档](../SwiftStoreSyncCloudTransport/README.md)。
