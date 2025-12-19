import SwiftSyntax
import SwiftSyntaxBuilder

/// Generates extension methods for relation entities
enum RelationExtensionGenerator {
    static func generate(
        structName: String,
        config: RelationConfig
    ) throws -> [DeclSyntax] {
        var extensions: [DeclSyntax] = []

        if config.hasFrom {
            // Relation entity with explicit 'from' - generate methods for both sides
            guard let fromType = config.fromType,
                  let fromKey = config.fromKey,
                  let toKey = config.toKey else {
                return []
            }

            // Handle self-referencing relation
            if config.isSelfReference {
                if let fromName = config.fromName, let toName = config.toName {
                    extensions.append(contentsOf: try generateSelfReferenceExtension(
                        entityType: fromType,
                        relationEntity: structName,
                        fromKey: fromKey,
                        toKey: toKey,
                        fromName: fromName,
                        toName: toName,
                        relationType: config.relationType
                    ))
                }
            } else {
                // Generate extension for 'from' entity
                extensions.append(contentsOf: try generateFromEntityExtension(
                    fromType: fromType,
                    toType: config.toType,
                    relationEntity: structName,
                    fromKey: fromKey,
                    toKey: toKey,
                    relationType: config.relationType
                ))

                // Generate extension for 'to' entity
                extensions.append(contentsOf: try generateToEntityExtension(
                    fromType: fromType,
                    toType: config.toType,
                    relationEntity: structName,
                    fromKey: fromKey,
                    toKey: toKey,
                    relationType: config.relationType
                ))
            }
        } else {
            // Simple relation on entity (no 'from')
            // Generate methods on the current struct
            guard let fromField = config.fromField else {
                return []
            }

            extensions.append(contentsOf: try generateSimpleRelationExtension(
                currentEntity: structName,
                targetType: config.toType,
                foreignKey: fromField,
                relationType: config.relationType
            ))
        }

        return extensions
    }

    // MARK: - Simple Relation (without 'from')

    private static func generateSimpleRelationExtension(
        currentEntity: String,
        targetType: String,
        foreignKey: String,
        relationType: RelationTypeEnum
    ) throws -> [DeclSyntax] {
        let targetName = MacroHelpers.lowercaseFirst(targetType)
        let targetIdParam = "\(targetName)Id"

        let extension_: DeclSyntax = """
            extension \(raw: currentEntity) {
                /// Get the related \(raw: targetType)
                public func \(raw: targetName)(in store: Store) throws -> \(raw: targetType)? {
                    try store.get(\(raw: targetType).self, id: self.\(raw: foreignKey))
                }

                /// Get the related \(raw: targetType) by ID
                public func \(raw: targetName)(\(raw: targetIdParam): UUID, in store: Store) throws -> \(raw: targetType)? {
                    try store.get(\(raw: targetType).self, id: \(raw: targetIdParam))
                }
            }
            """

        return [extension_]
    }

    // MARK: - From Entity Extension

    private static func generateFromEntityExtension(
        fromType: String,
        toType: String,
        relationEntity: String,
        fromKey: String,
        toKey: String,
        relationType: RelationTypeEnum
    ) throws -> [DeclSyntax] {
        let toNamePlural = MacroHelpers.pluralize(MacroHelpers.lowercaseFirst(toType))
        let toNameSingular = MacroHelpers.lowercaseFirst(toType)
        let toIdParam = "\(toNameSingular)Id"
        let relationName = MacroHelpers.lowercaseFirst(toType) + "Relations"

        switch relationType {
        case .oneToOne:
            return [generateOneToOneFromExtension(
                fromType: fromType,
                toType: toType,
                relationEntity: relationEntity,
                fromKey: fromKey,
                toKey: toKey,
                toNameSingular: toNameSingular,
                toIdParam: toIdParam
            )]

        case .oneToMany:
            return [generateOneToManyFromExtension(
                fromType: fromType,
                toType: toType,
                relationEntity: relationEntity,
                fromKey: fromKey,
                toKey: toKey,
                toNamePlural: toNamePlural,
                toNameSingular: toNameSingular,
                toIdParam: toIdParam,
                relationName: relationName
            )]

        case .manyToOne:
            return [generateManyToOneFromExtension(
                fromType: fromType,
                toType: toType,
                relationEntity: relationEntity,
                fromKey: fromKey,
                toKey: toKey,
                toNameSingular: toNameSingular,
                toIdParam: toIdParam
            )]

        case .manyToMany:
            return [generateManyToManyFromExtension(
                fromType: fromType,
                toType: toType,
                relationEntity: relationEntity,
                fromKey: fromKey,
                toKey: toKey,
                toNamePlural: toNamePlural,
                toNameSingular: toNameSingular,
                toIdParam: toIdParam,
                relationName: relationName
            )]
        }
    }

