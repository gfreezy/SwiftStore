// SwiftStoreMacros - Macro declarations for SwiftStore

@_exported import Foundation
@_exported import SwiftStoreProtocols

// MARK: - Entity Macro

/// Entity macro that generates EntityProtocol conformance
/// - Parameter tableName: Optional custom table name. If not provided, uses snake_case of struct name.
/// - Auto-generates init with default values: id = UUIDV7(), createdAt = Date(), updatedAt = Date()
/// - For #SyncKey entities: generates `id` computed property and `SyncKeyID` struct for Identifiable
@attached(member, names: named(tableName), named(columns), named(sqliteEncode), named(sqliteDecode), named(indexes), named(syncKeyColumns), named(init), named(CodingKeys), named(_decodeNested), named(_decodeNestedIfPresent), named(id), named(SyncKeyID))
@attached(extension, conformances: EntityProtocol, SQLiteCodable, Identifiable, Sendable, Embedded)
public macro Entity(tableName: String? = nil) = #externalMacro(module: "SwiftStoreMacrosImpl", type: "EntityMacro")

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
/// - `CodingKeys` enum
/// - `init(from decoder: Decoder)` that uses default values for missing fields (fault-tolerant)
/// - `Embedded` protocol conformance (includes SQLiteValueCodable)
///
/// Types marked with @Embedded are stored as JSON TEXT in SQLite.
/// They automatically get encode/decode methods for SQLite storage.
///
/// Usage:
/// ```swift
/// @Embedded
/// struct Address: Codable {
///     var street: String = ""
///     var city: String = ""
///     var zipCode: String = ""
/// }
///
/// @Entity
/// struct User {
///     var id: UUIDV7
///     var address: Address  // Stored as JSON TEXT
///     var createdAt: Date
///     var updatedAt: Date
/// }
/// ```
@attached(member, names: named(CodingKeys), named(init))
@attached(extension, conformances: Embedded)
public macro Embedded() = #externalMacro(module: "SwiftStoreMacrosImpl", type: "EmbeddedMacro")
