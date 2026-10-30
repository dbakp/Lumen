import Foundation
import SwiftUI

// MARK: - Sleep store: nights, need, debt, circadian plan (local-first)

@MainActor
public final class SleepStore: ObservableObject {
    public static let shared = SleepStore()
    @Published public var profile: UserProfile
    @Published public var episodes: [SleepEpisode] // oldest → newest
    @Published public var habits: [SleepHabit]

    @Published public var debt: TimeInterval = 0
    @Published public var energyPotential: Int = 80
    @Published public var prediction: CircadianPrediction?
    private var predictionDate: Date?
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
        reestimateNeed()
        recompute()
    }

    func installHealthEpisodes(_ values: [SleepEpisode]) {
        episodes = values; reestimateNeed(); recompute()
    }

    // MARK: derived

    public var lastNight: SleepEpisode? { SleepEvidence.latest(episodes) }
    public var currentNight: SleepEpisode? { SleepEvidence.today(episodes) }
    public var lastDuration: TimeInterval? { lastNight?.duration }
    public var recentEvidence: SleepEvidence.Recent { SleepEvidence.recent(episodes) }
    public var recordedDebt: TimeInterval? { CurrentHealthEvidence.estimatedSleepDebt(episodes, sleepNeed: profile.sleepNeed) }
    public var energyEstimate: Int? { recordedDebt.map { CircadianModel.energyPotential(debt: $0) } }
    public var avg7: TimeInterval { recentEvidence.meanDuration ?? 0 } // Legacy numeric API; UI uses optional evidence.
    public var consistency: TimeInterval { SleepEvidence.wakeSpread(episodes) ?? 0 }
    public var currentPrediction: CircadianPrediction? {
        guard let predictionDate, Calendar.current.isDateInToday(predictionDate), currentNight != nil else { return nil }
        return prediction
    }
    public var plannedBedtime: Date {
        currentPrediction == nil ? wakeGoalTomorrow.addingTimeInterval(-profile.sleepNeed - 15 * 60) : suggestedBedtime
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
        let coveredDebt = CurrentHealthEvidence.estimatedSleepDebt(episodes, sleepNeed: profile.sleepNeed, now: now)
        debt = coveredDebt ?? 0 // Retained compatibility field, never displayed without presence.
        energyPotential = coveredDebt.map { CircadianModel.energyPotential(debt: $0) } ?? 0
        let eligible = SleepEvidence.predictionEntries(episodes, now: now)
        predictionDate = now
        if let current = SleepEvidence.today(eligible, now: now), !eligible.isEmpty {
            prediction = CircadianModel.predict(recentEpisodes: eligible, todayWake: current.wakeTime, sleepDebt: coveredDebt, chronotype: profile.chronotype)
        } else { prediction = nil }
        suggestedBedtime = wakeGoalTomorrow.addingTimeInterval(-profile.sleepNeed - 15 * 60)
        bedtimeNote = "Based on your wake goal and profile sleep target. This is a plan, not a measured sleep need."
        if prediction != nil {
            let secs = CircadianModel.circularMean(eligible.suffix(7).map { CircadianModel.secondsSinceMidnight($0.bedtime, calendar: .current) }) ?? (23 * 3600)
            let habitual = Calendar.current.startOfDay(for: now).addingTimeInterval(secs)
            let plan = CircadianModel.suggestedBedtime(wakeGoal: wakeGoalTomorrow, sleepNeed: profile.sleepNeed, sleepDebt: coveredDebt, habitualBedtime: habitual)
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
        reestimateNeed()
        recompute()
    }

    public func deleteEpisode(_ ep: SleepEpisode) {
        guard ep.source == .manual else { return }
        episodes.removeAll { $0.id == ep.id && $0.source == .manual }
        recompute()
    }

    public func updateEpisode(_ ep: SleepEpisode) {
        guard ep.source == .manual, SleepEvidence.usable(ep) else { return }
        if let i = episodes.firstIndex(where: { $0.id == ep.id && $0.source == .manual }) {
            episodes[i] = ep
            episodes.sort { $0.bedtime < $1.bedtime }
            recompute()
        }
    }

    public func reestimateNeed() {
        let measured = SleepEvidence.needEstimationEntries(episodes)
        guard !measured.isEmpty else { return }
        let (need, conf) = SleepNeedEstimator.estimate(episodes: measured, age: profile.age, chronotype: profile.chronotype)
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
        d.set(currentNight != nil, forKey: "widget.hasSleep")
        d.set(debt / 3600, forKey: "widget.debt")
        d.set(energyPotential, forKey: "widget.energy")
        d.set(plannedBedtime, forKey: "widget.bedtime")
        d.set(currentNight?.duration ?? 0, forKey: "widget.lastSleep")
        WidgetBridge.reload()
        WatchSync.shared.scheduleSend()
    }

    func reloadAfterRestore() {
        profile = LocalStore.load(UserProfile.self, from: "profile") ?? profile
        episodes = LocalStore.load([SleepEpisode].self, from: "sleep") ?? episodes
        habits = LocalStore.load([SleepHabit].self, from: "habits") ?? habits
        recompute()
    }

    /// Start over: clears nights and returns to onboarding.
    public func resetAll() {
        profile = .default
        episodes = []
        habits = SleepHabit.defaults()
        recompute()
    }
}
