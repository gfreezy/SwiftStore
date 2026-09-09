import Foundation
import Testing
import SwiftStoreMigrationTool

@Suite("CLI project discovery")
struct ProjectDiscoveryTests {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Isolate tests from projects in parent folders.
        try Data().write(to: url.appendingPathComponent(".git"))
        return url
    }
    private func directory(_ path: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func package(in root: URL, targets: String) throws {
        try "import PackageDescription\nlet package = Package(name: \"Fixture\", targets: [\(targets)])"
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    }
    private func model(in root: URL) throws {
        try "@Entity(readonly: true) struct Item { var id: Int }"
            .write(to: root.appendingPathComponent("Item.swift"), atomically: true, encoding: .utf8)
    }

    @Test("Find Xcode project from a nested directory")
    func xcode() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try directory("App.xcodeproj", in: root)
        let nested = try directory("App/Views", in: root)
        #expect(try ProjectDiscovery.resolve(from: nested).path == root.resolvingSymlinksInPath().path)
    }

    @Test("Find sole Entity target, honour custom paths and ignore test targets")
    func swiftPackage() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try package(in: root, targets: ".target(name: \"Models\", path: \"Domain\"), .target(name: \"Utilities\"), .testTarget(name: \"Tests\")")
        let models = try directory("Domain", in: root)
        let tests = try directory("Tests", in: root)
        _ = try directory("Sources/Utilities", in: root)
        try model(in: models)
        try model(in: tests)
        #expect(try ProjectDiscovery.resolve(from: root).path == models.resolvingSymlinksInPath().path)
    }

    @Test("Multiple candidates fail at package root; location within a target disambiguates")
    func ambiguous() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try package(in: root, targets: ".target(name: \"A\"), .target(name: \"B\")")
        let a = try directory("Sources/A", in: root)
        let b = try directory("Sources/B", in: root)
        try model(in: a)
        try model(in: b)
        #expect(throws: (any Error).self) { try ProjectDiscovery.resolve(from: root) }
        #expect(try ProjectDiscovery.resolve(from: a).path == a.resolvingSymlinksInPath().path)
        #expect(try ProjectDiscovery.resolve(explicitTarget: "Sources/B", from: root).path == b.resolvingSymlinksInPath().path)
    }

    @Test("Existing history is discoverable even after the last Entity was removed")
    func existingHistory() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try directory("Migrations", in: root)
        let nested = try directory("Views", in: root)
        #expect(try ProjectDiscovery.resolve(from: nested).path == root.resolvingSymlinksInPath().path)
    }

    @Test("Prefer the plugin-enabled target")
    func pluginTarget() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try package(in: root, targets: ".target(name: \"App\", plugins: [.plugin(name: \"SwiftStoreMigrationCheck\", package: \"SwiftStore\")]), .target(name: \"Fixture\")")
        let app = try directory("Sources/App", in: root)
        let fixture = try directory("Sources/Fixture", in: root)
        try model(in: fixture)
        #expect(try ProjectDiscovery.resolve(from: root).path == app.resolvingSymlinksInPath().path)
    }

    @Test("Missing project or explicit nonexistent directory fails without creating files")
    func missing() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) { try ProjectDiscovery.resolve(from: root) }
        #expect(throws: (any Error).self) { try ProjectDiscovery.resolve(explicitTarget: "missing", from: root) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Migrations").path))
    }

    @Test("Computed manifests fail instead of being executed or guessed")
    func computedManifest() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try "let package = Package(name: \"App\", targets: makeTargets())"
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try ProjectDiscovery.resolve(from: root) }
    }
}
