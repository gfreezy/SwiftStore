import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

/// Freestanding declaration macro for marking sync key inside struct body
/// This macro expands to nothing - it serves as a marker that @Entity processes
/// Usage:
///   @Entity
///   struct User {
///       #SyncKey(\.email)
///       ...
///   }
///
///   @Entity
///   struct Employee {
///       #SyncKey(\.companyId, \.employeeCode)
///       ...
///   }
public struct SyncKeyMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This macro expands to nothing - it's just a marker for @Entity to process
        return []
    }
}

/// Parser for #SyncKey macro calls within struct body
struct SyncKeyMarkerParser {
    struct SyncKeyInfo {
        /// Column names for the sync key (snake_case)
        let columns: [String]
    }

    /// Parse #SyncKey marker from struct members
    /// Returns nil if no #SyncKey is declared (default to "id")
    static func parse(from members: MemberBlockItemListSyntax) -> SyncKeyInfo? {
        for member in members {
            // Look for macro expansion declarations (#SyncKey(...))
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "SyncKey" {
                return parseSyncKeyMacro(macroDecl.arguments)
            }
        }

        return nil
    }

    private static func parseSyncKeyMacro(_ arguments: LabeledExprListSyntax) -> SyncKeyInfo? {
        var columns: [String] = []

        for arg in arguments {
            // All arguments should be keypaths (no labels)
            if arg.label == nil {
                if let columnName = extractColumnName(from: arg.expression) {
                    columns.append(columnName)
                }
            }
        }

        guard !columns.isEmpty else {
            return nil
        }

        return SyncKeyInfo(columns: columns)
    }

    /// Extract column name from a keypath expression
    /// e.g., \.email -> "email", \.companyId -> "company_id"
    private static func extractColumnName(from keyPath: ExprSyntax) -> String? {
        guard let keyPathExpr = keyPath.as(KeyPathExprSyntax.self) else {
            return nil
        }

        // For sync key, we only support single-level properties (not nested)
        guard let firstComponent = keyPathExpr.components.first,
              let property = firstComponent.component.as(KeyPathPropertyComponentSyntax.self) else {
            return nil
        }

        let propertyName = property.declName.baseName.text
        return MacroHelpers.camelToSnakeCase(propertyName)
    }
}
