// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

/// SwiftStore - A type-safe SQLite ORM for Swift with macro support
///
/// Usage:
/// ```swift
/// .package(url: "https://github.com/gfreezy/SwiftStore", from: "4.0.0")
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
        .iOS(.v16),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "SwiftFileStore", targets: ["SwiftFileStore"]),
        .executable(name: "swiftstore", targets: ["SwiftStoreStandaloneCLI"]),
        // Keep the plugin tool in its own product with the same target name. Sharing
        // its target with the standalone product can omit Xcode's host-tool build edge.
        .executable(name: "SwiftStoreMigrationCLI", targets: ["SwiftStoreMigrationCLI"]),
        .plugin(name: "SwiftStoreMigrationCheck", targets: ["SwiftStoreMigrationCheck"]),
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
            name: "SwiftStoreSyncCloudTransport",
            targets: ["SwiftStoreSyncCloudTransport"]
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
        .target(name: "SwiftFileStore", path: "SwiftFileStore/Sources/SwiftFileStore"),
        .testTarget(name: "SwiftFileStoreTests", dependencies: ["SwiftFileStore"], path: "SwiftFileStore/Tests/SwiftFileStoreTests"),
        // MARK: - Protocols Layer (no dependencies)
        .target(
            name: "SwiftStoreProtocols",
            path: "SwiftStoreProtocols/Sources/SwiftStoreProtocols"
        ),

        // MARK: - Macros Layer
        .target(
            name: "SwiftStoreMacroSupport",
            dependencies: [
                "SwiftStoreProtocols",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ],
            path: "SwiftStoreMacros/Sources/SwiftStoreMacroSupport"
        ),
        .macro(
            name: "SwiftStoreMacrosImpl",
            dependencies: [
                "SwiftStoreMacroSupport",
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
            name: "SwiftStoreSQLiteSupport",
            path: "SwiftStoreSQLiteSupport",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SwiftStoreCore",
            dependencies: [
                "SwiftStoreSQLiteSupport",
                "SwiftStoreMacros",
                "SwiftStoreProtocols",
            ],
            path: "SwiftStoreCore/Sources/SwiftStoreCore"
        ),

        .target(
            name: "SwiftStoreMigrationTool",
            dependencies: [
                "SwiftStoreCore", "SwiftStoreMacroSupport",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            ],
            path: "SwiftStoreMigrationTool/Sources/SwiftStoreMigrationTool"
        ),
        .testTarget(
            name: "SwiftStoreMigrationToolTests",
            dependencies: ["SwiftStoreMigrationTool"],
            path: "SwiftStoreMigrationTool/Tests/SwiftStoreMigrationToolTests"
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
                "SwiftStoreSyncCloudTransport",
            ],
            path: "SwiftStoreConnectionQueue/Sources/SwiftStoreConnectionQueue"
        ),

        // MARK: - CloudKit Sync Transport
        .target(
            name: "SwiftStoreSyncCloudTransport",
            dependencies: [
                "SwiftStoreSync",
            ],
            path: "SwiftStoreSyncCloudTransport/Sources/SwiftStoreSyncCloudTransport"
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
            path: "SwiftStoreServer/Sources/SwiftStoreServerDemo",
            resources: [.copy("Migrations/001_initial.schema.json"), .copy("Migrations/002_trigger_format.schema.json")],
            plugins: ["SwiftStoreMigrationCheck"]
        ),

        .executableTarget(
            name: "SwiftStoreStandaloneCLI",
            dependencies: ["SwiftStoreMigrationTool"],
            path: "SwiftStoreMigrationTool/Sources/SwiftStoreStandaloneCLI"
        ),
        .executableTarget(
            name: "SwiftStoreMigrationCLI",
            dependencies: ["SwiftStoreMigrationTool"],
            path: "SwiftStoreMigrationTool/Sources/SwiftStoreCLI"
        ),
        .plugin(
            name: "SwiftStoreMigrationCheck",
            capability: .buildTool(),
            dependencies: ["SwiftStoreMigrationCLI"],
            path: "Plugins/SwiftStoreMigrationCheck"
        ),
        .executableTarget(
            name: "MigrationExample",
            dependencies: ["SwiftStoreCore"],
            path: "Examples/VersionedMigrations",
            resources: [.copy("Migrations/001_initial.schema.json"), .copy("Migrations/002_display_name.schema.json"), .copy("Migrations/003_update_timestamps.schema.json"), .copy("Migrations/004_trigger_format.schema.json")],
            plugins: ["SwiftStoreMigrationCheck"]
        ),

        // MARK: - Tests
        .testTarget(
            name: "SwiftStoreMacroTests",
            dependencies: [
                "SwiftStoreMacroSupport",
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
            name: "SwiftStoreSyncCloudTransportTests",
            dependencies: ["SwiftStoreSyncCloudTransport"],
            path: "SwiftStoreSyncCloudTransport/Tests/SwiftStoreSyncCloudTransportTests"
        ),
        .testTarget(
            name: "SwiftStoreServerTests",
            dependencies: ["SwiftStoreServer"],
            path: "SwiftStoreServer/Tests/SwiftStoreServerTests"
        ),
    ]
)
