import Foundation

public enum HealthSource: String, Codable, Sendable, CaseIterable {
    case healthKit, strava, manual, sample
    public var label: String {
        switch self { case .healthKit: return "Health"; case .strava: return "Strava"; case .manual: return "Manual"; case .sample: return "Demo" }
    }
}

public enum WorkoutKind: String, Codable, Sendable, CaseIterable {
    case run, ride, swim, walk, hike, strength, hiit, yoga, row, other
    public var label: String { rawValue.capitalized }
    public var icon: String {
        switch self {
        case .run: return "figure.run"; case .ride: return "bicycle"; case .swim: return "figure.pool.swim"
        case .walk: return "figure.walk"; case .hike: return "figure.hiking"; case .strength: return "dumbbell.fill"
        case .hiit: return "flame.fill"; case .yoga: return "figure.mind.and.body"; case .row: return "figure.rower"; case .other: return "figure.mixed.cardio"
        }
    }
    public var met: Double {
        switch self {
        case .run: return 9.5; case .ride: return 7.5; case .swim: return 8.0; case .walk: return 3.5; case .hike: return 6.0
        case .strength: return 5.0; case .hiit: return 9.0; case .yoga: return 3.0; case .row: return 7.0; case .other: return 5.0
        }
    }
}

public struct Workout: Identifiable, Codable, Sendable {
    public var id: String
    public var kind: WorkoutKind
    public var title: String
    public var start: Date
    public var duration: TimeInterval
    public var activeCalories: Double
    public var distanceM: Double?
    public var avgHR: Double?
    public var source: HealthSource
    public var stravaID: Int64?
    public var polyline: String?
    public init(id: String = UUID().uuidString, kind: WorkoutKind, title: String, start: Date, duration: TimeInterval, activeCalories: Double, distanceM: Double? = nil, avgHR: Double? = nil, source: HealthSource, stravaID: Int64? = nil, polyline: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.start = start
        self.duration = duration; self.activeCalories = activeCalories
        self.distanceM = distanceM; self.avgHR = avgHR; self.source = source
        self.stravaID = stravaID; self.polyline = polyline
    }
    public func overlaps(_ other: Workout) -> Bool {
        abs(start.timeIntervalSince(other.start)) < 10 * 60
    }
}

public struct DayMetrics: Codable, Sendable {
    public var date: Date
    public var steps: Double
    public var activeCalories: Double
    public var restingCalories: Double
    public var exerciseMin: Double
    public var standHours: Int
    public var avgHR: Double?
    public var restingHR: Double?
    public var hrvMS: Double?
    public var respiratoryRate: Double?
    public var spo2: Double?
    public var vo2max: Double?
    public var weightKg: Double?
    public var sleepSeconds: Double?
    public var waterML: Double
    public static var empty: DayMetrics {
        DayMetrics(date: Calendar.current.startOfDay(for: Date()), steps: 0, activeCalories: 0, restingCalories: 0, exerciseMin: 0, standHours: 0, waterML: 0)
    }
}

public struct Readiness: Sendable {
    public var score: Int
    public var factors: [ReadinessFactor]
    public var headline: String
    public var strainTarget: ClosedRange<Int>
    public struct ReadinessFactor: Sendable, Identifiable {
        public var id: String; public var label: String; public var delta: Int; public var detail: String
    }
}

public struct DayPlan: Sendable {
    public var briefing: String
    public var bullets: [String]
    public var calorieTarget: Int
    public var proteinTargetG: Int
    public var waterTargetML: Int
    public var caffeineCutoff: Date?
    public var workoutSuggestion: String
    public var bedtimeTonight: Date?
}

public struct HealthGoals: Codable, Sendable {
    public var stepGoal: Double = 10_000
    public var activeCalGoal: Double = 600
    public var exerciseGoalMin: Double = 30
    public var standGoal: Int = 12
    public var weightKg: Double? = 75
    public var heightCm: Double? = 178
    public var age: Int? = 30
    public var sex: Sex = .unspecified
    public var activityLevel: ActivityLevel = .moderate
    public var goal: BodyGoal = .maintain
    public enum Sex: String, Codable, Sendable { case female, male, unspecified }
    public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
        case sedentary, light, moderate, active, athlete
        public var label: String { rawValue.capitalized }
        public var multiplier: Double {
            switch self { case .sedentary: return 1.2; case .light: return 1.375; case .moderate: return 1.55; case .active: return 1.725; case .athlete: return 1.9 }
        }
    }
    public enum BodyGoal: String, Codable, Sendable, CaseIterable {
        case lose, maintain, gain
        public var label: String { self == .lose ? "Lose fat" : self == .maintain ? "Maintain" : "Build" }
        public var calAdjust: Double { self == .lose ? -450 : self == .gain ? 300 : 0 }
    }
    public func bmr() -> Double {
        let w = weightKg ?? 75, h = heightCm ?? 178, a = Double(age ?? 30)
        switch sex {
        case .male: return 10*w + 6.25*h - 5*a + 5
        case .female: return 10*w + 6.25*h - 5*a - 161
        case .unspecified: return 10*w + 6.25*h - 5*a - 78
        }
    }
    public func tdee() -> Double { bmr() * activityLevel.multiplier }
    public func calorieTarget() -> Int { Int((tdee() + goal.calAdjust).rounded()) }
    public func proteinTarget() -> Int {
        let w = weightKg ?? 75
        let perKg = goal == .lose ? 2.0 : goal == .gain ? 1.8 : 1.6
        return Int((w * perKg).rounded())
    }
}
