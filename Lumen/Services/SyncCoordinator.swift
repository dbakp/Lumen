import Foundation

// One serialized drain owns foreground refreshes and Health observer callbacks.
// A callback arriving during a refresh requests another pass before it completes.
@MainActor
public enum SyncCoordinator {
    private static let queue = HealthSyncQueue()

    public static func syncEverything(sleep: SleepStore, health: HealthStore, background: Bool = false) async {
        await queue.run(includeProviders: !background) { providers in
            health.isSyncing = true
            defer { health.isSyncing = false }
            sleep.resetHabitsIfNewDay()
            let hk = HealthKitService.shared
            if hk.isAuthorized {
                HealthBackgroundSync.shared.start()
                if providers { HealthBackgroundSync.shared.retryRegistration() }
                do { try await HealthBackgroundSync.shared.synchronize(sleep: sleep, health: health, deadline: providers ? nil : Date().addingTimeInterval(20)) }
                catch { HealthBackgroundSync.shared.report(error) }
            }
            sleep.recompute()
            await health.refreshSources(includeProviders: providers)
            propagate(sleep: sleep, health: health)
            if providers { await NotificationManager.shared.refreshAuthorization() }
            NotificationManager.shared.reschedule(from: sleep)
        }
    }

    public static func propagate(sleep: SleepStore, health: HealthStore) {
        health.recompute(sleepDebt: sleep.debt, sleepNeed: sleep.profile.sleepNeed, sleepEpisodes: sleep.episodes)
    }
}