    private static func generateOneToOneFromExtension(
        fromType: String,
        toType: String,
        relationEntity: String,
        fromKey: String,
        toKey: String,
        toNameSingular: String,
        toIdParam: String
    ) -> DeclSyntax {
        return """
            extension \(raw: fromType) {
                public func \(raw: toNameSingular)(in store: Store) throws -> \(raw: toType)? {
                    guard let relation = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .first() else { return nil }
                    return try store.get(\(raw: toType).self, id: relation.\(raw: toKey))
                }

                public func \(raw: toNameSingular)(\(raw: toIdParam): UUID, in store: Store) throws -> \(raw: toType)? {
                    try store.get(\(raw: toType).self, id: \(raw: toIdParam))
                }
            }
            """
    }

    private static func generateOneToManyFromExtension(
        fromType: String,
        toType: String,
        relationEntity: String,
        fromKey: String,
        toKey: String,
        toNamePlural: String,
        toNameSingular: String,
        toIdParam: String,
        relationName: String
    ) -> DeclSyntax {
        let capitalizedSingular = MacroHelpers.capitalizeFirst(toNameSingular)

        return """
            extension \(raw: fromType) {
                public func \(raw: toNamePlural)(in store: Store) throws -> [\(raw: toType)] {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .all()
                    var results: [\(raw: toType)] = []
                    for relation in relations {
                        if let entity = try store.get(\(raw: toType).self, id: relation.\(raw: toKey)) {
                            results.append(entity)
                        }
                    }
                    return results
                }

                public func \(raw: toNameSingular)(\(raw: toIdParam): UUID, in store: Store) throws -> \(raw: toType)? {
                    try store.get(\(raw: toType).self, id: \(raw: toIdParam))
                }

                public func \(raw: relationName)(in store: Store) throws -> [\(raw: relationEntity)] {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .all()
                }

                @discardableResult
                public func add\(raw: capitalizedSingular)(\(raw: toIdParam): UUID, in store: Store) throws -> \(raw: relationEntity) {
                    let relation = \(raw: relationEntity)(
                        id: UUID(),
                        \(raw: fromKey): self.id,
                        \(raw: toKey): \(raw: toIdParam),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try store.insert(relation)
                    return relation
                }

                public func remove\(raw: capitalizedSingular)(\(raw: toIdParam): UUID, in store: Store) throws {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .where(\\.\(raw: toKey) == \(raw: toIdParam))
                        .all()
                    for relation in relations {
                        try store.delete(relation)
                    }
                }

                public func removeAll\(raw: MacroHelpers.capitalizeFirst(toNamePlural))(in store: Store) throws {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .all()
                    for relation in relations {
                        try store.delete(relation)
                    }
                }

                public func \(raw: toNamePlural)Count(in store: Store) throws -> Int {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .count()
                }
            }
            """
    }

