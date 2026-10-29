import Foundation

struct SavedChatLog: Identifiable {
    let id: String
    let title: String
    let date: Date
}

@MainActor
enum HealthLogConfirmation {
    static func saved(from selection: HealthLogSelection, health: HealthStore) -> [SavedChatLog] {
        let messageID = selection.message.id
        func matches(_ origin: HealthLogOrigin?) -> Bool { origin?.messageID == messageID && origin?.conversationID == selection.conversationID }
        let companion = CompanionStore.shared
        let symptoms = companion.symptoms.filter { matches($0.logOrigin) }.map { SavedChatLog(id: $0.id, title: $0.name, date: $0.date) }
        let checks = companion.checkIns.filter { matches($0.logOrigin) }.map { SavedChatLog(id: $0.id, title: "Check-in", date: $0.date) }
        let water = health.waterLogs.filter { matches($0.logOrigin) }.map { SavedChatLog(id: $0.id, title: "Water · \(Int($0.ml)) ml", date: $0.date) }
        let workouts = health.workouts.filter { matches($0.logOrigin) }.map { SavedChatLog(id: $0.id, title: $0.title, date: $0.start) }
        return (symptoms + checks + water + workouts).sorted { $0.date < $1.date }
    }
    static func contains(_ id: String, health: HealthStore) -> Bool {
        health.waterLogs.contains { $0.id == id } || health.workouts.contains { $0.id == id } || CompanionStore.shared.symptoms.contains { $0.id == id } || CompanionStore.shared.checkIns.contains { $0.id == id }
    }
    /// A proposal writes exactly one domain atomically. Memory changes only after that write succeeds.
    static func confirm(_ draft: HealthLogDraft, selection: HealthLogSelection, health: HealthStore) throws {
        guard selection.message.role == .user, selection.message.text.count <= 8000 else { throw HealthLogDrafting.DraftError.invalid }
        guard draft.validationMessage == nil else { throw HealthLogDrafting.DraftError.invalid }
        guard !contains(draft.recordID, health: health) else { return }
        let origin = HealthLogOrigin(conversationID: selection.conversationID, messageID: selection.message.id, statement: selection.message.text, preparedBy: draft.preparedBy, confirmedAt: Date())
        switch draft.kind {
        case .symptom:
            let entry = SymptomEntry(logOrigin: origin, id: draft.recordID, date: draft.date, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), location: draft.location.trimmingCharacters(in: .whitespacesAndNewlines), severity: draft.severity!, durationMinutes: draft.durationMinutes.map(Int.init), note: draft.note, triggers: [], resolvedAt: nil)
            try CompanionStore.shared.confirmSymptom(entry)
        case .checkIn:
            let entry = WellbeingCheckIn(logOrigin: origin, id: draft.recordID, date: draft.date, energy: draft.energy!, mood: draft.mood!, stress: draft.stress!, note: draft.note)
            try CompanionStore.shared.confirmCheckIn(entry)
        case .water:
            var log = HydrationLog(id: draft.recordID, date: draft.date, ml: draft.waterML!)
            log.logOrigin = origin; log.note = draft.note
            let records = health.waterLogs + [log]
            try LocalStore.saveChecked(records, as: "water"); health.waterLogs = records; health.refresh()
        case .workout:
            var workout = Workout(id: draft.recordID, kind: draft.workoutKind!, title: draft.name.isEmpty ? draft.workoutKind!.label : draft.name, start: draft.date, duration: draft.durationMinutes! * 60, activeCalories: draft.energyKcal ?? 0, source: .manual)
            workout.energyKnown = draft.energyKcal != nil; workout.energyIsEstimate = false; workout.logOrigin = origin; workout.note = draft.note
            let records = (health.workouts + [workout]).sorted { $0.start < $1.start }
            try LocalStore.saveChecked(records, as: "workouts"); health.workouts = records; health.refresh()
        }
    }
}
