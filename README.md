# SwiftStore

基于 SQLite 的轻量级数据持久化框架，提供类似 SwiftData 的开发体验，支持多设备数据同步。

## 特性

- **声明式 API** - 使用 Swift 宏自动生成样板代码
- **类型安全查询** - 编译时检查的查询构建器
- **自动迁移** - 智能 Schema 迁移，无需手写 SQL
- **多设备同步** - 基于变更日志的双向同步机制
- **高性能** - SQLite WAL 模式 + 单写多读连接池

## 快速开始

### 定义实体

```swift
import SwiftStoreCore

@Entity
struct User {
    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    let createdAt: Date
    let updatedAt: Date
}
```

### 数据库操作

```swift
// 创建连接
let connection = try SQLiteConnection(path: "database.sqlite")

// 自动迁移
let migrator = Migrator(connection: connection)
try migrator.apply(try migrator.plan(for: [User.self]))

// 插入
let user = User(name: "Alice", email: "alice@example.com", age: 25)
try connection.insert(user)

// 查询
let users: [User] = try connection.query {
    $0.where(\.age > 18)
      .orderBy(\.name)
      .limit(10)
}

// 更新
var updatedUser = user
updatedUser.name = "Alice Smith"
try connection.update(updatedUser)

// 删除
try connection.delete(user)
```

### 索引定义

```swift
@Entity
struct User {
    #Index<Self>(\.email, unique: true)           // 唯一索引
    #Index<Self>(\.firstName, \.lastName)         // 复合索引

    let id: UUIDV4
    var email: String
    var firstName: String
    var lastName: String
    let createdAt: Date
    let updatedAt: Date
}
```

### 多设备同步

```swift
// 使用连接管理器（带同步功能）
let manager = try ConnectionManager(
    path: "database.sqlite",
    syncConfig: SyncConfig(
        changeLogDbPath: "changelog.sqlite",
        deviceId: myDeviceId,
        registeredEntities: [User.self],
        tickClock: { clock.tick() },
        transport: myTransport,
        syncableEntities: [User.self]
    )
)

// 执行同步
let result = try await manager.sync()
print("Pulled: \(result.pulledCount), Pushed: \(result.pushedCount)")
```

## 完整示例

以下示例展示了 SwiftStore 的所有核心功能：

### 1. 定义模型

```swift
import SwiftStoreCore
import SwiftStoreConnectionQueue

// MARK: - 嵌套 Codable 类型（支持 @Default 容错解码）

@Default
struct Address: Codable, Sendable {
    var street: String = ""
    var city: String = ""
    var zipCode: String = ""
}

@Default
struct Profile: Codable, Sendable {
    var bio: String = ""
    var avatarUrl: String?
    var settings: UserSettings = UserSettings()
}

@Default
struct UserSettings: Codable, Sendable {
    var theme: String = "light"
    var fontSize: Int = 14
    var notifications: Bool = true
}

// MARK: - 普通实体（使用 id 作为主键）

@Entity
struct User {
    #Index<Self>(\.email, unique: true)              // 唯一索引
    #Index<Self>(\.name)                             // 普通索引
    #Index<Self>(\.address.city)                     // 嵌套字段索引
    #Index<Self>(\.profile.settings.theme)           // 深层嵌套索引

    let id: UUIDV4
    var name: String
    var email: String
    var age: Int?
    var address: Address                             // 嵌套 Codable 类型
    var profile: Profile                             // 深层嵌套类型
    var tags: [String]                               // 数组类型
    let createdAt: Date
    let updatedAt: Date
}

@Entity
struct Post {
    #Index<Self>(\.authorId)
    #Index<Self>(\.status, \.createdAt)              // 复合索引

    let id: UUIDV4
    var authorId: UUIDV4
    var title: String
    var content: String
    var status: String
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - 同步实体（使用 #SyncKey 作为主键，无 id 字段）

@Entity
struct UserDevice {
    #SyncKey<Self>(\.userId, \.deviceId)             // 复合同步键

    var userId: UUIDV4
    var deviceId: String
    var deviceName: String
    var lastActiveAt: Date
    let createdAt: Date
    let updatedAt: Date
}

@Entity
struct Favorite {
    #SyncKey<Self>(\.userId, \.postId)               // 多对多关系的同步键

    var userId: UUIDV4
    var postId: UUIDV4
    let createdAt: Date
    let updatedAt: Date
}
```

### 2. 基础数据库操作

