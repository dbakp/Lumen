import Foundation
import SwiftUI

// MARK: - Central observable store (persisted, sample-seeded)

@MainActor
public final class SleepStore: ObservableObject {
    @Published public var profile: UserProfile
    @Published public var episodes: [SleepEpisode] // oldest → newest
    @Published public var habits: [SleepHabit]

    @Published public var debt: TimeInterval = 0
    @Published public var energyPotential: Int = 80
    @Published public var prediction: CircadianPrediction?
    @Published public var suggestedBedtime: Date = Date()
    @Published public var bedtimeNote: String = ""

    private let profileKey = "lumen.profile.v1"
    private let episodesKey = "lumen.episodes.v1"
    private let habitsKey = "lumen.habits.v1"

    public init() {
        // Load or seed (locals first: self isn't fully initialized until all properties are set).
        let loadedProfile: UserProfile
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
            loadedProfile = p
        } else {
            loadedProfile = .default
        }
        profile = loadedProfile
        if let data = UserDefaults.standard.data(forKey: episodesKey),
           let e = try? JSONDecoder().decode([SleepEpisode].self, from: data),
           !e.isEmpty {
            episodes = e.sorted { $0.bedtime < $1.bedtime }
        } else {
            episodes = Self.sampleEpisodes(need: loadedProfile.sleepNeed)
        }
        if let data = UserDefaults.standard.data(forKey: habitsKey),
           let h = try? JSONDecoder().decode([SleepHabit].self, from: data) {
            habits = h
        } else {
            habits = SleepHabit.defaults()
        }
        recompute()
    }

    // MARK: derived

    public var lastNight: SleepEpisode? { episodes.last }
    public var lastDuration: TimeInterval { lastNight?.duration ?? profile.sleepNeed }
    public var avg7: TimeInterval {
        let arr = episodes.suffix(7).map(\.duration)
        guard !arr.isEmpty else { return 0 }
        return arr.reduce(0, +) / Double(arr.count)
    }
    public var consistency: TimeInterval {
        // SD of wake times last 7d (lower = better).
        let wakes = episodes.suffix(7).map { CircadianModel.secondsSinceMidnight($0.wakeTime, calendar: .current) }
        guard wakes.count > 1 else { return 0 }
        let mean = wakes.reduce(0, +) / Double(wakes.count)
        let v = wakes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(wakes.count - 1)
        return sqrt(v)
    }

    public var wakeGoalToday: Date {
        let cal = Calendar.current
        let now = Date()
        let comps = profile.wakeGoal
        let today = cal.date(bySettingHour: comps.hour ?? 7, minute: comps.minute ?? 0, second: 0, of: now) ?? now
        return today
    }

    /// Tomorrow's wake goal (for tonight's bedtime planning).
    public var wakeGoalTomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: wakeGoalToday) ?? wakeGoalToday
    }

    public func recompute(now: Date = Date()) {
        let durations = episodes.map(\.duration)
        debt = SleepDebtCalculator.debt(sleepNeed: profile.sleepNeed, recentDurationsOldestFirst: durations)
        energyPotential = CircadianModel.energyPotential(debt: debt)
        // Use today's actual wake if last episode is today, else goal.
        let todayWake: Date
        if let last = lastNight, Calendar.current.isDateInToday(last.wakeTime) {
            todayWake = last.wakeTime
        } else {
            todayWake = wakeGoalToday
        }
        prediction = CircadianModel.predict(
            recentEpisodes: episodes,
            todayWake: todayWake,
            sleepDebt: debt,
            chronotype: profile.chronotype
        )
        if prediction != nil {
            let hb: Date = {
                // Circular-mean bedtime as a date tonight.
                let secs = CircadianModel.circularMean(episodes.suffix(7).map { CircadianModel.secondsSinceMidnight($0.bedtime, calendar: .current) }) ?? (23*3600)
                let sod = Calendar.current.startOfDay(for: now)
                return sod.addingTimeInterval(secs)
            }()
            let plan = CircadianModel.suggestedBedtime(
                wakeGoal: wakeGoalTomorrow,
                sleepNeed: profile.sleepNeed,
                sleepDebt: debt,
                habitualBedtime: hb
            )
            suggestedBedtime = plan.bedtime
            bedtimeNote = plan.note
        }
        persist()
    }

    // MARK: mutations

    public func logEpisode(bedtime: Date, wakeTime: Date, source: SleepSource = .manual, quality: Int? = nil) {
        let ep = SleepEpisode(bedtime: bedtime, wakeTime: wakeTime, source: source, quality: quality)
        episodes.append(ep)
        episodes.sort { $0.bedtime < $1.bedtime }
        // Keep 400 max.
        if episodes.count > 400 { episodes.removeFirst(episodes.count - 400) }
        reestimateNeed()
        recompute()
    }

    public func deleteEpisode(_ ep: SleepEpisode) {
        episodes.removeAll { $0.id == ep.id }
        recompute()
    }

    public func updateEpisode(_ ep: SleepEpisode) {
        if let i = episodes.firstIndex(where: { $0.id == ep.id }) {
            episodes[i] = ep
            episodes.sort { $0.bedtime < $1.bedtime }
            recompute()
        }
    }

    public func reestimateNeed() {
        let (need, conf) = SleepNeedEstimator.estimate(episodes: episodes, age: profile.age, chronotype: profile.chronotype)
        // Blend slowly to avoid jumps: 70% old + 30% new after onboarding.
        if profile.onboardingDone {
            profile.sleepNeed = profile.sleepNeed * 0.7 + need * 0.3
            profile.sleepNeedConfidence = conf
        } else {
            profile.sleepNeed = need
            profile.sleepNeedConfidence = conf
        }
    }

    public func toggleHabitDone(_ id: String) {
        if let i = habits.firstIndex(where: { $0.id == id }) {
            habits[i].doneToday.toggle()
            persist()
        }
    }

    public func setHabitEnabled(_ id: String, enabled: Bool) {
        if let i = habits.firstIndex(where: { $0.id == id }) {
            habits[i].isEnabled = enabled
            persist()
        }
    }

    public func completeOnboarding(need: TimeInterval, chronotype: Chronotype, wakeHour: Int, wakeMinute: Int, name: String) {
        profile.sleepNeed = need
        profile.chronotype = chronotype
        profile.wakeGoal.hour = wakeHour
        profile.wakeGoal.minute = wakeMinute
        profile.name = name.isEmpty ? "Sleeper" : name
        profile.onboardingDone = true
        // Re-seed sample episodes around chosen schedule so day-one looks personal.
        episodes = Self.sampleEpisodes(need: need, wakeHour: wakeHour, wakeMinute: wakeMinute)
        recompute()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(d, forKey: profileKey) }
        if let d = try? JSONEncoder().encode(episodes) { UserDefaults.standard.set(d, forKey: episodesKey) }
        if let d = try? JSONEncoder().encode(habits) { UserDefaults.standard.set(d, forKey: habitsKey) }
        // Widget snapshot (shared defaults in production via App Group).
        UserDefaults.standard.set(debt / 3600, forKey: "lumen.widget.debt")
        UserDefaults.standard.set(energyPotential, forKey: "lumen.widget.energy")
        UserDefaults.standard.set(suggestedBedtime, forKey: "lumen.widget.bedtime")
    }

    // MARK: sample data (so first-run + previews feel alive)

    static func sampleEpisodes(need: TimeInterval = 8*3600+10*60, wakeHour: Int = 7, wakeMinute: Int = 0) -> [SleepEpisode] {
        var out: [SleepEpisode] = []
        let cal = Calendar.current
        let now = Date()
        // Deterministic-ish pseudo-random for stable previews.
        var seed: UInt64 = 42
        func rand(_ lo: Double, _ hi: Double) -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let u = Double(seed >> 33) / Double(UInt64.max >> 33)
            return lo + u * (hi - lo)
        }
        for dayAgo in stride(from: 21, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -dayAgo, to: now) else { continue }
            let isWeekend: Bool = {
                let wd = cal.component(.weekday, from: day)
                return wd == 1 || wd == 7
            }()
            // Owlish drift on weekends.
            let wakeShift = (isWeekend ? rand(20, 70) : rand(-25, 25)) * 60
            var wakeComps = cal.dateComponents([.year, .month, .day], from: day)
            wakeComps.hour = wakeHour; wakeComps.minute = wakeMinute
            let wake = (cal.date(from: wakeComps) ?? day).addingTimeInterval(wakeShift)
            // Duration: need minus typical shortfall (0–90m), weekends catch up.
            let shortfall = isWeekend ? rand(-60, 30) * 60 : rand(-20, 95) * 60
            let dur = max(4*3600, need - shortfall + rand(-15, 15)*60)
            let bed = wake.addingTimeInterval(-dur - rand(5, 35)*60) // + latency
            out.append(SleepEpisode(bedtime: bed, wakeTime: wake, source: dayAgo % 4 == 0 ? .wearable : .phone, quality: Int(rand(2, 5).rounded())))
        }
        return out.sorted { $0.bedtime < $1.bedtime }
    }
}
