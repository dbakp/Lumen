import Foundation

/// Resolves today's observations once, so UI, coaching and assistant context use the same values.
public enum CurrentHealthEvidence {
    public struct WorkoutEnergyDay: Identifiable, Sendable {
        public var id: Date { date }
        public var date: Date
        public var kcal: Double
    }
    public static func recentWorkouts(_ workouts: [Workout], now: Date = Date(), calendar: Calendar = .current) -> [Workout] {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        return workouts.filter { $0.source != .sample && $0.start >= start && $0.start <= now && $0.duration.isFinite && $0.duration >= 0 }
    }
    /// Only days with an actual energy reading appear. A recorded zero stays present.
    public static func workoutEnergyByDay(_ workouts: [Workout], now: Date = Date(), calendar: Calendar = .current) -> [WorkoutEnergyDay] {
        var totals: [Date: Double] = [:]
        for workout in recentWorkouts(workouts, now: now, calendar: calendar) {
            guard let energy = workout.energyKcal, energy.isFinite, energy >= 0 else { continue }
            totals[calendar.startOfDay(for: workout.start), default: 0] += energy
        }
        return totals.filter { $0.value.isFinite && $0.value < Double(Int.max / 2) }.map { .init(date: $0.key, kcal: $0.value) }.sorted { $0.date < $1.date }
    }
    public struct StandHourEvent: Sendable {
        public var start: Date
        public var stood: Bool
    }
    /// Category records count qualifying clock hours, not continuous standing duration.
    public static func standHours(_ events: [StandHourEvent], start: Date, end: Date, calendar: Calendar = .current) -> Double? {
        let recorded = events.filter { $0.start.timeIntervalSince1970.isFinite && $0.start >= start && $0.start <= end }
        guard !recorded.isEmpty else { return nil }
        let hours = recorded.filter(\.stood).compactMap { calendar.dateInterval(of: .hour, for: $0.start)?.start }
        return Double(Set(hours).count)
    }
    public static func merging(_ incoming: DayMetrics, into previous: DayMetrics, now: Date = Date(), calendar: Calendar = .current) -> DayMetrics {
        let old = resolve(snapshot: previous, imported: nil, meals: [], water: [], workouts: [], sleep: nil, now: now, calendar: calendar)
        var result = incoming
        for key in HealthMetricCatalog.keys {
            let fresh = incoming.reading(key), cached = old.reading(key)
            if fresh.healthQuery?.outcome == .failed, cached.value != nil {
                var retained = cached; retained.healthQuery = fresh.healthQuery; result.setReading(retained, for: key)
            }
        }
        let localWeight = old.reading("weight")
        if localWeight.components.contains(where: { $0.origin == .localLog }),
           let localDate = localWeight.components.compactMap(\.lastSampleAt).max(),
           localDate > (result.reading("weight").components.compactMap(\.lastSampleAt).max() ?? .distantPast) {
            var retained = localWeight; retained.healthQuery = incoming.reading("weight").healthQuery
            result.setReading(retained, for: "weight")
        }
        return result
    }
    public static func resolve(snapshot: DayMetrics, imported: ImportedHealthDay?, meals: [Meal], water: [HydrationLog], workouts: [Workout], sleep: SleepEpisode?, now: Date = Date(), calendar: Calendar = .current) -> DayMetrics {
        let day = calendar.startOfDay(for: now)
        var result = DayMetrics.empty; result.date = day; result.readings = [:]; result.recordedTotalKeys = []
        let snapshotIsToday = calendar.isDate(snapshot.date, inSameDayAs: now)
        func validDate(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite && date <= now }
        func current(_ component: HealthMetricComponent, key: String) -> Bool {
            guard component.value.isFinite, component.value >= 0, validDate(component.start), component.checkedAt.map(validDate) ?? true,
                  component.lastSampleAt.map(validDate) ?? true, component.end.map(validDate) ?? true else { return false }
            if let end = component.end, end < component.start { return false }
            let anchor = key == "sleep" ? (component.end ?? component.start) : component.start
            return calendar.isDate(anchor, inSameDayAs: now)
        }
        for key in HealthMetricCatalog.keys {
            var reading = HealthMetricReading.unknown
            if snapshotIsToday {
                if let stored = snapshot.readings?[key] {
                    // A partial combined reading cannot be recomputed by dropping stale contributors.
                    if stored.components.allSatisfy({ current($0, key: key) }), stored.components.isEmpty || stored.value != nil { reading = stored }
                    else { reading.healthQuery = stored.healthQuery }
                    if let query = reading.healthQuery, !validDate(query.checkedAt) || !calendar.isDate(query.start, inSameDayAs: now) { reading = .unknown }
                } else if snapshot.readings == nil {
                    // Legacy daily totals have a day, but discrete samples have no provable sample date.
                    let legacy: Double?
                    switch key {
                    case "stand": legacy = nil // Old snapshots stored duration, not qualifying stand/roll hours.
                    case "calories": legacy = snapshot.dietaryCalories
                    case "protein": legacy = snapshot.dietaryProtein
                    case "carbs": legacy = snapshot.dietaryCarbs
                    case "fat": legacy = snapshot.dietaryFat
                    default: legacy = snapshot.recordedTotal(key)
                    }
                    if let value = legacy, value.isFinite, value >= 0 {
                        reading.components = [.init(value: value, origin: .legacyCache, source: "Cached daily total", start: day, aggregation: .reportedDay)]
                    }
                }
            }
            if reading.value == nil, HealthImportService.units[key] != nil, let imported, calendar.isDate(imported.date, inSameDayAs: now), let value = imported.values[key], value.isFinite, value >= 0 {
                reading.components = [.init(value: value, origin: .healthImport, source: imported.sources[key] ?? "Health import", start: day, aggregation: .reportedDay)]
            }
            result.setReading(reading, for: key)
        }
        func isToday(_ date: Date) -> Bool { validDate(date) && calendar.isDate(date, inSameDayAs: now) }
        func local(_ value: Double, dates: [Date], source: String, estimate: Bool = false) -> HealthMetricComponent? {
            guard !dates.isEmpty, value.isFinite, value >= 0, let first = dates.min(), let last = dates.max() else { return nil }
            return .init(value: value, origin: .localLog, source: source, start: first, end: last, lastSampleAt: last, aggregation: .total, isEstimate: estimate)
        }
        func combine(_ component: HealthMetricComponent?, key: String, additive: Bool) {
            guard let component else { return }
            var reading = result.reading(key)
            if reading.value == nil { reading.components = [component] }
            else if additive { reading.components.append(component) }
            else {
                if component.value > (reading.value ?? 0) { reading.components = [component] }
                reading.overlapKeptSeparate = true
            }
            result.setReading(reading, for: key)
        }
        let manual = workouts.filter { $0.source == .manual && $0.importOrigin == nil && isToday($0.start) }
        let energetic = manual.filter { $0.energyKcal != nil }
        for (key, component) in [
            ("exercise", local(manual.reduce(0) { $0 + $1.duration / 60 }, dates: manual.map(\.start), source: "Lumen workouts")),
            ("activeEnergy", local(energetic.reduce(0) { $0 + ($1.energyKcal ?? 0) }, dates: energetic.map(\.start), source: "Lumen workouts", estimate: energetic.contains { $0.energyIsEstimate ?? true }))
        ] {
            let live = result.reading(key).components.contains { $0.origin == .healthKit || $0.origin == .legacyCache }
            combine(component, key: key, additive: live)
        }
        let glasses = water.filter { isToday($0.date) && $0.ml.isFinite && $0.ml > 0 }
        let waterLive = result.reading("water").components.contains { $0.origin == .healthKit || $0.origin == .legacyCache }
        combine(local(glasses.reduce(0) { $0 + $1.ml }, dates: glasses.map(\.date), source: "Lumen water logs"), key: "water", additive: waterLive && snapshot.excludesLumenNutrition == true)
        let food = meals.filter { $0.source != .sample && isToday($0.date) }
        for (key, value) in [("calories", food.reduce(0) { $0 + $1.calories }), ("protein", food.reduce(0) { $0 + $1.protein }), ("carbs", food.reduce(0) { $0 + $1.carbs }), ("fat", food.reduce(0) { $0 + $1.fat })] {
            let live = result.reading(key).components.contains { $0.origin == .healthKit || $0.origin == .legacyCache }
            combine(local(value, dates: food.map(\.date), source: "Lumen meal logs", estimate: true), key: key, additive: live && snapshot.excludesLumenNutrition == true)
        }
        if let sleep, isToday(sleep.wakeTime), validDate(sleep.bedtime), sleep.wakeTime >= sleep.bedtime, sleep.duration.isFinite, sleep.duration > 0 {
            let component = HealthMetricComponent(value: sleep.duration / 3600, origin: .sleepHistory, source: "Sleep history · " + sleep.source.label, start: sleep.bedtime, end: sleep.wakeTime, lastSampleAt: sleep.wakeTime, aggregation: .total, isEstimate: sleep.asleepSeconds == nil)
            result.setReading(.init(components: [component]), for: "sleep")
        }
        result.excludesLumenNutrition = snapshot.excludesLumenNutrition
        return result
    }

