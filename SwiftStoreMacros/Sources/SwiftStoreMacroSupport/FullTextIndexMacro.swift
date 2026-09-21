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
                fields += try projections(argument.expression, properties: properties)
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

    private static func components(_ expression: ExprSyntax) throws -> [String] {
        guard let path = expression.as(KeyPathExprSyntax.self) else {
            throw MacroError.message("#FullTextIndex requires property key paths or .each(array, fields: ...)")
        }
        return try path.components.map { component in
            guard let property = component.component.as(KeyPathPropertyComponentSyntax.self) else {
                throw MacroError.message("#FullTextIndex supports property paths, not subscripts or optional chaining")
            }
            return property.declName.baseName.text
        }
    }

    private static func eachArguments(_ expression: ExprSyntax) throws -> [LabeledExprSyntax]? {
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return nil }
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.base == nil,
              member.declName.baseName.text == "each", call.trailingClosure == nil else {
            throw MacroError.message("Use .each(array, fields: ...) for full-text arrays")
        }
        let args = Array(call.arguments)
        guard args.count >= 2, args[0].label == nil, args[1].label?.text == "fields",
              args.dropFirst(2).allSatisfy({ $0.label == nil }) else {
            throw MacroError.message(".each requires an array key path and at least one field after fields:")
        }
        return args
    }

    private static func jsonPath(_ components: [String]) -> String {
        MacroHelpers.embeddedJSONPath(for: ["root"] + components) ?? "$"
    }

    private static func projections(_ expression: ExprSyntax, properties: [PropertyInfo],
                                    column: String? = nil, names: [String] = [],
                                    arrays: [String] = []) throws -> [FullTextColumn] {
        let args = try eachArguments(expression)
        let path = try components(args?.first?.expression ?? expression)
        guard let first = path.first else { throw MacroError.message("Empty full-text key path") }
        if column == nil {
            guard let property = properties.first(where: { $0.name == first }) else {
                throw MacroError.message("#FullTextIndex must reference a stored Entity property")
            }
            if args == nil, path.count == 1 {
                guard ["String", "String?", "Optional<String>"].contains(property.type) else {
                    throw MacroError.message("#FullTextIndex fields must be String or String?")
                }
            } else if property.isPrimitive {
                throw MacroError.message("Nested #FullTextIndex paths must start at a JSON property")
            }
        }
        let source = column ?? MacroHelpers.camelToSnakeCase(first)
        let fullNames = names + path.map { MacroHelpers.camelToSnakeCase($0) }
        let relative = column == nil ? Array(path.dropFirst()) : path
        if let args {
            return try args.dropFirst().flatMap {
                try projections($0.expression, properties: properties, column: source,
                                names: fullNames, arrays: arrays + [jsonPath(relative)])
            }
        }
        return [FullTextColumn(name: fullNames.joined(separator: "__"), column: source,
            jsonPath: relative.isEmpty ? nil : jsonPath(relative), arrayPaths: arrays.isEmpty ? nil : arrays)]
    }

    static func validation(_ expression: ExprSyntax) throws -> String {
        if let args = try eachArguments(expression) {
            let children = try args.dropFirst().map { try validation($0.expression) }.joined(separator: "\n")
            return "_validateFullTextEach(root, \(args[0].expression.trimmedDescription)) { root in\n\(children)\n}"
        }
        return "_validateFullTextColumn(root, \(expression.trimmedDescription))"
    }

}
