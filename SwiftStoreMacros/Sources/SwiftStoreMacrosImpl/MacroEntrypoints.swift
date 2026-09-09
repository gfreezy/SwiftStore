import SwiftSyntax
import SwiftSyntaxMacros
import SwiftStoreMacroSupport

// Keep compiler-plugin type identities stable while sharing expansion with the source tool.
public struct EntityMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try SwiftStoreMacroSupport.EntityMacro.expansion(of: node, providingMembersOf: declaration,
            conformingTo: protocols, in: context)
    }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        try SwiftStoreMacroSupport.EntityMacro.expansion(of: node, attachedTo: declaration,
            providingExtensionsOf: type, conformingTo: protocols, in: context)
    }
}

public struct EmbeddedMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try SwiftStoreMacroSupport.EmbeddedMacro.expansion(of: node, providingMembersOf: declaration,
            conformingTo: protocols, in: context)
    }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        try SwiftStoreMacroSupport.EmbeddedMacro.expansion(of: node, attachedTo: declaration,
            providingExtensionsOf: type, conformingTo: protocols, in: context)
    }
}

public struct IndexMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try SwiftStoreMacroSupport.IndexMacro.expansion(of: node, in: context)
    }
}

public struct SyncKeyMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try SwiftStoreMacroSupport.SyncKeyMacro.expansion(of: node, in: context)
    }
}

public struct DefaultMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try SwiftStoreMacroSupport.DefaultMacro.expansion(of: node, providingPeersOf: declaration, in: context)
    }
}
