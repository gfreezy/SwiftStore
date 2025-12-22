/// Marker protocol for types that support fault-tolerant decoding.
///
/// Types conforming to this protocol can be used as nested types in @Entity structs.
/// Use the @Default macro to automatically generate fault-tolerant Decodable conformance
/// and Default protocol conformance.
///
/// **Important**: This protocol can only be implemented via @Default macro.
/// Manual conformance is not allowed.
///
/// Example:
/// ```swift
/// @Default
/// struct UserSettings: Codable {
///     var theme: String = "light"
///     var fontSize: Int = 14
/// }
/// ```
public protocol Default {
    /// Internal marker to prevent manual conformance.
    /// Only @Default macro can implement this.
    static var _defaultMacroMarker: _DefaultMacroMarker { get }
}

/// Internal marker type that prevents manual Default conformance.
/// Only the @Default or @Entity macro can create this via `_makeDefaultMacroMarker()`.
public struct _DefaultMacroMarker: Sendable {
    @usableFromInline
    internal init() {}
}

/// Factory function for creating DefaultMacroMarker.
/// This is only meant to be called by @Default and @Entity macro generated code.
/// DO NOT call this directly - use @Default macro instead.
@inlinable
public func _makeDefaultMacroMarker() -> _DefaultMacroMarker {
    _DefaultMacroMarker()
}
