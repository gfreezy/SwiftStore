# SwiftStore 设计文档

基于 SQLite 的轻量级数据持久化框架，提供类似 SwiftData 的开发体验。

---

## 核心概念

### 1. Entity（实体）

所有数据结构统一使用 `@Entity` 宏定义，包括普通实体和关系实体。

**约束：**
- 必须有 `id` 字段，类型为 `UUID`
- 必须有 `createdAt` 和 `updatedAt` 时间戳字段（由框架自动管理值）
- 支持嵌套 `Codable` 类型字段
- 每个 Entity 对应一张数据库表

**内置字段：**

| 字段 | 类型 | 说明 |
|-----|------|------|
| `id` | `UUID` | 主键 |
| `createdAt` | `Date` | 创建时间，插入时自动填充 |
| `updatedAt` | `Date` | 更新时间，插入/更新时自动填充 |

**示例：**
```swift
// 嵌套的 Codable 类型
struct Address: Codable {
    var street: String
    var city: String
    var zipCode: String
    var location: Location?
}

struct Location: Codable {
    var latitude: Double
    var longitude: Double
}

// 普通 Entity
@Entity
struct User {
    let id: UUID
    var name: String
    var email: String
    var age: Int?
    var address: Address
    let createdAt: Date
    let updatedAt: Date
}

@Entity
struct Tag {
    let id: UUID
    var name: String
    let createdAt: Date
    let updatedAt: Date
}
```

---

### 2. 索引（Index）

在 Entity 上可以定义单列或复合索引。当索引涉及嵌套 Codable 字段时，框架会**自动创建对应的虚拟列**。

**语法：**
```swift
@Entity
@Index(\.email, unique: true)                              // 单列唯一索引
@Index(\.address.city)                                     // 嵌套字段 → 自动创建虚拟列
@Index(\.name, \.address.city)                             // 复合索引
@Index(\.address.city, \.address.location?.latitude)       // 多嵌套字段复合索引
struct User {
    let id: UUID
    var name: String
    var email: String
    var address: Address
    let createdAt: Date
    let updatedAt: Date
}
```

**参数说明：**

| 参数 | 类型 | 说明 |
|-----|------|------|
| KeyPath(s) | `KeyPath...` | 一个或多个字段路径（普通字段或嵌套字段路径）|
| `unique` | `Bool` | 是否唯一索引，默认 `false` |

**自动虚拟列生成：**
- 当 `@Index` 中包含嵌套字段路径（如 `\.address.city`）时，自动创建虚拟列
- 虚拟列命名规则：`\.address.city` → `address_city`
- 使用 SQLite `VIRTUAL` 生成列，按需计算，不占用额外存储空间

**索引名自动生成规则：**
- 单列：`idx_{table}_{column}` → `idx_user_email`
- 复合：`idx_{table}_{col1}_{col2}` → `idx_user_name_address_city`

**生成的 SQL：**
```sql
CREATE TABLE user (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    address TEXT NOT NULL,
    -- 自动生成的虚拟列（由 @Index 触发）
    address_city TEXT GENERATED ALWAYS AS (json_extract(address, '$.city')) VIRTUAL,
    address_location_latitude REAL GENERATED ALWAYS AS (json_extract(address, '$.location.latitude')) VIRTUAL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE UNIQUE INDEX idx_user_email ON user(email);
CREATE INDEX idx_user_address_city ON user(address_city);
CREATE INDEX idx_user_name_address_city ON user(name, address_city);
CREATE INDEX idx_user_address_city_address_location_latitude ON user(address_city, address_location_latitude);
```

**特性：**
- 嵌套字段索引时无需手动声明虚拟列，框架自动处理
- 使用 SQLite 的 `json_extract()` 函数从 JSON 字段提取值
- 虚拟列使用 `VIRTUAL` 类型，不额外占用存储空间
- 支持可选路径（如 `\.address.location?.latitude`），值为 NULL 当路径不存在时
- 相同嵌套路径在多个索引中只会创建一个虚拟列

---

### 3. 关系定义

关系通过 `@OneToOne`、`@OneToMany`、`@ManyToOne`、`@ManyToMany` 宏定义，可以加在任何 `@Entity` 上。

根据是否省略 `from` 参数，分为两种使用方式：
- **省略 from**：在 Entity 上直接定义关系（简单关系）
- **指定 from**：单独定义关系 Entity（需要附加字段）

---

#### 3.1 在 Entity 上直接定义关系（省略 from）

适用于简单关系，外键直接存储在 Entity 表中。

**参数格式（无 from）：**

```swift
// OneToOne: 一对一关系
@OneToOne(fromField: KeyPath, to: Entity.Type, toField: KeyPath)

// ManyToOne: 多对一关系
@ManyToOne(fromField: KeyPath, to: Entity.Type, toField: KeyPath)
```

| 参数 | 说明 |
|-----|------|
| `fromField` | 当前 Entity 的外键字段 |
| `to` | 目标 Entity 类型 |
| `toField` | 目标 Entity 的关联字段 |

**注意：** 在 Entity 上直接定义时，只支持 `@OneToOne` 和 `@ManyToOne`。一对多和多对多关系需要单独定义关系 Entity。

**示例：**

