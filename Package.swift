// swift-tools-version: 6.0
import PackageDescription

/// SwiftStore - A type-safe SQLite ORM for Swift with macro support
///
/// This is the root package that re-exports the sub-packages:
/// - SwiftStoreMacros: Entity and relation macros
/// - SwiftStoreCore: Main library with Store, Query, Sync functionality
///
/// Usage:
/// ```swift
/// .package(url: "https://github.com/user/swift-store.git", from: "1.0.0")
/// ```
/// Then depend on "SwiftStore" to get both macros and core library.
let package = Package(
    name: "SwiftStore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SwiftStore",
            targets: ["SwiftStore"]
        ),
    ],
    dependencies: [
        .package(path: "./SwiftStoreCore"),
        .package(path: "./SwiftStoreChangeTracker"),
        .package(path: "./SwiftStoreSync"),
        .package(path: "./SwiftStoreConnectionQueue"),
        .package(path: "./SwiftStoreMacros"),
    ],
    targets: [
        // Re-export all SwiftStore sub-packages
        .target(
            name: "SwiftStore",
            dependencies: [
                .product(name: "SwiftStoreCore", package: "SwiftStoreCore"),
                .product(name: "SwiftStoreChangeTracker", package: "SwiftStoreChangeTracker"),
                .product(name: "SwiftStoreSync", package: "SwiftStoreSync"),
                .product(name: "SwiftStoreConnectionQueue", package: "SwiftStoreConnectionQueue"),
            ]
        ),
    ]
)
