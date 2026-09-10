import Foundation
import PackagePlugin

@main
struct SwiftStoreMigrationCheck: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let module = target as? SwiftSourceModuleTarget else { return [] }
        return try commands(root: module.directoryURL, targetName: module.name, sources: module.sourceFiles.filter { $0.type == .source }.map(\.url),
            work: context.pluginWorkDirectoryURL, executable: context.tool(named: "SwiftStoreMigrationCLI").url)
    }

    private func commands(root: URL, targetName: String, sources: [URL], work: URL, executable: URL) throws -> [Command] {
        let swiftSources = sources.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        let list = work.appendingPathComponent("sources.json")
        let data = try JSONEncoder().encode(swiftSources.map(\.path))
        if (try? Data(contentsOf: list)) != data { try data.write(to: list, options: .atomic) }
        let fm = FileManager.default
        var directories = [root.appendingPathComponent("Migrations")]
        var inputs = swiftSources + [list]
        if let file = MigrationConfiguration.find(from: root) {
            let config = try MigrationConfiguration.read(at: file)
            guard let target = config.targets[targetName] else {
                throw ConfigurationError("No swiftstore.json configuration for target \(targetName)")
            }
            inputs.append(file)
            let configRoot = file.deletingLastPathComponent()
            directories = try target.databases.flatMap { database in
                try ([database.migrations] + (database.schemas.map { [$0] } ?? [])).map {
                    try MigrationConfiguration.resolve($0, relativeTo: configRoot)
                }
            }
            // Include configured files outside Compile Sources too, so turning a helper into an
            // uncompiled Entity invalidates the command and produces an ownership diagnostic.
            for path in target.databases.flatMap(\.sources) {
                let url = try MigrationConfiguration.resolve(path, relativeTo: configRoot)
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        let files = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
                        while let file = files?.nextObject() as? URL {
                            if file.pathExtension == "swift" { inputs.append(file) }
                        }
                    } else { inputs.append(url) }
                }
            }
        }
        for directory in directories {
            let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            inputs += files.filter { $0.lastPathComponent.hasSuffix(".schema.json") || $0.pathExtension == "swift" }
        }
        inputs = Array(Set(inputs)).sorted { $0.path < $1.path }
        // Changing the set of inputs (including deleting a schema file for a data-only step)
        // must invalidate the command even when all remaining input timestamps are unchanged.
        let manifest = work.appendingPathComponent("migration-inputs.json")
        let manifestData = try JSONEncoder().encode(inputs.map(\.path))
        if (try? Data(contentsOf: manifest)) != manifestData { try manifestData.write(to: manifest, options: .atomic) }
        inputs.append(manifest)
        return [.buildCommand(
            displayName: "Check SwiftStore incremental migrations",
            executable: executable,
            arguments: ["migration", "check", "--target", root.path, "--target-name", targetName, "--sources-file", list.path,
                        "--stamp", work.appendingPathComponent("migration-check.stamp").path],
            inputFiles: inputs,
            outputFiles: [work.appendingPathComponent("migration-check.stamp")]
        )]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftStoreMigrationCheck: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        try commands(root: context.xcodeProject.directoryURL, targetName: target.displayName, sources: target.inputFiles.map(\.url),
            work: context.pluginWorkDirectoryURL, executable: context.tool(named: "SwiftStoreMigrationCLI").url)
    }
}
#endif