```swift
// ManyToOne: Post 属于 User
@Entity
@ManyToOne(fromField: \.userId, to: User.self, toField: \.id)
struct Post {
    let id: UUID
    var title: String
    var content: String
    let userId: UUID          // 外键字段，手动定义
    let createdAt: Date
    let updatedAt: Date
}

// OneToOne: Profile 属于 User
@Entity
@OneToOne(fromField: \.userId, to: User.self, toField: \.id)
struct Profile {
    let id: UUID
    var bio: String
    let userId: UUID          // 外键字段 + UNIQUE 约束
    let createdAt: Date
    let updatedAt: Date
}
```

**生成的数据库结构：**

```sql
-- OneToOne: 外键直接存储在 Profile 表中
CREATE TABLE profile (
    id TEXT PRIMARY KEY NOT NULL,
    bio TEXT NOT NULL,
    user_id TEXT NOT NULL UNIQUE,  -- 外键字段 + UNIQUE 约束
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    FOREIGN KEY (user_id) REFERENCES user(id) ON DELETE CASCADE
);

-- ManyToOne: 外键直接存储在 Post 表中
CREATE TABLE post (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    user_id TEXT NOT NULL,         -- 外键字段（无 UNIQUE）
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    FOREIGN KEY (user_id) REFERENCES user(id) ON DELETE CASCADE
);
```

---

#### 3.2 单独定义关系 Entity（指定 from）

适用于需要附加字段的关系，或需要直接操作关系表的场景。

**参数格式（有 from）：**

```swift
// OneToOne: 一对一关系
@OneToOne(from: Entity.Type, fromField: KeyPath, fromKey: KeyPath,
          to: Entity.Type, toField: KeyPath, toKey: KeyPath)

// OneToMany: 一对多关系
@OneToMany(from: Entity.Type, fromField: KeyPath, fromKey: KeyPath,
           to: Entity.Type, toField: KeyPath, toKey: KeyPath)

// ManyToOne: 多对一关系
@ManyToOne(from: Entity.Type, fromField: KeyPath, fromKey: KeyPath,
           to: Entity.Type, toField: KeyPath, toKey: KeyPath)

// ManyToMany: 多对多关系
@ManyToMany(from: Entity.Type, fromField: KeyPath, fromKey: KeyPath,
            to: Entity.Type, toField: KeyPath, toKey: KeyPath)

// ManyToMany 自引用（需要 fromName/toName 区分方向）
@ManyToMany(from: Entity.Type, fromField: KeyPath, fromKey: KeyPath,
            to: Entity.Type, toField: KeyPath, toKey: KeyPath,
            fromName: String, toName: String)
```

| 参数 | 说明 |
|-----|------|
| `from` | 源 Entity 类型 |
| `fromField` | 源 Entity 的关联字段 |
| `fromKey` | 当前 struct 中存储源关联值的字段 |
| `to` | 目标 Entity 类型 |
| `toField` | 目标 Entity 的关联字段 |
| `toKey` | 当前 struct 中存储目标关联值的字段 |
| `fromName` | 自引用关系时，正向方法名 |
| `toName` | 自引用关系时，反向方法名 |

**示例：**

```swift
// OneToOne 关系 Entity
@Entity
@OneToOne(from: User.self, fromField: \.id, fromKey: \.userId,
          to: Profile.self, toField: \.id, toKey: \.profileId)
struct UserProfile {
    let id: UUID
    let userId: UUID
    let profileId: UUID
    var isPrimary: Bool       // 附加字段
    let createdAt: Date
    let updatedAt: Date
}

// OneToMany 关系 Entity
@Entity
@OneToMany(from: User.self, fromField: \.id, fromKey: \.userId,
           to: Post.self, toField: \.id, toKey: \.postId)
struct UserPosts {
    let id: UUID
    let userId: UUID
    let postId: UUID
    var order: Int?           // 附加字段：排序
    let createdAt: Date
    let updatedAt: Date
}

// ManyToMany 关系 Entity（带附加字段）
@Entity
@ManyToMany(from: User.self, fromField: \.id, fromKey: \.userId,
            to: Tag.self, toField: \.id, toKey: \.tagId)
struct UserTags {
    let id: UUID
    let userId: UUID          // 手动定义，对应 fromKey
    let tagId: UUID           // 手动定义，对应 toKey
    var metadata: RelationMetadata  // 附加字段
    let createdAt: Date
    let updatedAt: Date
}

// 自引用 ManyToMany（需要 fromName/toName）
@Entity
@ManyToMany(from: User.self, fromField: \.id, fromKey: \.followerId,
            to: User.self, toField: \.id, toKey: \.followeeId,
            fromName: "following", toName: "followers")
struct Friendship {
    let id: UUID
    let followerId: UUID      // 关注者
    let followeeId: UUID      // 被关注者
    var status: String        // pending, accepted, blocked
    var since: Date?
    let createdAt: Date
    let updatedAt: Date
}
```

**生成的数据库结构：**

```sql
-- UserTags 关系表
CREATE TABLE user_tags (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    metadata TEXT NOT NULL,        -- JSON 序列化
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    FOREIGN KEY (user_id) REFERENCES user(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tag(id) ON DELETE CASCADE,
    UNIQUE (user_id, tag_id)
);

-- Friendship 自引用关系表
CREATE TABLE friendship (
    id TEXT PRIMARY KEY NOT NULL,
    follower_id TEXT NOT NULL,
    followee_id TEXT NOT NULL,
    status TEXT NOT NULL,
    since REAL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    FOREIGN KEY (follower_id) REFERENCES user(id) ON DELETE CASCADE,
    FOREIGN KEY (followee_id) REFERENCES user(id) ON DELETE CASCADE,
    UNIQUE (follower_id, followee_id)
);
```

