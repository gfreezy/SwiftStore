# 统一同步后端接口

CloudKit 与 HTTP 都通过 SyncTransport 提供“上传阶段裁决 → 正常 pull → 拒绝项修复 → 本地应用”的流程。SyncManager 不再比较谁更新，只应用适配器提供的已提交结果。

## 冲突规则

业务记录使用 updatedAt，删除使用删除时间，取整为 Unix 毫秒。传入时间严格更大才覆盖，相等保留已提交版本；不按设备、schema、payload 或删除类型排序。时间校验强制开启，默认 ±5 秒。

| 环节 | HTTP | CloudKit |
| --- | --- | --- |
| 裁决 | 服务器批次事务比较时间 | 适配器在准备上传/处理上传响应时比较时间 |
| 并发保障 | 原子比较、更新、追加服务端 sequence | CloudKit change tag 条件写入；本地仍较新则用新 tag 重试 |
| 上传结果 | 200 确认整个批次，附 rejected 元信息 | 逐项处理成功/失败，只将确定输掉的修改记为 rejectedKeys |
| 下载进度 | 服务端 sequence cursor | CKSyncEngine 状态或 iOS 16 zone token |
| 拒绝修复 | 优先 pull，缺失的 key 通过 records 接口补查 | 优先 pull，缺失时复用冲突响应的服务器内容 |
| 本地应用 | SyncManager 事务写入，来源标记 remote | 相同 |

`serverRecordChanged` 只是条件写入失败，不等于业务拒绝。CloudKit 适配器取得服务器记录后，在上传流程里比较时间：本地较新保留待上传并重试，否则产生拒绝记录。普通 fetch 只记录已提交版本及系统字段，不裁决待上传修改。enqueue 只持久化排队，上传准备阶段合并同 key 的待上传候选。

## 共用不透明记录

两端共同使用 SwiftStoreSync 的 `SyncRecordEnvelope`，统一生成和校验 key、updatedAt、payload：

- key：实体名长度前缀 + 实体名 + syncKey 的 SHA-256，固定 64 个十六进制字符。HTTP 用外层 key 字段，CloudKit 用原生 CKRecord.ID.recordName，不重复存储 key 字段。
- updatedAt：Unix 毫秒 Int64，普通数据取业务更新时间，删除取删除时间。
- payload：稳定编码的完整 SyncChange JSON 字节；包含客户端的修改 ID、实体信息、操作和业务内容。服务器不理解这些字段。

HTTP 将 payload 编码为 Base64；CloudKit 小记录也使用 Base64 String，大记录通过 CKAsset 保存相同的原始 JSON 字节。两端解码时检查不透明内容中的身份、时间是否与外层一致。CloudKit 不再创建 id、entityType、syncKey、operation、deviceId、logicalClock、schemaVersion、createdAt 等独立自定义字段。

CloudKit 的条件写入仍需要原生 change tag，但上传裁决只比较时间：即使服务器记录中的客户端修改 ID 相同，也不据此确认重试成功，相同时间统一产生携带服务器版本的拒绝修复项。实际成功写入的 CloudKit 回调仍按本地修改 ID 确认对应 outbox，避免清除期间的新编辑；这是客户端队列确认，不是修改 ID 幂等裁决。

## 共用拒绝记录

```swift
public struct RejectedChange: Codable, Sendable {
    public let change: SyncChange
    public var changeID: UUIDV7 { change.id }
    public fileprivate(set) var serverVersion: SyncChange?
    public fileprivate(set) var isResolved: Bool
}
```

两端 journal 都持久化 SyncRejectionStore，它不比较 updatedAt、不选择赢家。适配器验证投递的新旧关系后，才把普通 pull 或补查结果交给它解决拒绝项。

HTTP 的 push 响应只含 rejected 数组，各项仅包含 key 和当前赢家 sequence；上传外层只含 key、updatedAt、payload，服务器不使用修改 ID。客户端用 sequence 判断某条历史 pull 是否已经覆盖此次裁决；仅 key 相同不够。CloudKit 的拒绝记录可以直接携带 serverVersion，但先等待本轮普通 fetch，再使用缺失项的缓存内容。

拒绝记录有内容并不代表已应用。上传回执可以先确认，拒绝修复任务只能在对应服务器版本实际应用成功后清除。旧 ACK 必须同时匹配拒绝修改 ID 与已应用版本 ID，不能清除同 key 后来产生的拒绝任务。

## 生命周期

```swift
func enqueue(_ changes: [SyncChange]) async throws
func syncNow() async throws -> SyncCycleResult
func acknowledge(_ result: SyncCycleResult) async throws
```

- enqueue 成功表示 outbox 已持久化，SyncManager 才推进本地 lastLocalClock。
- syncNow 返回 pulled、pushed、conflicts、pendingChanges 和 rejectedKeys。pushed/conflicts 用于客户端上传处理统计；HTTP 的拒绝按 key 关联本批本地修改，重试也可能被计入，不代表每次都发生了实际内容冲突。rejectedKeys 独立保留尚待本地应用的修复任务。
- HTTP 每轮固定待上传列表，逐批 push 全部确认后才分页 pull 到 hasMore=false，之后补查缺失 key。上传期间新编辑留到下一轮。每批确认和每页下载分别原子持久化，后续失败不恢复已确认的 outbox。
- CloudKit 显式同步同样固定本轮修改 ID，全部上传候选完成裁决后才 fetch，期间的新编辑下一轮发送；CKSyncEngine 后台调度同样通过上传准备与上传结果回调裁决。网络错误保留待上传，不能误判成业务拒绝。
- 各 key 的 pulled 只交付最新已知已提交版本。未解决拒绝项挡住同 key 的旧历史页。
- pendingChanges 包含全部尚未提交的本地修改。SyncManager 还检查网络期间新增的本地日志，对这些 key 暂缓应用、不 ACK。
- 应用失败、未知实体或未来 schema 保留收件箱和拒绝记录；成功应用后才通过 acknowledge 清理。自己设备产生的服务器版本也可以用于恢复被拒绝的后续编辑。

CloudKit 保留已提交版本与 systemFields，防止使用较新 tag 上传旧候选，以及处理迟到的旧回调。HTTP 保留每 key 最大已接收 sequence，补查不改变 cursor。这些是传输进度与缓存，不是第二套业务冲突裁决。

所有 CloudKit 参与设备必须使用同一时间规则，删除通过 tombstone 表示。服务端接口见 [HTTP 同步服务端接口](http-sync-server-api.md)。

HTTP 使用三个独立接口：POST /sync/v1/push、GET /sync/v1/pull、POST /sync/v1/records。namespace 是公共 query 参数，数据库实例 ID 是公共头 X-SwiftStore-Server-ID，版本由 /v1 路径指定。

HTTP 服务器无需修改幂等回执表：仅 updatedAt 严格增加才更新并追加增量，重复上传自然不再写入。相同时间一律保留服务器内容并返回拒绝 key。修改 ID 仍保留在客户端及不透明 payload 内，用于本地队列、应用和 ACK 的关联。
