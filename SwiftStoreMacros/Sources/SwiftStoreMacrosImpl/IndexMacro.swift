import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

/// Freestanding declaration macro for marking indexes inside struct body
/// This macro expands to nothing - it serves as a marker that @Entity processes
/// Usage:
///   @Entity
///   struct User {
///       #Index(\.email, unique: true)
///       #Index(\.firstName, \.lastName, name: "custom_name")
///       ...
///   }
public struct IndexMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This macro expands to nothing - it's just a marker for @Entity to process
        return []
    }
}

/// Parser for #Index macro calls within struct body
struct IndexMarkerParser {
    struct IndexInfo {
        let columns: [String]
        let unique: Bool
        let name: String?
    }

    /// Parse all #Index markers from struct members
    static func parse(from members: MemberBlockItemListSyntax, tableName: String) -> [IndexInfo] {
        var indexes: [IndexInfo] = []

        for member in members {
            // Look for macro expansion declarations (#Index(...))
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Index" {
                if let info = parseIndexMacro(macroDecl.arguments, tableName: tableName) {
                    indexes.append(info)
                }
            }
        }

        return indexes
    }

    private static func parseIndexMacro(_ arguments: LabeledExprListSyntax, tableName: String) -> IndexInfo? {
        var columns: [String] = []
        var unique = false
        var customName: String? = nil

        for arg in arguments {
            if let label = arg.label?.text {
                if label == "unique" {
                    if let boolLiteral = arg.expression.as(BooleanLiteralExprSyntax.self) {
                        unique = boolLiteral.literal.tokenKind == .keyword(.true)
                    }
                } else if label == "name" {
                    if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                       let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                        customName = segment.content.text
                    }
                }
            } else {
                // Unlabeled argument - should be a keypath
                if let columnName = MacroHelpers.extractPropertyName(from: arg.expression) {
                    let snakeCase = MacroHelpers.camelToSnakeCase(columnName)
                    columns.append(snakeCase)
                }
            }
        }

        guard !columns.isEmpty else {
            return nil
        }

        return IndexInfo(columns: columns, unique: unique, name: customName)
    }
}