    private static func generateManyToOneFromExtension(
        fromType: String,
        toType: String,
        relationEntity: String,
        fromKey: String,
        toKey: String,
        toNameSingular: String,
        toIdParam: String
    ) -> DeclSyntax {
        let capitalizedSingular = MacroHelpers.capitalizeFirst(toNameSingular)
        let relationNameSingular = MacroHelpers.lowercaseFirst(toType) + "Relation"

        return """
            extension \(raw: fromType) {
                public func \(raw: toNameSingular)(in store: Store) throws -> \(raw: toType)? {
                    guard let relation = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .first() else { return nil }
                    return try store.get(\(raw: toType).self, id: relation.\(raw: toKey))
                }

                public func \(raw: toNameSingular)(\(raw: toIdParam): UUID, in store: Store) throws -> \(raw: toType)? {
                    try store.get(\(raw: toType).self, id: \(raw: toIdParam))
                }

                public func \(raw: relationNameSingular)(in store: Store) throws -> \(raw: relationEntity)? {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .first()
                }

                @discardableResult
                public func set\(raw: capitalizedSingular)(\(raw: toIdParam): UUID, in store: Store) throws -> \(raw: relationEntity) {
                    // Remove existing relation
                    if let existing = try \(raw: relationNameSingular)(in: store) {
                        try store.delete(existing)
                    }
                    // Create new relation
                    let relation = \(raw: relationEntity)(
                        id: UUID(),
                        \(raw: fromKey): self.id,
                        \(raw: toKey): \(raw: toIdParam),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try store.insert(relation)
                    return relation
                }
            }
            """
    }

    private static func generateManyToManyFromExtension(
        fromType: String,
        toType: String,
        relationEntity: String,
        fromKey: String,
        toKey: String,
        toNamePlural: String,
        toNameSingular: String,
        toIdParam: String,
        relationName: String
    ) -> DeclSyntax {
        let capitalizedSingular = MacroHelpers.capitalizeFirst(toNameSingular)

        return """
            extension \(raw: fromType) {
                public func \(raw: toNamePlural)(in store: Store) throws -> [\(raw: toType)] {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .all()
                    var results: [\(raw: toType)] = []
                    for relation in relations {
                        if let entity = try store.get(\(raw: toType).self, id: relation.\(raw: toKey)) {
                            results.append(entity)
                        }
                    }
                    return results
                }

                public func \(raw: toNameSingular)(\(raw: toIdParam): UUID, in store: Store) throws -> \(raw: toType)? {
                    try store.get(\(raw: toType).self, id: \(raw: toIdParam))
                }

                public func \(raw: relationName)(in store: Store) throws -> [\(raw: relationEntity)] {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .all()
                }

                @discardableResult
                public func add\(raw: capitalizedSingular)(\(raw: toIdParam): UUID, in store: Store) throws -> \(raw: relationEntity) {
                    let relation = \(raw: relationEntity)(
                        id: UUID(),
                        \(raw: fromKey): self.id,
                        \(raw: toKey): \(raw: toIdParam),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try store.insert(relation)
                    return relation
                }

                public func remove\(raw: capitalizedSingular)(\(raw: toIdParam): UUID, in store: Store) throws {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .where(\\.\(raw: toKey) == \(raw: toIdParam))
                        .all()
                    for relation in relations {
                        try store.delete(relation)
                    }
                }

                public func removeAll\(raw: MacroHelpers.capitalizeFirst(toNamePlural))(in store: Store) throws {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .all()
                    for relation in relations {
                        try store.delete(relation)
                    }
                }

                public func has\(raw: capitalizedSingular)(\(raw: toIdParam): UUID, in store: Store) throws -> Bool {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .where(\\.\(raw: toKey) == \(raw: toIdParam))
                        .exists()
                }

                public func \(raw: toNamePlural)Count(in store: Store) throws -> Int {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .count()
                }
            }
            """
    }

    // MARK: - To Entity Extension