---

#### 3.3 关系表创建规则

| 关系类型 | 定义位置 | 是否创建独立关系表 | 约束 |
|---------|---------|------------------|------|
| `@OneToOne` | Entity 上（无 from） | ❌ 不创建 | fromField 字段 + UNIQUE |
| `@ManyToOne` | Entity 上（无 from） | ❌ 不创建 | fromField 字段（无 UNIQUE） |
| `@OneToOne` | 单独 Entity（有 from） | ✅ 创建 | fromKey UNIQUE + toKey UNIQUE |
| `@OneToMany` | 单独 Entity（有 from） | ✅ 创建 | toKey UNIQUE |
| `@ManyToOne` | 单独 Entity（有 from） | ✅ 创建 | fromKey（无 UNIQUE） |
| `@ManyToMany` | 单独 Entity（有 from） | ✅ 创建 | (fromKey, toKey) 联合唯一 |

---

### 4. 自动生成的快捷方法

定义关系后，框架会自动在相关的 Entity 上生成快捷访问方法。

#### 4.1 OneToOne 快捷方法

```swift
@Entity
@OneToOne(fromField: \.userId, to: User.self, toField: \.id)
struct Profile {
    let id: UUID
    var bio: String
    let userId: UUID
    let createdAt: Date
    let updatedAt: Date
}

// ✅ 自动在 Profile 上生成：
extension Profile {
    func user(in store: Store) throws -> User?
    func user(userId: UUID, in store: Store) throws -> User?
}

// ✅ 自动在 User 上生成（反向）：
extension User {
    func profile(in store: Store) throws -> Profile?
    func profile(profileId: UUID, in store: Store) throws -> Profile?
}
```

#### 4.2 ManyToOne 快捷方法

```swift
@Entity
@ManyToOne(fromField: \.userId, to: User.self, toField: \.id)
struct Post {
    let id: UUID
    var title: String
    let userId: UUID
    let createdAt: Date
    let updatedAt: Date
}

// ✅ 自动在 Post 上生成：
extension Post {
    func user(in store: Store) throws -> User?
    func user(userId: UUID, in store: Store) throws -> User?
}

// ✅ 自动在 User 上生成（反向，OneToMany 语义）：
extension User {
    func posts(in store: Store) throws -> [Post]
    func post(postId: UUID, in store: Store) throws -> Post?
    func postsCount(in store: Store) throws -> Int
}
```

#### 4.3 ManyToMany 快捷方法

```swift
@Entity
@ManyToMany(from: User.self, fromField: \.id, fromKey: \.userId,
            to: Tag.self, toField: \.id, toKey: \.tagId)
struct UserTags {
    let id: UUID
    let userId: UUID
    let tagId: UUID
    var metadata: RelationMetadata
    let createdAt: Date
    let updatedAt: Date
}

// ✅ 自动在 User 上生成：
extension User {
    func tags(in store: Store) throws -> [Tag]
    func tag(tagId: UUID, in store: Store) throws -> Tag?
    func tagRelations(in store: Store) throws -> [UserTags]
    func addTag(tagId: UUID, in store: Store) throws -> UserTags
    func addTag(tagId: UUID, metadata: RelationMetadata, in store: Store) throws -> UserTags
    func addTags(tagIds: [UUID], in store: Store) throws -> [UserTags]
    func removeTag(tagId: UUID, in store: Store) throws
    func removeAllTags(in store: Store) throws
    func hasTag(tagId: UUID, in store: Store) throws -> Bool
    func tagsCount(in store: Store) throws -> Int
}

// ✅ 自动在 Tag 上生成（双向）：
extension Tag {
    func users(in store: Store) throws -> [User]
    func user(userId: UUID, in store: Store) throws -> User?
    func userRelations(in store: Store) throws -> [UserTags]
    func addUser(userId: UUID, in store: Store) throws -> UserTags
    func removeUser(userId: UUID, in store: Store) throws
    func hasUser(userId: UUID, in store: Store) throws -> Bool
    func usersCount(in store: Store) throws -> Int
}
```

#### 4.4 OneToMany 快捷方法

```swift
@Entity
@OneToMany(from: User.self, fromField: \.id, fromKey: \.userId,
           to: Post.self, toField: \.id, toKey: \.postId)
struct UserPosts {
    let id: UUID
    let userId: UUID
    let postId: UUID
    var order: Int?
    let createdAt: Date
    let updatedAt: Date
}

// ✅ 自动在 User（One 端）上生成：
extension User {
    func posts(in store: Store) throws -> [Post]
    func post(postId: UUID, in store: Store) throws -> Post?
    func postRelations(in store: Store) throws -> [UserPosts]
    func addPost(postId: UUID, in store: Store) throws -> UserPosts
    func addPost(postId: UUID, order: Int?, in store: Store) throws -> UserPosts
    func addPosts(postIds: [UUID], in store: Store) throws -> [UserPosts]
    func removePost(postId: UUID, in store: Store) throws
    func removeAllPosts(in store: Store) throws
    func postsCount(in store: Store) throws -> Int
}

// ✅ 自动在 Post（Many 端）上生成：
extension Post {
    func user(in store: Store) throws -> User?
    func user(userId: UUID, in store: Store) throws -> User?
    func userRelation(in store: Store) throws -> UserPosts?
    func setUser(userId: UUID, in store: Store) throws -> UserPosts
}
```

#### 4.5 自引用关系快捷方法

