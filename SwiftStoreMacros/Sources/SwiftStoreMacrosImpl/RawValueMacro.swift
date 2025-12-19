import SwiftSyntax
import SwiftSyntaxMacros

/// RawValue macro - marker for RawRepresentable enum properties
/// This macro doesn't generate any code itself, but is detected by @Entity macro
public struct RawValueMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This macro is just a marker - no code generation needed
        // The @Entity macro will detect this attribute and handle encoding/decoding
        return []
    }
}
