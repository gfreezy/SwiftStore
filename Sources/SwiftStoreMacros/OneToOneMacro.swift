import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

/// OneToOne relation macro
public struct OneToOneMacro: MemberMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@OneToOne can only be applied to structs")
        }

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            throw MacroError.message("@OneToOne requires arguments")
        }

        let config = try RelationConfig.parse(from: arguments, relationType: .oneToOne)
        let structName = structDecl.name.text
        let properties = structDecl.extractProperties()

        // If has 'from', this is a relation entity - validate and add RelationMarker conformance
        if config.hasFrom {
            guard let fromKey = config.fromKey else {
                throw MacroError.message("@OneToOne requires 'fromKey' parameter")
            }
            guard let toKey = config.toKey else {
                throw MacroError.message("@OneToOne requires 'toKey' parameter")
            }

            try MacroHelpers.validateFieldExists(properties: properties, fieldName: fromKey, structName: structName)
            try MacroHelpers.validateFieldExists(properties: properties, fieldName: toKey, structName: structName)

            return try generateRelationMarkerMembers(config: config)
        }

        // Without 'from', validate fromField exists
        guard let fromField = config.fromField else {
            throw MacroError.message("@OneToOne requires 'fromField' parameter")
        }
        try MacroHelpers.validateFieldExists(properties: properties, fieldName: fromField, structName: structName)

        return []
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

        let config = try RelationConfig.parse(from: arguments, relationType: .oneToOne)
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
            throw MacroError.message("@OneToOne with 'from' requires fromType, fromKey, and toKey")
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
            public static var relationType: RelationType { .oneToOne }
            """

        return [fromEntityDecl, toEntityDecl, fromKeyPathDecl, toKeyPathDecl, relationTypeDecl]
    }
}
