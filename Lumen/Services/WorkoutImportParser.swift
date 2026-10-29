import Foundation
import CryptoKit

struct WorkoutImportDraft {
    var type: String
    var source: String
    var start: Date
    var end: Date
    var duration: Double
    var energy: Double?
    var distance: Double?
    var heartRate: Double?
    var warnings: [String] = []
    var statistics: [String: Double] = [:]
    var blockedStatistics: Set<String> = []
    var durationWasReported = true

    static func make(_ attributes: [String: String], date: (String) -> Date?) -> WorkoutImportDraft? {
        guard let type = attributes["workoutActivityType"], type.hasPrefix("HKWorkoutActivityType"), type.count > "HKWorkoutActivityType".count, type.count <= 100,
              type.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }),
              let start = attributes["startDate"].flatMap(date), let end = attributes["endDate"].flatMap(date),
              start < end, end <= Date().addingTimeInterval(60), end.timeIntervalSince(start) <= 7 * 86400 else { return nil }
        let duration: Double
        if let raw = attributes["duration"] {
            guard let value = Double(raw), let seconds = seconds(value, unit: attributes["durationUnit"] ?? ""), seconds > 0,
                  seconds <= end.timeIntervalSince(start) + 60 else { return nil }
            duration = seconds
        } else { duration = end.timeIntervalSince(start) }
        var draft = WorkoutImportDraft(type: type, source: String((attributes["sourceName"] ?? "Apple Health export").prefix(500)), start: start, end: end, duration: duration)
        draft.durationWasReported = attributes["duration"] != nil
        if let raw = attributes["totalEnergyBurned"] {
            draft.energy = Double(raw).flatMap { energy($0, unit: attributes["totalEnergyBurnedUnit"] ?? "") }
            if draft.energy == nil { draft.warnings.append("Energy value could not be read") }
        }
        if let raw = attributes["totalDistance"] {
            draft.distance = Double(raw).flatMap { distance($0, unit: attributes["totalDistanceUnit"] ?? "") }
            if draft.distance == nil { draft.warnings.append("Distance value could not be read") }
        }
        return draft
    }
    mutating func statistic(_ a: [String: String]) {
        guard let type = a["type"], !blockedStatistics.contains(type) else { return }
        let value: Double?
        switch type {
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            value = a["sum"].flatMap(Double.init).flatMap { Self.energy($0, unit: a["unit"] ?? "") }
        case "HKQuantityTypeIdentifierDistanceWalkingRunning", "HKQuantityTypeIdentifierDistanceCycling", "HKQuantityTypeIdentifierDistanceSwimming", "HKQuantityTypeIdentifierDistanceWheelchair":
            value = a["sum"].flatMap(Double.init).flatMap { Self.distance($0, unit: a["unit"] ?? "") }
        case "HKQuantityTypeIdentifierHeartRate":
            value = a["average"].flatMap(Double.init).flatMap { number in
                guard ["count/min", "bpm"].contains(a["unit"] ?? ""), number.isFinite, (0...300).contains(number) else { return nil }
                return number
            }
        default: return
        }
        guard let value else { warnings.append("A workout statistic could not be read"); return }
        // Repeated statistics are not additive. Conflicting duplicates are left unknown.
        if let old = statistics[type], old != value { warnings.append("Conflicting workout statistics"); statistics[type] = nil; blockedStatistics.insert(type); return }
        statistics[type] = value
    }
    func workout() -> Workout {
        let suffix = String(type.dropFirst("HKWorkoutActivityType".count))
        let known: [String: (WorkoutKind, String)] = ["Running":(.run,"Run"), "Cycling":(.ride,"Ride"), "Walking":(.walk,"Walk"), "Swimming":(.swim,"Swim"), "Hiking":(.hike,"Hike"), "TraditionalStrengthTraining":(.strength,"Strength training"), "FunctionalStrengthTraining":(.strength,"Functional strength"), "HighIntensityIntervalTraining":(.hiit,"HIIT"), "Yoga":(.yoga,"Yoga"), "Rowing":(.row,"Row")]
        let label = suffix.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        let identity = (try? JSONEncoder().encode([type, source, String(start.timeIntervalSince1970), String(end.timeIntervalSince1970)])) ?? Data()
        let id = "apple-export-" + SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        let energy = self.energy ?? statistics["HKQuantityTypeIdentifierActiveEnergyBurned"]
        let distances = statistics.filter { $0.key.hasPrefix("HKQuantityTypeIdentifierDistance") }.map(\.value)
        let distance = self.distance ?? (distances.count == 1 ? distances.first : nil)
        var workout = Workout(id: id, kind: known[suffix]?.0 ?? .other, title: known[suffix]?.1 ?? (label.isEmpty ? "Workout" : label), start: start, duration: duration, activeCalories: energy ?? 0, distanceM: distance, avgHR: statistics["HKQuantityTypeIdentifierHeartRate"], source: .healthKit)
        workout.importOrigin = WorkoutImportOrigin(sourceName: source, activityType: type, end: end, durationWasReported: durationWasReported, warnings: warnings)
        workout.energyKnown = energy != nil; workout.energyIsEstimate = false
        return workout
    }
    static func seconds(_ value: Double, unit: String) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        switch unit { case "s", "sec": return value; case "min": return value * 60; case "h", "hr": return value * 3600; default: return nil }
    }
    static func energy(_ value: Double, unit: String) -> Double? {
        let result: Double
        switch unit { case "kcal": result = value; case "kJ": result = value / 4.184; default: return nil }
        return result.isFinite && (0...100000).contains(result) ? result : nil
    }
    static func distance(_ value: Double, unit: String) -> Double? {
        let result: Double
        switch unit { case "m": result = value; case "km": result = value * 1000; case "mi": result = value * 1609.344; default: return nil }
        return result.isFinite && (0...2_000_000).contains(result) ? result : nil
    }
}
