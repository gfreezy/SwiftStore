// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftStoreConnectionQueue",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SwiftStoreConnectionQueue",
            targets: ["SwiftStoreConnectionQueue"]
        ),
    ],
    dependencies: [
        .package(path: "../SwiftStoreCore"),
        .package(path: "../SwiftStoreSync"),
    ],
    targets: [
        .target(
            name: "SwiftStoreConnectionQueue",
            dependencies: [
                .product(name: "SwiftStoreCore", package: "SwiftStoreCore"),
                .product(name: "SwiftStoreSync", package: "SwiftStoreSync"),
            ]
        ),
    ]
)