    private static func generateToEntityExtension(
        fromType: String,
        toType: String,
        relationEntity: String,
        fromKey: String,
        toKey: String,
        relationType: RelationTypeEnum
    ) throws -> [DeclSyntax] {
        let fromNamePlural = MacroHelpers.pluralize(MacroHelpers.lowercaseFirst(fromType))
        let fromNameSingular = MacroHelpers.lowercaseFirst(fromType)
        let fromIdParam = "\(fromNameSingular)Id"
        let relationName = MacroHelpers.lowercaseFirst(fromType) + "Relations"
        let capitalizedSingular = MacroHelpers.capitalizeFirst(fromNameSingular)

        switch relationType {
        case .oneToOne:
            let extension_: DeclSyntax = """
                extension \(raw: toType) {
                    public func \(raw: fromNameSingular)(in store: Store) throws -> \(raw: fromType)? {
                        guard let relation = try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .first() else { return nil }
                        return try store.get(\(raw: fromType).self, id: relation.\(raw: fromKey))
                    }

                    public func \(raw: fromNameSingular)(\(raw: fromIdParam): UUID, in store: Store) throws -> \(raw: fromType)? {
                        try store.get(\(raw: fromType).self, id: \(raw: fromIdParam))
                    }
                }
                """
            return [extension_]

        case .oneToMany:
            // For OneToMany, the 'to' side (Many) has one 'from' (One)
            let extension_: DeclSyntax = """
                extension \(raw: toType) {
                    public func \(raw: fromNameSingular)(in store: Store) throws -> \(raw: fromType)? {
                        guard let relation = try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .first() else { return nil }
                        return try store.get(\(raw: fromType).self, id: relation.\(raw: fromKey))
                    }

                    public func \(raw: fromNameSingular)(\(raw: fromIdParam): UUID, in store: Store) throws -> \(raw: fromType)? {
                        try store.get(\(raw: fromType).self, id: \(raw: fromIdParam))
                    }

                    public func \(raw: fromNameSingular)Relation(in store: Store) throws -> \(raw: relationEntity)? {
                        try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .first()
                    }

                    @discardableResult
                    public func set\(raw: capitalizedSingular)(\(raw: fromIdParam): UUID, in store: Store) throws -> \(raw: relationEntity) {
                        if let existing = try \(raw: fromNameSingular)Relation(in: store) {
                            try store.delete(existing)
                        }
                        let relation = \(raw: relationEntity)(
                            id: UUID(),
                            \(raw: fromKey): \(raw: fromIdParam),
                            \(raw: toKey): self.id,
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        try store.insert(relation)
                        return relation
                    }
                }
                """
            return [extension_]

        case .manyToOne:
            // For ManyToOne, the 'to' side (One) has many 'from' (Many)
            let extension_: DeclSyntax = """
                extension \(raw: toType) {
                    public func \(raw: fromNamePlural)(in store: Store) throws -> [\(raw: fromType)] {
                        let relations = try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .all()
                        var results: [\(raw: fromType)] = []
                        for relation in relations {
                            if let entity = try store.get(\(raw: fromType).self, id: relation.\(raw: fromKey)) {
                                results.append(entity)
                            }
                        }
                        return results
                    }

                    public func \(raw: fromNameSingular)(\(raw: fromIdParam): UUID, in store: Store) throws -> \(raw: fromType)? {
                        try store.get(\(raw: fromType).self, id: \(raw: fromIdParam))
                    }

                    public func \(raw: fromNamePlural)Count(in store: Store) throws -> Int {
                        try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .count()
                    }
                }
                """
            return [extension_]

        case .manyToMany:
            let extension_: DeclSyntax = """
                extension \(raw: toType) {
                    public func \(raw: fromNamePlural)(in store: Store) throws -> [\(raw: fromType)] {
                        let relations = try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .all()
                        var results: [\(raw: fromType)] = []
                        for relation in relations {
                            if let entity = try store.get(\(raw: fromType).self, id: relation.\(raw: fromKey)) {
                                results.append(entity)
                            }
                        }
                        return results
                    }

                    public func \(raw: fromNameSingular)(\(raw: fromIdParam): UUID, in store: Store) throws -> \(raw: fromType)? {
                        try store.get(\(raw: fromType).self, id: \(raw: fromIdParam))
                    }

                    public func \(raw: relationName)(in store: Store) throws -> [\(raw: relationEntity)] {
                        try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .all()
                    }

                    @discardableResult
                    public func add\(raw: capitalizedSingular)(\(raw: fromIdParam): UUID, in store: Store) throws -> \(raw: relationEntity) {
                        let relation = \(raw: relationEntity)(
                            id: UUID(),
                            \(raw: fromKey): \(raw: fromIdParam),
                            \(raw: toKey): self.id,
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        try store.insert(relation)
                        return relation
                    }

                    public func remove\(raw: capitalizedSingular)(\(raw: fromIdParam): UUID, in store: Store) throws {
                        let relations = try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .where(\\.\(raw: fromKey) == \(raw: fromIdParam))
                            .all()
                        for relation in relations {
                            try store.delete(relation)
                        }
                    }

                    public func has\(raw: capitalizedSingular)(\(raw: fromIdParam): UUID, in store: Store) throws -> Bool {
                        try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .where(\\.\(raw: fromKey) == \(raw: fromIdParam))
                            .exists()
                    }

                    public func \(raw: fromNamePlural)Count(in store: Store) throws -> Int {
                        try store.fetch(\(raw: relationEntity).self)
                            .where(\\.\(raw: toKey) == self.id)
                            .count()
                    }
                }
                """
            return [extension_]
        }
    }

