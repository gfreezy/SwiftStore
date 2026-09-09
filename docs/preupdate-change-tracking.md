# 基于 pre-update hook 的变更追踪

ChangeTracker 使用 `sqlite3_preupdate_hook` 捕获每次行修改的新旧值，继续生成原有 `SyncChange` 完整记录和删除标记。CloudKit、HTTP 协议及时间冲突规则保持一致。

## 事件处理

1. SQL 语句首次 `step()` 时固定本次执行的 local/remote 来源。
2. 原生 hook 只处理已注册实体的本地写入，通过 `sqlite3_preupdate_old/new` 复制旧值和新值；不查询或修改数据库。
3. 每个事件保存自己的值数组、来源和发生时间，不保存 SQLite 的临时指针。远端事件在进入缓冲区前被过滤。
4. 等语句执行到 `SQLITE_DONE` 后，按实体和同步键整理事件。自动更新时间等触发器产生的同一键事件会合并为最终版本。
5. 使用现有实体 Codable 编码生成日志；删除时间使用事件捕获时间，而不是延后处理时间。

同一语句中的同步键更新会产生旧键删除和新键写入。`REPLACE` 隐含删除、外键级联和触发器删除均通过原生事件捕获。复合 `SyncKey` 仍可使用唯一索引，不要求改成 Session 扩展所需的显式主键。

## 来源与事务

`withWriteSource(.remote)` 仍用于给该作用域内开始执行的语句指定来源。语句的后续 `step()`、触发器和延后消费使用固定的来源，不会重新读取连接当时的标记。仅在作用域内 `prepare()`、到作用域外才首次 `step()`，不算在该作用域内执行。

连接仍通过单个 writer actor 串行使用；来源标记不能让 `NOMUTEX` 连接变得线程安全。

带 `RETURNING` 的写入必须执行到 `step()` 返回 false 才会完成日志处理。提前 `reset()` 或释放语句会撤销该语句的业务修改和待处理事件。捕获、编码或日志写入失败也会回滚该语句。使用 `SQLiteConnection.transaction` / `ConnectionManager.write` 时，嵌套事务和整个事务的回滚会同步撤销日志，包括远端作用域中显式嵌套的本地写入。

业务库与日志库仍是两个 SQLite 文件，当前正常错误回滚机制不提供跨文件的崩溃原子提交。这次变更没有把日志迁入业务库。

## 迁移和接入

ConnectionManager 启用同步时，正式迁移创建业务表和更新时间触发器。删除直接通过 pre-update hook 捕获，不需要删除触发器或中间表。

直接使用组件的代码可以这样迁移：

```swift
let migrator = Migrator(
    connection: connection,
    createUpdateTrigger: true
)
try migrator.apply(migrator.plan(for: entities))
try tracker.start()
```

表结构变更后应重新启动追踪以刷新实体列到物理列的映射。

底层注册接口是可抛错的 `setPreUpdateHook`。公开事件 `SQLiteUpdateInfo` 包含 `oldValues`、`newValues`、`source` 和 `occurredAt`。`rowId` 只适用于 rowid 表；同步身份从值快照提取。

## 平台支持

SwiftStoreSQLiteSupport 在运行时查找可选的 pre-update C 接口，不对旧系统创建必需的符号链接依赖。缺少接口时，ChangeTracker 初始化直接抛错，不会启用一个漏记删除的替代方案。

已在 iOS 16.4 模拟器的系统 SQLite 3.39.5 上验证 pre-update hook 的全部所需接口及插入、更新、删除回调。时间表达式优先使用 `unixepoch('subsec')`，在该运行时回退到 `strftime`，继续返回 `REAL` 小数秒。检查入口为 `SQLiteConnection.supportsPreUpdateHook`；接入说明见 [iOS 16 兼容说明](ios16-compatibility.md)。

同一连接的 pre-update slot 由 SwiftStore 独占，不能同时在该连接上启用 SQLite Session 扩展。增量 BLOB 写入不在当前 SwiftStore API 范围内；捕获层会对该事件报错，避免把它当成删除。

参考：[SQLite pre-update API](https://www.sqlite.org/c3ref/preupdate_blobwrite.html)、[Session 对 hook 的占用](https://www.sqlite.org/session/sqlite3session_create.html)。
