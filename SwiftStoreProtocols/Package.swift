// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftStoreProtocols",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SwiftStoreProtocols",
            targets: ["SwiftStoreProtocols"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftStoreProtocols"
        ),
    ]
)
