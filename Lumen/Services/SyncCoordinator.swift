import Foundation

// MARK: - One place that keeps every store in step.
// Runs on launch, on every return to foreground, and on pull-to-refresh.

@MainActor
public enum SyncCoordinator {
    public static func syncEverything(sleep: SleepStore, health: HealthStore) async {
        sleep.resetHabitsIfNewDay()
        let hk = HealthKitService.shared
        if hk.isAuthorized {
            sleep.mergeHealthSleep(await hk.fetchSleep(days: 60))
        }
        await health.syncAll()
        propagate(sleep: sleep, health: health)
        await NotificationManager.shared.refreshAuthorization()
        NotificationManager.shared.reschedule(from: sleep)
    }

    /// Push sleep-derived numbers into the coaching side.
    public static func propagate(sleep: SleepStore, health: HealthStore) {
        health.recompute(sleepDebt: sleep.debt, sleepNeed: sleep.profile.sleepNeed, lastSleepSeconds: sleep.lastNight?.duration)
    }
}
