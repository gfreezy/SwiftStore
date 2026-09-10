import Foundation

/// Shared entry point for the standalone CLI and the build plugin host tool.
package enum MigrationCLI {
    package static func main() {
        let usage = """
        Usage:
          swiftstore migration add <ID> [--database <id>] [--target-name <name>] [--target <directory>]
          swiftstore migration catalog [--database <id>] [--target-name <name>] [--target <directory>]
          swiftstore migration check [--database <id>] [--target-name <name>] [--target <directory>]

        Without --target, discover the project from the current directory (ambiguous or missing roots are errors).
        With swiftstore.json, check defaults to every configured database; add must select one.
        Without configuration, use one database with migrations in <source-directory>/Migrations. IDs use <digits>_<description> and sort by numeric prefix.
        Numbers must be unique ignoring leading zeros; a new number must exceed the latest one.
        Tables with updated_at automatically receive an update trigger, whether or not sync is enabled.
        add writes an editable catalog; catalog explicitly regenerates it after manual history changes.
        The build plugin only checks, using --sources-file and a private --stamp output.
        """

        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.isEmpty || arguments == ["--help"] { print(usage); exit(0) }
            guard arguments.count >= 2, arguments.removeFirst() == "migration" else {
                throw CLIError.message(usage)
            }
            let action = arguments.removeFirst()
            var id: String?
            if action == "add", let first = arguments.first, !first.hasPrefix("--") { id = arguments.removeFirst() }
            var options: [String: String] = [:]
            while !arguments.isEmpty {
                let key = arguments.removeFirst()
                guard ["--target", "--target-name", "--database", "--sources-file", "--stamp"].contains(key), !arguments.isEmpty, options[key] == nil else {
                    throw CLIError.message("Invalid or repeated option: \(key)\n\(usage)")
                }
                options[key] = arguments.removeFirst()
            }
            guard ["add", "catalog", "check"].contains(action), action != "add" || id != nil else { throw CLIError.message(usage) }
            let start = try options["--target"].map { try ProjectDiscovery.resolve(explicitTarget: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let root: URL
            if let configuration = MigrationConfiguration.find(from: start) {
                root = configuration.deletingLastPathComponent()
            } else {
                root = try ProjectDiscovery.resolve(explicitTarget: options["--target"])
            }
            print("Migration project: \(root.path)")
            let sources = try options["--sources-file"].map { path in
                try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: path))).map { URL(fileURLWithPath: $0) }
            }
            let project = try MigrationProject.load(root: root, targetName: options["--target-name"], sources: sources)
            switch action {
            case "add":
                guard let id, options["--stamp"] == nil else { throw CLIError.message(usage) }
                try project.generate(id: id, databaseID: options["--database"])
                print("Created \(id). Review the migration and fill any manual SQL before building.")
            case "catalog":
                guard options["--stamp"] == nil else { throw CLIError.message(usage) }
                try project.writeCatalogs(databaseID: options["--database"])
                print("Wrote migration catalogs. Review and commit the Swift files.")
            case "check":
                try project.check(databaseID: options["--database"])
                if let stamp = options["--stamp"] {
                    try Data("Migration check passed.\n".utf8).write(to: URL(fileURLWithPath: stamp), options: .atomic)
                }
                print("Schema, migration history and catalogs match.")
            default: throw CLIError.message(usage)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }

    }
}

private enum CLIError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let text): return text } }
}
