import Foundation

struct HealthWriteOperationFailure: Error {
    let issue: HealthWriteJournal.Issue
}

/// Only dispatches durable intent. Every callback reloads the latest journal;
/// completion never writes a captured whole-file snapshot over a newer edit.
/// The host commits journal + local record changes before calling kick().
@MainActor final class HealthWriteRecovery {
    typealias Journal = HealthWriteJournal
    private let read: () throws -> Journal
    private let commit: (Journal, Journal) throws -> Void
    private let operate: (Journal.Claim) async throws -> Void
    private let changed: () -> Void
    private var active: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    private var blocked = Set<UUID>()
    private(set) var storageIssue = false
    var activeCount: Int { active.count }

    init(read: @escaping () throws -> Journal, commit: @escaping (Journal, Journal) throws -> Void,
         operate: @escaping (Journal.Claim) async throws -> Void, changed: @escaping () -> Void = {}) {
        self.read = read; self.commit = commit; self.operate = operate; self.changed = changed
    }

    /// At most one task per event. Different records can complete while one
    /// callback is held. A failed event stops until explicit retry/foreground;
    /// no timer, busy-loop or timeout invents a successful Health outcome.
    func kick() {
        blocked = []
        schedule()
    }

    private func schedule() {
        do {
            let journal = try read()
            if active.isEmpty && blocked.isEmpty { storageIssue = false }
            let candidates = journal.pendingEvents.filter { active[$0.id] == nil && !blocked.contains($0.id) }.prefix(max(0, 4 - active.count))
            for event in candidates {
                let token = UUID(), id = event.id
                let task = Task { @MainActor [weak self] in
                    guard let self else { return }
                    if await self.process(id) { self.blocked.insert(id) }
                    if self.active[id]?.token == token { self.active[id] = nil }
                    self.schedule()
                    self.changed()
                }
                active[id] = (token, task)
            }
        } catch { storageIssue = true }
        changed()
    }

    private func process(_ eventID: UUID) async -> Bool {
        while true {
            let claim: Journal.Claim
            do {
                let journal = try read()
                let others = Set(journal.events.map(\.id)).subtracting([eventID])
                guard let next = journal.next(excluding: others) else { return false }
                claim = next
            } catch { storageIssue = true; return true }
            let issue: Journal.Issue?
            do { try await operate(claim); issue = nil }
            catch let failure as HealthWriteOperationFailure { issue = failure.issue }
            catch { issue = .operation }
            do {
                var latest = try read()
                let expected = latest
                // Save -> delete or lifecycle withdrawal while awaiting the
                // callback: never acknowledge the new operation with old work.
                guard latest.contains(claim) else { continue }
                if let issue { try latest.recordFailure(claim, issue: issue) }
                else { try latest.acknowledge(claim) }
                try commit(latest, expected)
                changed()
                if issue != nil { return true }
            } catch { storageIssue = true; changed(); return true }
        }
    }

    /// For controlled verification and lifecycle coordination, without
    /// cancelling an underlying Health operation whose outcome is unknown.
    func waitForCurrentWork() async {
        while !active.isEmpty {
            let tasks = active.values.map(\.task)
            for task in tasks { await task.value }
        }
    }
}
