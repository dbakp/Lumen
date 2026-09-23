import SwiftUI

// MARK: - Liquid Glass tab root: Today · Activity · Snap · Sleep · Coach

public struct MainTabView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var health: HealthStore
    @State private var snapOpen = false
    @State private var selection = 0
    @State private var previousSelection = 0

    public init() {}

    public var body: some View {
        Group {
            if !store.profile.onboardingDone {
                OnboardingView()
            } else {
                ZStack(alignment: .bottom) {
                    TabView(selection: $selection) {
                        NavigationStack { TodayView() }
                            .tabItem { Label("Today", systemImage: "sunrise.fill") }
                            .tag(0)
                        NavigationStack { ActivityView() }
                            .tabItem { Label("Activity", systemImage: "flame.fill") }
                            .tag(1)
                        // Spacer tab — the floating Snap button below owns this slot.
                        Color.clear
                            .tabItem { Label("Snap", systemImage: "camera.fill") }
                            .tag(2)
                        NavigationStack { SleepTabView() }
                            .tabItem { Label("Sleep", systemImage: "moon.fill") }
                            .tag(3)
                        NavigationStack { CoachView() }
                            .tabItem { Label("Coach", systemImage: "sparkles") }
                            .tag(4)
                    }
                    .tint(.cyan)
                    .onChange(of: selection) { _, new in
                        if new == 2 {
                            // Reselect previous tab and open capture instead.
                            selection = previousSelection
                            snapOpen = true
                        } else {
                            previousSelection = new
                        }
                    }
                    Button { snapOpen = true } label: {
                        Image(systemName: "camera.viewfinder").font(.title2.weight(.bold))
                            .foregroundStyle(.black).frame(width: 56, height: 56)
                            .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                            .shadow(color: .orange.opacity(0.5), radius: 14)
                    }
                    .offset(y: -28)
                    // Coach owns the bottom edge with its input bar — yield the space.
                    .opacity(selection == 4 ? 0 : 1)
                    .allowsHitTesting(selection != 4)
                    .animation(.spring(response: 0.4), value: selection)
                    .sheet(isPresented: $snapOpen) { MealCaptureView().environmentObject(health) }
                }
            }
        }
    }
}

// MARK: - Sleep tab reuses the proven sleep engine, plus More hub.

public struct SleepTabView: View {
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NavigationLink { HomeView() } label: { navCard(icon: "moon.stars.fill", tint: .indigo, title: "Tonight", sub: "Debt, energy curve, bedtime plan") }
                NavigationLink { EnergyView() } label: { navCard(icon: "waveform.path.ecg", tint: .cyan, title: "Energy schedule", sub: "Peaks, dips, melatonin window") }
                NavigationLink { SleepLogView() } label: { navCard(icon: "bed.double.fill", tint: .purple, title: "Sleep log", sub: "Nights, edit, trends") }
                NavigationLink { HabitsView() } label: { navCard(icon: "checklist", tint: .green, title: "Rituals", sub: "Timed habits that move debt") }
                NavigationLink { NutritionView() } label: { navCard(icon: "fork.knife", tint: .orange, title: "Nutrition", sub: "Calories, protein, water") }
                NavigationLink { SoundsView() } label: { navCard(icon: "speaker.wave.2.fill", tint: .teal, title: "Sleep sounds", sub: "Rain, ocean, brown noise") }
                NavigationLink { LearnView() } label: { navCard(icon: "book.fill", tint: .yellow, title: "Learn", sub: "Debt, need, naps, caffeine") }
                NavigationLink { ProfileView() } label: { navCard(icon: "person.crop.circle.fill", tint: .pink, title: "Profile & integrations", sub: "Health, Strava, Coach AI") }
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .navigationTitle("Sleep & More")
        .navigationBarTitleDisplayMode(.inline)
    }

    func navCard(icon: String, tint: Color, title: String, sub: String) -> some View {
        GlassCard {
            HStack {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                    .frame(width: 48, height: 48).background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(sub).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
