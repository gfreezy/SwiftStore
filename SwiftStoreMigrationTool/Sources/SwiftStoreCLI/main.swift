import Foundation
import SwiftStoreMigrationTool

let usage = """
Usage:
  swiftstore migration add <ID> [--target <source-directory>]
  swiftstore migration check [--target <source-directory>]

Without --target, discover the project from the current directory (ambiguous or missing roots are errors).
Migrations live in <source-directory>/Migrations. IDs use <digits>_<description> and sort by numeric prefix.
Numbers must be unique ignoring leading zeros; a new number must exceed the latest one.
Tables with updated_at automatically receive an update trigger, whether or not sync is enabled.
The build plugin calls check with --sources-file and --output automatically.
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
        guard ["--target", "--sources-file", "--output"].contains(key), !arguments.isEmpty, options[key] == nil else {
            throw CLIError.message("Invalid or repeated option: \(key)\n\(usage)")
        }
        options[key] = arguments.removeFirst()
    }
    guard ["add", "check"].contains(action), action != "add" || id != nil else { throw CLIError.message(usage) }
    let root = try ProjectDiscovery.resolve(explicitTarget: options["--target"])
    print("Migration project: \(root.path)")
    let sources = try options["--sources-file"].map { path in
        try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: path))).map { URL(fileURLWithPath: $0) }
    }
    switch action {
    case "add":
        guard let id, options["--output"] == nil else { throw CLIError.message(usage) }
        try MigrationTool.generate(id: id, target: MigrationTool.currentSchema(at: root, sources: sources),
            directory: root.appendingPathComponent("Migrations"))
        print("Created \(id). Review the migration and fill any manual SQL before building.")
    case "check":
        try MigrationTool.check(root: root, sources: sources, output: options["--output"].map { URL(fileURLWithPath: $0) })
        print("Schema and migration history match.")
    default: throw CLIError.message(usage)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let text): return text } }
}
