# CLAUDE.md

Project-specific notes for Claude.

## Swift Concurrency: 让 async API 在 caller isolation 上跑

写"接收 closure + 在内部 `Task { }` 跑它"这类异步 API 时,如果想要"caller 在 `@MainActor` 上调用 → body 也在 `@MainActor` 上跑"(不是被 hop 到通用 executor),需要**三件事一起到位**,缺一不可:

### 方案

```swift
public func run<T>(
    isolation: isolated (any Actor)? = #isolation,          // ① 方法体跟 caller 同 isolation
    _ block: @escaping @isolated(any) () async throws -> T  // ② closure 自带 isolation
) async throws -> T {
    let task = Task {
        _ = isolation                                       // ③ Task 闭包捕获 isolation
        return try await block()
    }
    return try await task.value
}
```

### 每一件的作用

| 改动 | 作用 | 不做的后果 |
|---|---|---|
| ① `isolation: isolated (any Actor)? = #isolation` | `run` 方法体本身在 caller 的 isolation 上执行 | `run` 一进入就 hop 到通用 executor(SE-0338 老行为,SPM 默认) |
| ② `@isolated(any)` 在 closure 类型上 | closure 携带**调用方传入时**的 isolation;Task 调它时按 closure 自己的 isolation 跑 | closure 是 nonisolated,即使 Task 在 MainActor 上,`block()` 也会 hop 出去 |
| ③ Task 闭包内 `_ = isolation` | 让 Task closure **强捕获** `isolation` 参数,从而继承其 isolation(见下方 SE-0420 引文) | unstructured `Task { }` 默认 `@concurrent`,不继承 |

> SE-0420 原文(规则源头):
>
> > a closure inherits isolation if ... the current context has an `isolated` parameter ... **and that parameter is strongly captured by the closure** ... [or] **a non-optional binding of an isolated parameter is captured by the closure**.
>
> 也就是说,**"capture" 是显式条件**: closure 必须在 body 里实际引用 `isolation`(哪怕只是 `_ = isolation`)。光把 `isolation` 作为参数挂在外层方法上不够。
>
> 实验验证: 在 `Task { }` 里去掉 `_ = isolation` 后,编译器立刻报 "Passing closure as a 'sending' parameter risks causing data races between 'isolation'-isolated code and **concurrent execution of the closure**" —— 证明 closure 已退回 `@concurrent`,没继承 isolation。

### SPM 默认坑

SPM 包**默认不开** `NonisolatedNonsendingByDefault` upcoming feature,即使 `swift-tools-version: 6.3`。也就是说 nonisolated async 函数默认是老行为(SE-0338): 一进入就 hop 出 caller actor。

所以即使项目升到 Swift 6.3,SPM target 里的 async API 想要"跟 caller 同 isolation",**必须**手动加 ①(`isolation: ... = #isolation`)。不能依赖 SE-0461 的新默认。

如果改成显式开 feature: `swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]`,可以省掉 ①,但 ② ③ 仍然需要。

### 验证测试

`@MainActor` 测试方法里写:

```swift
@MainActor var counter: SomeMainActorClass
_ = try await api.method {
    counter.value += 1               // 不带 await/hop 直接访问 MainActor 状态
    MainActor.assertIsolated()       // 运行时再验证一次
    return counter.value
}
```

如果 closure 没真正继承 isolation,第一行就编译失败("can not be mutated from a nonisolated context"); 编译通过 + 运行时 assert 不抛 = body 真在 MainActor 上跑。

### 不需要这样做的情况

- 同步 closure: 不涉及 Task/await,问题不存在。
- 不在内部开 `Task { }` 的 async API: 加 ① 就够了(`AsyncMutex.withLock`、`timeLog` 异步版的情形)。
- 用 `@isolated(any)` 而不要 `isolation:` 参数也行——但那样**整个外层方法体仍然 hop 出去**,只是 `block()` 调用回到原 isolation。多两次 hop。

### 参考

- [SE-0420: Inheritance of Actor Isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md) — `#isolation` 宏 + `isolated (any Actor)?` 参数;**"strongly captured by the closure" 规则的官方出处**
- [SE-0431: `@isolated(any)` Functions](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0431-isolated-any-functions.md) — closure 类型上的 isolation 标注
- [SE-0461: Async Function Isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md) — nonisolated async 默认行为
- 本项目实现: [SerialLatestRunner.swift](Sources/TalkerCommonSync/SerialLatestRunner.swift), [AsyncMutex.swift](Sources/TalkerCommonSync/AsyncMutex.swift), [Logger.swift](Sources/TalkerCommonLogging/Logger.swift) (`timeLog` 异步版)
