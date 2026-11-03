import SwiftUI

@main
struct LumenApp: App {
    @UIApplicationDelegateAdaptor(LumenAppDelegate.self) private var appDelegate
    @State private var protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable

    init() {
        HealthZIPArchive.clearTemporaryFiles()
        #if DEBUG && targetEnvironment(simulator)
        // Clean slate only for dedicated simulator UI tests, before stores load.
        if ProcessInfo.processInfo.arguments.contains("-resetForUITests") && !ProviderAuthorizationNativeProbe.resumesRemovalCheck && !ProviderAuthorizationNativeProbe.resumesAccountResetCheck && !ProviderConnectionUIFixture.resuming {
            LocalStore.eraseAll()
            SemanticSearchService.resetForUITests()
            do { try ConversationNativeFixtures.prepareStartupIfRequested() }
            catch { preconditionFailure("Synthetic startup fixture could not be prepared: \(error)") }
            do { try PersonalContextUIFixture.prepareIfRequested() }
            catch { preconditionFailure("Synthetic personal fixture could not be prepared: \(error)") }
            do { try ProviderConnectionUIFixture.prepareIfRequested() }
            catch { preconditionFailure("Synthetic connection fixture could not be prepared: \(error)") }
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
    #if DEBUG && targetEnvironment(simulator)
    @StateObject private var preferenceProbe = PreferenceNativeProbe.shared
    @StateObject private var conversationProbe = ConversationNativeProbe.shared
    @StateObject private var personalProbe = PersonalContextNativeProbe.shared
    #endif

    var body: some View {
        Group {
            #if DEBUG && targetEnvironment(simulator)
            if ProviderConnectionUIFixture.isAuthorized { ProviderConnectionUIRoot() }
            else { RootView() }
            #else
            RootView()
            #endif
        }
            .environmentObject(sleep)
            .environmentObject(health)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .transaction { if reduceMotion { $0.animation = nil } }
            .tint(Theme.accent)
            .task {
                #if DEBUG && targetEnvironment(simulator)
                if ProviderConnectionUIFixture.isAuthorized { return }
                if PreferenceNativeProbe.requested { await preferenceProbe.run(); return }
                if ConversationNativeProbe.requested { await conversationProbe.run(); return }
                if PersonalContextNativeProbe.requested { await personalProbe.run(); return }
                try? PreferenceNativeProbe.prepareFixtures(health: health)
                #endif
                SyncCoordinator.propagate(sleep: sleep, health: health)
                WatchSync.shared.activate(sleep: sleep, health: health)
                HealthBackgroundSync.shared.start()
            }
            #if DEBUG && targetEnvironment(simulator)
            .overlay(alignment: .bottom) {
                if PreferenceNativeProbe.requested {
                    VStack(spacing: 4) {
                        Text("Synthetic verification").font(.caption)
                        Text(preferenceProbe.status).font(.footnote).accessibilityIdentifier("preferenceProbeStatus")
                    }.padding().background(Theme.bg)
                }
                if ConversationNativeProbe.requested {
                    Text(conversationProbe.status).font(.footnote).accessibilityIdentifier("conversationProbeStatus")
                        .padding().background(Theme.bg)
                }
                if PersonalContextNativeProbe.requested {
                    Text(personalProbe.status).font(.footnote).accessibilityIdentifier("personalProvenanceProbeStatus")
                        .padding().background(Theme.bg)
                }
            }
            #endif
            .onChange(of: scenePhase) { _, phase in
                #if DEBUG && targetEnvironment(simulator)
                if ProviderConnectionUIFixture.isAuthorized { return }
                #endif
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
