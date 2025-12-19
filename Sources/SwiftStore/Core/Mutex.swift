import Foundation

/// Thread-safe mutex wrapper
/// Uses os_unfair_lock for best performance
public final class Mutex<Value>: @unchecked Sendable {
    private var _value: Value
    private let _lock = NSLock()

    public init(_ initialValue: Value) {
        self._value = initialValue
    }

    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        _lock.lock()
        defer { _lock.unlock() }
        return try body(&_value)
    }
}
