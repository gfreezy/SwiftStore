# SwiftStoreProtocols

SwiftStore 的协议定义层，提供所有实体必须遵循的基础协议和类型定义。

## 概述

此 package 定义了 SwiftStore 框架的核心协议，是整个框架的基础依赖。它不包含任何具体实现，仅提供协议和类型定义。

## 主要内容

### EntityProtocol

所有实体必须遵循的协议：

```swift
public protocol EntityProtocol: Codable, Sendable {
    var createdAt: Date { get }
    var updatedAt: Date { get }

    static var tableName: String { get }
    static var columns: [ColumnDefinition] { get }
    static var indexes: [IndexDefinition] { get }
    static var syncKeyColumns: [String] { get }
}
```

### SQLiteCodable

SQLite 编解码协议，用于实体与 SQLite 值之间的转换：

```swift
public protocol SQLiteEncodable {
    func sqliteEncode() throws -> [String: SQLiteValue]
}

public protocol SQLiteDecodable {
    static func sqliteDecode(from statement: any SQLiteStatementProtocol) throws -> Self
}

public typealias SQLiteCodable = SQLiteEncodable & SQLiteDecodable
```

### 其他类型

- `ColumnDefinition` - 列定义，描述数据库列的名称和类型
- `SQLiteValue` - SQLite 值类型枚举
- `SQLiteStatementProtocol` - SQLite 语句协议
- `StoreError` - 错误类型定义
- `UUIDV4` - UUID v4 类型，存储为 16 字节 BLOB

## 支持平台

- macOS 14+
- iOS 17+

## 依赖

无外部依赖。
