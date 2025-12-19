// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

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
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        // Main library target
        .target(
            name: "SwiftStore",
            dependencies: ["SwiftStoreMacros"],
            path: "Sources/SwiftStore"
        ),

        // Macro implementation target
        .macro(
            name: "SwiftStoreMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/SwiftStoreMacros"
        ),

        // Test target for Store functionality
        .testTarget(
            name: "SwiftStoreTests",
            dependencies: ["SwiftStore"],
            path: "Tests/SwiftStoreTests"
        ),

        // Test target for Macros
        .testTarget(
            name: "SwiftStoreMacroTests",
            dependencies: [
                "SwiftStoreMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/SwiftStoreMacroTests"
        ),
    ]
)