```swift
@Entity
@ManyToMany(from: User.self, fromField: \.id, fromKey: \.followerId,
            to: User.self, toField: \.id, toKey: \.followeeId,
            fromName: "following", toName: "followers")
struct Friendship {
    let id: UUID
    let followerId: UUID
    let followeeId: UUID
    var status: String
    var since: Date?
    let createdAt: Date
    let updatedAt: Date
}

// ✅ 自动在 User 上生成（基于 fromName/toName 派生）：
extension User {
    // --- 正向方法（基于 fromName: "following"）---
    // {fromName}() → following()
    // {fromName}(userId:) → following(userId:)
    // {fromName}Relations() → followingRelations()
    // add{FromName}(userId:) → addFollowing(userId:)
    // add{FromName}(userId:, 附加字段...) → addFollowing(userId:, status:, since:)
    // remove{FromName}(userId:) → removeFollowing(userId:)
    // has{FromName}(userId:) → hasFollowing(userId:)
    // {fromName}Count() → followingCount()
    func following(in store: Store) throws -> [User]
    func following(userId: UUID, in store: Store) throws -> User?
    func followingRelations(in store: Store) throws -> [Friendship]
    func addFollowing(userId: UUID, in store: Store) throws -> Friendship
    func addFollowing(userId: UUID, status: String, since: Date?, in store: Store) throws -> Friendship
    func removeFollowing(userId: UUID, in store: Store) throws
    func hasFollowing(userId: UUID, in store: Store) throws -> Bool
    func followingCount(in store: Store) throws -> Int

    // --- 反向方法（基于 toName: "followers"）---
    // {toName}() → followers()
    // {toName}(userId:) → followers(userId:)
    // {toName}Relations() → followersRelations()
    // {toName}Count() → followersCount()
    func followers(in store: Store) throws -> [User]
    func followers(userId: UUID, in store: Store) throws -> User?
    func followersRelations(in store: Store) throws -> [Friendship]
    func followersCount(in store: Store) throws -> Int
}
```

**自引用关系方法命名规则：**

| fromName/toName | 派生方法 |
|-----------------|---------|
| `{name}` | `{name}()` - 获取所有关联 |
| `{name}` | `{name}(userId:)` - 通过 ID 获取 |
| `{name}` | `{name}Relations()` - 获取关系对象 |
| `{Name}` | `add{Name}(userId:)` - 添加关联 |
| `{Name}` | `remove{Name}(userId:)` - 移除关联 |
| `{Name}` | `has{Name}(userId:)` - 检查关联 |
| `{name}` | `{name}Count()` - 关联数量 |

**注意：** 反向方法（toName）不生成 `add`、`remove`、`has` 方法，因为反向关系是只读的。

---

### 5. 快捷方法命名规则

框架根据关系定义自动推断方法名：

| 关系 Entity | 关联 Entity | 生成的方法名前缀 |
|------------|-------------|-----------------|
| `UserTags` | User | `tags`, `tagRelations`, `addTag` |
| `UserTags` | Tag | `users`, `userRelations`, `addUser` |
| `UserPosts` | User | `posts`, `postRelations`, `addPost` |
| `UserPosts` | Post | `user`, `userRelation`, `setUser` |

**自定义方法名：**

```swift
@Entity
@ManyToMany(from: User.self, fromField: \.id, fromKey: \.followerId,
            to: User.self, toField: \.id, toKey: \.followeeId,
            fromName: "following",    // 自定义正向名称
            toName: "followers")      // 自定义反向名称
struct Friendship { ... }

// 生成：user.following(), user.followers()
```

---

## 数据库 Schema 设计

### 嵌套字段存储策略

嵌套的 `Codable` 字段采用 **JSON 序列化存储**，整个嵌套结构序列化为 JSON 字符串存储在单个 TEXT 列中：

| Swift 字段 | 数据库列名 | 列类型 | 存储内容 |
|-----------|-----------|--------|---------|
| `address: Address` | `address` | TEXT | `{"street":"...","city":"...","zipCode":"...","location":null}` |
| `metadata: RelationMetadata` | `metadata` | TEXT | `{"source":"...","confidence":0.9}` |

**优点：**
- 简化数据库结构，嵌套对象只占用一列
- 支持任意深度的嵌套结构
- 无需为嵌套类型变更修改数据库 Schema
- 更容易处理可选嵌套类型（JSON 中直接用 `null` 表示）

**注意：**
- 嵌套字段内部属性不支持直接查询（如 `\.address.city == "Shanghai"` 需要取出后在内存中过滤）
- 如需按嵌套字段查询，可通过 `@Index` 创建虚拟列

---

## 核心协议设计

### EntityProtocol

```swift
protocol EntityProtocol: Identifiable, Codable {
    var id: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }

    static var tableName: String { get }
    static var columns: [ColumnDefinition] { get }
}
```

### RelationMarker（关系标记协议）

```swift
protocol RelationMarker {
    associatedtype FromEntity: EntityProtocol
    associatedtype ToEntity: EntityProtocol

    static var fromKeyPath: String { get }
    static var toKeyPath: String { get }
    static var relationType: RelationType { get }
}

enum RelationType {
    case oneToOne
    case oneToMany
    case manyToOne
    case manyToMany
}
```

---

## 类型映射

### 基础类型

