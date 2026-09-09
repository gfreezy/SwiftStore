import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftStoreProtocols

public struct FullTextIndexMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        // Marker only; Entity emits metadata and type checks with known member names.
        []
    }
}

struct FullTextMarkerParser {
    static func parse(from members: MemberBlockItemListSyntax, tableName: String,
                      keyColumns: [String], properties: [PropertyInfo]) throws -> [FullTextIndexDefinition] {
        var result: [FullTextIndexDefinition] = []
        for member in members {
            guard let macro = member.decl.as(MacroExpansionDeclSyntax.self),
                  macro.macroName.text == "FullTextIndex" else { continue }
            var fields: [FullTextColumn] = []
            var name: String?
            var tokenizer: FullTextTokenizer = .unicode61
            for argument in macro.arguments {
                if let label = argument.label?.text {
                    switch label {
                    case "name":
                        guard let value = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                            throw MacroError.message("#FullTextIndex name must be a string literal")
                        }
                        name = value
                    case "tokenizer":
                        guard let value = argument.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
                              let parsed = FullTextTokenizer(rawValue: value) else {
                            throw MacroError.message("#FullTextIndex tokenizer must be .unicode61, .porter or .trigram")
                        }
                        tokenizer = parsed
                    default: throw MacroError.message("Unknown #FullTextIndex argument: \(label)")
                    }
                    continue
                }
                guard let path = argument.expression.as(KeyPathExprSyntax.self) else {
                    throw MacroError.message("#FullTextIndex requires property key paths")
                }
                var components: [String] = []
                for component in path.components {
                    guard let property = component.component.as(KeyPathPropertyComponentSyntax.self) else {
                        throw MacroError.message("#FullTextIndex supports property paths, not subscripts or optional chaining")
                    }
                    components.append(property.declName.baseName.text)
                }
                guard let root = components.first, let property = properties.first(where: { $0.name == root }) else {
                    throw MacroError.message("#FullTextIndex must reference a stored Entity property")
                }
                if components.count == 1 {
                    guard ["String", "String?", "Optional<String>"].contains(property.type) else {
                        throw MacroError.message("#FullTextIndex fields must be String or String?")
                    }
                } else if property.isPrimitive {
                    throw MacroError.message("Nested #FullTextIndex paths must start at a JSON property")
                }
                let names = components.map { MacroHelpers.camelToSnakeCase($0) }
                fields.append(FullTextColumn(name: names.joined(separator: "__"), column: names[0],
                    jsonPath: names.count > 1 ? "$." + names.dropFirst().joined(separator: ".") : nil))
            }
            guard !fields.isEmpty else { throw MacroError.message("#FullTextIndex requires at least one text field") }
            result.append(FullTextIndexDefinition(name: name ?? "\(tableName)_fts", columns: fields,
                keyColumns: keyColumns, tokenizer: tokenizer))
        }
        guard Set(result.map { $0.name.lowercased() }).count == result.count else {
            throw MacroError.message("Full-text index names must be unique; give additional indexes an explicit name")
        }
        return result
    }
}
