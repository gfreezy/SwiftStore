import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

/// Index macro for defining database indexes
public struct IndexMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let _ = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@Index can only be applied to structs")
        }

        // Parse index attributes from all @Index macros on this struct
        // The actual index generation will be handled elsewhere
        // This macro primarily serves as a marker for metadata extraction

        return []
    }
}

/// Helper to parse index definitions from attributes
struct IndexDefinitionParser {
    static func parse(from attributes: AttributeListSyntax, tableName: String) -> [(columns: [String], unique: Bool, name: String)] {
        var indexes: [(columns: [String], unique: Bool, name: String)] = []

        for attribute in attributes {
            guard let attr = attribute.as(AttributeSyntax.self),
                  let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
                  identifier.name.text == "Index" else {
                continue
            }

            guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
                continue
            }

            var columns: [String] = []
            var unique = false

            for arg in arguments {
                if let label = arg.label?.text, label == "unique" {
                    if let boolLiteral = arg.expression.as(BooleanLiteralExprSyntax.self) {
                        unique = boolLiteral.literal.tokenKind == .keyword(.true)
                    }
                } else {
                    // This is a keypath argument
                    if let columnName = MacroHelpers.extractPropertyName(from: arg.expression) {
                        // Handle nested paths like address.city
                        let snakeCase = columnName.split(separator: ".").map {
                            MacroHelpers.camelToSnakeCase(String($0))
                        }.joined(separator: "_")
                        columns.append(snakeCase)
                    }
                }
            }

            if !columns.isEmpty {
                let indexName = "idx_\(tableName)_\(columns.joined(separator: "_"))"
                indexes.append((columns: columns, unique: unique, name: indexName))
            }
        }

        return indexes
    }
}