| Swift 类型 | SQLite 类型 | 说明 |
|-----------|-------------|------|
| `UUID` | `TEXT` | 字符串形式存储 |
| `String` | `TEXT` | - |
| `Int` | `INTEGER` | - |
| `Double` | `REAL` | - |
| `Bool` | `INTEGER` | 0/1 |
| `Date` | `REAL` | Unix 时间戳 |
| `Data` | `BLOB` | - |
| `Optional<T>` | 对应类型 + `NULL` | 允许空值 |

### 嵌套 Codable 类型

| Swift 类型 | SQLite 存储 | 说明 |
|-----------|-------------|------|
| 嵌套 `struct` | TEXT (JSON) | 整个结构序列化为 JSON 字符串 |
| `Optional<NestedType>` | TEXT (允许 `NULL`) | 整体为 nil 时列值为 NULL |

---

## API 设计

### Store（数据库管理器）

```swift
class Store {
    // 初始化
    init(path: String) throws

    // Schema 管理（统一使用 register）
    func register<E: EntityProtocol>(_ type: E.Type) throws
    func migrate() throws
}
```

### CRUD 操作

```swift
extension Store {
    // Create
    func insert<E: EntityProtocol>(_ entity: E) throws

    // Read
    func fetch<E: EntityProtocol>(_ type: E.Type) -> Query<E>
    func get<E: EntityProtocol>(_ type: E.Type, id: UUID) throws -> E?

    // Update
    func update<E: EntityProtocol>(_ entity: E) throws

    // Delete
    func delete<E: EntityProtocol>(_ entity: E) throws
    func delete<E: EntityProtocol>(_ type: E.Type, id: UUID) throws
}
```

### 查询构建器

```swift
struct Query<T> {
    func `where`(_ predicate: Predicate<T>) -> Query<T>
    func order(by keyPath: KeyPath<T, some Comparable>, ascending: Bool) -> Query<T>
    func limit(_ count: Int) -> Query<T>
    func offset(_ count: Int) -> Query<T>

    func all() throws -> [T]
    func first() throws -> T?
    func count() throws -> Int
}

// 查询示例
let users = try store.fetch(User.self)
    .where(\.name == "Alice")
    .where(\.age > 18)
    .order(by: \.createdAt, ascending: false)
    .all()

// 查询嵌套字段（需要已通过 @Index 创建虚拟列）
let shanghaiUsers = try store.fetch(User.self)
    .where(\.address.city == "Shanghai")
    .all()
```

---

## 宏设计

### @Entity 宏

```swift
@attached(member, names: named(tableName), named(columns))
@attached(extension, conformances: EntityProtocol)
macro Entity() = #externalMacro(module: "SwiftStoreMacros", type: "EntityMacro")
```

### 关系宏

#### 在 Entity 上直接定义（无 from）

```swift
// OneToOne（无 from）
macro OneToOne<To, FromField, ToField>(
    fromField: KeyPath<Self, FromField>,
    to: To.Type,
    toField: KeyPath<To, ToField>
) = #externalMacro(module: "SwiftStoreMacros", type: "OneToOneMacro")

// ManyToOne（无 from）
macro ManyToOne<To, FromField, ToField>(
    fromField: KeyPath<Self, FromField>,
    to: To.Type,
    toField: KeyPath<To, ToField>
) = #externalMacro(module: "SwiftStoreMacros", type: "ManyToOneMacro")
```

#### 单独定义关系 Entity（有 from）

```swift
// OneToOne（有 from）
macro OneToOne<From, To, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Self, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Self, ToKey>
) = #externalMacro(module: "SwiftStoreMacros", type: "OneToOneMacro")

// OneToMany（有 from）
macro OneToMany<From, To, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Self, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Self, ToKey>
) = #externalMacro(module: "SwiftStoreMacros", type: "OneToManyMacro")

// ManyToOne（有 from）
macro ManyToOne<From, To, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Self, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Self, ToKey>
) = #externalMacro(module: "SwiftStoreMacros", type: "ManyToOneMacro")

// ManyToMany（有 from）
macro ManyToMany<From, To, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Self, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Self, ToKey>
) = #externalMacro(module: "SwiftStoreMacros", type: "ManyToManyMacro")

// ManyToMany 自引用（有 from + fromName/toName）
macro ManyToMany<From, To, FromField, FromKey, ToField, ToKey>(
    from: From.Type,
    fromField: KeyPath<From, FromField>,
    fromKey: KeyPath<Self, FromKey>,
    to: To.Type,
    toField: KeyPath<To, ToField>,
    toKey: KeyPath<Self, ToKey>,
    fromName: String,
    toName: String
) = #externalMacro(module: "SwiftStoreMacros", type: "ManyToManyMacro")
```

---

### 宏展开效果

#### 普通 Entity 展开

```swift
@Entity
struct User {
    let id: UUID
    var name: String
    let createdAt: Date
    let updatedAt: Date
}

// ========== 展开为 ==========

struct User: EntityProtocol {
    let id: UUID
    var name: String
    let createdAt: Date
    let updatedAt: Date

    static var tableName: String { "user" }
    static var columns: [ColumnDefinition] {
        [
            ColumnDefinition(name: "id", type: .text, nullable: false, primaryKey: true),
            ColumnDefinition(name: "name", type: .text, nullable: false),
            ColumnDefinition(name: "created_at", type: .real, nullable: false),
            ColumnDefinition(name: "updated_at", type: .real, nullable: false)
        ]
    }
}
```

#### 带关系的 Entity 展开

