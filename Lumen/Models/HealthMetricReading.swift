import Foundation

public struct HealthMetricQuery: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable { case recorded, noData, failed }
    public var start: Date
    public var end: Date
    public var checkedAt: Date
    public var outcome: Outcome
}

public struct HealthMetricComponent: Codable, Sendable, Equatable {
    public enum Origin: String, Codable, Sendable { case healthKit, healthImport, localLog, sleepHistory, legacyCache }
    public enum Aggregation: String, Codable, Sendable { case total, average, latest, reportedDay }
    public var value: Double
    public var origin: Origin
    public var source: String
    public var start: Date
    public var end: Date?
    public var lastSampleAt: Date?
    public var checkedAt: Date?
    public var aggregation: Aggregation
    public var isEstimate: Bool = false
}

public struct HealthMetricReading: Codable, Sendable, Equatable {
    public var components: [HealthMetricComponent] = []
    public var healthQuery: HealthMetricQuery? = nil
    public var overlapKeptSeparate: Bool = false
    public var value: Double? {
        guard !components.isEmpty, components.allSatisfy({ $0.value.isFinite && $0.value >= 0 }) else { return nil }
        let total = components.reduce(0) { $0 + $1.value }
        // All legacy native consumers can safely convert a resolved reading to Int.
        return total.isFinite && total < Double(Int.max) / 2 ? total : nil
    }
    public var sourceLabel: String {
        Array(Set(components.map { ($0.origin == .healthImport ? "Import · " : "") + String($0.source.prefix(120)) })).sorted().joined(separator: " + ")
    }
    public var isEstimate: Bool { components.contains(where: \.isEstimate) }
    public static var unknown: Self { .init() }
}

extension HealthMetricComponent {
    public var periodDescription: String {
        func date(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
        if aggregation == .reportedDay { return "Reported for \(start.formatted(date: .abbreviated, time: .omitted)). Sample times are unavailable." }
        if aggregation == .latest { return "Recorded \(date(lastSampleAt ?? end ?? start))." }
        let type = aggregation == .average ? "Average" : "Total"
        let window = "\(type) from \(date(start))" + (end.map { " through " + date($0) } ?? "") + "."
        return window + (lastSampleAt == nil ? " Latest sample time is unavailable." : "")
    }
}

public enum HealthMetricCatalog {
    public static let keys = ["sleep", "steps", "activeEnergy", "restingEnergy", "exercise", "stand", "restingHR", "hrv", "heartRate", "respiratoryRate", "spo2", "vo2max", "weight", "bodyFat", "bmi", "calories", "protein", "carbs", "fat", "water"]
    public static let labels = ["sleep": "Sleep", "steps": "Steps", "activeEnergy": "Active energy", "restingEnergy": "Resting energy", "exercise": "Exercise", "stand": "Stand or roll hours", "restingHR": "Resting heart rate", "hrv": "Heart rate variability", "heartRate": "Heart rate", "respiratoryRate": "Breathing rate", "spo2": "Oxygen saturation", "vo2max": "VO₂ max", "weight": "Weight", "bodyFat": "Body fat", "bmi": "Body mass index", "calories": "Food energy", "protein": "Protein", "carbs": "Carbohydrates", "fat": "Fat", "water": "Water"]
    public static let units = ["sleep": "h", "steps": "steps", "activeEnergy": "kcal", "restingEnergy": "kcal", "exercise": "min", "stand": "hours", "restingHR": "bpm", "hrv": "ms", "heartRate": "bpm", "respiratoryRate": "breaths/min", "spo2": "%", "vo2max": "ml/kg/min", "weight": "kg", "bodyFat": "%", "bmi": "", "calories": "kcal", "protein": "g", "carbs": "g", "fat": "g", "water": "ml"]
    public static func display(_ value: Double?, key: String) -> String {
        guard let value, value.isFinite else { return "Not recorded" }
        return number(value) + (units[key].map { $0.isEmpty ? "" : " " + $0 } ?? "")
    }
    public static func number(_ value: Double) -> String {
        if value > 0 && value < 0.01 { return "<0.01" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

extension DayMetrics {
    public func reading(_ key: String) -> HealthMetricReading { readings?[key] ?? .unknown }

    public mutating func setReading(_ reading: HealthMetricReading, for key: String) {
        var value = reading.value
        if key == "stand", let v = value, v.rounded() >= Double(Int.max) { value = nil }
        if key == "sleep", let v = value, v > Double(Int.max / 2) / 3600 { value = nil }
        if readings == nil { readings = [:] }
        readings?[key] = value == nil && reading.value != nil ? .unknown : reading
        if Self.cumulativeKeys.contains(key) {
            var known = recordedTotalKeys ?? Set(Self.cumulativeKeys.filter { recordedTotal($0) != nil })
            if value != nil { known.insert(key) } else { known.remove(key) }
            recordedTotalKeys = known
        }
        switch key {
        case "steps": steps = value ?? 0
        case "activeEnergy": activeCalories = value ?? 0
        case "restingEnergy": restingCalories = value ?? 0
        case "exercise": exerciseMin = value ?? 0
        case "stand": standHours = Int((value ?? 0).rounded())
        case "water": waterML = value ?? 0
        case "sleep": sleepSeconds = value.map { $0 * 3600 }
        case "restingHR": restingHR = value
        case "hrv": hrvMS = value
        case "heartRate": avgHR = value
        case "respiratoryRate": respiratoryRate = value
        case "spo2": spo2 = value
        case "vo2max": vo2max = value
        case "weight": weightKg = value
        case "calories": dietaryCalories = value
        case "protein": dietaryProtein = value
        case "carbs": dietaryCarbs = value
        case "fat": dietaryFat = value
        default: break
        }
    }
}
