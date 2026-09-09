import Foundation
import PackagePlugin

@main
struct SwiftStoreMigrationCheck: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let module = target as? SourceModuleTarget else { return [] }
        return try commands(root: URL(fileURLWithPath: target.directory.string), sources: module.sourceFiles.filter { $0.type == .source }.map(\.url),
            work: context.pluginWorkDirectoryURL, executable: context.tool(named: "SwiftStoreMigrationCLI").url)
    }

    private func commands(root: URL, sources: [URL], work: URL, executable: URL) throws -> [Command] {
        let swiftSources = sources.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        let list = work.appendingPathComponent("sources.json")
        let data = try JSONEncoder().encode(swiftSources.map(\.path))
        if (try? Data(contentsOf: list)) != data { try data.write(to: list, options: .atomic) }
        let directory = root.appendingPathComponent("Migrations")
        let fm = FileManager.default
        let snapshots = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let config = root.appendingPathComponent("swiftstore-migrations.json")
        var inputs = swiftSources + snapshots.filter { $0.lastPathComponent.hasSuffix(".schema.json") } + [list]
        if fm.fileExists(atPath: config.path) { inputs.append(config) }
        return [.buildCommand(
            displayName: "Check SwiftStore incremental migrations",
            executable: executable,
            arguments: ["migration", "check", "--target", root.path, "--sources-file", list.path,
                        "--output", work.appendingPathComponent("StoreMigrations.swift").path],
            inputFiles: inputs,
            outputFiles: [work.appendingPathComponent("StoreMigrations.swift")]
        )]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftStoreMigrationCheck: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        try commands(root: context.xcodeProject.directoryURL, sources: target.inputFiles.map(\.url),
            work: context.pluginWorkDirectoryURL, executable: context.tool(named: "SwiftStoreMigrationCLI").url)
    }
}
#endif
