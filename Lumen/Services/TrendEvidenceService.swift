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
        return TrendEvidence.includingLocal(Array(days.values), workouts: health.workouts, water: health.waterLogs, sleep: sleep.episodes, since: start)
    }
}
