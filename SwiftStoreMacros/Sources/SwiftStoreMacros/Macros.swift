// SwiftStoreMacros - Macro declarations for SwiftStore

@_exported import Foundation
@_exported import SwiftStoreProtocols
@_exported import OSLog

// MARK: - Entity Macro

/// Entity macro that generates EntityProtocol conformance
/// - Parameter tableName: Optional custom table name. If not provided, uses snake_case of struct name.
/// - Parameter readonly: Whether the entity is readonly/local-only (default: false).
///   - When false (default): `id` must be UUIDV7, `createdAt` and `updatedAt` are required, entity can be synced
///   - When true: `id` can be any type (Int, String, etc.), timestamps are optional, entity is local-only
/// - Use `@Default` or inline initializers for default values on `let` and `var` properties
/// - For #SyncKey entities: generates `id` computed property and `SyncKeyID` struct for Identifiable
/// - Note: Readonly entities can only be used with ConnectionManager in readonly mode
@attached(member, names: named(tableName), named(columns), named(sqliteEncode), named(sqliteDecode), named(indexes), named(syncKeyColumns), named(id), named(SyncKeyID), named(isReadonly), named(init))
@attached(extension, conformances: EntityProtocol, Encodable, Decodable, Identifiable, Sendable, Equatable, Hashable, names: named(CodingKeys), named(init), named(_decodeNested), named(_decodeNestedIfPresent))
public macro Entity(tableName: String? = nil, readonly: Bool = false) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "EntityMacro")

// MARK: - Index Macro

/// Freestanding declaration macro for defining indexes inside struct body
/// Usage:
///   @Entity
///   struct User {
///       #Index(\.email, unique: true)
///       #Index(\.firstName, \.lastName, name: "custom_name")
///       var email: String
///       ...
///   }
@freestanding(declaration)
public macro Index<T: EntityProtocol>(_ keyPaths: PartialKeyPath<T>..., unique: Bool = false, name: String? = nil) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "IndexMacro")

// MARK: - SyncKey Macro

/// Freestanding declaration macro for defining sync key inside struct body
/// The sync key is used to uniquely identify entities during synchronization.
/// A unique index is automatically created for the sync key columns.
/// The sync key columns become the primary key when #SyncKey is used.
///
/// Note: #SyncKey and `id` field are mutually exclusive:
/// - Use #SyncKey for sync-based entities (no id field)
/// - Use `id: UUIDV7` for standard entities (no #SyncKey)
///
/// Usage:
///   @Entity
///   struct User {
///       #SyncKey<User>(\.email)                  // Single field sync key
///       var email: String
///       var name: String
///       let createdAt: Date
///       let updatedAt: Date
///   }
///
///   @Entity
///   struct Employee {
///       #SyncKey<Employee>(\.companyId, \.employeeCode)  // Composite key
///       var companyId: UUIDV7
///       var employeeCode: String
///       var name: String
///       let createdAt: Date
///       let updatedAt: Date
///   }
@freestanding(declaration)
public macro SyncKey<T: EntityProtocol>(_ keyPaths: PartialKeyPath<T>...) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "SyncKeyMacro")

// MARK: - Embedded Macro

/// Embedded macro for types that can be embedded in @Entity structs as JSON.
///
/// This macro generates:
/// - `Codable` conformance (for enums, Swift auto-synthesizes; for structs, fault-tolerant Decodable init)
/// - `Embedded` protocol conformance (includes SQLiteValueCodable)
/// - `Equatable` and `Hashable` conformances
///
/// Note: Do NOT declare Codable/Decodable on your type - the macro adds it automatically.
/// Types marked with @Embedded are stored as JSON TEXT in SQLite.
///
/// Usage:
/// ```swift
/// @Embedded
/// struct Address {
///     var street: String = ""
///     var city: String = ""
///     var zipCode: String = ""
/// }
///
/// @Embedded
/// enum Status: String {
///     case active, inactive
/// }
/// ```
@attached(member, names: named(init))
@attached(extension, conformances: Embedded, Codable, Encodable, Decodable, Equatable, Hashable, names: named(CodingKeys), named(init), named(_decodeNested), named(_decodeNestedIfPresent))
public macro Embedded() = #externalMacro(module: "SwiftStoreMacrosImpl", type: "EmbeddedMacro")

// MARK: - Default Macro

/// Marker type for nil default values in @Default macro.
/// This allows `@Default(nil)` to compile by providing a concrete type for the nil literal.
public struct OptionalNil: ExpressibleByNilLiteral, Sendable {
    public init(nilLiteral: ()) {}
}

/// Default value marker macro for `let` properties in @Entity and @Embedded structs.
///
/// This macro allows specifying default values for `let` properties, which cannot have
/// inline initializers while still allowing a memberwise init to be generated.
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
///
///     @Default(Date())
///     let updatedAt: Date
/// }
///
/// @Embedded
/// struct Settings {
///     @Default("light")
///     let theme: String
///
///     @Default(true)
///     let notifications: Bool
///
///     @Default(nil)
///     let optionalField: String?
/// }
/// ```
@attached(peer)
public macro Default<T>(_ value: T) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "DefaultMacro")

/// Overload for @Default(nil) to support optional properties with nil default.
@attached(peer)
public macro Default(_ value: OptionalNil) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "DefaultMacro")
