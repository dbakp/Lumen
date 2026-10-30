import Foundation

/// Serializes local writes with the short restore commit and detects changes made
/// while an off-thread restore was being prepared. A revision is process-local.
final class BackupStorageRevision: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    var current: UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
    func write<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock(); defer { generation &+= 1; lock.unlock() }
        return try operation()
    }
    func commit<T>(ifUnchanged expected: UInt64, _ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard expected == generation else { throw BackupError.recordsChanged }
        defer { generation &+= 1 }
        return try operation()
    }
}
