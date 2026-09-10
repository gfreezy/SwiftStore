# HTTP 同步服务端接口

同步分为三个接口。客户端每轮固定待上传列表，分批全部处理完成后才开始分页 pull；同步期间的新修改留到下一轮。只有 pull 完成后仍未解决的拒绝项才需要补查。

| 接口 | 专用参数 | 成功响应 body |
| --- | --- | --- |
| `POST /sync/v1/push` | body：changes | rejected |
| `GET /sync/v1/pull` | query：cursor、可选 limit | changes、cursor、hasMore |
| `POST /sync/v1/records` | body：keys | records |

文中的 payload 使用占位符，实际请求必须发送客户端生成的完整 Base64 内容。

## 公共信息

- 三个接口都携带 query `namespace=<授权数据集>`，例如 `/sync/v1/push?namespace=account-123`。按 URL 查询参数编码，支持非 ASCII 数据集名。
- 请求头使用 `Authorization: Bearer <token>`。服务器必须验证 Token 对 namespace 的权限，不能信任客户端自行声明的范围。
- POST 使用 `Content-Type: application/json`。GET 不带 body；响应使用 JSON。
- API 版本由路径 `/v1` 指定。
- **所有 HTTP 200 响应都必须带 `X-SwiftStore-Server-ID` 头**，其值是服务器持久化的数据库实例 ID，使用非空、无空白的可打印 ASCII 字符串。
- 首次请求可以省略该实例头。客户端保存首次成功响应的值，之后三个接口的请求都带同名头。服务器必须在处理上传之前校验，若与自身实例 ID 不一致则返回 409。
- 数据库实例 ID 不能随服务进程重启改变。数据库恢复后历史若不能连续，应更换实例 ID；不能静默接受旧 cursor 或旧上传状态。

namespace 最多 200 UTF-8 字节，不能为空。服务端可按业务定义更严格规则。生产环境使用 HTTPS。

## 不透明记录

上传记录只含 key（同步身份 SHA-256）、updatedAt（Unix 毫秒安全整数）、payload（Base64 不透明内容）。服务器下发时额外带正整数 sequence，表示服务端提交顺序，不参与冲突时间比较。

客户端生成 key：实体名 UTF-8 字节长度的 8 字节大端整数 + 实体名 UTF-8 + syncKey 原始字节，整体 SHA-256 后转为小写十六进制字符串。服务器直接保存 key，不需要知道实体类型、表名、字段或删除操作。

HTTP 和 iCloud 客户端共用 SyncRecordEnvelope 编码，生成相同的 key、updatedAt 和 payload 字节。服务器不能解码或重编码 payload，也不能把 updatedAt 改成服务器接收时间。时间和 payload 在重试中保持稳定。payload 内可包含客户端自己的修改 ID，但服务器不解码、不使用它。

## 批量上传

`POST /sync/v1/push?namespace=account-123`

```json
{
  "changes": [
    {
      "key": "d0886d7121d5a392ec133e9ee64fad94371f279be2951944bb7db40a6124d0c7",
      "updatedAt": 1788307200125,
      "payload": "<Base64 编码的 SyncChange>"
    }
  ]
}
```

- changes 最多 500 条；客户端默认每批 100 条，不发送空上传批次。
- 同一 key 可以有多个修改，服务器按请求数组顺序处理，不需要区分它们的修改 ID。
- 整批数据与增量日志提交成功后才能返回 200，无需单独存储修改幂等回执。

成功响应（整个批次已处理）：

```json
{
  "rejected": []
}
```

普通冲突属于成功处理，不返回 HTTP 409。

需要客户端纠正的项采用 `{"key":"不透明同步key","sequence":123}`，sequence 是整批处理结束时该 key 的当前赢家序号。

