import Foundation
import SwiftParser
import SwiftSyntax
import SwiftStoreCore

/// Resolves a migration root without executing Package.swift, building, or fetching dependencies.
public enum ProjectDiscovery {
    public static func resolve(explicitTarget: String? = nil,
                               from workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> URL {
        let start = workingDirectory.standardizedFileURL.resolvingSymlinksInPath()
        if let explicitTarget {
            let url = URL(fileURLWithPath: explicitTarget, relativeTo: start.appendingPathComponent("", isDirectory: true))
                .standardizedFileURL.resolvingSymlinksInPath()
            guard isDirectory(url) else { throw failure("Target directory does not exist: \(url.path)") }
            return url
        }
        var directory = start
        while true {
            // Existing schema roots also work for nonstandard layouts and deletion of all Entities.
            if isDirectory(directory.appendingPathComponent("Migrations")) {
                return directory
            }
            let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            if entries.contains(where: { $0.pathExtension == "xcodeproj" && isDirectory($0) }) { return directory }
            let manifest = directory.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return try packageTarget(manifest: manifest, start: start)
            }
            // Do not escape the current repository and accidentally select a neighbouring project.
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) { break }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        throw failure("Cannot find a migration project from \(start.path). Run inside an Xcode/SwiftPM project or specify --target <directory>.")
    }

    private static func packageTarget(manifest: URL, start: URL, targetName: String? = nil) throws -> URL {
        let root = manifest.deletingLastPathComponent()
        let syntax = Parser.parse(source: try String(contentsOf: manifest, encoding: .utf8))
        let visitor = PackageTargetsVisitor()
        visitor.walk(syntax)
        guard !syntax.hasError, let expressions = visitor.targets else {
            throw failure("Cannot infer targets from \(manifest.path). Specify --target <source-directory> for a computed Package.swift manifest.")
        }
        var directories: [(name: String, url: URL, plugin: Bool)] = []
        for element in expressions {
            guard let call = element.expression.as(FunctionCallExprSyntax.self),
                  let kind = call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text else {
                throw failure("Cannot infer computed SwiftPM targets. Specify --target <source-directory>.")
            }
            guard ["target", "executableTarget"].contains(kind) else { continue }
            guard let name = literal(call, argument: "name") else {
                throw failure("Cannot infer a computed target name. Specify --target <source-directory>.")
            }
            let path: String
            if call.arguments.contains(where: { $0.label?.text == "path" }) {
                guard let value = literal(call, argument: "path") else {
                    throw failure("Cannot infer path for target \(name). Specify --target <source-directory>.")
                }
                path = value
            } else { path = "Sources/" + name }
            let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
            guard isDirectory(url) else { continue }
            let plugin = call.arguments.first { $0.label?.text == "plugins" }?
                .expression.trimmedDescription.contains("SwiftStoreMigrationCheck") ?? false
            directories.append((name, url, plugin))
        }
        if let targetName {
            return try unique(directories.filter { $0.name == targetName }.map(\.url))
        }
        // Invocation from within a target is an explicit enough signal, even in a multi-target package.
        let containing = directories.filter { start.path == $0.url.path || start.path.hasPrefix($0.url.path + "/") }
        if !containing.isEmpty {
            let deepest = containing.map { $0.url.path.count }.max()!
            return try unique(containing.filter { $0.url.path.count == deepest }.map(\.url))
        }
        let enabled = directories.filter(\.plugin)
        if !enabled.isEmpty { return try unique(enabled.map(\.url)) }
        var candidates: [URL] = []
        for item in directories {
            if try isDirectory(item.url.appendingPathComponent("Migrations")) ||
                EntitySourceSchema.containsEntity(files: MigrationTool.sourceFiles(at: item.url)) {
                candidates.append(item.url)
            }
        }
        return try unique(candidates)
    }

    /// Resolve a named SwiftPM target without executing its manifest. Xcode source membership
    /// is supplied by the build plugin through --sources-file.
    public static func sourceDirectory(targetName: String, projectRoot: URL) throws -> URL? {
        let manifest = projectRoot.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        return try packageTarget(manifest: manifest, start: projectRoot, targetName: targetName)
    }

    private static func unique(_ paths: [URL]) throws -> URL {
        let paths = Array(Set(paths)).sorted { $0.path < $1.path }
        if paths.count == 1 { return paths[0] }
        if paths.isEmpty { throw failure("No Entity target found. Specify --target <source-directory>.") }
        throw failure("Multiple migration targets found: \(paths.map(\.path).joined(separator: ", ")). Specify --target <source-directory>.")
    }
    private static func literal(_ call: FunctionCallExprSyntax, argument: String) -> String? {
        call.arguments.first { $0.label?.text == argument }?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    }
    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
    private static func failure(_ message: String) -> VersionedMigrationError { .invalidHistory(message) }
}

private final class PackageTargetsVisitor: SyntaxVisitor {
    var targets: ArrayElementListSyntax?
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if node.calledExpression.trimmedDescription == "Package" {
            targets = node.arguments.first { $0.label?.text == "targets" }?.expression.as(ArrayExprSyntax.self)?.elements
        }
        return .visitChildren
    }
}
