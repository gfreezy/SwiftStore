// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftStoreCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SwiftStoreCore",
            targets: ["SwiftStoreCore"]
        ),
    ],
    dependencies: [
        .package(path: "../SwiftStoreMacros"),
        .package(path: "../SwiftStoreProtocols"),
    ],
    targets: [
        .target(
            name: "SwiftStoreCore",
            dependencies: [
                .product(name: "SwiftStoreMacros", package: "SwiftStoreMacros"),
                .product(name: "SwiftStoreProtocols", package: "SwiftStoreProtocols"),
            ],
            path: "Sources/SwiftStoreCore"
        ),
        .testTarget(
            name: "SwiftStoreTests",
            dependencies: ["SwiftStoreCore"],
            path: "Tests/SwiftStoreTests"
        ),
    ]
)
