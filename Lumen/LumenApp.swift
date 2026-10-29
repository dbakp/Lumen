import SwiftUI

@main
struct LumenApp: App {
    @StateObject private var sleep = SleepStore()
    @StateObject private var health = HealthStore.shared
    @AppStorage("lumen.appearance") private var appearance = "light"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Clean slate for UI tests (runs before any store loads).
        if ProcessInfo.processInfo.arguments.contains("-resetForUITests") { LocalStore.eraseAll() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sleep)
                .environmentObject(health)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                .transaction { if reduceMotion { $0.animation = nil } }
                .tint(Theme.accent)
                .task {
                    SyncCoordinator.propagate(sleep: sleep, health: health)
                    WatchSync.shared.activate(sleep: sleep, health: health)
                }
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
