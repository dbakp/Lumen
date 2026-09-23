import Foundation
import WatchConnectivity

// MARK: - iPhone ⇄ Apple Watch
// The phone owns the brain (readiness, sleep debt, circadian plan); the Watch gets a
// compact snapshot via application context and sends back ritual check-offs and water.

@MainActor
public final class WatchSync: NSObject, ObservableObject {
    public static let shared = WatchSync()
    @Published public private(set) var isPaired = false
    @Published public private(set) var isWatchAppInstalled = false

    private weak var sleep: SleepStore?
    private weak var health: HealthStore?
    private var pending: Task<Void, Never>?
    private var lastSent: WatchSnapshot?

    public func activate(sleep: SleepStore, health: HealthStore) {
        self.sleep = sleep
        self.health = health
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Coalesce bursts of store changes into one send.
    public func scheduleSend() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.sendNow()
        }
    }

    func sendNow() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              let snap = makeSnapshot() else { return }
        // Ignore generatedAt when deciding whether anything changed.
        var a = snap; a.generatedAt = .distantPast
        var b = lastSent; b?.generatedAt = .distantPast
        guard a != b, let data = snap.encoded() else { return }
        do {
            try WCSession.default.updateApplicationContext([WatchSnapshot.contextKey: data])
            lastSent = snap
        } catch { /* watch unreachable; next change retries */ }
    }

    func makeSnapshot() -> WatchSnapshot? {
        guard let sleep, let health, sleep.profile.onboardingDone else { return nil }
        var s = WatchSnapshot()
        s.name = sleep.profile.name
        if let r = health.readiness {
            s.readiness = r.score
            s.readinessHeadline = r.headline
            s.strainLow = r.strainTarget.lowerBound
            s.strainHigh = r.strainTarget.upperBound
        }
        s.briefing = health.isCalibrating ? nil : health.plan?.briefing
        if let last = sleep.lastNight {
            s.hasSleep = true
            s.lastSleepSeconds = last.duration
            s.lastBedtime = last.bedtime
            s.lastWake = last.wakeTime
            s.deepSeconds = last.deepSeconds
            s.remSeconds = last.remSeconds
            s.coreSeconds = last.coreSeconds
            s.awakeSeconds = last.awakeSeconds
        }
        s.debtHours = sleep.debt / 3600
        s.sleepNeedSeconds = sleep.profile.sleepNeed
        s.energyPotential = sleep.energyPotential
        s.bedtime = sleep.suggestedBedtime
        if let p = sleep.prediction {
            s.windDown = p.windDown
            s.melatoninStart = p.melatoninWindow.lowerBound
            s.melatoninEnd = p.melatoninWindow.upperBound
            s.caffeineCutoff = p.caffeineCutoff
            s.energyCurve = (0..<24).map { h in
                let t = Double(h) * 3600
                let nearest = p.curve.min { abs($0.time - t) < abs($1.time - t) }
                return (nearest?.energy ?? 0) * 100
            }
        }
        s.caloriesEaten = Int(health.caloriesEaten)
        s.calorieTarget = health.goals.calorieTarget()
        s.protein = Int(health.proteinEaten)
        s.proteinTarget = health.goals.proteinTarget()
        s.waterML = Int(health.waterTodayML)
        s.waterTargetML = health.plan?.waterTargetML ?? 2500
        s.moveGoal = health.goals.activeCalGoal
        s.exerciseGoal = health.goals.exerciseGoalMin
        s.standGoal = health.goals.standGoal
        s.stepGoal = health.goals.stepGoal
        s.rituals = sleep.habits.filter(\.isEnabled).map { h in
            WatchSnapshot.Ritual(id: h.id, title: h.title, icon: h.icon, time: ritualTime(h, sleep), done: h.doneToday)
        }.sorted { ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture) }
        return s
    }

    private func ritualTime(_ h: SleepHabit, _ sleep: SleepStore) -> Date? {
        guard let pred = sleep.prediction else { return nil }
        switch h.anchor {
        case .wakePlus, .fixedClock: return pred.wakeZone.lowerBound.addingTimeInterval(h.offset)
        case .bedtimeMinus: return sleep.suggestedBedtime.addingTimeInterval(-h.offset)
        }
    }

    fileprivate func handle(_ info: [String: Any]) {
        guard let sleep, let health else { return }
        if let id = info[WatchMessage.toggleRitual] as? String {
            sleep.toggleHabitDone(id)
            scheduleSend()
        }
        if let ml = info[WatchMessage.loggedWater] as? Double {
            if HealthKitService.shared.isAuthorized {
                // Already written to Health by the Watch — just re-read it.
                Task { await health.syncAll() }
            } else {
                health.addWater(ml: ml)
            }
        }
        if info[WatchMessage.requestSnapshot] != nil {
            lastSent = nil
            scheduleSend()
        }
    }

    fileprivate func updateState() {
        isPaired = WCSession.default.isPaired
        isWatchAppInstalled = WCSession.default.isWatchAppInstalled
        if isWatchAppInstalled { lastSent = nil; scheduleSend() }
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.updateState() }
    }
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.updateState() }
    }
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let info = userInfo
        Task { @MainActor in self.handle(info) }
    }
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let info = message
        Task { @MainActor in self.handle(info) }
    }
}