```swift
@Entity
@ManyToMany(from: User.self, fromField: \.id, fromKey: \.userId,
            to: Tag.self, toField: \.id, toKey: \.tagId)
struct UserTags {
    let id: UUID
    let userId: UUID
    let tagId: UUID
    var metadata: RelationMetadata
    let createdAt: Date
    let updatedAt: Date
}

// ========== 展开为 ==========

struct UserTags: EntityProtocol, RelationMarker {
    let id: UUID
    let userId: UUID
    let tagId: UUID
    var metadata: RelationMetadata
    let createdAt: Date
    let updatedAt: Date

    // @Entity 生成
    static var tableName: String { "user_tags" }
    static var columns: [ColumnDefinition] { ... }

    // @ManyToMany 生成
    typealias FromEntity = User
    typealias ToEntity = Tag
    static var fromKeyPath: String { "userId" }
    static var toKeyPath: String { "tagId" }
    static var relationType: RelationType { .manyToMany }
}

// User 扩展
extension User {
    func tags(in store: Store) throws -> [Tag] { ... }
    func tag(tagId: UUID, in store: Store) throws -> Tag? { ... }
    func tagRelations(in store: Store) throws -> [UserTags] { ... }
    func addTag(tagId: UUID, in store: Store) throws -> UserTags { ... }
    func addTag(tagId: UUID, metadata: RelationMetadata, in store: Store) throws -> UserTags { ... }
    func addTags(tagIds: [UUID], in store: Store) throws -> [UserTags] { ... }
    func removeTag(tagId: UUID, in store: Store) throws { ... }
    func removeAllTags(in store: Store) throws { ... }
    func hasTag(tagId: UUID, in store: Store) throws -> Bool { ... }
    func tagsCount(in store: Store) throws -> Int { ... }
}

// Tag 扩展
extension Tag {
    func users(in store: Store) throws -> [User] { ... }
    func user(userId: UUID, in store: Store) throws -> User? { ... }
    func userRelations(in store: Store) throws -> [UserTags] { ... }
    func addUser(userId: UUID, in store: Store) throws -> UserTags { ... }
    func removeUser(userId: UUID, in store: Store) throws { ... }
    func hasUser(userId: UUID, in store: Store) throws -> Bool { ... }
    func usersCount(in store: Store) throws -> Int { ... }
}
```

---

## 时间戳自动填充机制

### 填充规则

| 操作 | createdAt | updatedAt |
|-----|-----------|-----------|
| `insert` | 设置为当前时间 | 设置为当前时间 |
| `update` | 保持不变 | 更新为当前时间 |

---

## 事务支持

```swift
extension Store {
    func transaction<T>(_ block: () throws -> T) throws -> T
}

// 使用示例
try store.transaction {
    try store.insert(user)
    try store.insert(post)
    try user.addPost(postId: post.id, in: store)
}
```

---

## 错误处理

```swift
enum StoreError: Error {
    case databaseNotFound
    case invalidSchema(String)
    case entityNotFound(UUID)
    case constraintViolation(String)
    case migrationFailed(String)
    case queryFailed(String)
}
```

---

## 使用示例

```swift
// ============================================================
// 1. 定义辅助类型
// ============================================================

struct Address: Codable {
    var street: String
    var city: String
    var zipCode: String
}

struct RelationMetadata: Codable {
    var source: String
    var confidence: Double
}

// ============================================================
// 2. 定义 Entity
// ============================================================

@Entity
struct User {
    let id: UUID
    var name: String
    var email: String
    var address: Address
    let createdAt: Date
    let updatedAt: Date
}

@Entity
struct Tag {
    let id: UUID
    var name: String
    let createdAt: Date
    let updatedAt: Date
}

// ManyToOne: Post 属于 User
@Entity
@ManyToOne(fromField: \.userId, to: User.self, toField: \.id)
struct Post {
    let id: UUID
    var title: String
    var content: String
    let userId: UUID
    let createdAt: Date
    let updatedAt: Date
}

// OneToOne: Profile 属于 User
@Entity
@OneToOne(fromField: \.userId, to: User.self, toField: \.id)
struct Profile {
    let id: UUID
    var bio: String
    var avatarUrl: String?
    let userId: UUID
    let createdAt: Date
    let updatedAt: Date
}

// ManyToMany: User ↔ Tag（带附加字段）
@Entity
@ManyToMany(from: User.self, fromField: \.id, fromKey: \.userId,
            to: Tag.self, toField: \.id, toKey: \.tagId)
struct UserTags {
    let id: UUID
    let userId: UUID
    let tagId: UUID
    var metadata: RelationMetadata
    let createdAt: Date
    let updatedAt: Date
}

// 自引用 ManyToMany: 关注关系
@Entity
@ManyToMany(from: User.self, fromField: \.id, fromKey: \.followerId,
            to: User.self, toField: \.id, toKey: \.followeeId,
            fromName: "following", toName: "followers")
struct Friendship {
    let id: UUID
    let followerId: UUID
    let followeeId: UUID
    var status: String
    let createdAt: Date
    let updatedAt: Date
}

// ============================================================
// 3. 初始化 Store
// ============================================================

let store = try Store(path: "app.db")
try store.register(User.self)
try store.register(Tag.self)
try store.register(Post.self)
try store.register(Profile.self)
try store.register(UserTags.self)
try store.register(Friendship.self)
try store.migrate()

// ============================================================
// 4. 创建数据
// ============================================================

let alice = User(
    id: UUID(),
    name: "Alice",
    email: "alice@example.com",
    address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
    createdAt: Date(),
    updatedAt: Date()
)
try store.insert(alice)

let bob = User(
    id: UUID(),
    name: "Bob",
    email: "bob@example.com",
    address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
    createdAt: Date(),
    updatedAt: Date()
)
try store.insert(bob)

let swiftTag = Tag(id: UUID(), name: "swift", createdAt: Date(), updatedAt: Date())
let iosTag = Tag(id: UUID(), name: "ios", createdAt: Date(), updatedAt: Date())
try store.insert(swiftTag)
try store.insert(iosTag)

// ============================================================
// 5. 使用快捷方法操作关系
// ============================================================

// --- ManyToMany: 添加 Tags ---
try alice.addTag(tagId: swiftTag.id, in: store)
try alice.addTag(tagId: iosTag.id, metadata: RelationMetadata(source: "auto", confidence: 0.9), in: store)

// 查询（双向）
let aliceTags = try alice.tags(in: store)        // [Tag]
let swiftUsers = try swiftTag.users(in: store)   // [User]

// 检查关系
let hasSwift = try alice.hasTag(tagId: swiftTag.id, in: store)  // true

// 获取关系对象（包含附加字段）
let tagRelations = try alice.tagRelations(in: store)  // [UserTags]

// --- 自引用 ManyToMany: 关注关系 ---
// 方法名从 fromName: "following" 派生
try alice.addFollowing(userId: bob.id, in: store)

// 查询
let aliceFollowing = try alice.following(in: store)   // [User]
let bobFollowers = try bob.followers(in: store)       // [User]

// 检查关系
let isFollowing = try alice.hasFollowing(userId: bob.id, in: store)  // true

// 取消关注
try alice.removeFollowing(userId: bob.id, in: store)

// ============================================================
// 6. 查询
// ============================================================

let allUsers = try store.fetch(User.self).all()

let recentUsers = try store.fetch(User.self)
    .order(by: \.createdAt, ascending: false)
    .limit(10)
    .all()
```

