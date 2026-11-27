import Foundation

/// A value that may be read and written from several threads.
public final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) { self.value = value }

    public func get() -> Value { lock.withLock { value } }
    public func set(_ newValue: Value) { lock.withLock { value = newValue } }

    @discardableResult
    public func withLock<Result>(_ body: (inout Value) -> Result) -> Result { lock.withLock { body(&value) } }
}
