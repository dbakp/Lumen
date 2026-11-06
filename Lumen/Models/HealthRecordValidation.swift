import Foundation

/// Domain invariants shared by current/legacy local reads and backup import.
/// Numeric limits protect calculations; they are not clinical reference ranges.
enum HealthRecordValidation {
    private static func bounded(_ value: Double) -> Bool { value.isFinite && (0...1_000_000_000).contains(value) }
    private static func optional(_ value: Double?) -> Bool { value.map(bounded) ?? true }
    private static func date(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite && abs(value.timeIntervalSince1970) <= 1_000_000_000_000
    }
    private static func unique<T: Identifiable>(_ records: [T]) -> Bool where T.ID == String {
        records.count <= 200_000 && records.allSatisfy { !$0.id.isEmpty && $0.id.utf8.count <= 1024 }
        && Set(records.map(\.id)).count == records.count
    }
    static func water(_ values: [HydrationLog]) -> Bool {
        unique(values) && values.allSatisfy {
            $0.ml.isFinite && $0.ml > 0 && $0.ml <= 10000 && date($0.date) && ($0.lastEditedAt.map(date) ?? true)
        }
    }
    static func meals(_ values: [Meal]) -> Bool {
        guard unique(values) else { return false }
        var foods = 0
        for meal in values {
            foods += meal.items.count
            guard foods <= 500_000, date(meal.date), unique(meal.items),
                  meal.photoID.map(BackupArchive.safePhotoID) ?? true else { return false }
            guard meal.items.allSatisfy({ item in
                (0...1).contains(item.confidence) && [item.grams, item.calories, item.proteinG, item.carbsG, item.fatG, item.fiberG].allSatisfy(bounded)
            }) else { return false }
        }
        return true
    }
    static func workouts(_ values: [Workout]) -> Bool {
        unique(values) && values.allSatisfy { workout in
            guard date(workout.start), workout.lastEditedAt.map(date) ?? true,
                  bounded(workout.duration), bounded(workout.activeCalories), optional(workout.distanceM), optional(workout.avgHR) else { return false }
            guard let origin = workout.importOrigin else { return true }
            return date(origin.end) && origin.end >= workout.start && origin.end.timeIntervalSince(workout.start) <= 7 * 86400
                && workout.duration <= origin.end.timeIntervalSince(workout.start) + 60
        }
    }
    static func goals(_ value: HealthGoals) -> Bool {
        [value.stepGoal, value.activeCalGoal, value.exerciseGoalMin].allSatisfy(bounded)
        && optional(value.weightKg) && optional(value.heightCm)
        && (0...150).contains(value.age ?? 30) && (0...24).contains(value.standGoal)
    }
    static func today(_ value: DayMetrics) -> Bool {
        guard date(value.date), [value.steps, value.activeCalories, value.restingCalories, value.exerciseMin, value.waterML].allSatisfy(bounded),
              (0...1_000_000_000).contains(value.standHours),
              [value.avgHR, value.restingHR, value.hrvMS, value.respiratoryRate, value.spo2, value.vo2max, value.weightKg, value.sleepSeconds,
               value.dietaryCalories, value.dietaryProtein, value.dietaryCarbs, value.dietaryFat].allSatisfy(optional),
              (value.recordedTotalKeys?.count ?? 0) <= 1000, (value.readings?.count ?? 0) <= 1000 else { return false }
        var components = 0
        for reading in (value.readings ?? [:]).values {
            components += reading.components.count
            guard components <= 500_000, reading.components.allSatisfy({ part in
                bounded(part.value) && date(part.start) && (part.end.map { date($0) && $0 >= part.start } ?? true)
                && (part.lastSampleAt.map(date) ?? true) && (part.checkedAt.map(date) ?? true)
            }) else { return false }
            if let query = reading.healthQuery {
                guard date(query.start), date(query.end), date(query.checkedAt), query.end >= query.start else { return false }
            }
        }
        return true
    }
    static func accepts<T>(_ value: T, domain: HealthLocalFiles.Domain) -> Bool {
        switch domain {
        case .water: return (value as? [HydrationLog]).map(water) ?? false
        case .meals: return (value as? [Meal]).map(meals) ?? false
        case .workouts: return (value as? [Workout]).map(workouts) ?? false
        case .goals: return (value as? HealthGoals).map(goals) ?? false
        case .today: return (value as? DayMetrics).map(today) ?? false
        }
    }
}
