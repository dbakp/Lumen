import Foundation

public enum HealthTotals {
    /// HealthKit totals exclude samples written by Lumen, so local logs are counted exactly once.
    /// Imported daily totals can overlap local logs: use the larger until a live source exists.
    public static func nutrient(local: Double, external: Double?, imported: Double?, excludesLumen: Bool) -> Double {
        if excludesLumen, let external { return local + external }
        return max(local, external ?? imported ?? 0)
    }
    public static func water(local: Double, snapshot: Double?, imported: Double?, excludesLumen: Bool) -> Double {
        if let snapshot { return excludesLumen ? local + snapshot : max(local, snapshot) }
        return max(local, imported ?? 0)
    }
}

extension DayMetrics {
    public static let cumulativeKeys = ["steps", "activeEnergy", "restingEnergy", "exercise", "stand", "water"]

    /// Legacy zero-filled snapshots cannot tell an empty query from a recorded zero.
    /// New snapshots carry explicit presence, including genuine zero readings.
    public func recordedTotal(_ key: String) -> Double? {
        let value: Double
        switch key {
        case "steps": value = steps
        case "activeEnergy": value = activeCalories
        case "restingEnergy": value = restingCalories
        case "exercise": value = exerciseMin
        case "stand": value = Double(standHours)
        case "water": value = waterML
        default: return nil
        }
        guard value.isFinite, value >= 0 else { return nil }
        if let recordedTotalKeys { return recordedTotalKeys.contains(key) ? value : nil }
        return value > 0 ? value : nil
    }

    public mutating func recordTotal(_ value: Double, for key: String) {
        guard value.isFinite, value >= 0, Self.cumulativeKeys.contains(key) else { return }
        if key == "stand", value >= Double(Int.max) { return }
        if recordedTotalKeys == nil {
            recordedTotalKeys = Set(Self.cumulativeKeys.filter { recordedTotal($0) != nil })
        }
        switch key {
        case "steps": steps = value
        case "activeEnergy": activeCalories = value
        case "restingEnergy": restingCalories = value
        case "exercise": exerciseMin = value
        case "stand": standHours = Int(value.rounded())
        case "water": waterML = value
        default: return
        }
        recordedTotalKeys?.insert(key)
    }

    public mutating func fillMissingActivity(from imported: [String: Double]) {
        for key in ["steps", "activeEnergy", "exercise"] where recordedTotal(key) == nil {
            if let value = imported[key] { recordTotal(value, for: key) }
        }
    }

    /// Imported day totals may already include manual sessions. Only a per-metric
    /// live reading establishes a separate total to which those sessions can be added.
    public mutating func reconcileActivity(from imported: [String: Double], manualWorkouts: [Workout]) {
        let liveKeys = Set(["activeEnergy", "exercise"].filter { recordedTotal($0) != nil })
        fillMissingActivity(from: imported)
        let manual = manualWorkouts.filter { $0.source == .manual }
        let energy = manual.compactMap(\.energyKcal)
        if !energy.isEmpty, imported["activeEnergy"] == nil || liveKeys.contains("activeEnergy") {
            recordTotal(activeCalories + energy.reduce(0, +), for: "activeEnergy")
        }
        if !manual.isEmpty, imported["exercise"] == nil || liveKeys.contains("exercise") {
            recordTotal(exerciseMin + manual.reduce(0) { $0 + $1.duration / 60 }, for: "exercise")
        }
    }
}