    public static func estimatedSleepDebt(_ episodes: [SleepEpisode], sleepNeed: TimeInterval, now: Date = Date(), calendar: Calendar = .current) -> TimeInterval? {
        guard sleepNeed.isFinite, sleepNeed > 0, sleepNeed <= 24 * 3600,
              let nights = completeSleepWindow(episodes, now: now, calendar: calendar) else { return nil }
        return SleepDebtCalculator.debt(sleepNeed: sleepNeed, recentDurationsOldestFirst: nights.map(\.duration))
    }

    public static func hasCompleteSleepWindow(_ episodes: [SleepEpisode], now: Date = Date(), calendar: Calendar = .current) -> Bool {
        completeSleepWindow(episodes, now: now, calendar: calendar) != nil
    }

    private static func completeSleepWindow(_ episodes: [SleepEpisode], now: Date, calendar: Calendar) -> [SleepEpisode]? {
        guard now.timeIntervalSince1970.isFinite,
              episodes.allSatisfy({ $0.wakeTime.timeIntervalSince1970.isFinite && $0.bedtime.timeIntervalSince1970.isFinite }),
              let start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) else { return nil }
        let nights = episodes.filter { $0.wakeTime >= start && $0.wakeTime <= now }
        guard nights.count == 14, Set(nights.map { calendar.startOfDay(for: $0.wakeTime) }).count == 14,
              nights.allSatisfy({ $0.bedtime < $0.wakeTime && $0.duration.isFinite && $0.duration > 0 }) else { return nil }
        return nights.sorted { $0.wakeTime < $1.wakeTime }
    }
}
