import Foundation

// MARK: - Core models (Rise parity)

public enum SleepSource: String, Codable, Sendable, CaseIterable {
    case phone, wearable, manual
    public var label: String {
        switch self { case .phone: return "Phone"; case .wearable: return "Watch"; case .manual: return "Manual" }
    }
}

public enum Chronotype: String, Codable, Sendable, CaseIterable {
    case morning, intermediate, evening
    public var label: String {
        switch self { case .morning: return "Morning Lark"; case .intermediate: return "Balanced"; case .evening: return "Night Owl" }
    }
    public var description: String {
        switch self {
        case .morning: return "You peak early and melatonin arrives sooner."
        case .intermediate: return "You sit in the flexible middle."
        case .evening: return "Your clock runs late — peaks and melatonin shift later."
        }
    }
}

public struct SleepEpisode: Identifiable, Codable, Sendable {
    public var id: UUID
    public var bedtime: Date
    public var wakeTime: Date
    public var source: SleepSource
    public var quality: Int? // 1...5
    public var note: String?

    public init(id: UUID = UUID(), bedtime: Date, wakeTime: Date, source: SleepSource = .phone, quality: Int? = nil, note: String? = nil) {
        self.id = id
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.source = source
        self.quality = quality
        self.note = note
    }

    public var duration: TimeInterval {
        max(0, wakeTime.timeIntervalSince(bedtime))
    }

    public var midSleep: Date {
        bedtime.addingTimeInterval(duration / 2)
    }
}

public struct UserProfile: Codable, Sendable {
    public var sleepNeed: TimeInterval // seconds
    public var sleepNeedConfidence: Double
    public var chronotype: Chronotype
    public var wakeGoal: DateComponents // hour/minute
    public var birthYear: Int?
    public var name: String
    public var onboardingDone: Bool
    public var isSubscribed: Bool

    public static var `default`: UserProfile {
        var wc = DateComponents(); wc.hour = 7; wc.minute = 0
        return UserProfile(
            sleepNeed: 8 * 3600 + 10 * 60,
            sleepNeedConfidence: 0.3,
            chronotype: .intermediate,
            wakeGoal: wc,
            birthYear: nil,
            name: "Sleeper",
            onboardingDone: false,
            isSubscribed: false
        )
    }

    public var age: Int? {
        guard let y = birthYear else { return nil }
        return Calendar.current.component(.year, from: Date()) - y
    }
}

// MARK: - Habits (16 science-based, Rise parity)

public struct SleepHabit: Identifiable, Codable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var icon: String // SF Symbol
    public var anchor: HabitAnchor
    public var isEnabled: Bool
    public var doneToday: Bool

    public enum HabitAnchor: String, Codable, Sendable {
        case wakePlus, bedtimeMinus, fixedClock
    }

    /// Offset in seconds relative to anchor (wake+ or bedtime−), or time-of-day for fixed.
    public var offset: TimeInterval
}

public extension SleepHabit {
    static func defaults() -> [SleepHabit] {
        [
            .init(id: "light", title: "Get bright light", detail: "10 min of daylight within 30 min of waking anchors your clock.", icon: "sun.max.fill", anchor: .wakePlus, isEnabled: true, doneToday: false, offset: 30*60),
            .init(id: "caffeine", title: "Caffeine cutoff", detail: "No caffeine within 10h of bed — half-life is ~6h.", icon: "cup.and.saucer.fill", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 10*3600),
            .init(id: "exercise", title: "Move your body", detail: "20+ min. Finish intense workouts 3h+ before bed.", icon: "figure.run", anchor: .wakePlus, isEnabled: true, doneToday: false, offset: 6*3600),
            .init(id: "nap", title: "Smart nap window", detail: "If napping: 20–30 min, before your dip ends. No late naps.", icon: "moon.zzz.fill", anchor: .wakePlus, isEnabled: true, doneToday: false, offset: 7*3600),
            .init(id: "alcohol", title: "Skip nightcap", detail: "Alcohol fragments sleep even when it speeds onset.", icon: "wineglass", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 4*3600),
            .init(id: "meal", title: "Last big meal", detail: "Finish large meals 3h before bed; light snack OK.", icon: "fork.knife", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 3*3600),
            .init(id: "screens", title: "Dim screens", detail: "Lower brightness + Night Shift 2h before bed.", icon: "iphone.gen2", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 2*3600),
            .init(id: "lights", title: "Dim the lights", detail: "Overhead off, lamps low — light delays melatonin.", icon: "lightbulb.fill", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 90*60),
            .init(id: "winddown", title: "Wind down", detail: "20–30 min ritual: shower, stretch, read, breathe.", icon: "wind", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 45*60),
            .init(id: "bedtime", title: "In bed on time", detail: "Hit your melatonin window — the easiest falling-asleep.", icon: "bed.double.fill", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 0),
            .init(id: "cool", title: "Cool & dark room", detail: "65–68°F / 18–20°C, blackout dark, quiet.", icon: "thermometer.snowflake", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 30*60),
            .init(id: "consistent", title: "Consistent wake", detail: "Same wake ±30 min — even weekends. #1 rhythm lever.", icon: "alarm.fill", anchor: .wakePlus, isEnabled: true, doneToday: false, offset: 0),
            .init(id: "hydration", title: "Morning hydration", detail: "Water + light before coffee boosts alertness.", icon: "drop.fill", anchor: .wakePlus, isEnabled: true, doneToday: false, offset: 5*60),
            .init(id: "stress", title: "Brain dump", detail: "2-min worry list after dinner clears night rumination.", icon: "pencil.and.list.clipboard", anchor: .bedtimeMinus, isEnabled: true, doneToday: false, offset: 5*3600),
            .init(id: "nicotine", title: "No late nicotine", detail: "Stimulant — avoid within 4h of bed.", icon: "smoke.fill", anchor: .bedtimeMinus, isEnabled: false, doneToday: false, offset: 4*3600),
            .init(id: "sunset", title: "Evening light walk", detail: "A dusk walk sharpens DLMO timing.", icon: "sunset.fill", anchor: .bedtimeMinus, isEnabled: false, doneToday: false, offset: 4*3600),
        ]
    }
}

