# SwiftStoreCore

SwiftStore 的核心层，提供 SQLite 数据库连接、查询构建和迁移功能。

## 概述

此 package 是 SwiftStore 框架的核心实现，封装了 SQLite 数据库操作，提供类型安全的查询 API 和自动 schema 迁移能力。

## 主要功能

### SQLite 连接

```swift
let connection = try SQLiteConnection(path: "database.sqlite")
```

支持选项：
- WAL 模式
- 外键约束
- 自定义配置

### CRUD 操作

```swift
// 插入
try connection.insert(user)

// 查询
let users: [User] = try connection.query {
    $0.where(\.age > 18)
      .orderBy(\.name)
      .limit(10)
}

// 更新
try connection.update(user)

// 删除
try connection.delete(user)
```

### 查询构建器

支持类型安全的查询构建：

```swift
// 条件查询
let result: [User] = try connection.query {
    $0.where(\.email == "test@example.com")
}

// 复合条件
let result: [User] = try connection.query {
    $0.where(\.age >= 18 && \.status == "active")
      .orderBy(\.createdAt, .desc)
}
```

### Schema 迁移

自动迁移系统支持：
- 添加新表
- 添加新列
- 创建索引
- 删除触发器（用于变更追踪）

```swift
let migrator = Migrator(connection: connection)
let plan = try migrator.plan(for: [User.self, Post.self])
try migrator.apply(plan)
```

## 模块结构

```
SwiftStoreCore/
├── Core/           # 核心类型和连接
├── Query/          # 查询构建器
├── SQLite/         # SQLite 封装
└── Migration/      # Schema 迁移
```

## 支持平台

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## 依赖

- SwiftStoreMacros
- SwiftStoreProtocols
