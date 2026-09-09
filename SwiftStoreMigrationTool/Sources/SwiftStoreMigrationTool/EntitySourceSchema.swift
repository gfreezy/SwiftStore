import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftStoreMacroSupport
import SwiftStoreCore

/// Uses the actual Entity macro implementation, not a second set of type/default/index rules.
public enum EntitySourceSchema {
    /// Lightweight discovery only; full schema extraction still validates the selected target.
    public static func containsEntity(files: [URL]) throws -> Bool {
        for file in files {
            let visitor = EntityVisitor()
            visitor.walk(Parser.parse(source: try String(contentsOf: file, encoding: .utf8)))
            if !visitor.entities.isEmpty { return true }
        }
        return false
    }

    public static func extract(files: [URL], createUpdateTrigger: Bool = false) throws -> SchemaSnapshot {
        var tables: [TableSchema] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let syntax = Parser.parse(source: source)
            guard !syntax.hasError else { throw failure("Cannot parse Swift source: \(file.path)") }
            let visitor = EntityVisitor()
            visitor.walk(syntax)
            for (node, attribute) in visitor.entities {
                // Source tools cannot infer the consuming compiler's active #if configuration.
                var ancestor: Syntax? = Syntax(node)
                while let current = ancestor {
                    if current.is(IfConfigDeclSyntax.self) {
                        throw failure("Conditional @Entity is unsupported: \(file.path). Use a stable schema across configurations.")
                    }
                    ancestor = current.parent
                }
                let conditions = ConditionalVisitor()
                conditions.walk(node.memberBlock)
                guard !conditions.found else { throw failure("Conditional members in @Entity \(node.name.text) are unsupported: \(file.path)") }
                let context = BasicMacroExpansionContext()
                let members = try EntityMacro.expansion(of: attribute, providingMembersOf: node,
                    conformingTo: [], in: context)
                guard context.diagnostics.isEmpty else { throw failure("Entity macro diagnostics for \(node.name.text): \(context.diagnostics)") }
                let metadata = MetadataVisitor()
                for member in members {
                    guard let property = member.as(VariableDeclSyntax.self),
                          let name = property.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                          ["tableName", "columns", "indexes"].contains(name) else { continue }
                    if name == "tableName" {
                        let strings = StringVisitor()
                        strings.walk(property)
                        metadata.tableName = strings.values.first
                    } else { metadata.walk(property) }
                }
                guard let name = metadata.tableName else { throw failure("Missing table metadata for \(node.name.text)") }
                if let error = metadata.error { throw error }
                let triggers = createUpdateTrigger && metadata.columns.contains(where: { $0.name == "updated_at" })
                    ? [DatabaseSchemaBuilder.updateTrigger(for: name)] : []
                tables.append(TableSchema(name: name, columns: metadata.columns, indexes: metadata.indexes, triggers: triggers))
            }
        }
        let result = SchemaSnapshot(tables: tables)
        try result.validate()
        return result
    }

    private static func failure(_ message: String) -> VersionedMigrationError { .invalidHistory(message) }
}

private final class EntityVisitor: SyntaxVisitor {
    var entities: [(StructDeclSyntax, AttributeSyntax)] = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        for attribute in node.attributes {
            if let value = attribute.as(AttributeSyntax.self),
               value.attributeName.trimmedDescription.split(separator: ".").last == "Entity" {
                entities.append((node, value))
            }
        }
        return .visitChildren
    }
}

private final class ConditionalVisitor: SyntaxVisitor {
    var found = false
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind { found = true; return .skipChildren }
}

private final class StringVisitor: SyntaxVisitor {
    var values: [String] = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        if let value = node.representedLiteralValue { values.append(value) }
        return .skipChildren
    }
}

private final class MetadataVisitor: SyntaxVisitor {
    var tableName: String?
    var columns: [ColumnSchema] = []
    var indexes: [IndexSchema] = []
    var error: Error?
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let function = node.calledExpression.trimmedDescription
        guard function == "ColumnDefinition" || function == "IndexDefinition" else { return .visitChildren }
        let arguments = Dictionary(uniqueKeysWithValues: node.arguments.compactMap { argument in
            argument.label.map { ($0.text, argument.expression) }
        })
        func string(_ key: String) -> String? { arguments[key]?.as(StringLiteralExprSyntax.self)?.representedLiteralValue }
        func flag(_ key: String) -> Bool { arguments[key]?.trimmedDescription == "true" }
        guard let name = string("name") else {
            error = VersionedMigrationError.invalidHistory("Invalid generated metadata: \(node)")
            return .skipChildren
        }
        if function == "ColumnDefinition" {
            guard let type = arguments["type"]?.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
                  ["text", "integer", "real", "blob"].contains(type) else {
                error = VersionedMigrationError.invalidHistory("Unsupported generated column type: \(node)")
                return .skipChildren
            }
            columns.append(ColumnSchema(name: name, type: type.uppercased(), isNullable: flag("nullable"),
                isPrimaryKey: flag("primaryKey"), defaultValue: string("defaultValue"), generatedAs: string("generatedAs")))
        } else {
            let array = arguments["columns"]?.as(ArrayExprSyntax.self)
            let names = array?.elements.compactMap { $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue } ?? []
            indexes.append(IndexSchema(name: name, columns: names, isUnique: flag("unique")))
        }
        return .skipChildren
    }
}
