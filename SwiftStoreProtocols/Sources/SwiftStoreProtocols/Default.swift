/// Marker protocol for types that support fault-tolerant decoding.
///
/// Types conforming to this protocol can be used as nested types in @Entity structs.
/// Use the @Default macro to automatically generate fault-tolerant Decodable conformance
/// and Default protocol conformance.
///
/// Example:
/// ```swift
/// @Default
/// struct UserSettings: Codable {
///     var theme: String = "light"
///     var fontSize: Int = 14
/// }
/// ```
public protocol Default {}
