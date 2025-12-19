import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

/// OneToMany relation macro
public struct OneToManyMacro: MemberMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@OneToMany can only be applied to structs")
        }

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            throw MacroError.message("@OneToMany requires arguments")
        }

        let config = try RelationConfig.parse(from: arguments, relationType: .oneToMany)
        let structName = structDecl.name.text
        let properties = structDecl.extractProperties()

        // OneToMany always requires 'from' parameter (can't be on entity directly)
        guard config.hasFrom else {
            throw MacroError.message("@OneToMany must specify 'from' parameter. Use @ManyToOne on the child entity instead.")
        }

        // Validate that fromKey and toKey fields exist in the struct
        guard let fromKey = config.fromKey else {
            throw MacroError.message("@OneToMany requires 'fromKey' parameter")
        }
        guard let toKey = config.toKey else {
            throw MacroError.message("@OneToMany requires 'toKey' parameter")
        }

        try MacroHelpers.validateFieldExists(properties: properties, fieldName: fromKey, structName: structName)
        try MacroHelpers.validateFieldExists(properties: properties, fieldName: toKey, structName: structName)

        return try generateRelationMarkerMembers(config: config)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return []
        }

        let config = try RelationConfig.parse(from: arguments, relationType: .oneToMany)
        let structName = structDecl.name.text

        return try RelationExtensionGenerator.generate(
            structName: structName,
            config: config
        )
    }

    private static func generateRelationMarkerMembers(config: RelationConfig) throws -> [DeclSyntax] {
        guard let fromType = config.fromType,
              let fromKey = config.fromKey,
              let toKey = config.toKey else {
            throw MacroError.message("@OneToMany requires fromType, fromKey, and toKey")
        }

        let fromEntityDecl: DeclSyntax = """
            public typealias FromEntity = \(raw: fromType)
            """

        let toEntityDecl: DeclSyntax = """
            public typealias ToEntity = \(raw: config.toType)
            """

        let fromKeyPathDecl: DeclSyntax = """
            public static var fromKeyPath: String { "\(raw: fromKey)" }
            """

        let toKeyPathDecl: DeclSyntax = """
            public static var toKeyPath: String { "\(raw: toKey)" }
            """

        let relationTypeDecl: DeclSyntax = """
            public static var relationType: RelationType { .oneToMany }
            """

        return [fromEntityDecl, toEntityDecl, fromKeyPathDecl, toKeyPathDecl, relationTypeDecl]
    }
}
