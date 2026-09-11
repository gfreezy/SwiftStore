// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftFileStore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "SwiftFileStore", targets: ["SwiftFileStore"])],
    targets: [
        .target(name: "SwiftFileStore"),
        .testTarget(name: "SwiftFileStoreTests", dependencies: ["SwiftFileStore"])
    ]
)