```swift
// 创建数据库连接
let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("app.sqlite").path
let connection = try SQLiteConnection(path: dbPath, options: .init(walMode: true))

// 自动迁移 Schema
let migrator = Migrator(connection: connection)
let plan = try migrator.plan(for: [User.self, Post.self, UserDevice.self, Favorite.self])
try migrator.apply(plan)

// 插入数据（实例方法风格）
let user = User(
    name: "Alice",
    email: "alice@example.com",
    age: 28,
    address: Address(street: "123 Main St", city: "Beijing", zipCode: "100000"),
    profile: Profile(bio: "Swift Developer", settings: UserSettings(theme: "dark")),
    tags: ["developer", "swift"]
)
try user.insert(connection)

let post = Post(
    authorId: user.id,
    title: "Hello SwiftStore",
    content: "This is my first post!",
    status: "published"
)
try post.insert(connection)

// 插入同步实体（使用 SyncKey）
let device = UserDevice(
    userId: user.id,
    deviceId: "iPhone-001",
    deviceName: "My iPhone",
    lastActiveAt: Date()
)
try device.insert(connection)

let favorite = Favorite(userId: user.id, postId: post.id)
try favorite.insert(connection)
```

### 3. 类型安全查询

```swift
// 简单条件查询
let adultUsers = try User.filter { $0.age >= 18 }.all(connection)

// 多条件查询
let activeUsers = try User
    .filter { $0.age >= 18 && $0.profile.settings.theme == "dark" }
    .order(by: \.createdAt, ascending: false)
    .limit(20)
    .all(connection)

// 嵌套字段查询
let beijingUsers = try User.filter { $0.address.city == "Beijing" }.all(connection)

// 可选字段查询
let usersWithAge = try User.filter { $0.age != nil }.all(connection)

// 复合条件
let publishedPosts = try Post
    .filter { $0.status == "published" && $0.authorId == user.id }
    .orderDesc(by: \.createdAt)
    .all(connection)

// 通过同步键查询
let userDevices = try UserDevice.filter { $0.userId == user.id }.all(connection)

// 通过 ID 查询
let foundUser = try User.find(user.id, connection)        // 返回 Optional
let requiredUser = try User.get(user.id, connection)      // 不存在则抛错

// 聚合查询
let totalUsers = try User.count(connection)
let hasUsers = try User.exists(connection)
let firstUser = try User.first(connection)

// 批量操作
let deletedCount = try User.filter { $0.age < 18 }.deleteAll(connection)
let updatedCount = try User.filter { $0.status == "inactive" }
    .updateAll(connection, [\.status <- "archived"])
```

### 4. 更新和删除

```swift
// 更新实体（实例方法）
var updatedUser = user
updatedUser.name = "Alice Smith"
updatedUser.profile.bio = "Senior Swift Developer"
try updatedUser.update(connection)

// 保存实体（自动判断插入或更新）
var newOrExisting = User(name: "Bob", email: "bob@example.com", ...)
try newOrExisting.save(connection)  // 不存在则插入，存在则更新

// 重新加载实体
if let reloaded = try updatedUser.reload(connection) {
    print("Latest data: \(reloaded.name)")
}

// 删除实体（实例方法）
try post.delete(connection)
try favorite.delete(connection)

// 通过 ID 删除
try User.delete(user.id, connection)

// 批量删除
try User.filter { $0.age < 18 }.deleteAll(connection)
try User.deleteAll(connection)  // 删除所有
```

### 5. 连接池管理（单写多读）

```swift
// 创建连接管理器
let manager = try ConnectionManager(
    path: dbPath,
    options: .init(walMode: true),
    maxReadConnections: 4
)

// 并发读取（使用连接池）
async let users1 = manager.read { conn in
    try User.filter { $0.age > 20 }.all(conn)
}
async let users2 = manager.read { conn in
    try User.filter { $0.address.city == "Shanghai" }.all(conn)
}
let (result1, result2) = try await (users1, users2)

// 写操作（串行执行）
try await manager.write { conn in
    try User(
        name: "Bob",
        email: "bob@example.com",
        age: 30,
        address: Address(city: "Shanghai"),
        profile: Profile(),
        tags: []
    ).insert(conn)
}

// 便捷静态方法
try await manager.read { conn in
    let count = try User.count(conn)
    let first = try User.first(conn)
    let all = try User.all(conn)
}
```

### 6. 多设备同步

