import SwiftUI

@main
struct LumenApp: App {
    @UIApplicationDelegateAdaptor(LumenAppDelegate.self) private var appDelegate
    @State private var protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable

    init() {
        HealthZIPArchive.clearTemporaryFiles()
        #if DEBUG && targetEnvironment(simulator)
        // Clean slate only for dedicated simulator UI tests, before stores load.
        if ProcessInfo.processInfo.arguments.contains("-resetForUITests") {
            LocalStore.eraseAll()
            SemanticSearchService.resetForUITests()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if protectedDataAvailable { LumenReadyView() }
                else { Theme.bg.ignoresSafeArea() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                protectedDataAvailable = true
            }
        }
    }
}

/// A Health-triggered launch may precede unlock. Do not instantiate stores whose
/// protected reads would otherwise look like missing files and produce defaults.
private struct LumenReadyView: View {
    @StateObject private var sleep = SleepStore.shared
    @StateObject private var health = HealthStore.shared
    @AppStorage("lumen.appearance") private var appearance = "light"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RootView()
            .environmentObject(sleep)
            .environmentObject(health)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .transaction { if reduceMotion { $0.animation = nil } }
            .tint(Theme.accent)
            .task {
                SyncCoordinator.propagate(sleep: sleep, health: health)
                WatchSync.shared.activate(sleep: sleep, health: health)
                HealthBackgroundSync.shared.start()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, sleep.profile.onboardingDone else { return }
                Task { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
            }
            .onChange(of: sleep.debt) { _, _ in SyncCoordinator.propagate(sleep: sleep, health: health) }
            .onChange(of: sleep.episodes) { _, _ in SyncCoordinator.propagate(sleep: sleep, health: health) }
            .onChange(of: sleep.profile.sleepNeed) { _, _ in SyncCoordinator.propagate(sleep: sleep, health: health) }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in sleep.resetHabitsIfNewDay(); sleep.recompute(); SyncCoordinator.propagate(sleep: sleep, health: health) }
            .onOpenURL { DeepLink.shared.handle($0) }
    }
}
