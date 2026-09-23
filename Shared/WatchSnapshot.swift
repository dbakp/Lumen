import Foundation

// MARK: - What the iPhone sends the Watch (WatchConnectivity application context).
// Compiled into the iPhone app, the Watch app and the Watch complications.

public struct WatchSnapshot: Codable, Equatable, Sendable {
    public struct Ritual: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var icon: String
        public var time: Date?
        public var done: Bool
        public init(id: String, title: String, icon: String, time: Date?, done: Bool) {
            self.id = id; self.title = title; self.icon = icon; self.time = time; self.done = done
        }
    }

    public var generatedAt = Date()
    public var name = ""
    // Readiness
    public var readiness: Int?
    public var readinessHeadline: String?
    public var briefing: String?
    public var strainLow: Int?
    public var strainHigh: Int?
    // Sleep
    public var hasSleep = false
    public var lastSleepSeconds: Double?
    public var lastBedtime: Date?
    public var lastWake: Date?
    public var deepSeconds: Double?
    public var remSeconds: Double?
    public var coreSeconds: Double?
    public var awakeSeconds: Double?
    public var debtHours: Double = 0
    public var sleepNeedSeconds: Double = 8 * 3600
    public var energyPotential: Int = 0
    public var bedtime: Date?
    public var windDown: Date?
    public var melatoninStart: Date?
    public var melatoninEnd: Date?
    public var caffeineCutoff: Date?
    /// Energy 0–100 sampled hourly from midnight (24 values).
    public var energyCurve: [Double] = []
    // Fuel + goals
    public var caloriesEaten = 0
    public var calorieTarget = 2000
    public var protein = 0
    public var proteinTarget = 120
    public var waterML = 0
    public var waterTargetML = 2500
    public var moveGoal: Double = 500
    public var exerciseGoal: Double = 30
    public var standGoal = 12
    public var stepGoal: Double = 10000
    public var rituals: [Ritual] = []

    public init() {}

    public static let contextKey = "snapshot"
    public static let storeKey = "watch.snapshot"

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data?) -> WatchSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    public static let preview: WatchSnapshot = {
        var s = WatchSnapshot()
        s.name = "Alex"; s.readiness = 82; s.readinessHeadline = "Ready — a strong, full day."
        s.briefing = "A strong day. Spend energy early, coast intelligently in the evening."
        s.strainLow = 450; s.strainHigh = 750
        s.hasSleep = true; s.lastSleepSeconds = 7.6 * 3600
        s.deepSeconds = 1.1 * 3600; s.remSeconds = 1.7 * 3600; s.coreSeconds = 4.8 * 3600; s.awakeSeconds = 0.3 * 3600
        s.debtHours = 2.1; s.energyPotential = 84
        s.bedtime = Calendar.current.date(bySettingHour: 22, minute: 40, second: 0, of: Date())
        s.windDown = Calendar.current.date(bySettingHour: 21, minute: 40, second: 0, of: Date())
        s.melatoninStart = Calendar.current.date(bySettingHour: 21, minute: 10, second: 0, of: Date())
        s.melatoninEnd = Calendar.current.date(bySettingHour: 22, minute: 10, second: 0, of: Date())
        s.caffeineCutoff = Calendar.current.date(bySettingHour: 13, minute: 40, second: 0, of: Date())
        s.energyCurve = (0..<24).map { h in max(5, 60 + 35 * sin(Double(h - 8) / 24 * 2 * .pi)) }
        s.caloriesEaten = 1320; s.calorieTarget = 2400; s.protein = 88; s.proteinTarget = 140; s.waterML = 1250
        s.rituals = [.init(id: "light", title: "Get bright light", icon: "sun.max.fill", time: nil, done: true),
                     .init(id: "caffeine", title: "Caffeine cutoff", icon: "cup.and.saucer.fill", time: nil, done: false),
                     .init(id: "winddown", title: "Wind down", icon: "wind", time: nil, done: false)]
        return s
    }()
}

/// Messages the Watch sends back to the iPhone (transferUserInfo).
public enum WatchMessage {
    public static let toggleRitual = "toggleRitual"   // value: ritual id
    public static let loggedWater = "loggedWater"     // value: ml (already saved to Health on the Watch)
    public static let requestSnapshot = "requestSnapshot"
}
