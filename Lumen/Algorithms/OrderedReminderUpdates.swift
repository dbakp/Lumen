import Foundation

/// A replacement waits for an earlier add callback before its final removal.
/// Otherwise a late add can restore a notification after check-ins are off.
@MainActor final class OrderedReminderUpdates {
    private var token = UUID()
    private var tail: Task<Void, Never>?

    @discardableResult
    func replace(remove: @escaping @MainActor @Sendable () -> Void,
                 add: (@MainActor @Sendable () async throws -> Void)?,
                 succeeded: @escaping @MainActor @Sendable () -> Void = {},
                 failed: @escaping @MainActor @Sendable (Error) -> Void) -> Task<Void, Never> {
        let expected = UUID(); token = expected
        // Best effort immediately, then again after any in-flight add finishes.
        remove()
        let previous = tail
        let task = Task { @MainActor [weak self] in
            if let previous { await previous.value }
            guard let self, self.token == expected else { return }
            remove()
            if let add {
                do { try await add(); if self.token == expected { succeeded() } }
                catch { if self.token == expected { failed(error) } }
                if self.token != expected { remove() }
            }
            if self.token == expected { self.tail = nil }
        }
        tail = task
        return task
    }
}
