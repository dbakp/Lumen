import SwiftUI

@main
struct LumenApp: App {
    @StateObject private var sleep = SleepStore()
    @StateObject private var health = HealthStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(sleep)
                .environmentObject(health)
                .preferredColorScheme(.dark)
                .task {
                    // First sync: HealthKit status is asked from Integrations (no surprise prompt).
                    // Recompute coaching once both stores are live.
                    health.recompute(sleepDebt: sleep.debt, sleepNeed: sleep.profile.sleepNeed, lastSleepSeconds: sleep.lastDuration)
                }
                .onChange(of: sleep.debt) { _, debt in
                    health.recompute(sleepDebt: debt, sleepNeed: sleep.profile.sleepNeed, lastSleepSeconds: sleep.lastDuration)
                }
        }
    }
}