---

## 目录结构

```
SwiftStore/
├── Sources/
│   ├── SwiftStore/
│   │   ├── Core/
│   │   │   ├── Store.swift
│   │   │   ├── EntityProtocol.swift
│   │   │   ├── RelationMarker.swift
│   │   │   └── ColumnDefinition.swift
│   │   ├── Query/
│   │   │   ├── Query.swift
│   │   │   ├── Predicate.swift
│   │   │   └── OrderBy.swift
│   │   ├── SQLite/
│   │   │   ├── SQLiteConnection.swift
│   │   │   ├── SQLiteStatement.swift
│   │   │   ├── SQLiteEncoder.swift
│   │   │   └── SQLiteDecoder.swift
│   │   └── Migration/
│   │       └── MigrationManager.swift
│   └── SwiftStoreMacros/
│       ├── EntityMacro.swift
│       ├── OneToOneMacro.swift
│       ├── OneToManyMacro.swift
│       ├── ManyToOneMacro.swift
│       ├── ManyToManyMacro.swift
│       └── RelationExtensionGenerator.swift
└── Tests/
    └── SwiftStoreTests/
        ├── EntityTests.swift
        ├── RelationTests.swift
        └── QueryTests.swift
```

---

## 变更追踪与同步

用于多设备数据同步场景，框架自动捕获所有 Entity 的 CUD 操作。

### 变更日志 Entity

```swift
enum ChangeOperation: String, Codable {
    case insert
    case update
    case delete
}

@Entity
struct ChangeLog {
    let id: UUID
    var entityType: String          // 表名，如 "user", "user_tags"
    var entityId: UUID              // 被修改记录的 ID
    var operation: ChangeOperation  // insert, update, delete
    var payload: String?            // JSON: 变更后的完整数据（delete 时为 nil）
    var deviceId: String            // 产生变更的设备 ID
    var logicalClock: Int64         // 逻辑时钟
    let createdAt: Date
    let updatedAt: Date
}
```

**生成的数据库结构：**

```sql
CREATE TABLE change_log (
    id TEXT PRIMARY KEY NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    payload TEXT,
    device_id TEXT NOT NULL,
    logical_clock INTEGER NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE INDEX idx_change_log_clock ON change_log(logical_clock);
CREATE INDEX idx_change_log_entity ON change_log(entity_type, entity_id);
```

### 启用同步

```swift
let store = try Store(path: "app.db")
store.enableSync(deviceId: "device_A")  // 启用同步，指定设备 ID
```

### 自动记录变更

启用同步后，所有 CUD 操作自动记录到 `change_log` 表：

```swift
// 插入
try store.insert(user)
// 自动记录: ChangeLog(entityType: "user", entityId: user.id, operation: .insert, payload: "{...}")

// 更新
user.name = "New Name"
try store.update(user)
// 自动记录: ChangeLog(entityType: "user", entityId: user.id, operation: .update, payload: "{...}")

// 删除
try store.delete(user)
// 自动记录: ChangeLog(entityType: "user", entityId: user.id, operation: .delete, payload: nil)

// 关系操作也会记录
try alice.addTag(tagId: swift.id, in: store)
// 自动记录: ChangeLog(entityType: "user_tags", entityId: <relation_id>, operation: .insert, payload: "{...}")
```

### 同步 API

```swift
extension Store {
    /// 启用同步
    func enableSync(deviceId: String)

    /// 获取指定时钟之后的所有变更
    func changesSince(clock: Int64) throws -> [ChangeLog]

    /// 获取当前逻辑时钟
    func currentClock() -> Int64

    /// 应用远程变更
    func applyChanges(_ changes: [ChangeLog]) throws

    /// 清理已同步的变更日志（可选）
    func pruneChanges(before clock: Int64) throws
}
```

