import Foundation

enum LocalHealthCorrection {
    enum Failure: Error { case missing, protectedRecord, invalid }
    static func canEdit(_ workout: Workout) -> Bool { workout.source == .manual && workout.importOrigin == nil && workout.logOrigin != nil }
    static func water(id: String, draft: HealthLogDraft?, records: [HydrationLog], now: Date = Date()) throws -> [HydrationLog] {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw Failure.missing }
        guard records[index].logOrigin != nil else { throw Failure.protectedRecord }
        var result = records
        if let draft {
            guard draft.kind == .water, draft.validationMessage(now: now) == nil, let amount = draft.waterML else { throw Failure.invalid }
            result[index].ml = amount; result[index].date = draft.date; result[index].note = draft.note
            result[index].lastEditedAt = now
        } else { result.remove(at: index) }
        return result
    }
    static func workout(id: String, draft: HealthLogDraft?, records: [Workout], now: Date = Date()) throws -> [Workout] {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw Failure.missing }
        guard canEdit(records[index]) else { throw Failure.protectedRecord }
        var result = records
        if let draft {
            guard draft.kind == .workout, draft.validationMessage(now: now) == nil, let kind = draft.workoutKind, let minutes = draft.durationMinutes else { throw Failure.invalid }
            result[index].kind = kind; result[index].title = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(kind.label)
            result[index].start = draft.date; result[index].duration = minutes * 60
            result[index].activeCalories = draft.energyKcal ?? 0; result[index].energyKnown = draft.energyKcal != nil
            result[index].energyIsEstimate = false; result[index].note = draft.note; result[index].lastEditedAt = now
        } else { result.remove(at: index) }
        return result.sorted { $0.start < $1.start }
    }
}

private extension String { func ifBlank(_ fallback: String) -> String { isEmpty ? fallback : self } }
