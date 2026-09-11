# 基于 pre-update hook 的变更追踪

ChangeTracker 使用 `sqlite3_preupdate_hook` 捕获每次行修改的新旧值，生成 `SyncChange` 完整记录和删除标记。

## 事件处理

1. SQL 语句首次 `step()` 时固定本次执行的 local/remote 来源。
2. 原生 hook 只处理已注册实体的本地写入，通过 `sqlite3_preupdate_old/new` 复制旧值和新值；不查询或修改数据库。
3. 每个事件保存自己的值数组、来源和发生时间，不保存 SQLite 的临时指针。远端事件在进入缓冲区前被过滤。
4. 等语句执行到 `SQLITE_DONE` 后，按实体和同步键整理事件。自动更新时间等触发器产生的同一键事件会合并为最终版本。
5. 真实业务修改的时间为 `max(当前时间, 已知版本 + 1ms)`；仅更新自动时间戳的无效编辑不产生日志。修正时间戳引发的业务触发器修改也被捕获，合并最终快照；不收敛的触发器会使原语句回滚。
6. 使用实体 Codable 编码最终快照，在原语句 savepoint 内追加日志及版本元数据，再释放 savepoint。删除也获得递增版本，保留无 payload 的事件。

同一语句中的同步键更新会产生旧键删除和新键写入。`REPLACE` 隐含删除、外键级联和触发器删除均通过原生事件捕获。复合 `SyncKey` 的身份由值快照提取。

## 来源与事务

`withWriteSource(.remote)` 用于给该作用域内开始执行的语句指定来源。语句的后续 `step()`、触发器和延后消费使用固定的来源，不会重新读取连接当时的标记。仅在作用域内 `prepare()`、到作用域外才首次 `step()`，不算在该作用域内执行。

连接通过单个 writer actor 串行使用；来源标记不能让 `NOMUTEX` 连接变得线程安全。

带 `RETURNING` 的写入必须执行到 `step()` 返回 false 才会完成日志处理。提前 `reset()` 或释放语句会撤销该语句的业务修改和待处理事件。捕获、编码或日志写入失败也会回滚该语句。使用 `SQLiteConnection.transaction` / `ConnectionManager.write` 时，嵌套事务和整个事务的回滚会同步撤销日志，包括远端作用域中显式嵌套的本地写入。

业务行、`__swiftstore_change_log` 和同步元数据使用同一个 SQLite 文件、同一个 writer 连接和同一个事务。日志写入失败会回滚业务行；外层事务未提交时，日志也未提交。ConnectionManager 启用同步时强制 writer 使用 `synchronous=FULL`。

原始 `BEGIN/COMMIT/ROLLBACK` 和 SAVEPOINT 同样生效。同步会等待原始事务结束后再读取或确认进度；不要在尚未结束的原始事务内等待 `sync()`。同步上传的批次合并只发生在已提交日志上，原日志禁止 UPDATE/DELETE/REPLACE，当前不做自动清理。

## 迁移和接入

ConnectionManager 启用同步时，正式迁移创建业务表和更新时间触发器。删除直接通过 pre-update hook 捕获，不需要删除触发器或中间表。

先按[版本化迁移指南](versioned-migrations.md)生成并提交迁移。包含 `updated_at` 的表会自动生成更新时间触发器，无需额外配置，也不依赖是否开启同步。直接使用组件的代码可以这样迁移：

```swift
try VersionedMigrator(connection: connection, migrations: StoreMigrations.all()).migrate()
try tracker.start()
```

表结构变更后应重新启动追踪以刷新实体列到物理列的映射。

底层注册接口是可抛错的 `setPreUpdateHook`。公开事件 `SQLiteUpdateInfo` 包含 `oldValues`、`newValues`、`source` 和 `occurredAt`。`rowId` 只适用于 rowid 表；同步身份从值快照提取。

## 平台支持

SwiftStoreSQLiteSupport 在运行时查找可选的 pre-update C 接口，不对旧系统创建必需的符号链接依赖。缺少接口时，ChangeTracker 初始化直接抛错，不会启用一个漏记删除的替代方案。

可通过 `SQLiteConnection.supportsPreUpdateHook` 检查运行时能力。iOS 平台接入和测试范围见
[iOS 16 兼容说明](ios16-compatibility.md)。

同一连接的 pre-update slot 由 SwiftStore 独占，不能同时在该连接上启用 SQLite Session 扩展。增量 BLOB 写入不在当前 SwiftStore API 范围内；捕获层会对该事件报错，避免把它当成删除。

参考：[SQLite pre-update API](https://www.sqlite.org/c3ref/preupdate_blobwrite.html)、[Session 对 hook 的占用](https://www.sqlite.org/session/sqlite3session_create.html)。
