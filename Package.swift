// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

/// SwiftStore - A type-safe SQLite ORM for Swift with macro support
///
/// Usage:
/// ```swift
/// .package(url: "https://github.com/gfreezy/SwiftStore", from: "1.0.0")
/// ```
///
/// Products:
/// - SwiftStore: Full framework (recommended)
/// - SwiftStoreCore: Core functionality only (no sync)
/// - SwiftStoreConnectionQueue: With connection pool and sync support
let package = Package(
    name: "SwiftStore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        // Main umbrella library - includes everything
        .library(
            name: "SwiftStore",
            targets: ["SwiftStore"]
        ),
        // Individual libraries for granular imports
        .library(
            name: "SwiftStoreCore",
            targets: ["SwiftStoreCore"]
        ),
        .library(
            name: "SwiftStoreConnectionQueue",
            targets: ["SwiftStoreConnectionQueue"]
        ),
        .library(
            name: "SwiftStoreMacros",
            targets: ["SwiftStoreMacros"]
        ),
        .library(
            name: "SwiftStoreServer",
            targets: ["SwiftStoreServer"]
        ),
        // Development server demo executable
        .executable(
            name: "SwiftStoreServerDemo",
            targets: ["SwiftStoreServerDemo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ],
    targets: [
        // MARK: - Protocols Layer (no dependencies)
        .target(
            name: "SwiftStoreProtocols",
            path: "SwiftStoreProtocols/Sources/SwiftStoreProtocols"
        ),

        // MARK: - Macros Layer
        .macro(
            name: "SwiftStoreMacrosImpl",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "SwiftStoreMacros/Sources/SwiftStoreMacrosImpl"
        ),
        .target(
            name: "SwiftStoreMacros",
            dependencies: [
                "SwiftStoreMacrosImpl",
                "SwiftStoreProtocols",
            ],
            path: "SwiftStoreMacros/Sources/SwiftStoreMacros"
        ),

        // MARK: - Core Layer
        .target(
            name: "SwiftStoreCore",
            dependencies: [
                "SwiftStoreMacros",
                "SwiftStoreProtocols",
            ],
            path: "SwiftStoreCore/Sources/SwiftStoreCore"
        ),

        // MARK: - Change Tracker Layer
        .target(
            name: "SwiftStoreChangeTracker",
            dependencies: [
                "SwiftStoreCore",
                "SwiftStoreMacros",
            ],
            path: "SwiftStoreChangeTracker/Sources/SwiftStoreChangeTracker"
        ),

        // MARK: - Sync Layer
        .target(
            name: "SwiftStoreSync",
            dependencies: [
                "SwiftStoreCore",
                "SwiftStoreChangeTracker",
            ],
            path: "SwiftStoreSync/Sources/SwiftStoreSync"
        ),

        // MARK: - Connection Queue Layer
        .target(
            name: "SwiftStoreConnectionQueue",
            dependencies: [
                "SwiftStoreCore",
                "SwiftStoreSync",
            ],
            path: "SwiftStoreConnectionQueue/Sources/SwiftStoreConnectionQueue"
        ),

        // MARK: - Server Layer (Development HTTP Server)
        .target(
            name: "SwiftStoreServer",
            dependencies: [
                "SwiftStoreConnectionQueue",
            ],
            path: "SwiftStoreServer/Sources/SwiftStoreServer"
        ),

        // MARK: - Umbrella Target
        .target(
            name: "SwiftStore",
            dependencies: [
                "SwiftStoreCore",
                "SwiftStoreChangeTracker",
                "SwiftStoreSync",
                "SwiftStoreConnectionQueue",
            ],
            path: "Sources/SwiftStore"
        ),

        // MARK: - Demo Executable
        .executableTarget(
            name: "SwiftStoreServerDemo",
            dependencies: [
                "SwiftStore",
                "SwiftStoreServer",
            ],
            path: "SwiftStoreServer/Sources/SwiftStoreServerDemo"
        ),

        // MARK: - Tests
        .testTarget(
            name: "SwiftStoreMacroTests",
            dependencies: [
                "SwiftStoreMacrosImpl",
                "SwiftStoreMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "SwiftStoreMacros/Tests/SwiftStoreMacroTests"
        ),
        .testTarget(
            name: "SwiftStoreTests",
            dependencies: ["SwiftStoreCore"],
            path: "SwiftStoreCore/Tests/SwiftStoreTests"
        ),
        .testTarget(
            name: "SwiftStoreChangeTrackerTests",
            dependencies: ["SwiftStoreChangeTracker"],
            path: "SwiftStoreChangeTracker/Tests/SwiftStoreChangeTrackerTests"
        ),
        .testTarget(
            name: "SwiftStoreSyncTests",
            dependencies: ["SwiftStoreSync"],
            path: "SwiftStoreSync/Tests/SwiftStoreSyncTests"
        ),
        .testTarget(
            name: "SwiftStoreConnectionQueueTests",
            dependencies: ["SwiftStoreConnectionQueue"],
            path: "SwiftStoreConnectionQueue/Tests/SwiftStoreConnectionQueueTests"
        ),
        .testTarget(
            name: "SwiftStoreServerTests",
            dependencies: ["SwiftStoreServer"],
            path: "SwiftStoreServer/Tests/SwiftStoreServerTests"
        ),
    ]
)
