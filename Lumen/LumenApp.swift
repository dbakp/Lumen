import SwiftUI

@main
struct LumenApp: App {
    @UIApplicationDelegateAdaptor(LumenAppDelegate.self) private var appDelegate
    @State private var protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable

    init() {
        HealthZIPArchive.clearTemporaryFiles()
        #if DEBUG && targetEnvironment(simulator)
        // Clean slate only for dedicated simulator UI tests, before stores load.
        do {
            try HealthLegacyResetUIFixture.preflightIfRequested()
            try HealthLegacyTargetChangeUIFixture.preflightIfRequested()
            try HealthHealthyTargetChangeUIFixture.preflightIfRequested()
        }
        catch {
            if !HealthLegacyResetUIFixture.diagnosticOnly { preconditionFailure("Synthetic reset context is not safe") }
        }
        // This dedicated diagnostic launch cannot reach generic fixture reset.
        if HealthLegacyResetUIFixture.diagnosticOnly { return }
        if ProcessInfo.processInfo.arguments.contains("-resetForUITests") && !ProviderAuthorizationNativeProbe.resumesRemovalCheck && !ProviderAuthorizationNativeProbe.resumesAccountResetCheck && !ProviderConnectionUIFixture.resuming && !HealthWriteLifecycleProbe.resuming {
            LocalStore.eraseAll()
            SemanticSearchService.resetForUITests()
            do { try ConversationNativeFixtures.prepareStartupIfRequested() }
            catch { preconditionFailure("Synthetic startup fixture could not be prepared: \(error)") }
            do { try PersonalContextUIFixture.prepareIfRequested() }
            catch { preconditionFailure("Synthetic personal fixture could not be prepared: \(error)") }
            do { try ProviderConnectionUIFixture.prepareIfRequested() }
            catch { preconditionFailure("Synthetic connection fixture could not be prepared: \(error)") }
            do { try HealthRecoveryUIFixture.prepareIfRequested() }
            catch { preconditionFailure("Synthetic recovery fixture could not be prepared: \(error)") }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if HealthLegacyResetUIFixture.diagnosticOnly { HealthLegacyResetDiagnosticView() }
                else if protectedDataAvailable { LumenReadyView() }
                else { Theme.bg.ignoresSafeArea() }
                #else
                if protectedDataAvailable { LumenReadyView() }
                else { Theme.bg.ignoresSafeArea() }
                #endif
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
    @StateObject private var healthWriteProbe = HealthWriteNativeProbe.shared
    @StateObject private var healthKitWriteProbe = HealthWriteHealthKitProbe.shared
    @StateObject private var healthLifecycleProbe = HealthWriteLifecycleProbe.shared
    #endif

    var body: some View {
        Group {
            #if DEBUG && targetEnvironment(simulator)
            if ProviderConnectionUIFixture.isAuthorized { ProviderConnectionUIRoot() }
            else if HealthRecoveryUIFixture.requested { HealthRetainedRecoveryFixtureRoot() }
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
                if HealthWriteNativeProbe.requested, ProcessInfo.processInfo.arguments.contains("-health-legacy-root-probe") {
                    await healthWriteProbe.run(); return
                }
                if HealthRecoveryUIFixture.requested || HealthRecoveryUIFixture.backupRequested {
                    if HealthRecoveryUIFixture.dailyRebuildRequested { await HealthDailyCacheHealthUIFixture.connect() }
                    return
                }
                if PreferenceNativeProbe.requested { await preferenceProbe.run(); return }
                if ConversationNativeProbe.requested { await conversationProbe.run(); return }
                if PersonalContextNativeProbe.requested { await personalProbe.run(); return }
                if HealthWriteNativeProbe.requested { await healthWriteProbe.run(); return }
                if HealthWriteHealthKitProbe.requested { await healthKitWriteProbe.run(); return }
                if HealthWriteLifecycleProbe.requested { await healthLifecycleProbe.run(); return }
                try? PreferenceNativeProbe.prepareFixtures(health: health)
                #endif
                SyncCoordinator.propagate(sleep: sleep, health: health)
                WatchSync.shared.activate(sleep: sleep, health: health)
                HealthBackgroundSync.shared.start()
                health.retryHealthWrites()
            }
            #if DEBUG && targetEnvironment(simulator)
            .overlay(alignment: .bottom) {
                HealthLegacyResetUIProbe(location: "root")
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
                if HealthWriteNativeProbe.requested {
                    Text(healthWriteProbe.status).font(.footnote).accessibilityIdentifier("healthWriteProbeStatus")
                        .padding().background(Theme.bg)
                }
                if HealthWriteHealthKitProbe.requested {
                    VStack {
                        if healthKitWriteProbe.accessReturned {
                            Text("Health access request finished").accessibilityIdentifier("healthKitProbeAccessReturned")
                        }
                        Text(healthKitWriteProbe.status).accessibilityIdentifier("healthKitWriteProbeStatus")
                    }.font(.footnote).padding().background(Theme.bg)
                }
                if HealthWriteLifecycleProbe.requested {
                    VStack {
                        if healthLifecycleProbe.accessReturned {
                            Text("Health restart access ready").accessibilityIdentifier("healthLifecycleAccessReady")
                        }
                        Text(healthLifecycleProbe.status).accessibilityIdentifier("healthLifecycleStatus")
                    }.font(.footnote).padding().background(Theme.bg)
                }
            }
            #endif
            .onChange(of: scenePhase) { _, phase in
                #if DEBUG && targetEnvironment(simulator)
                if ProviderConnectionUIFixture.isAuthorized || HealthWriteLifecycleProbe.requested || HealthRecoveryUIFixture.backupRequested { return }
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
