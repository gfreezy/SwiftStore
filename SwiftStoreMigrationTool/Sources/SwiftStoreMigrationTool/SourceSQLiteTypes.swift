import Foundation
import SwiftSyntax
import SwiftStoreCore

/// Resolve generated `SomeType.sqliteType` expressions from source, without guessing that
/// every unfamiliar name is JSON. Primitive metadata comes from the same runtime codecs.
final class SourceSQLiteTypes {
    private let declarations: [String: [Syntax]]
    private let extensions: [String: [ExtensionDeclSyntax]]
    private static let primitives: [String: SQLiteType] = [
        "String": String.sqliteType, "Int": Int.sqliteType, "Int8": Int8.sqliteType,
        "Int16": Int16.sqliteType, "Int32": Int32.sqliteType, "Int64": Int64.sqliteType,
        "UInt": UInt.sqliteType, "UInt8": UInt8.sqliteType, "UInt16": UInt16.sqliteType,
        "UInt32": UInt32.sqliteType, "UInt64": UInt64.sqliteType,
        "Double": Double.sqliteType, "Float": Float.sqliteType, "Bool": Bool.sqliteType,
        "Date": Date.sqliteType, "Data": Data.sqliteType, "UUID": UUID.sqliteType,
        "UUIDV7": UUIDV7.sqliteType, "URL": URL.sqliteType
    ]
    private static let standardProtocols: Set<String> = [
        "Sendable", "Codable", "Encodable", "Decodable", "Equatable", "Hashable", "Comparable",
        "CaseIterable", "RawRepresentable", "Identifiable", "Embedded", "SQLiteValueComparable",
        "SQLiteValueCodable", "SQLiteValueEncodable", "SQLiteValueDecodable"
    ]

    init(trees: [SourceFileSyntax]) {
        let visitor = StorageTypeVisitor()
        for tree in trees { visitor.walk(tree) }
        declarations = visitor.declarations
        extensions = visitor.extensions
    }

    static func scope(of node: some SyntaxProtocol) -> [String] {
        var result: [String] = []
        var current: Syntax? = Syntax(node)
        while let value = current {
            if let name = declaredName(value) { result.insert(name, at: 0) }
            if let ext = value.as(ExtensionDeclSyntax.self) { result.insert(ext.extendedType.trimmedDescription, at: 0) }
            current = value.parent
        }
        return result
    }

    func resolve(_ name: String, scope: [String]) throws -> SQLiteType {
        try resolve(name, scope: scope, visiting: [])
    }

