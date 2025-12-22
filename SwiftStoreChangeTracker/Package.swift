// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftStoreChangeTracker",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SwiftStoreChangeTracker",
            targets: ["SwiftStoreChangeTracker"]
        ),
    ],
    dependencies: [
        .package(path: "../SwiftStoreCore"),
        .package(path: "../SwiftStoreMacros"),
    ],
    targets: [
        .target(
            name: "SwiftStoreChangeTracker",
            dependencies: [
                .product(name: "SwiftStoreCore", package: "SwiftStoreCore"),
                .product(name: "SwiftStoreMacros", package: "SwiftStoreMacros"),
            ]
        ),
        .testTarget(
            name: "SwiftStoreChangeTrackerTests",
            dependencies: ["SwiftStoreChangeTracker"]
        ),
    ]
)