    // MARK: - Self Reference Extension

    private static func generateSelfReferenceExtension(
        entityType: String,
        relationEntity: String,
        fromKey: String,
        toKey: String,
        fromName: String,
        toName: String,
        relationType: RelationTypeEnum
    ) throws -> [DeclSyntax] {
        let capitalizedFromName = MacroHelpers.capitalizeFirst(fromName)
        let capitalizedToName = MacroHelpers.capitalizeFirst(toName)

        let extension_: DeclSyntax = """
            extension \(raw: entityType) {
                // --- Forward methods (fromName: "\(raw: fromName)") ---

                public func \(raw: fromName)(in store: Store) throws -> [\(raw: entityType)] {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .all()
                    var results: [\(raw: entityType)] = []
                    for relation in relations {
                        if let entity = try store.get(\(raw: entityType).self, id: relation.\(raw: toKey)) {
                            results.append(entity)
                        }
                    }
                    return results
                }

                public func \(raw: fromName)(userId: UUID, in store: Store) throws -> \(raw: entityType)? {
                    try store.get(\(raw: entityType).self, id: userId)
                }

                public func \(raw: fromName)Relations(in store: Store) throws -> [\(raw: relationEntity)] {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .all()
                }

                @discardableResult
                public func add\(raw: capitalizedFromName)(userId: UUID, in store: Store) throws -> \(raw: relationEntity) {
                    let relation = \(raw: relationEntity)(
                        id: UUID(),
                        \(raw: fromKey): self.id,
                        \(raw: toKey): userId,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try store.insert(relation)
                    return relation
                }

                public func remove\(raw: capitalizedFromName)(userId: UUID, in store: Store) throws {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .where(\\.\(raw: toKey) == userId)
                        .all()
                    for relation in relations {
                        try store.delete(relation)
                    }
                }

                public func has\(raw: capitalizedFromName)(userId: UUID, in store: Store) throws -> Bool {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .where(\\.\(raw: toKey) == userId)
                        .exists()
                }

                public func \(raw: fromName)Count(in store: Store) throws -> Int {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: fromKey) == self.id)
                        .count()
                }

                // --- Reverse methods (toName: "\(raw: toName)") - read-only ---

                public func \(raw: toName)(in store: Store) throws -> [\(raw: entityType)] {
                    let relations = try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: toKey) == self.id)
                        .all()
                    var results: [\(raw: entityType)] = []
                    for relation in relations {
                        if let entity = try store.get(\(raw: entityType).self, id: relation.\(raw: fromKey)) {
                            results.append(entity)
                        }
                    }
                    return results
                }

                public func \(raw: toName)(userId: UUID, in store: Store) throws -> \(raw: entityType)? {
                    try store.get(\(raw: entityType).self, id: userId)
                }

                public func \(raw: toName)Relations(in store: Store) throws -> [\(raw: relationEntity)] {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: toKey) == self.id)
                        .all()
                }

                public func \(raw: toName)Count(in store: Store) throws -> Int {
                    try store.fetch(\(raw: relationEntity).self)
                        .where(\\.\(raw: toKey) == self.id)
                        .count()
                }
            }
            """

        return [extension_]
    }
}