- rejected 必须出现，空时为 []；key 必须来自本批上传且不能重复，sequence 大于 0。
- 批内某次修改的 updatedAt 不大于当前值时，保留服务器内容，并将该 key 加入拒绝集合。整批处理完成后，再为集合中的每个 key 读取最终 sequence。
- 同一个 key 可以既有成功修改也有被忽略的修改；响应按 key 去重，不报告每条修改的独立接受结果。
- **HTTP 200 确认整个批次**。客户端清除本批 outbox，并把拒绝 key 与该 key 本批的本地修改关联，持久化修复任务。上传期间新产生的修改不属于这次确认或拒绝。
- 某一批失败后，不开始 pull；保留尚未确认的数据重试。已经成功的前几批不会重传。

## 上传阶段的冲突规则与安全重试

服务器只需按时间判断，不需要区分新修改和网络重试：

```text
rejectedKeys = set()
begin transaction
for incoming in changes:
    current = latest(namespace, incoming.key)
    if current does not exist OR incoming.updatedAt > current.updatedAt:
        save incoming as latest
        append delta with next server sequence
    else:
        retain current unchanged
        rejectedKeys.add(incoming.key)
rejected = [{ key, sequence: latest(namespace, key).sequence }
            for key in rejectedKeys]
commit transaction
return HTTP 200 { rejected }
```

相同时间保留已提交版本。服务器不需要比较 payload，也不根据设备、schema、删除状态或修改 ID 排序。同一 key 的读取、比较、覆盖必须原子化。推荐以 namespace 为范围串行化批次事务，使 sequence 的分配顺序与可见提交顺序一致，避免漏拉。

**严格大于才更新，本身就能安全重试：**

- 首次上传已成功但响应丢失：重试时间与当前相同，数据不更新、不追加增量，只返回该 key 的纠正信息。
- 期间服务器已有更新版本：重试时间更早，仍保留服务器新版本。
- 同 key、同时间、不同 payload：保留已提交内容，返回拒绝 key，不必读取业务数据判断是不是重试。
- 重试可能让原本成功的上传被统计为需要纠正的项，这是允许的；普通 pull/补查取得的仍是服务器当前版本。

删除标记和当前记录必须保留，否则服务器失去时间下界后，旧重试可能再次被当作新数据接受。

## 分页 pull

`GET /sync/v1/pull?namespace=account-123&cursor=0&limit=100`

cursor 首次 0，后续用已保存的下载位置；它独立于本地上传日志位置。limit 可省略，默认 100，范围 1～500。

```json
{
  "changes": [
    {
      "key": "d0886d7121d5a392ec133e9ee64fad94371f279be2951944bb7db40a6124d0c7",
      "updatedAt": 1788307200125,
      "payload": "<Base64 编码的 SyncChange>",
      "sequence": 101
    }
  ],
  "cursor": 101,
  "hasMore": false
}
```

```sql
SELECT sequence, key, updated_at, payload
FROM sync_deltas
WHERE namespace = :authorized_namespace AND sequence > :cursor
ORDER BY sequence ASC
LIMIT :limit_plus_one;
```

多取一条判断 hasMore，返回前 limit 条。changes 按 sequence 严格递增；cursor 等于本页最后实际返回的 sequence，空页保持请求值。hasMore=true 时 cursor 必须推进，不能直接跳到全局最大值。

pull 读取已提交数据，不能用落后于刚完成上传的副本。客户端一轮内连续取页，直到 hasMore=false，再处理缺失的拒绝项。每页与 cursor 原子保存，后续页失败或重启从检查点继续，无须重传已确认上传。

某个 key 出现在历史页中不代表已解决拒绝：必须 sequence 不小于拒绝项的 sequence。客户端暂缓应用本轮上传 key 的历史页，直到 pull 完成，避免刚成功的本地修改被旧页临时覆盖。

当前协议没有历史截断或快照恢复接口。必须保留从 cursor 0 起可重放的历史及全部当前记录，不能按固定天数清理长期离线设备仍需的数据。

## 只补查缺失 key

`POST /sync/v1/records?namespace=account-123`

