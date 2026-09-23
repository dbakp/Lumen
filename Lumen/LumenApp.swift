import SwiftUI

@main
struct LumenApp: App {
    @StateObject private var sleep = SleepStore()
    @StateObject private var health = HealthStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sleep)
                .environmentObject(health)
                .preferredColorScheme(.dark)
                .task { SyncCoordinator.propagate(sleep: sleep, health: health) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, sleep.profile.onboardingDone else { return }
                    Task { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
                }
                .onChange(of: sleep.debt) { _, _ in SyncCoordinator.propagate(sleep: sleep, health: health) }
                .onChange(of: sleep.episodes.count) { _, _ in SyncCoordinator.propagate(sleep: sleep, health: health) }
                .onOpenURL { url in
                    // Widget deep links: lumen://today, lumen://snap, lumen://sleep
                    DeepLink.shared.handle(url)
                }
        }
    }
}
