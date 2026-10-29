import Foundation

/// Shared only between the parser and its screen. Cancellation never commits partial data.
public final class HealthImportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var processed = 0
    public init() {}
    public var recordsProcessed: Int { lock.lock(); defer { lock.unlock() }; return processed }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func checkCancellation() throws {
        lock.lock(); let stop = cancelled; lock.unlock()
        if stop { throw CancellationError() }
    }
    func record(_ progress: @Sendable (Int) -> Void) throws {
        try checkCancellation()
        lock.lock(); processed += 1; let count = processed; lock.unlock()
        if count.isMultiple(of: 512) { progress(count) }
        try checkCancellation()
    }
}
