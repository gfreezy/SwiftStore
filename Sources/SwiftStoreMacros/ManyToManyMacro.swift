import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

/// ManyToMany relation macro
public struct ManyToManyMacro: MemberMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@ManyToMany can only be applied to structs")
        }

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            throw MacroError.message("@ManyToMany requires arguments")
        }

        let config = try RelationConfig.parse(from: arguments, relationType: .manyToMany)
        let structName = structDecl.name.text
        let properties = structDecl.extractProperties()

        // ManyToMany always requires 'from' parameter
        guard config.hasFrom else {
            throw MacroError.message("@ManyToMany must specify 'from' parameter")
        }

        // Validate that fromKey and toKey fields exist in the struct
        guard let fromKey = config.fromKey else {
            throw MacroError.message("@ManyToMany requires 'fromKey' parameter")
        }
        guard let toKey = config.toKey else {
            throw MacroError.message("@ManyToMany requires 'toKey' parameter")
        }

        try MacroHelpers.validateFieldExists(properties: properties, fieldName: fromKey, structName: structName)
        try MacroHelpers.validateFieldExists(properties: properties, fieldName: toKey, structName: structName)

        var members = try generateRelationMarkerMembers(config: config)

        // If self-referencing with fromName/toName, add SelfReferenceRelation conformance
        if config.isSelfReference, let fromName = config.fromName, let toName = config.toName {
            let fromNameDecl: DeclSyntax = """
                public static var fromName: String { "\(raw: fromName)" }
                """

            let toNameDecl: DeclSyntax = """
                public static var toName: String { "\(raw: toName)" }
                """

            members.append(fromNameDecl)
            members.append(toNameDecl)
        }

        return members
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

        let config = try RelationConfig.parse(from: arguments, relationType: .manyToMany)
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
            throw MacroError.message("@ManyToMany requires fromType, fromKey, and toKey")
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
            public static var relationType: RelationType { .manyToMany }
            """

        return [fromEntityDecl, toEntityDecl, fromKeyPathDecl, toKeyPathDecl, relationTypeDecl]
    }
}
