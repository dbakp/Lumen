import Foundation

/// Preserve each local record's write/delete order across asynchronous Health
/// callbacks. Different records remain independent. This is an in-process
/// completion dependency, not a durable retry queue or synchronization receipt.
@MainActor
final class OrderedHealthWrites {
    enum Key: Hashable, Sendable { case water(String), meal(String) }
    private struct Tail {
        let token: UUID
        let task: Task<Void, Never>
    }
    private var tails: [Key: Tail] = [:]
    private var saveEpoch = UUID()
    var pendingRecordCount: Int { tails.count }

    /// Reset/restore invalidates saves that have not started. Keep the task
    /// dependency chain: a requested delete must still follow an in-flight save.
    func invalidatePendingSaves() { saveEpoch = UUID() }

    @discardableResult
    func enqueueSave(_ key: Key, isCurrent: @escaping @MainActor @Sendable () -> Bool,
                     operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let expected = saveEpoch
        return enqueue(key) { [weak self] in
            guard self?.saveEpoch == expected, isCurrent() else { return }
            await operation()
        }
    }

    /// Enqueue synchronously with the local mutation, before yielding the actor.
    /// Callers handle operation failures. Cancellation cannot bypass a prior
    /// callback: starting a delete early could leave a later save behind it.
    @discardableResult
    func enqueue(_ key: Key, operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = tails[key]?.task
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            if let previous { await previous.value }
            await operation()
            if self?.tails[key]?.token == token { self?.tails[key] = nil }
        }
        tails[key] = .init(token: token, task: task)
        return task
    }
}
