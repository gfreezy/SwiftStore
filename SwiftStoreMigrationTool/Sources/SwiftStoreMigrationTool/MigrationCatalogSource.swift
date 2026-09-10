import Foundation
import SwiftParser
import SwiftSyntax
import SwiftStoreCore

/// Editable, checked-in registration source. CLI add preserves existing statements and comments.
/// Static registration metadata is checked without evaluating migration code during a build.
enum MigrationCatalogSource {
    static func name(namespace: String?) -> String { namespace.map { $0 + "Migrations" } ?? "StoreMigrations" }

    static func render(history: [MigrationFile], namespace: String?) throws -> String {
        var lines = ["// Created by swiftstore CLI. Commit this file; manual edits are allowed.",
                     "import Foundation", "import SwiftStoreCore", "",
                     "public enum \(name(namespace: namespace)) {", "    public static func all(bundle: Bundle = .main, subdirectory: String? = nil) throws -> [StoreMigration] {",
                     "        var catalog = StoreMigrationCatalog()"]
        for entry in history { lines += try registration(entry) }
        lines += ["        return catalog.migrations", "    }", "}", ""]
        return lines.joined(separator: "\n")
    }

    private static func registration(_ entry: MigrationFile) throws -> [String] {
        var lines = ["        try catalog.append(id: \(String(reflecting: entry.id)),"]
        if entry.hasSnapshot {
            lines.append("            delta: try SchemaDelta.load(\(String(reflecting: entry.schemaFilename)), in: bundle, subdirectory: subdirectory),")
        }
        lines.append("            up: \(entry.symbol).up)")
        return lines
    }

    static func appending(_ entry: MigrationFile, to source: String, history: [MigrationFile], namespace: String?) throws -> String {
        try validate(source, history: history, namespace: namespace)
        let body = try body(source, namespace: namespace)
        guard let last = body.statements.last, last.item.is(ReturnStmtSyntax.self) else {
            throw failure("Catalog all() must end with a return statement to append a migration automatically")
        }
        let offset = last.position.utf8Offset
        let bytes = Array(source.utf8)
        let addition = "\n" + (try registration(entry)).joined(separator: "\n")
        return String(decoding: bytes[..<offset], as: UTF8.self) + addition + String(decoding: bytes[offset...], as: UTF8.self)
    }

    static func validate(_ source: String, history: [MigrationFile], namespace: String?) throws {
        let body = try body(source, namespace: namespace)
        let calls = body.statements.compactMap { statement -> FunctionCallExprSyntax? in
            guard let expression = statement.item.as(ExprSyntax.self),
                  let call = unwrapped(expression).as(FunctionCallExprSyntax.self),
                  tokens(call.calledExpression) == "catalog.append" else { return nil }
            return call
        }
        guard calls.count == history.count else {
            throw failure("Catalog registrations do not match migration history. Update the catalog manually or run swiftstore migration catalog")
        }
        for (call, entry) in zip(calls, history) {
            let ids = call.arguments.filter { $0.label?.text == "id" }
            let ups = call.arguments.filter { $0.label?.text == "up" }
            let deltas = call.arguments.filter { $0.label?.text == "delta" }
            guard ids.count == 1, ups.count == 1, deltas.count <= 1,
                  ids.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == entry.id,
                  ups.first.map({ tokens($0.expression) }) == entry.symbol + ".up" else {
                throw failure("Catalog ID, order or up reference differs at \(entry.id)")
            }
            if entry.hasSnapshot {
                let filename = entry.schemaFilename
                guard let expression = deltas.first?.expression,
                      let load = unwrapped(expression).as(FunctionCallExprSyntax.self),
                      tokens(load.calledExpression) == "SchemaDelta.load", load.arguments.count == 3,
                      load.arguments.first?.label == nil,
                      load.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == filename,
                      load.arguments.filter({ $0.label?.text == "in" }).count == 1,
                      load.arguments.first(where: { $0.label?.text == "in" }).map({ tokens($0.expression) }) == "bundle",
                      load.arguments.filter({ $0.label?.text == "subdirectory" }).count == 1,
                      load.arguments.first(where: { $0.label?.text == "subdirectory" }).map({ tokens($0.expression) }) == "subdirectory" else {
                    throw failure("Catalog schema resource differs at \(entry.id). Use SchemaDelta.load(\"\(filename)\", in: bundle, subdirectory: subdirectory)")
                }
            } else if !deltas.isEmpty {
                throw failure("Data-only catalog entry \(entry.id) must inherit the preceding schema without a resource")
            }
        }
    }

    private static func body(_ source: String, namespace: String?) throws -> CodeBlockSyntax {
        let syntax = Parser.parse(source: source)
        let declarations = syntax.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }
            .filter { $0.name.text == name(namespace: namespace) }
        let methods = declarations.flatMap { $0.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) } }
            .filter { $0.name.text == "all" }
        guard !syntax.hasError, declarations.count == 1, methods.count == 1, let body = methods.first?.body else {
            throw failure("Expected one enum \(name(namespace: namespace)) with an all() method")
        }
        return body
    }

    private static func unwrapped(_ expression: ExprSyntax) -> ExprSyntax {
        if let value = expression.as(TryExprSyntax.self) { return value.expression }
        return expression
    }

    private static func tokens(_ syntax: some SyntaxProtocol) -> String {
        syntax.tokens(viewMode: .sourceAccurate).map(\.text).joined()
    }

    private static func failure(_ message: String) -> VersionedMigrationError { .invalidHistory(message) }
}