    private func resolve(_ name: String, scope: [String], visiting: Set<String>) throws -> SQLiteType {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix("?") { return try resolve(String(name.dropLast()), scope: scope, visiting: visiting) }
        let unqualified = name.hasPrefix("Swift.") ? String(name.dropFirst(6)) : name
        if unqualified.hasPrefix("Optional<"), unqualified.hasSuffix(">") {
            return try resolve(String(unqualified.dropFirst(9).dropLast()), scope: scope, visiting: visiting)
        }
        if unqualified.hasPrefix("[") || ["Array<", "Set<", "Dictionary<"].contains(where: unqualified.hasPrefix) {
            return [String].sqliteType
        }
        if let (key, node) = try lookup(name, scope: scope) {
            guard !visiting.contains(key) else { throw failure("Cyclic SQLite storage type: \(key)") }
            let conditions = StorageConditionalVisitor()
            conditions.walk(node)
            guard !conditions.found else { throw failure("Conditional storage members in \(key) are unsupported") }
            let visiting = visiting.union([key])
            let parentScope = key.split(separator: ".").dropLast().map(String.init)
            if let alias = node.as(TypeAliasDeclSyntax.self) {
                return try resolve(alias.initializer.value.trimmedDescription, scope: parentScope, visiting: visiting)
            }
            var members: [MemberBlockItemSyntax] = []
            var inherited: [String] = []
            var attributes: AttributeListSyntax = []
            if let value = node.as(StructDeclSyntax.self) {
                members = Array(value.memberBlock.members); attributes = value.attributes
                inherited = value.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
            } else if let value = node.as(EnumDeclSyntax.self) {
                members = Array(value.memberBlock.members); attributes = value.attributes
                inherited = value.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
            } else { throw failure("No statically resolvable SQLite codec for \(key)") }
            for ext in extensions[key] ?? [] {
                let conditions = StorageConditionalVisitor()
                conditions.walk(ext)
                var ancestor: Syntax? = Syntax(ext)
                while let current = ancestor {
                    if current.is(IfConfigDeclSyntax.self) { conditions.found = true }
                    ancestor = current.parent
                }
                guard !conditions.found else { throw failure("Conditional storage extension for \(key) is unsupported") }
                guard ext.genericWhereClause == nil else { throw failure("Conditional SQLite storage extension for \(key) requires an explicit schema") }
                members += ext.memberBlock.members
                inherited += ext.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
            }
            let typeScope = key.split(separator: ".").map(String.init)
            let storageProperties = members.flatMap { item -> [PatternBindingSyntax] in
                guard let variable = item.decl.as(VariableDeclSyntax.self),
                      variable.modifiers.contains(where: { $0.name.text == "static" || $0.name.text == "class" }) else { return [] }
                return variable.bindings.filter { $0.pattern.trimmedDescription == "sqliteType" }
            }
            guard storageProperties.count <= 1 else { throw failure("Ambiguous sqliteType declaration for \(key)") }
            if let property = storageProperties.first {
                guard let expression = Self.expression(property) else { throw failure("Cannot evaluate \(key).sqliteType; use a literal SQLite type or delegate to another codec") }
                if let member = expression.as(MemberAccessExprSyntax.self) {
                    let field = member.declName.baseName.text
                    if let value = SQLiteType(rawValue: field.uppercased()),
                       member.base == nil || member.base?.trimmedDescription == "SQLiteType" { return value }
                    if field == "sqliteType", let base = member.base?.trimmedDescription {
                        return try resolve(base, scope: typeScope, visiting: visiting)
                    }
                }
                throw failure("Cannot evaluate \(key).sqliteType: \(expression)")
            }
            // RawValue may be an explicitly declared alias on a custom RawRepresentable type.
            if inherited.contains(where: { $0.split(separator: ".").last == "RawRepresentable" }) {
                guard let alias = members.compactMap({ $0.decl.as(TypeAliasDeclSyntax.self) }).first(where: { $0.name.text == "RawValue" }) else {
                    throw failure("Declare RawValue explicitly for the source schema of \(key)")
                }
                return try resolve(alias.initializer.value.trimmedDescription, scope: typeScope, visiting: visiting)
            }
            if node.is(EnumDeclSyntax.self) {
                let candidates = try inherited.filter { try !isProtocol($0, scope: parentScope, visiting: []) }
                guard candidates.count <= 1 else { throw failure("Ambiguous raw storage type for \(key)") }
                if let raw = candidates.first { return try resolve(raw, scope: parentScope, visiting: visiting) }
            }
            let embedded = attributes.contains { item in
                guard let attribute = item.as(AttributeSyntax.self) else { return false }
                return ["Embedded", "Entity"].contains(String(attribute.attributeName.trimmedDescription.split(separator: ".").last ?? ""))
            } || inherited.contains("Embedded")
            guard embedded else { throw failure("Cannot resolve SQLite storage for \(key); include its codec declaration in the selected source files") }
            return [String].sqliteType // Embedded's explicitly declared JSON codec.
        }
        let builtin = unqualified.hasPrefix("Foundation.") ? String(unqualified.dropFirst(11)) : unqualified
        if let value = Self.primitives[builtin] { return value }
        throw failure("Cannot resolve SQLite storage type \(name); include its type/codec source instead of assuming TEXT")
    }

    func isJSONEncoded(_ name: String, scope: [String]) throws -> Bool {
        _ = try resolve(name, scope: scope)
        return try resolveJSON(name, scope: scope, visiting: [])
    }

