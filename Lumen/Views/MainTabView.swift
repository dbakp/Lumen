import SwiftUI

// MARK: - Root: onboarding gate → optional app lock → tabs

public struct RootView: View {
    @EnvironmentObject var sleep: SleepStore
    @StateObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            if !sleep.profile.onboardingDone {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
            if lock.isLocked && sleep.profile.onboardingDone {
                LockScreen().transition(.opacity).zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: sleep.profile.onboardingDone)
        .animation(.easeInOut(duration: 0.25), value: lock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            lock.handle(phase: phase, enabled: sleep.profile.appLock ?? false)
        }
        .onAppear { lock.handle(phase: .active, enabled: sleep.profile.appLock ?? false, coldStart: true) }
    }
}

// MARK: - Tabs: Today · Activity · Snap · Sleep · Coach

public struct MainTabView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var health: HealthStore
    @StateObject private var links = DeepLink.shared
    @State private var snapOpen = false
    @State private var selection = 0
    @State private var previousSelection = 0

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                NavigationStack { TodayView() }
                    .tabItem { Label("Today", systemImage: "sun.max.fill") }
                    .tag(0)
                NavigationStack { ActivityView() }
                    .tabItem { Label("Activity", systemImage: "flame.fill") }
                    .tag(1)
                // Spacer tab — the floating Snap button below owns this slot.
                Color.clear
                    .tabItem { Label("Snap", systemImage: "camera.fill") }
                    .tag(2)
                NavigationStack { HomeView() }
                    .tabItem { Label("Sleep", systemImage: "moon.fill") }
                    .tag(3)
                NavigationStack { CoachView() }
                    .tabItem { Label("Coach", systemImage: "sparkles") }
                    .tag(4)
            }
            .tint(.cyan)
            .onChange(of: selection) { _, new in
                if new == 2 {
                    selection = previousSelection
                    snapOpen = true
                } else {
                    if new != previousSelection { UISelectionFeedbackGenerator().selectionChanged() }
                    previousSelection = new
                }
            }
            Button { haptic(.medium); snapOpen = true } label: {
                Image(systemName: "camera.viewfinder").font(.title2.weight(.bold))
                    .foregroundStyle(.black).frame(width: 56, height: 56)
                    .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .shadow(color: .orange.opacity(0.5), radius: 14)
            }
            .accessibilityLabel("Snap a meal")
            .offset(y: -28)
            // Coach owns the bottom edge with its input bar — yield the space.
            .opacity(selection == 4 ? 0 : 1)
            .allowsHitTesting(selection != 4)
            .animation(.spring(response: 0.4), value: selection)
        }
        .sheet(isPresented: $snapOpen) { MealCaptureView().environmentObject(health) }
        .onChange(of: links.pending) { _, target in route(target) }
        .onAppear { route(links.pending) }
    }

    func route(_ target: DeepLink.Target?) {
        guard let target else { return }
        switch target {
        case .today: selection = 0
        case .activity: selection = 1
        case .snap: snapOpen = true
        case .sleep: selection = 3
        case .coach: selection = 4
        }
        links.pending = nil
    }
}
