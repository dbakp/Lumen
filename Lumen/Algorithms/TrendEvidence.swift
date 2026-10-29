import Foundation

public struct MetricEvidence: Identifiable, Sendable {
    public var id: String { metric }
    public var metric: String
    public var unit: String
    public var window: Int
    public var current: [ImportedHealthDay]
    public var previous: [ImportedHealthDay]
    public var currentMean: Double? { mean(current) }
    public var previousMean: Double? { mean(previous) }
    public var comparable: Bool { current.count >= 3 && previous.count >= 3 }
    public var change: Double? { guard comparable, let a = currentMean, let b = previousMean else { return nil }; return a - b }
    public var changePercent: Double? { guard let change, let base = previousMean, base != 0 else { return nil }; return change / abs(base) * 100 }
    public var sources: [String] { Array(Set((current + previous).compactMap { $0.sources[metric] })).sorted() }
    private func mean(_ days: [ImportedHealthDay]) -> Double? {
        let values = days.compactMap { $0.values[metric] }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

public enum TrendEvidence {
    /// Rebuilt from current local records each time, so edits and deletions cannot leave stale totals.
    public static func includingLocal(_ sourceDays: [ImportedHealthDay], workouts: [Workout], water: [HydrationLog], sleep: [SleepEpisode], since start: Date, now: Date = Date(), calendar: Calendar = .current) -> [ImportedHealthDay] {
        var days: [Date: ImportedHealthDay] = [:]
        for day in sourceDays where day.date >= start && day.date <= now { days[calendar.startOfDay(for: day.date)] = day }
        func set(_ date: Date, _ metric: String, _ value: Double, _ source: String) {
            guard value.isFinite, value >= 0, value < Double(Int.max / 2) else { return }
            var day = days[date] ?? ImportedHealthDay(date: date, values: [:], sources: [:])
            day.values[metric] = value; day.sources[metric] = source; days[date] = day
        }
        func merge(_ date: Date, _ metric: String, _ value: Double, _ source: String) {
            let existing = days[date]?.values[metric]
            if days[date]?.sources[metric] == "Apple Health", let existing {
                set(date, metric, existing + value, "Apple Health + " + source)
            } else if existing == nil || value > (existing ?? 0) {
                set(date, metric, value, source)
            }
        }
        let sessions = workouts.filter { $0.source == .manual && $0.importOrigin == nil && $0.start >= start && $0.start <= now && $0.duration.isFinite && $0.duration >= 0 }
        for (date, sessions) in Dictionary(grouping: sessions, by: { calendar.startOfDay(for: $0.start) }) {
            merge(date, "exercise", sessions.reduce(0) { $0 + $1.duration / 60 }, "Lumen manual workouts")
            let known = sessions.compactMap(\.energyKcal).filter { $0.isFinite && $0 >= 0 }
            if !known.isEmpty { merge(date, "activeEnergy", known.reduce(0, +), "Lumen manual workouts") }
        }
        let glasses = water.filter { $0.date >= start && $0.date <= now && $0.ml.isFinite && $0.ml > 0 }
        for (date, logs) in Dictionary(grouping: glasses, by: { calendar.startOfDay(for: $0.date) }) {
            // Water source overlap is unknown; keep the larger available daily total.
            let total = logs.reduce(0) { $0 + $1.ml }
            if days[date]?.values["water"] == nil || total > (days[date]?.values["water"] ?? 0) { set(date, "water", total, "Lumen water logs") }
        }
        let nights = sleep.filter { $0.wakeTime >= start && $0.wakeTime <= now && $0.bedtime < $0.wakeTime && $0.duration.isFinite && $0.duration > 0 }
        for (date, episodes) in Dictionary(grouping: nights, by: { calendar.startOfDay(for: $0.wakeTime) }) {
            set(date, "sleep", episodes.reduce(0) { $0 + $1.duration } / 3600, "Lumen sleep history")
        }
        return days.values.sorted { $0.date < $1.date }
    }

    /// Compare completed calendar days, excluding the incomplete current day and never filling gaps.
    public static func compare(_ days: [ImportedHealthDay], metric: String, window: Int, now: Date = Date(), calendar: Calendar = .current) -> MetricEvidence {
        let window = max(1, window)
        let end = calendar.startOfDay(for: now)
        let cut = calendar.date(byAdding: .day, value: -window, to: end)!
        let start = calendar.date(byAdding: .day, value: -window, to: cut)!
        var unique: [Date: ImportedHealthDay] = [:]
        for day in days {
            guard let value = day.values[metric], value.isFinite, value >= 0 else { continue }
            let key = calendar.startOfDay(for: day.date)
            unique[key] = ImportedHealthDay(date: key, values: [metric: value], sources: day.sources)
        }
        let ordered = unique.values.sorted { $0.date < $1.date }
        return MetricEvidence(metric: metric, unit: ImportedMetrics.displayUnit(metric), window: window, current: ordered.filter { $0.date >= cut && $0.date < end }, previous: ordered.filter { $0.date >= start && $0.date < cut })
    }
}

public enum AppointmentSummary {
    public static func make(symptoms: [SymptomEntry], checkIns: [WellbeingCheckIn], workouts: [Workout], days: Int, now: Date = Date(), context: PersonalHealthContext? = nil) -> HealthDocument {
        let start = Calendar.current.date(byAdding: .day, value: -max(1, days) + 1, to: Calendar.current.startOfDay(for: now))!
        let selected = symptoms.filter { $0.date <= now && ($0.date >= start || $0.isActive) }.sorted { $0.date < $1.date }
        let checks = checkIns.filter { $0.date >= start && $0.date <= now }.sorted { $0.date < $1.date }
        let sessions = workouts.filter { $0.start >= start && $0.start <= now }.sorted { $0.start < $1.start }
        var body = ["Prepared from user-recorded logs for \(start.formatted(date: .abbreviated, time: .omitted)) through \(now.formatted(date: .abbreviated, time: .omitted)). Older unresolved symptoms are included. Review and edit before sharing. Missing logs do not mean an event or symptom did not occur.", "## Symptoms"]
        if selected.isEmpty { body.append("No symptom entries available in this range.") }
        for entry in selected.prefix(200) {
            body.append("- \(entry.date.formatted(date: .abbreviated, time: .shortened)): \(entry.name), \(entry.location), severity \(entry.severity)/10. \(entry.resolvedAt.map { "Marked resolved " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Still marked ongoing").\(entry.durationMinutes.map { " Duration at logging: \($0) minutes." } ?? "")\n  Description: \(entry.note.isEmpty ? "Not entered" : entry.note)\n  Self-reported possible triggers: \(entry.triggers.isEmpty ? "None entered" : entry.triggers.joined(separator: ", ")).")
        }
        if selected.count > 200 { body.append("Showing 200 of \(selected.count) symptom entries; consult the Journal for all entries.") }
        let checkDays = Set(checks.map { Calendar.current.startOfDay(for: $0.date) }).count
        body.append("## Check-ins\n\(checks.count) \(checks.count == 1 ? "entry" : "entries") across \(checkDays) recorded \(checkDays == 1 ? "day" : "days").")
        for entry in checks.suffix(60) { body.append("- \(entry.date.formatted(date: .abbreviated, time: .shortened)): energy \(entry.energy)/5, mood \(entry.mood)/5, stress \(entry.stress)/5. \(entry.note)") }
        if checks.count > 60 { body.append("Showing the latest 60 check-ins.") }
        body.append("## Activity\n\(sessions.count) recorded workouts, \(Int(sessions.reduce(0) { $0 + $1.duration } / 60)) minutes total. Source coverage may be incomplete.")
        for session in sessions.suffix(30) { body.append("- \(session.start.formatted(date: .abbreviated, time: .omitted)): \(session.title), \(Int(session.duration / 60)) minutes · \(session.source.label).") }
        if sessions.count > 30 { body.append("Showing the latest 30 workouts.") }
        if var context { context.includeInAssistant = true; body.append("## Personal notes included by you\n" + context.assistantText) }
        body.append("## Questions to discuss\n- What has changed, and how long does it last?\n- What else should I record to make this history useful?\n- Which symptoms or changes should prompt follow-up?\n\nThis is a record summary, not a diagnosis or a claim about what caused a symptom.")
        return HealthDocument(title: "Appointment summary · \(now.formatted(date: .abbreviated, time: .omitted))", kind: .review, body: body.joined(separator: "\n\n"), source: "Lumen · local log summary")
    }
}
