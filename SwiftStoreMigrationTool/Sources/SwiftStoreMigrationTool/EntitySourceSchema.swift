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

    public static func extract(files: [URL]) throws -> SchemaSnapshot {
        var tables: [TableSchema] = []
        let sources = try files.sorted(by: { $0.path < $1.path }).map { file in
            let syntax = Parser.parse(source: try String(contentsOf: file, encoding: .utf8))
            guard !syntax.hasError else { throw failure("Cannot parse Swift source: \(file.path)") }
            return (file, syntax)
        }
        let types = SourceSQLiteTypes(trees: sources.map { $0.1 })
        for (file, syntax) in sources {
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
                let metadata = MetadataVisitor(types: types, scope: SourceSQLiteTypes.scope(of: node))
                for member in members {
                    guard let property = member.as(VariableDeclSyntax.self),
                          let name = property.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                          ["tableName", "columns", "indexes", "fullTextIndexes"].contains(name) else { continue }
                    if name == "tableName" {
                        let strings = StringVisitor()
                        strings.walk(property)
                        metadata.tableName = strings.values.first
                    } else { metadata.walk(property) }
                }
                guard let name = metadata.tableName else { throw failure("Missing table metadata for \(node.name.text)") }
                if let error = metadata.error { throw error }
                let triggers = metadata.columns.contains(where: { $0.name == "updated_at" })
                    ? [DatabaseSchemaBuilder.updateTrigger(for: name)] : []
                tables.append(TableSchema(name: name, columns: metadata.columns, indexes: metadata.indexes, triggers: triggers, fullTextIndexes: metadata.fullTextIndexes))
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
    var fullTextIndexes: [FullTextIndexDefinition] = []
    var error: Error?
    private let types: SourceSQLiteTypes
    private let scope: [String]
    init(types: SourceSQLiteTypes, scope: [String]) {
        self.types = types; self.scope = scope
        super.init(viewMode: .sourceAccurate)
    }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let function = node.calledExpression.trimmedDescription
        guard ["ColumnDefinition", "IndexDefinition", "FullTextIndexDefinition"].contains(function) else { return .visitChildren }
        let arguments = Dictionary(uniqueKeysWithValues: node.arguments.compactMap { argument in
            argument.label.map { ($0.text, argument.expression) }
        })
        func string(_ key: String) -> String? { arguments[key]?.as(StringLiteralExprSyntax.self)?.representedLiteralValue }
        func flag(_ key: String) -> Bool { arguments[key]?.trimmedDescription == "true" }
        guard let name = string("name") else {
            error = VersionedMigrationError.invalidHistory("Invalid generated metadata: \(node)")
            return .skipChildren
        }
        if function == "FullTextIndexDefinition" {
            let fields = arguments["columns"]?.as(ArrayExprSyntax.self)?.elements.compactMap { element -> FullTextColumn? in
                guard let call = element.expression.as(FunctionCallExprSyntax.self) else { return nil }
                let args = Dictionary(uniqueKeysWithValues: call.arguments.compactMap { arg in
                    arg.label.map { ($0.text, arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue) }
                })
                guard let fieldName = args["name"] ?? nil, let column = args["column"] ?? nil else { return nil }
                let arrays = call.arguments.first(where: { $0.label?.text == "arrayPaths" })?
                    .expression.as(ArrayExprSyntax.self)?.elements.compactMap {
                        $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
                    }
                return FullTextColumn(name: fieldName, column: column, jsonPath: args["jsonPath"] ?? nil, arrayPaths: arrays)
            } ?? []
            let keys = arguments["keyColumns"]?.as(ArrayExprSyntax.self)?.elements.compactMap {
                $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
            } ?? []
            guard let tokenizerName = arguments["tokenizer"]?.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
                  let tokenizer = FullTextTokenizer(rawValue: tokenizerName) else {
                error = VersionedMigrationError.invalidHistory("Invalid FTS tokenizer metadata")
                return .skipChildren
            }
            fullTextIndexes.append(FullTextIndexDefinition(name: name, columns: fields, keyColumns: keys, tokenizer: tokenizer))
        } else if function == "ColumnDefinition" {
            do {
                guard let member = arguments["type"]?.as(MemberAccessExprSyntax.self) else {
                    throw VersionedMigrationError.invalidHistory("Unsupported generated column type: \(node)")
                }
                let field = member.declName.baseName.text
                let type: SQLiteType
                if field == "sqliteType", let base = member.base?.trimmedDescription {
                    type = try types.resolve(base, scope: scope)
                } else if let literal = SQLiteType(rawValue: field.uppercased()), member.base == nil {
                    type = literal
                } else { throw VersionedMigrationError.invalidHistory("Unsupported generated column type: \(node)") }
                var defaultValue = string("defaultValue")
                if let call = arguments["defaultValue"]?.as(FunctionCallExprSyntax.self),
                   call.calledExpression.trimmedDescription == "ColumnDefinition.jsonDefaultValue" {
                    guard let reference = call.arguments.first?.expression.as(MemberAccessExprSyntax.self),
                          reference.declName.baseName.text == "self", let codec = reference.base?.trimmedDescription,
                          let fallback = call.arguments.last?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                        throw VersionedMigrationError.invalidHistory("Unsupported JSON default metadata: \(call)")
                    }
                    defaultValue = try types.isJSONEncoded(codec, scope: scope) ? fallback : nil
                }
                columns.append(ColumnSchema(name: name, type: type.rawValue, isNullable: flag("nullable"),
                    isPrimaryKey: flag("primaryKey"), defaultValue: defaultValue, generatedAs: string("generatedAs")))
            } catch { self.error = error }
        } else {
            let array = arguments["columns"]?.as(ArrayExprSyntax.self)
            let names = array?.elements.compactMap { $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue } ?? []
            indexes.append(IndexSchema(name: name, columns: names, isUnique: flag("unique")))
        }
        return .skipChildren
    }
}
