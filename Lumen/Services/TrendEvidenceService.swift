import Foundation

@MainActor
enum TrendEvidenceService {
    static func collect(health: HealthStore, sleep: SleepStore) async -> [ImportedHealthDay] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -61, to: calendar.startOfDay(for: Date()))!
        var days: [Date: ImportedHealthDay] = [:]
        for day in CompanionStore.shared.importedDays where day.date >= start { days[calendar.startOfDay(for: day.date)] = day }
        func set(_ date: Date, _ metric: String, _ value: Double, _ source: String) {
            let date = calendar.startOfDay(for: date)
            var day = days[date] ?? ImportedHealthDay(date: date, values: [:], sources: [:])
            day.values[metric] = value; day.sources[metric] = source; days[date] = day
        }
        if HealthKitService.shared.isAuthorized {
            for metric in [TrendMetric.steps, .activeEnergy, .exercise, .restingHR, .hrv] {
                for value in await HealthKitService.shared.dailySeries(metric, days: 61) { set(value.date, metric.rawValue, value.value, "Apple Health") }
            }
        }
        let nights = Dictionary(grouping: sleep.episodes.filter { $0.wakeTime >= start }) { calendar.startOfDay(for: $0.wakeTime) }
        for (date, episodes) in nights { set(date, "sleep", episodes.reduce(0) { $0 + $1.duration } / 3600, "Lumen sleep history") }
        let manual = Dictionary(grouping: health.workouts.filter { $0.source == .manual && $0.start >= start }) { calendar.startOfDay(for: $0.start) }
        for (date, sessions) in manual {
            for (metric, value) in [("exercise", sessions.reduce(0) { $0 + $1.duration / 60 }), ("activeEnergy", sessions.reduce(0) { $0 + $1.activeCalories })] {
                if days[date]?.sources[metric] == "Apple Health" {
                    set(date, metric, (days[date]?.values[metric] ?? 0) + value, "Apple Health + Lumen manual workouts")
                } else if value > (days[date]?.values[metric] ?? 0) { set(date, metric, value, "Lumen manual workouts") }
            }
        }
        let water = Dictionary(grouping: health.waterLogs.filter { $0.date >= start }) { calendar.startOfDay(for: $0.date) }
        for (date, logs) in water {
            let total = logs.reduce(0) { $0 + $1.ml }
            if total > (days[date]?.values["water"] ?? 0) { set(date, "water", total, "Lumen water logs") }
        }
        return days.values.sorted { $0.date < $1.date }
    }
}
