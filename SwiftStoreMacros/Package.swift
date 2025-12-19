// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftStoreMacros",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SwiftStoreMacros",
            targets: ["SwiftStoreMacros"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0"),
        .package(path: "../SwiftStoreProtocols"),
    ],
    targets: [
        // Macro implementation (compiler plugin)
        .macro(
            name: "SwiftStoreMacrosImpl",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/SwiftStoreMacrosImpl"
        ),
        // Library with macro declarations
        .target(
            name: "SwiftStoreMacros",
            dependencies: [
                "SwiftStoreMacrosImpl",
                .product(name: "SwiftStoreProtocols", package: "SwiftStoreProtocols"),
            ],
            path: "Sources/SwiftStoreMacros"
        ),
        .testTarget(
            name: "SwiftStoreMacroTests",
            dependencies: [
                "SwiftStoreMacrosImpl",
                "SwiftStoreMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/SwiftStoreMacroTests"
        ),
    ]
)
