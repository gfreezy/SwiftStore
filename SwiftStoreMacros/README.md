# SwiftStoreMacros

SwiftStore 的宏定义层，提供 Swift 宏用于自动生成实体代码。

## 概述

此 package 使用 Swift 宏技术自动生成 EntityProtocol 所需的样板代码，包括表名、列定义、编解码实现等。

## 宏列表

### @Entity

主宏，用于标记实体 struct：

```swift
@Entity
struct User {
    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    let createdAt: Date
    let updatedAt: Date
}

// 自定义表名
@Entity(tableName: "users_table")
struct User { ... }
```

自动生成：
- `tableName` 静态属性
- `columns` 列定义数组
- `sqliteEncode()` / `sqliteDecode(from:)` 方法
- `init` 带默认值的初始化器
- `CodingKeys` 枚举
- `EntityProtocol` / `SQLiteCodable` / `Identifiable` 协议遵循

### #Index

在实体内部定义索引：

```swift
@Entity
struct User {
    #Index<Self>(\.email, unique: true)           // 唯一索引
    #Index<Self>(\.firstName, \.lastName)         // 复合索引
    #Index<Self>(\.address.city)                  // 嵌套字段索引

    let id: UUIDV4
    var email: String
    var firstName: String
    var lastName: String
    var address: Address
    let createdAt: Date
    let updatedAt: Date
}
```

### #SyncKey

定义同步键，用于多设备同步场景：

```swift
@Entity
struct Employee {
    #SyncKey<Self>(\.companyId, \.employeeCode)  // 复合同步键

    var companyId: UUIDV4
    var employeeCode: String
    var name: String
    let createdAt: Date
    let updatedAt: Date
}
```

注意：使用 `#SyncKey` 时不需要 `id` 字段，两者互斥。

### @Default

为 Codable 结构体生成容错解码实现：

```swift
@Default
struct UserSettings: Codable {
    var theme: String = "light"   // 缺失时使用默认值
    var fontSize: Int = 14        // 缺失时使用默认值
    var userId: String            // 必需字段
}
```

## 支持平台

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## 依赖

- swift-syntax 600.0.0+
- SwiftStoreProtocols