// MARK: - Sounds & Learn

public struct SoundTrack: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var icon: String
    public var gradient: [String]
    public var kind: SoundKind

    public enum SoundKind: Sendable, Hashable {
        case whiteNoise, pinkNoise, brownNoise, rain, ocean, fan, forest, fireplace
    }

    public static var all: [SoundTrack] = [
        .init(id: "rain", title: "Soft Rain", subtitle: "Steady patter for onset", icon: "cloud.rain.fill", gradient: ["#1e3a5f", "#0b1526"], kind: .rain),
        .init(id: "ocean", title: "Ocean Swell", subtitle: "Slow waves, slow breath", icon: "water.waves", gradient: ["#0b3b4f", "#071522"], kind: .ocean),
        .init(id: "white", title: "White Noise", subtitle: "Masks disturbances", icon: "waveform", gradient: ["#3a3a44", "#141419"], kind: .whiteNoise),
        .init(id: "brown", title: "Brown Noise", subtitle: "Deep rumble calm", icon: "speaker.wave.2.fill", gradient: ["#4a2b1d", "#160d08"], kind: .brownNoise),
        .init(id: "fan", title: "Night Fan", subtitle: "Airy soft hum", icon: "fanblades.fill", gradient: ["#223344", "#0c141c"], kind: .fan),
        .init(id: "forest", title: "Forest Night", subtitle: "Crickets + air", icon: "tree.fill", gradient: ["#123524", "#070f0b"], kind: .forest),
        .init(id: "fire", title: "Fireplace", subtitle: "Warm crackle", icon: "flame.fill", gradient: ["#4d1f0e", "#140705"], kind: .fireplace),
        .init(id: "pink", title: "Pink Hush", subtitle: "Softer than white", icon: "moon.fill", gradient: ["#2b2350", "#0e0b1e"], kind: .pinkNoise),
    ]
}

public struct Article: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var minutes: Int
    public var tag: String
    public var body: String

    public static var all: [Article] = [
        .init(id: "debt", title: "Sleep debt: the only score that matters", minutes: 6, tag: "Foundations",
              body: "Sleep debt is the gap between what you need and what you got over the last 14 nights — recent nights weighted more. Keep it under 5 hours. Zero is lovely but chasing it anxiously backfires.\n\nPay it back 20–30 min at a time: slightly earlier bed, slightly later wake (≤1h), or a well-timed nap. Recovery is slower than loss — about 3–4 nights per lost hour."),
        .init(id: "need", title: "Your sleep need is personal", minutes: 4, tag: "Foundations",
              body: "Forget 8 hours for everyone. Across ~2M sleepers, needs range 5h–11.5h with a median near 8h. Half need 8h+. Your need is trait-like (genetic). Lumen estimates it from your history, not a goal you typed."),
        .init(id: "circadian", title: "Your circadian rhythm, decoded", minutes: 5, tag: "Energy",
              body: "Your clock predicts peaks, dips, and the melatonin window — the ~1h when falling asleep is easiest (about 2h before habitual bed). Light is the strongest lever: bright mornings advance owls, dim evenings protect onset."),
        .init(id: "caffeine", title: "Caffeine has a 6-hour half-life", minutes: 3, tag: "Habits",
              body: "A 2pm espresso is still quarter-strength at 2am. Cut caffeine 10h before bed. Morning coffee after light + water hits harder."),
        .init(id: "naps", title: "The perfect nap", minutes: 3, tag: "Habits",
              body: "20–30 min, in the early-afternoon dip, before your nap deadline. Long or late naps steal night pressure. After all-night loss, a 2h rescue nap helps — rarely needed."),
        .init(id: "inertia", title: "Why mornings feel groggy", minutes: 3, tag: "Energy",
              body: "Sleep inertia lasts 15–90 min — worse with debt, short nights, or waking in your melatonin window. Light, movement, and water shorten it. Don't judge your day by minute five."),
        .init(id: "consistency", title: "Consistency beats intensity", minutes: 4, tag: "Energy",
              body: "Low-debt sleepers keep wake times within ~30 min. One late weekend lie-in shifts Monday's clock. Protect wake time first; bedtime follows."),
        .init(id: "weekend", title: "Weekend catch-up: partial credit", minutes: 3, tag: "Recovery",
              body: "Extra weekend sleep chips at weekday debt but doesn't fully reset attention or metabolism. Keep lie-ins ≤1–2h and add a slightly earlier weeknight bed instead."),
    ]
}

// MARK: - Formatting helpers

public enum SleepFormat {
    public static func hours(_ interval: TimeInterval) -> String {
        let h = interval / 3600
        if h < 10 { return String(format: "%.1f h", h) }
        return String(format: "%.0f h", h)
    }
    public static func debtString(_ interval: TimeInterval) -> String {
        let h = interval / 3600
        return String(format: "%.1f hr", h)
    }
    public static func durationHM(_ interval: TimeInterval) -> String {
        let total = Int(interval / 60)
        return "\(total / 60)h \(total % 60)m"
    }
    public static func time(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
    public static func timeRange(_ r: ClosedRange<Date>) -> String {
        "\(time(r.lowerBound)) – \(time(r.upperBound))"
    }
}
