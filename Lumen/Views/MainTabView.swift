import SwiftUI

// MARK: - Router: one place that owns tabs, sheets and toasts.

@MainActor
public final class AppRouter: ObservableObject {
    public static let shared = AppRouter()
    public enum TabID: Hashable { case today, sleep, activity, food, coach }
    public enum Sheet: Identifiable, Equatable {
        case log, meal(camera: Bool), settings, sleepLog, workout, weight, readiness
        public var id: String {
            switch self {
            case .log: return "log"; case .meal(let c): return "meal\(c)"; case .settings: return "settings"
            case .sleepLog: return "sleep"; case .workout: return "workout"; case .weight: return "weight"; case .readiness: return "readiness"
            }
        }
    }
    @Published public var tab: TabID = .today
    @Published public var sheet: Sheet?
    @Published public var toast: String?

    public func show(_ s: Sheet) { sheet = s }
    public func confirm(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4)) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut) { if toast == message { toast = nil } }
        }
    }
}

// MARK: - Root: onboarding gate → optional app lock → tabs

public struct RootView: View {
    @EnvironmentObject var sleep: SleepStore
    @StateObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            if !sleep.profile.onboardingDone {
                OnboardingView().transition(.opacity)
            } else {
                MainTabView().transition(.opacity)
            }
            if lock.isLocked && sleep.profile.onboardingDone {
                LockScreen().transition(.opacity).zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: sleep.profile.onboardingDone)
        .animation(.easeInOut(duration: 0.25), value: lock.isLocked)
        .onChange(of: scenePhase) { _, phase in lock.handle(phase: phase, enabled: sleep.profile.appLock ?? false) }
        .onAppear { lock.handle(phase: .active, enabled: sleep.profile.appLock ?? false, coldStart: true) }
    }
}

// MARK: - Tabs: Today · Sleep · Activity · Food · Coach

public struct MainTabView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var health: HealthStore
    @StateObject private var router = AppRouter.shared
    @StateObject private var links = DeepLink.shared

    public init() {}

    public var body: some View {
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppRouter.TabID.today) { NavigationStack { TodayView() } }
            Tab("Sleep", systemImage: "moon.fill", value: AppRouter.TabID.sleep) { NavigationStack { HomeView() } }
            Tab("Activity", systemImage: "figure.walk", value: AppRouter.TabID.activity) { NavigationStack { ActivityView() } }
            Tab("Food", systemImage: "fork.knife", value: AppRouter.TabID.food) { NavigationStack { NutritionView() } }
            Tab("Coach", systemImage: "sparkles", value: AppRouter.TabID.coach) { NavigationStack { CoachView() } }
        }
        .tint(.white)
        .sensoryFeedback(.selection, trigger: router.tab)
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                case .log: LogSheet()
                case .meal(let camera): MealCaptureView(openCamera: camera)
                case .settings: SettingsView()
                case .sleepLog: LogSleepSheet()
                case .workout: ManualWorkoutSheet()
                case .weight: WeightLogSheet()
                case .readiness: ReadinessDetailSheet()
                }
            }
            .environmentObject(store)
            .environmentObject(health)
        }
        .overlay(alignment: .top) {
            if let t = router.toast {
                Label(t, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .onChange(of: links.pending) { _, target in route(target) }
        .onAppear { route(links.pending) }
    }

    func route(_ target: DeepLink.Target?) {
        guard let target else { return }
        switch target {
        case .today: router.tab = .today
        case .activity: router.tab = .activity
        case .snap: router.tab = .food; router.show(.meal(camera: true))
        case .sleep: router.tab = .sleep
        case .coach: router.tab = .coach
        }
        links.pending = nil
    }
}

// MARK: - Log sheet: every "add" in one calm place

struct LogSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    var router: AppRouter { .shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                logButton("Meal", "Snap a photo of your plate", "camera.fill", Theme.food) { next(.meal(camera: true)) }
                logButton("Water", "Add a glass · 250 ml", "drop.fill", Theme.water) {
                    health.addWater(ml: 250); dismiss(); router.confirm("Added 250 ml of water")
                }
                logButton("Workout", "Log a session", "figure.run", Theme.move) { next(.workout) }
                logButton("Sleep", "Add a night", "bed.double.fill", Theme.sleep) { next(.sleepLog) }
                logButton("Weight", "Update your weight", "scalemass.fill", Theme.steps) { next(.weight) }
                Spacer()
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 8)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Log").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.fraction(0.68), .large])
        .presentationBackground(Theme.bg)
        .tint(.white)
    }

    func next(_ s: AppRouter.Sheet) {
        dismiss()
        Task { try? await Task.sleep(for: .milliseconds(350)); router.show(s) }
    }

    func logButton(_ title: String, _ sub: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.text)
                    Text(sub).font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "plus").font(.headline).foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .surface(18)
        }
        .buttonStyle(.plain)
    }
}

/// Toolbar "+" used on every main tab.
struct LogToolbarButton: View {
    var body: some View {
        Button { AppRouter.shared.show(.log) } label: { Image(systemName: "plus") }
            .accessibilityLabel("Log")
    }
}
