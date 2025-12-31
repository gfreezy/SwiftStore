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
        /// Property names for the sync key (camelCase, as declared in source)
        let propertyNames: [String]
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
        var propertyNames: [String] = []

        for arg in arguments {
            // All arguments should be keypaths (no labels)
            if arg.label == nil {
                if let (columnName, propertyName) = extractColumnAndPropertyName(from: arg.expression) {
                    columns.append(columnName)
                    propertyNames.append(propertyName)
                }
            }
        }

        guard !columns.isEmpty else {
            return nil
        }

        return SyncKeyInfo(columns: columns, propertyNames: propertyNames)
    }

    /// Extract column name and property name from a keypath expression
    /// e.g., \.email -> ("email", "email"), \.companyId -> ("company_id", "companyId")
    private static func extractColumnAndPropertyName(from keyPath: ExprSyntax) -> (columnName: String, propertyName: String)? {
        guard let keyPathExpr = keyPath.as(KeyPathExprSyntax.self) else {
            return nil
        }

        // For sync key, we only support single-level properties (not nested)
        guard let firstComponent = keyPathExpr.components.first,
              let property = firstComponent.component.as(KeyPathPropertyComponentSyntax.self) else {
            return nil
        }

        let propertyName = property.declName.baseName.text
        let columnName = MacroHelpers.camelToSnakeCase(propertyName)
        return (columnName, propertyName)
    }
}