```json
{
  "keys": [
    "d0886d7121d5a392ec133e9ee64fad94371f279be2951944bb7db40a6124d0c7"
  ]
}
```

```json
{
  "records": [
    {
      "key": "d0886d7121d5a392ec133e9ee64fad94371f279be2951944bb7db40a6124d0c7",
      "updatedAt": 1788307200125,
      "payload": "<Base64 编码的 SyncChange>",
      "sequence": 101
    }
  ]
}
```

- keys 去重，每批最多 500 个。
- records 必须恰好覆盖这些 key，每个 key 返回当前已提交完整记录及 sequence，不能返回落后于上传裁决的副本。
- 拒绝项对应的服务器记录必须存在，包括删除标记。缺失说明服务器状态不满足协议，应报错，不能返回成功空结果。
- 补查不写入同步流，也不推进下载 cursor。
- 只有正常 pull 没覆盖的拒绝 key 才会补查。例如赢家已在请求 cursor 之前，增量不再返回它。
- 客户端校验最低赢家 sequence 和每 key 已知最大 sequence，避免旧副本或迟到历史页回退数据。这是投递顺序校验，不是再比较一次 updatedAt。

## 删除

删除使用相同的 key、updatedAt、payload 包装，payload 内的操作为 delete。
服务器保留该记录，不物理删除；旧上传按时间被拒绝，更晚的重建正常替换。
未知 entity/schema 也原样保存和下发，由客户端决定何时应用。

## 客户端统一流程

1. 本地修改进入持久化 outbox，才推进本地日志进度。
2. 固定本轮上传列表，逐批 push。每批成功立即保存确认和拒绝项，新编辑留到下一轮。
3. 本轮上传全部完成后，分页 pull 到 hasMore=false。
4. pull 优先解决拒绝项，其余通过 records 补查；iCloud 共用拒绝记录逻辑，但已携带服务器内容，省去补查。
5. 应用已裁决版本时标记 remote，不生成新的上传日志。同 key 仍有待上传的新编辑时暂缓应用。
6. 成功应用对应服务器版本后才清除拒绝项。上传回执 ACK、补查失败、未来 schema 或应用失败都不能丢掉修复任务。

服务器不需要 ACK 接口。客户端已保存的业务数据、变更日志和同步状态文件必须配套，一份状态文件不能被多个活跃 transport 共享。

## 时间与错误

客户端在每个进程第一次同步时进行一次 NTP 校验（默认允许 ±5 秒），并发及后续调用复用结果。总等待上限为 3 秒；网络失败或超时记录日志后放行，直到新进程启动才重新检查。成功测得偏差超限时仍拒绝同步。服务端可拒绝过远的未来 updatedAt，但**不能要求离线历史修改接近服务器当前时间**。时间校验缩小误判范围，不代替拒绝后的数据修复。

| HTTP 状态 | 用途 |
| --- | --- |
| 400 | 请求格式/版本错误、时间超范围 |
| 401 / 403 | Token 无效或 namespace 未授权 |
| 409 | 数据库实例 ID 不匹配或 cursor 无法恢复，不能用于普通冲突 |
| 413 | 请求过大 |
| 429 | 限流 |
| 500 / 503 | 存储故障或临时不可用 |

非 200 或无效响应不会确认本次请求。若上传已成功而后续 pull/补查失败，已确认上传仍保持完成，下载与修复可重试。客户端当前不自动刷新 Token，也不根据 Retry-After 调整退避。

推荐存储 sync_records（当前版本）、sync_deltas（提交序列）、metadata（数据库实例 ID）。无需实体表或设备拒绝收件箱。

## 验证

[双设备集成测试](../IntegrationTests/TwoDeviceSync/README.md)覆盖分页、冲突、响应丢失、重启和账号隔离。
实现自己的服务端时，应使用同样的场景验证事务、sequence 顺序和拒绝项修复。
客户端接口约定见[同步后端约定](sync-backend-contract.md)。