    private func resolveJSON(_ name: String, scope: [String], visiting: Set<String>) throws -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix("?") { return try resolveJSON(String(name.dropLast()), scope: scope, visiting: visiting) }
        let unqualified = name.hasPrefix("Swift.") ? String(name.dropFirst(6)) : name
        if unqualified.hasPrefix("Optional<"), unqualified.hasSuffix(">") {
            return try resolveJSON(String(unqualified.dropFirst(9).dropLast()), scope: scope, visiting: visiting)
        }
        if unqualified.hasPrefix("[") || ["Array<", "Set<", "Dictionary<"].contains(where: unqualified.hasPrefix) { return true }
        guard let (key, node) = try lookup(name, scope: scope) else { return false }
        guard !visiting.contains(key) else { throw failure("Cyclic JSON storage metadata: \(key)") }
        let visiting = visiting.union([key])
        let parentScope = key.split(separator: ".").dropLast().map(String.init)
        if let alias = node.as(TypeAliasDeclSyntax.self) {
            return try resolveJSON(alias.initializer.value.trimmedDescription, scope: parentScope, visiting: visiting)
        }
        let structure = node.as(StructDeclSyntax.self)
        let enumeration = node.as(EnumDeclSyntax.self)
        var members = Array((structure?.memberBlock ?? enumeration?.memberBlock)?.members ?? [])
        var inherited = (structure?.inheritanceClause ?? enumeration?.inheritanceClause)?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        for ext in extensions[key] ?? [] {
            members += ext.memberBlock.members
            inherited += ext.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        }
        let flags = members.flatMap { item -> [PatternBindingSyntax] in
            guard let variable = item.decl.as(VariableDeclSyntax.self), variable.modifiers.contains(where: { $0.name.text == "static" }) else { return [] }
            return variable.bindings.filter { $0.pattern.trimmedDescription == "sqliteIsJSONEncoded" }
        }
        guard flags.count <= 1 else { throw failure("Ambiguous JSON storage metadata for \(key)") }
        if let flag = flags.first {
            guard let expression = Self.expression(flag) else { throw failure("Cannot evaluate \(key).sqliteIsJSONEncoded") }
            if let literal = expression.as(BooleanLiteralExprSyntax.self) { return literal.literal.text == "true" }
            if let member = expression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "sqliteIsJSONEncoded",
               let base = member.base?.trimmedDescription {
                return try resolveJSON(base, scope: key.split(separator: ".").map(String.init), visiting: visiting)
            }
            throw failure("Cannot evaluate \(key).sqliteIsJSONEncoded")
        }
        if inherited.contains(where: { $0.split(separator: ".").last == "RawRepresentable" }),
           let alias = members.compactMap({ $0.decl.as(TypeAliasDeclSyntax.self) }).first(where: { $0.name.text == "RawValue" }) {
            return try resolveJSON(alias.initializer.value.trimmedDescription, scope: key.split(separator: ".").map(String.init), visiting: visiting)
        }
        if enumeration != nil, let raw = try inherited.first(where: { try !isProtocol($0, scope: parentScope, visiting: []) }) {
            return try resolveJSON(raw, scope: parentScope, visiting: visiting)
        }
        return (structure?.attributes ?? enumeration?.attributes ?? []).contains { item in
            guard let attribute = item.as(AttributeSyntax.self) else { return false }
            return ["Embedded", "Entity"].contains(String(attribute.attributeName.trimmedDescription.split(separator: ".").last ?? ""))
        } || inherited.contains("Embedded")
    }

    private func isProtocol(_ name: String, scope: [String], visiting: Set<String>) throws -> Bool {
        if let (key, node) = try lookup(name, scope: scope) {
            guard !visiting.contains(key) else { throw failure("Cyclic protocol alias: \(key)") }
            if node.is(ProtocolDeclSyntax.self) { return true }
            if let alias = node.as(TypeAliasDeclSyntax.self) {
                return try isProtocol(alias.initializer.value.trimmedDescription,
                    scope: key.split(separator: ".").dropLast().map(String.init), visiting: visiting.union([key]))
            }
            return false
        }
        return Self.standardProtocols.contains(String(name.split(separator: ".").last ?? ""))
    }

    private func lookup(_ name: String, scope: [String]) throws -> (String, Syntax)? {
        for length in stride(from: scope.count, through: 0, by: -1) {
            let key = (Array(scope.prefix(length)) + [name]).joined(separator: ".")
            if let nodes = declarations[key] {
                guard nodes.count == 1, let node = nodes.first else { throw failure("Ambiguous storage declaration: \(key)") }
                var current: Syntax? = node
                while let value = current {
                    if value.is(IfConfigDeclSyntax.self) { throw failure("Conditional storage declaration: \(key)") }
                    current = value.parent
                }
                return (key, node)
            }
        }
        return nil
    }

    private static func expression(_ property: PatternBindingSyntax) -> ExprSyntax? {
        if let value = property.initializer?.value { return value }
        guard let accessors = property.accessorBlock?.accessors else { return nil }
        let body: CodeBlockItemListSyntax?
        switch accessors {
        case .getter(let statements): body = statements
        case .accessors(let values): body = values.first(where: { $0.accessorSpecifier.text == "get" })?.body?.statements
        }
        guard let body, body.count == 1, let item = body.first?.item else { return nil }
        return item.as(ExprSyntax.self) ?? item.as(ReturnStmtSyntax.self)?.expression
    }

    private func failure(_ message: String) -> VersionedMigrationError { .invalidHistory(message) }
}

private func declaredName(_ node: Syntax) -> String? {
    if let value = node.as(StructDeclSyntax.self) { return value.name.text }
    if let value = node.as(EnumDeclSyntax.self) { return value.name.text }
    if let value = node.as(ClassDeclSyntax.self) { return value.name.text }
    if let value = node.as(ProtocolDeclSyntax.self) { return value.name.text }
    if let value = node.as(TypeAliasDeclSyntax.self) { return value.name.text }
    return nil
}

private final class StorageTypeVisitor: SyntaxVisitor {
    var declarations: [String: [Syntax]] = [:]
    var extensions: [String: [ExtensionDeclSyntax]] = [:]
    init() { super.init(viewMode: .sourceAccurate) }
    private func record(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if declaredName(node) != nil {
            let key = SourceSQLiteTypes.scope(of: node).joined(separator: ".")
            declarations[key, default: []].append(node)
        }
        if let ext = node.as(ExtensionDeclSyntax.self) {
            let key = SourceSQLiteTypes.scope(of: ext).joined(separator: ".")
            extensions[key, default: []].append(ext)
        }
        return .visitChildren
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { record(Syntax(node)) }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { record(Syntax(node)) }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { record(Syntax(node)) }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { record(Syntax(node)) }
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind { record(Syntax(node)) }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { record(Syntax(node)) }
}

private final class StorageConditionalVisitor: SyntaxVisitor {
    var found = false
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind { found = true; return .skipChildren }
}
