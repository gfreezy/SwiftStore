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
    /// Represents a column in an index, which can be a regular column or a virtual column for nested JSON properties
    struct IndexColumn {
        /// The column name to use in the index (snake_case)
        let columnName: String
        /// The original keypath components (e.g., ["settings", "theme"] for \.settings.theme)
        let keypathComponents: [String]
        /// Whether this is a nested property requiring a virtual column
        var isNested: Bool { keypathComponents.count > 1 }
        /// The JSON path for extraction (e.g., "$.theme" for \.settings.theme)
        var jsonPath: String? {
            guard isNested else { return nil }
            let path = keypathComponents.dropFirst().map { MacroHelpers.camelToSnakeCase($0) }
            return "$." + path.joined(separator: ".")
        }
        /// The base column that contains the JSON (e.g., "settings" for \.settings.theme)
        var jsonColumn: String? {
            guard isNested else { return nil }
            return MacroHelpers.camelToSnakeCase(keypathComponents.first!)
        }
    }

    struct IndexInfo {
        let columns: [IndexColumn]
        let unique: Bool
        let name: String?

        /// Column names for index creation
        var columnNames: [String] {
            columns.map { $0.columnName }
        }

        /// Virtual columns that need to be created
        var virtualColumns: [IndexColumn] {
            columns.filter { $0.isNested }
        }
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
        var columns: [IndexColumn] = []
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
                if let components = extractKeypathComponents(from: arg.expression) {
                    let snakeCaseComponents = components.map { MacroHelpers.camelToSnakeCase($0) }
                    // For nested properties, use double underscore as separator
                    let columnName = snakeCaseComponents.joined(separator: "__")
                    columns.append(IndexColumn(columnName: columnName, keypathComponents: components))
                }
            }
        }

        guard !columns.isEmpty else {
            return nil
        }

        return IndexInfo(columns: columns, unique: unique, name: customName)
    }

    /// Extract all components from a keypath expression
    /// e.g., \.settings.theme -> ["settings", "theme"]
    private static func extractKeypathComponents(from keyPath: ExprSyntax) -> [String]? {
        guard let keyPathExpr = keyPath.as(KeyPathExprSyntax.self) else {
            return nil
        }

        var components: [String] = []
        for component in keyPathExpr.components {
            if let property = component.component.as(KeyPathPropertyComponentSyntax.self) {
                components.append(property.declName.baseName.text)
            }
        }

        return components.isEmpty ? nil : components
    }
}
