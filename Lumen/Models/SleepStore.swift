import Foundation
import SwiftUI

// MARK: - Sleep store: nights, need, debt, circadian plan (local-first)

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

    private let habitsDayKey = "lumen.habits.day"

    public init() {
        // Locals first: self isn't fully initialized until all properties are set.
        let loadedProfile = LocalStore.load(UserProfile.self, from: "profile", legacyKey: profileKey) ?? .default
        profile = loadedProfile
        // Real nights only. Legacy builds seeded fake nights (source .phone) — drop them.
        let loaded = LocalStore.load([SleepEpisode].self, from: "sleep", legacyKey: episodesKey) ?? []
        let migrated = LocalStore.load([SleepEpisode].self, from: "sleep") != nil
        episodes = (migrated ? loaded : loaded.filter { $0.source == .manual }).sorted { $0.bedtime < $1.bedtime }
        habits = LocalStore.load([SleepHabit].self, from: "habits", legacyKey: habitsKey) ?? SleepHabit.defaults()
        resetHabitsIfNewDay()
        recompute()
    }

    public var hasSleepData: Bool { !episodes.isEmpty }

    /// Ritual check-marks are per day.
    public func resetHabitsIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if UserDefaults.standard.double(forKey: habitsDayKey) != today {
            for i in habits.indices { habits[i].doneToday = false }
            UserDefaults.standard.set(today, forKey: habitsDayKey)
        }
    }

    /// Merge nights from Apple Health: Health wins for any night it measured,
    /// manual logs stay for nights Health doesn't know about.
    public func mergeHealthSleep(_ incoming: [SleepEpisode]) {
        guard !incoming.isEmpty else { return }
        var kept = episodes.filter { ep in
            !incoming.contains { abs($0.midSleep.timeIntervalSince(ep.midSleep)) < 5 * 3600 }
        }
        kept.append(contentsOf: incoming)
        episodes = kept.sorted { $0.bedtime < $1.bedtime }
        if episodes.count > 1200 { episodes.removeFirst(episodes.count - 1200) }
        reestimateNeed()
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
        if episodes.count > 1200 { episodes.removeFirst(episodes.count - 1200) }
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

    public func completeOnboarding(need: TimeInterval, chronotype: Chronotype, wakeHour: Int, wakeMinute: Int, name: String, birthYear: Int?, units: UnitSystem) {
        profile.sleepNeed = need
        profile.birthYear = birthYear
        profile.units = units
        profile.createdAt = profile.createdAt ?? Date()
        profile.chronotype = chronotype
        profile.wakeGoal.hour = wakeHour
        profile.wakeGoal.minute = wakeMinute
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.onboardingDone = true
        recompute()
    }

    public func persist() {
        LocalStore.save(profile, as: "profile")
        LocalStore.save(episodes, as: "sleep")
        LocalStore.save(habits, as: "habits")
        let d = AppGroup.defaults
        d.set(hasSleepData, forKey: "widget.hasSleep")
        d.set(debt / 3600, forKey: "widget.debt")
        d.set(energyPotential, forKey: "widget.energy")
        d.set(suggestedBedtime, forKey: "widget.bedtime")
        d.set(lastNight?.duration ?? 0, forKey: "widget.lastSleep")
        WidgetBridge.reload()
        WatchSync.shared.scheduleSend()
    }

    /// Start over: clears nights and returns to onboarding.
    public func resetAll() {
        profile = .default
        episodes = []
        habits = SleepHabit.defaults()
        recompute()
    }
}
