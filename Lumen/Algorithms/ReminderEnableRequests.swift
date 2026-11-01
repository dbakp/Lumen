import Foundation

/// A newer choice or a departed editor invalidates a pending permission reply.
@MainActor final class ReminderEnableRequests {
    enum Outcome: Equatable { case enabled, denied, cancelled }
    private var active: (owner: UUID, token: UUID)?
    var isRequesting: Bool { active != nil }

    func cancel(owner: UUID? = nil) {
        if owner == nil || active?.owner == owner { active = nil }
    }

    func enable(owner: UUID, authorize: () async -> Bool, commit: () throws -> Void) async throws -> Outcome {
        let token = UUID(); active = (owner, token)
        defer { if active?.token == token { active = nil } }
        let allowed = await authorize()
        guard active?.token == token, !Task.isCancelled else { return .cancelled }
        guard allowed else { return .denied }
        try commit()
        return .enabled
    }
}