### 同步流程

```
设备 A                                    设备 B
  │                                          │
  │ 本地操作 insert/update/delete             │
  │   └─ 自动记录到 change_log                │
  │                                          │
  │  ─────────── 同步请求 ───────────►        │
  │  store.changesSince(clock: 1000)         │
  │                                          │
  │  ◄─────────── 返回变更 ───────────        │
  │  [ChangeLog1, ChangeLog2, ...]           │
  │                                          │
  │ store.applyChanges(changes)              │
  │   └─ 更新本地数据                          │
  │   └─ 更新本地时钟                          │
  │                                          │
```

### 应用变更的内部逻辑

```swift
extension Store {
    func applyChanges(_ changes: [ChangeLog]) throws {
        // 按类型排序：先普通 Entity，后关系 Entity（确保外键存在）
        let sorted = changes.sorted { a, b in
            let aIsRelation = isRelationEntity(a.entityType)
            let bIsRelation = isRelationEntity(b.entityType)
            if aIsRelation != bIsRelation {
                return !aIsRelation  // 普通 Entity 优先
            }
            return a.logicalClock < b.logicalClock
        }

        try transaction {
            for change in sorted {
                // 更新本地逻辑时钟
                updateClock(max: change.logicalClock)

                switch change.operation {
                case .insert, .update:
                    // UPSERT: 存在则更新，不存在则插入
                    // 冲突时比较 logicalClock，较大者胜出
                    try upsertFromPayload(
                        entityType: change.entityType,
                        entityId: change.entityId,
                        payload: change.payload!,
                        remoteClock: change.logicalClock
                    )
                case .delete:
                    try deleteById(
                        entityType: change.entityType,
                        id: change.entityId
                    )
                }
            }
        }
    }
}
```

### 逻辑时钟（Hybrid Logical Clock）

```swift
struct HybridClock {
    private var logical: Int64 = 0
    private var counter: Int32 = 0

    /// 生成下一个时钟值
    mutating func tick() -> Int64 {
        let physical = Int64(Date().timeIntervalSince1970 * 1000)

        if physical > logical {
            logical = physical
            counter = 0
        } else {
            counter += 1
        }

        // 高 48 位是逻辑时间，低 16 位是计数器
        return (logical << 16) | Int64(counter)
    }

    /// 更新时钟（收到远程消息时）
    mutating func update(received: Int64) {
        let receivedLogical = received >> 16
        let physical = Int64(Date().timeIntervalSince1970 * 1000)
        logical = max(logical, max(receivedLogical, physical))
    }
}
```

### 冲突解决策略

默认使用 **Last Write Wins**（最后写入胜出）：

```swift
func upsertFromPayload(entityType: String, entityId: UUID, payload: String, remoteClock: Int64) throws {
    if let local = try getExisting(entityType: entityType, id: entityId) {
        // 比较时钟，远程更新才覆盖
        if remoteClock > local.logicalClock {
            try performUpdate(decoded)
        }
        // 否则忽略（本地数据更新）
    } else {
        try performInsert(decoded)
    }
}
```

### 关系 Entity 同步注意事项

关系 Entity（如 `UserTags`、`Friendship`）的同步与普通 Entity 相同：

1. **同步顺序**：先同步普通 Entity，再同步关系 Entity（确保外键引用存在）
2. **唯一性判断**：ManyToMany 按 `(fromKey, toKey)` 判断唯一性，而非单独的 `id`
3. **级联删除**：如果普通 Entity 被删除，相关关系记录由数据库级联删除

```swift
// 两台设备同时添加相同关系的冲突处理
func upsertRelation(entityType: String, payload: String, remoteClock: Int64) throws {
    let relation = try decode(payload)

    // 按 (fromKey, toKey) 查找是否存在
    if let existing = try findRelation(fromKey: relation.fromKey, toKey: relation.toKey) {
        if remoteClock > existing.logicalClock {
            // 保留原 id，更新其他字段
            var updated = relation
            updated.id = existing.id
            try performUpdate(updated)
        }
    } else {
        try performInsert(relation)
    }
}
```

### 使用示例

```swift
// ============================================================
// 设备 A：产生变更
// ============================================================

let storeA = try Store(path: "app_A.db")
storeA.enableSync(deviceId: "device_A")

let alice = User(id: UUID(), name: "Alice", ...)
try storeA.insert(alice)

let tag = Tag(id: UUID(), name: "swift", ...)
try storeA.insert(tag)

try alice.addTag(tagId: tag.id, in: storeA)

// 获取变更
let changes = try storeA.changesSince(clock: 0)
// changes 包含 3 条记录：User insert, Tag insert, UserTags insert

// ============================================================
// 设备 B：应用变更
// ============================================================

let storeB = try Store(path: "app_B.db")
storeB.enableSync(deviceId: "device_B")

// 从设备 A 获取变更并应用
try storeB.applyChanges(changes)

// 现在设备 B 有相同的数据
let aliceOnB = try storeB.get(User.self, id: alice.id)  // ✓ 存在
let tagsOnB = try aliceOnB?.tags(in: storeB)            // ✓ [Tag]
```

---

## 未来扩展方向

1. **观察者模式** - 支持数据变化通知
2. **异步 API** - async/await 支持
3. **加密存储** - SQLCipher 集成
4. **全文搜索** - FTS5 集成