```swift
// 实现 SyncTransport 协议
struct MySyncTransport: SyncTransport {
    let serverURL: URL

    func pull(sinceClock: Int64, deviceId: UUIDV4) async throws -> PullResponse {
        // 从服务器拉取变更
        var request = URLRequest(url: serverURL.appendingPathComponent("pull"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode([
            "sinceClock": sinceClock,
            "deviceId": deviceId.uuidString
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PullResponse.self, from: data)
    }

    func push(changes: [SyncChange], deviceId: UUIDV4) async throws -> PushResponse {
        // 推送本地变更到服务器
        var request = URLRequest(url: serverURL.appendingPathComponent("push"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode([
            "changes": changes,
            "deviceId": deviceId.uuidString
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PushResponse.self, from: data)
    }
}

// 创建混合逻辑时钟
let clock = HybridClock()

// 配置同步
let deviceId = UUIDV4()
let syncConfig = SyncConfig(
    changeLogDbPath: dbPath.replacingOccurrences(of: ".sqlite", with: "_changelog.sqlite"),
    deviceId: deviceId,
    pendingDeletesTable: "__pending_deletes",
    registeredEntities: [User.self, Post.self, UserDevice.self, Favorite.self],
    tickClock: { clock.tick() },
    transport: MySyncTransport(serverURL: URL(string: "https://api.example.com/sync")!),
    syncableEntities: [User.self, Post.self, UserDevice.self, Favorite.self],
    syncConfiguration: SyncConfiguration(batchSize: 50, yieldBetweenBatches: true),
    schemaVersion: 1,
    ntpToleranceMs: 5000  // 时间偏差容忍度 5 秒
)

// 创建带同步功能的连接管理器
let syncManager = try ConnectionManager(
    path: dbPath,
    syncConfig: syncConfig
)

// 检查同步状态
if await syncManager.hasSyncEnabled {
    print("Sync is enabled")

    // 执行同步
    do {
        let result = try await syncManager.sync()
        print("""
        Sync completed:
        - Pulled: \(result.pulledCount) changes
        - Pushed: \(result.pushedCount) changes
        - Conflicts: \(result.conflictCount)
        - Server clock: \(result.state.lastServerClock)
        """)
    } catch let error as NTPError {
        print("Time sync error: \(error)")
    } catch let error as SyncError {
        print("Sync error: \(error)")
    }

    // 获取当前同步状态
    if let state = await syncManager.syncState {
        print("Last server clock: \(state.lastServerClock)")
        print("Last local clock: \(state.lastLocalClock)")
    }
}
```

### 7. @Default 容错解码示例

```swift
// @Default 宏让解码更健壮，缺失字段使用默认值
let json = """
{
    "street": "456 Oak Ave"
}
""".data(using: .utf8)!

// 即使缺少 city 和 zipCode，也能正常解码
let address = try JSONDecoder().decode(Address.self, from: json)
print(address.street)   // "456 Oak Ave"
print(address.city)     // "" (默认值)
print(address.zipCode)  // "" (默认值)

// 嵌套场景也能正常工作
let profileJson = """
{
    "bio": "Hello"
}
""".data(using: .utf8)!

let profile = try JSONDecoder().decode(Profile.self, from: profileJson)
print(profile.bio)                      // "Hello"
print(profile.settings.theme)           // "light" (嵌套默认值)
print(profile.settings.notifications)   // true (嵌套默认值)
```

## 架构

```
SwiftStore
├── SwiftStoreProtocols     # 协议定义层
├── SwiftStoreMacros        # 宏定义层
├── SwiftStoreCore          # 核心层（连接、查询、迁移）
├── SwiftStoreChangeTracker # 变更追踪层
├── SwiftStoreSync          # 同步层
└── SwiftStoreConnectionQueue # 连接管理层
```

### 依赖关系

```
SwiftStoreProtocols (无依赖)
       ↓
SwiftStoreMacros (依赖 swift-syntax)
       ↓
SwiftStoreCore
       ↓
SwiftStoreChangeTracker
       ↓
SwiftStoreSync
       ↓
SwiftStoreConnectionQueue
```

## Packages

| Package | 说明 |
|---------|------|
| [SwiftStoreProtocols](./SwiftStoreProtocols/) | 协议定义 - EntityProtocol、SQLiteCodable 等 |
| [SwiftStoreMacros](./SwiftStoreMacros/) | 宏定义 - @Entity、#Index、#SyncKey、@Default |
| [SwiftStoreCore](./SwiftStoreCore/) | 核心功能 - SQLite 连接、查询构建、迁移 |
| [SwiftStoreChangeTracker](./SwiftStoreChangeTracker/) | 变更追踪 - SQLite update hook 记录变更 |
| [SwiftStoreSync](./SwiftStoreSync/) | 数据同步 - 双向同步、冲突解决、NTP 校验 |
| [SwiftStoreConnectionQueue](./SwiftStoreConnectionQueue/) | 连接管理 - 单写多读连接池 |

## 支持平台

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+

## 要求

- Swift 6.0+
- Xcode 16+

## 安装

### Swift Package Manager

```swift
dependencies: [
    .package(path: "path/to/SwiftStore")
]
```

根据需要选择导入的模块：

```swift
// 基础功能
import SwiftStoreCore

// 带同步功能
import SwiftStoreConnectionQueue
```

## License

MIT
