import SwiftSyntax
import SwiftSyntaxMacros

/// Attached peer macro for marking default values on `let` properties.
/// This macro expands to nothing - it serves as a marker that @Entity and @Embedded process.
///
/// Usage:
/// ```swift
/// @Entity
/// struct User {
///     @Default(UUIDV7())
///     let id: UUIDV7
///
///     var name: String
///
///     @Default(Date())
///     let createdAt: Date
/// }
///
/// @Embedded
/// struct Settings {
///     @Default("light")
///     let theme: String
///
///     @Default(true)
///     let notifications: Bool
/// }
/// ```
public struct DefaultMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This macro expands to nothing - it's just a marker for @Entity and @Embedded to process
        return []
    }
}

/// Parser for @Default attribute on properties
struct DefaultMarkerParser {
    /// Extract default value from @Default attribute in an attribute list
    /// Returns nil if no @Default attribute is found
    /// - Parameter attributes: The attribute list from a variable declaration
    /// - Returns: The default value expression as a string, or nil if not found
    static func extractDefaultValue(from attributes: AttributeListSyntax) -> String? {
        for attribute in attributes {
            // Look for @Default(value) attribute
            guard let attr = attribute.as(AttributeSyntax.self),
                  let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
                  identifier.name.text == "Default" else {
                continue
            }

            // Extract the argument from @Default(value)
            if let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
               let firstArg = arguments.first {
                // Return the expression as a trimmed string
                return firstArg.expression.trimmedDescription
            }
        }

        return nil
    }
}
