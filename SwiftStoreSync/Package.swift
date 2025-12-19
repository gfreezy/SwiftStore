// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftStoreSync",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SwiftStoreSync",
            targets: ["SwiftStoreSync"]
        ),
    ],
    dependencies: [
        .package(path: "../SwiftStoreCore"),
        .package(path: "../SwiftStoreMacros"),
    ],
    targets: [
        .target(
            name: "SwiftStoreSync",
            dependencies: [
                .product(name: "SwiftStoreCore", package: "SwiftStoreCore"),
                .product(name: "SwiftStoreMacros", package: "SwiftStoreMacros"),
            ]
        ),
        .testTarget(
            name: "SwiftStoreSyncTests",
            dependencies: ["SwiftStoreSync"]
        ),
    ]
)
