import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Embedded macro that generates:
/// - Memberwise init with default values
/// - Fault-tolerant Decodable conformance with do-catch for default values (in extension)
/// - Embedded protocol conformance
/// - SQLiteValueCodable conformance (via Embedded protocol)
///
/// Note: Do NOT declare Codable/Decodable on your struct - the macro adds it automatically.
/// Use this for types that will be embedded in @Entity structs as JSON.
/// @Entity automatically conforms to Embedded, so you don't need to add it manually.
public struct EmbeddedMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // For structs, generate memberwise init
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            let properties = structDecl.extractProperties()
            let memberwiseInitDecl = generateMemberWiseInit(properties: properties)
            return [memberwiseInitDecl]
        }

        // For enums, no additional members needed
        if declaration.is(EnumDeclSyntax.self) {
            return []
        }

        throw MacroError.message("@Embedded can only be applied to structs or enums")
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Support both structs and enums
        guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
            return []
        }

        var extensions: [ExtensionDeclSyntax] = []

        // Embedded protocol conformance (includes SQLiteValueCodable via protocol extension)
        let embeddedProtocol: DeclSyntax = """
            extension \(type.trimmed): Embedded {}
            """
        if let ext = embeddedProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // Codable extensions
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            // Struct: generate Decodable extension with init(from decoder:) - in extension to preserve memberwise init
            let properties = structDecl.extractProperties()
            let decodableExt = generateDecodableExtension(for: type, properties: properties, typeName: structDecl.name.text)
            if let ext = decodableExt.as(ExtensionDeclSyntax.self) {
                extensions.append(ext)
            }

            // Struct: add empty Encodable conformance (Swift auto-synthesizes encode method)
            let encodableProtocol: DeclSyntax = """
                extension \(type.trimmed): Encodable {}
                """
            if let ext = encodableProtocol.as(ExtensionDeclSyntax.self) {
                extensions.append(ext)
            }
        } else if declaration.is(EnumDeclSyntax.self) {
            // Enum: add empty Codable conformance (Swift auto-synthesizes for RawRepresentable enums)
            let codableProtocol: DeclSyntax = """
                extension \(type.trimmed): Codable {}
                """
            if let ext = codableProtocol.as(ExtensionDeclSyntax.self) {
                extensions.append(ext)
            }
        }

        // Equatable conformance (auto-synthesized by compiler)
        let equatableProtocol: DeclSyntax = """
            extension \(type.trimmed): Equatable {}
            """
        if let ext = equatableProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        // Hashable conformance (auto-synthesized by compiler)
        let hashableProtocol: DeclSyntax = """
            extension \(type.trimmed): Hashable {}
            """
        if let ext = hashableProtocol.as(ExtensionDeclSyntax.self) {
            extensions.append(ext)
        }

        return extensions
    }

    // MARK: - Shared Init Generation (used by both @Embedded and @Entity)

    /// Generate memberwise init method with default values
    /// This is called by both @Embedded and @Entity macros
    static func generateMemberWiseInit(properties: [PropertyInfo]) -> DeclSyntax {
        // Build parameter list
        let params: [String] = properties.map { prop in
            if let defaultValue = prop.defaultValue {
                return "\(prop.name): \(prop.type) = \(defaultValue)"
            } else {
                return "\(prop.name): \(prop.type)"
            }
        }

        // Build assignment list
        let assignments: [String] = properties.map { prop in
            "self.\(prop.name) = \(prop.name)"
        }

        let paramsStr = MacroHelpers.joinList(params, indent: 4)
        let assignmentsStr = MacroHelpers.joinLines(assignments, indent: 4)

        return """
            public init(
            \(raw: paramsStr)
            ) {
            \(raw: assignmentsStr)
            }
            """
    }

    // MARK: - Shared Decodable Generation (used by both @Embedded and @Entity)

    /// Generate Decodable extension with init(from decoder:)
    /// This is placed in an extension to preserve Swift's auto-generated memberwise init
    static func generateDecodableExtension(
        for type: some TypeSyntaxProtocol,
        properties: [PropertyInfo],
        typeName: String
    ) -> DeclSyntax {
        // Generate CodingKeys enum entries (indent 8 = extension + enum)
        let codingKeysEntries = properties.map { "case \($0.name)" }
        let codingKeysStr = MacroHelpers.joinLines(codingKeysEntries, indent: 8)

        // Check if we have any nested struct types that need Embedded validation
        let hasNestedTypes = properties.contains { MacroHelpers.isNestedStructType($0.type) }

        // Generate decoding statements (indent 8 = extension + init body)
        let decodingStatements: [String] = properties.map { prop in
            generateDecodingStatement(for: prop, typeName: typeName)
        }
        let decodingCode = MacroHelpers.joinLines(decodingStatements, indent: 8)

        // Generate helper functions for nested type decoding if needed
        let helperFunctions = hasNestedTypes ? generateNestedHelpersForExtension() : ""

        return """
            extension \(type.trimmed): Decodable {
                private enum CodingKeys: String, CodingKey {
            \(raw: codingKeysStr)
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
            \(raw: decodingCode)
                }
            \(raw: helperFunctions)
            }
            """
    }

    // MARK: - Private Helpers

    /// Generate a single decoding statement for a property
    private static func generateDecodingStatement(for prop: PropertyInfo, typeName: String) -> String {
        let propName = prop.name
        let baseType = prop.type.replacingOccurrences(of: "?", with: "")
        let isNestedType = MacroHelpers.isNestedStructType(prop.type)

        if let defaultVal = prop.defaultValue {
            // Non-optional with default: use do-catch to fallback on any error
            let tryExpr: String
            if prop.isOptional {
                // Optional types: use decodeIfPresent, default to nil
                if isNestedType {
                    tryExpr =
                        "self.\(propName) = try Self._decodeNestedIfPresent(\(baseType).self, from: container, forKey: .\(propName))"
                } else {
                    tryExpr =
                        "self.\(propName) = try container.decodeIfPresent(\(baseType).self, forKey: .\(propName))"
                }
            } else {
                if isNestedType {
                    tryExpr =
                        "self.\(propName) = try Self._decodeNested(\(baseType).self, from: container, forKey: .\(propName))"
                } else {
                    tryExpr =
                        "self.\(propName) = try container.decode(\(baseType).self, forKey: .\(propName))"
                }
            }
            let catchExpr = "self.\(propName) = \(defaultVal)"
            return MacroHelpers.doCatchBlock(try: tryExpr, catch: catchExpr, logFieldName: propName, logTypeName: typeName)
        } else if prop.isOptional {
            // Optional types: use decodeIfPresent, default to nil
            if isNestedType {
                return
                    "self.\(propName) = try Self._decodeNestedIfPresent(\(baseType).self, from: container, forKey: .\(propName))"
            } else {
                return
                    "self.\(propName) = try container.decodeIfPresent(\(baseType).self, forKey: .\(propName))"
            }
        } else {
            // Non-optional without default: required field
            if isNestedType {
                return
                    "self.\(propName) = try Self._decodeNested(\(baseType).self, from: container, forKey: .\(propName))"
            } else {
                return
                    "self.\(propName) = try container.decode(\(prop.type).self, forKey: .\(propName))"
            }
        }
    }

    /// Generate helper functions for nested type decoding (for use in extension)
    private static func generateNestedHelpersForExtension() -> String {
        return """
            /// Helper to decode nested types with Embedded constraint (compile-time validation)
            @inline(__always)
            private static func _decodeNested<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T {
                try container.decode(T.self, forKey: key)
            }

            /// Helper to decode optional nested types with Embedded constraint (compile-time validation)
            @inline(__always)
            private static func _decodeNestedIfPresent<T: Embedded & Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> T? {
                try container.decodeIfPresent(T.self, forKey: key)
            }
            """
    }
}
