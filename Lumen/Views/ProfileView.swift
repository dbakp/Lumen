import SwiftUI

// MARK: - Profile / settings + integrations + paywall

public struct ProfileView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var healthStore: HealthStore
    @StateObject private var sleepHealth = HealthKitManager.shared
    @StateObject private var hk = HealthKitExtended.shared
    @StateObject private var strava = StravaService.shared
    @StateObject private var notifications = NotificationManager.shared
    @State private var showPaywall = false
    @State private var showNeedEditor = false
    @State private var showGoals = false
    @State private var llmKey = UserDefaults.standard.string(forKey: "lumen.llm.key") ?? ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    HStack(spacing: 14) {
                        Text(String(store.profile.name.prefix(1)).uppercased())
                            .font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        VStack(alignment: .leading) {
                            Text(store.profile.name).font(.title3.weight(.bold)).foregroundStyle(.white)
                            Text("\(store.profile.chronotype.label) · Need \(SleepFormat.durationHM(store.profile.sleepNeed))")
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                        Button(store.profile.isSubscribed ? "PRO" : "Go Pro") {
                            if !store.profile.isSubscribed { showPaywall = true }
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(store.profile.isSubscribed ? Color.green.opacity(0.25) : Color.cyan.opacity(0.25), in: Capsule())
                        .foregroundStyle(store.profile.isSubscribed ? .green : .cyan)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Your biology", subtitle: "Personalized from your history", systemImage: "person.fill")
                        BioRow(label: "Sleep need", value: "\(SleepFormat.durationHM(store.profile.sleepNeed)) · \(Int(store.profile.sleepNeedConfidence*100))% confidence") {
                            showNeedEditor = true
                        }
                        BioRow(label: "Chronotype", value: store.profile.chronotype.label) {
                            cycleChronotype()
                        }
                        BioRow(label: "Wake goal", value: wakeString) {
                            nudgeWake()
                        }
                        Text(store.profile.chronotype.description).font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Integrations", subtitle: "Health + Strava + Watch — deduped", systemImage: "applewatch")
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Apple Health (sleep)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(sleepHealth.statusMessage).font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Button(sleepHealth.isAuthorized ? "Synced" : "Connect") {
                                Task { await sleepHealth.requestAuthorization(); await syncHealth() }
                            }
                            .buttonStyle(.borderedProminent).tint(.cyan).font(.caption.weight(.bold))
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Health — activity + vitals").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(hk.status).font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Button(hk.isAuthorized ? "Synced" : "Connect") {
                                Task { await hk.requestAuthorization(); await healthStore.syncAll() }
                            }
                            .buttonStyle(.borderedProminent).tint(.green).font(.caption.weight(.bold))
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Strava").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(strava.status).font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            if strava.isConnected {
                                Button("Sync") { Task { await strava.sync(); await healthStore.syncAll() } }
                                    .buttonStyle(.bordered).tint(.orange).font(.caption.weight(.bold))
                            } else {
                                Button("Connect") { Task { await strava.connect() } }
                                    .buttonStyle(.borderedProminent).tint(.orange).font(.caption.weight(.bold))
                            }
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Smart reminders").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(notifications.authorized ? "Timed to your clock" : "Allow notifications to time habits").font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Button(notifications.authorized ? "On" : "Enable") {
                                Task {
                                    await notifications.request()
                                    reschedule()
                                }
                            }
                            .buttonStyle(.bordered).tint(.cyan).font(.caption.weight(.bold))
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Goals", subtitle: "Calories, protein, steps adapt to you", systemImage: "target")
                        BioRow(label: "Calorie target", value: "\(healthStore.goals.calorieTarget()) kcal · \(healthStore.goals.goal.label)") { showGoals = true }
                        BioRow(label: "Protein", value: "\(healthStore.goals.proteinTarget())g / day") { showGoals = true }
                        BioRow(label: "Move / Exercise / Stand", value: "\(Int(healthStore.goals.activeCalGoal)) / \(Int(healthStore.goals.exerciseGoalMin)) / \(healthStore.goals.standGoal)h") { showGoals = true }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Coach AI", subtitle: coachAIStatus, systemImage: "sparkles")
                        SecureField("OpenAI-compatible API key (optional)", text: $llmKey)
                            .textFieldStyle(.roundedBorder).colorScheme(.dark)
                            .onChange(of: llmKey) { _, v in UserDefaults.standard.set(v, forKey: "lumen.llm.key") }
                        Text("Without a key the coach runs on-device with your real data. With a key it upgrades to vision meal analysis + LLM chat. Keys stay on your device.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.55))
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("The science", subtitle: "What Lumen measures", systemImage: "flask.fill")
                        Text("• Sleep need (personal, not 8h)\n• 14-night sleep debt (last night 15%)\n• Circadian timing via SAFTE-based prediction\n• Energy Potential 0–100 tied to debt")
                            .font(.caption).foregroundStyle(.white.opacity(0.75)).lineSpacing(4)
                        Text("Not medical advice. If you suspect a sleep disorder, talk to a clinician.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.45))
                    }
                }

                Button("Reset demo data") {
                    UserDefaults.standard.removeObject(forKey: "lumen.episodes.v1")
                    store.episodes = SleepStore.sampleEpisodes(need: store.profile.sleepNeed)
                    store.recompute()
                }
                .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showNeedEditor) { NeedEditorSheet() }
        .sheet(isPresented: $showGoals) { GoalsSheet() }
        .onAppear {
            llmKey = UserDefaults.standard.string(forKey: "lumen.llm.key") ?? ""
            reschedule()
        }
    }

    var coachAIStatus: String {
        (UserDefaults.standard.string(forKey: "lumen.llm.key") ?? "").isEmpty ? "On-device brain active" : "LLM vision + chat active"
    }

    var wakeString: String {
        let h = store.profile.wakeGoal.hour ?? 7, m = store.profile.wakeGoal.minute ?? 0
        var c = DateComponents(); c.hour = h; c.minute = m
        let d = Calendar.current.date(from: c) ?? Date()
        return SleepFormat.time(d)
    }

    func cycleChronotype() {
        let all: [Chronotype] = [.morning, .intermediate, .evening]
        if let i = all.firstIndex(of: store.profile.chronotype) {
            store.profile.chronotype = all[(i + 1) % all.count]
            store.recompute()
        }
    }

    func nudgeWake() {
        var w = store.profile.wakeGoal
        w.hour = ((w.hour ?? 7) + 1) % 24
        store.profile.wakeGoal = w
        store.recompute()
    }

    func syncHealth() async {
        let eps = await sleepHealth.fetchRecentSleep(days: 30)
        if !eps.isEmpty {
            // Merge: replace sample with real (keep manual).
            store.episodes = (store.episodes.filter { $0.source == .manual } + eps).sorted { $0.bedtime < $1.bedtime }
            store.reestimateNeed()
            store.recompute()
        }
        await healthStore.syncAll()
    }

    func reschedule() {
        guard let pred = store.prediction else { return }
        notifications.schedule(habits: store.habits, wakeToday: pred.wakeZone.lowerBound, bedtimeTonight: store.suggestedBedtime, melatoninStart: pred.melatoninWindow.lowerBound)
    }
}

struct BioRow: View {
    let label: String; let value: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

struct NeedEditorSheet: View {
    @EnvironmentObject var store: SleepStore
    @Environment(\.dismiss) var dismiss
    @State private var hours: Double = 8
    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                VStack(spacing: 16) {
                    Text("\(SleepFormat.durationHM(hours*3600))").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                    Slider(value: $hours, in: 5...11.5, step: 0.0833).tint(.cyan)
                        .onAppear { hours = store.profile.sleepNeed / 3600 }
                    Text("Most people need 7–9h; Lumen's median is ~8h. Your history suggests \(SleepFormat.durationHM(store.profile.sleepNeed)).")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                    Button("Save") {
                        store.profile.sleepNeed = hours * 3600
                        store.recompute(); dismiss()
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan).font(.headline)
                    Spacer()
                }.padding(22)
            }
            .navigationTitle("Sleep need").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Paywall (premium upsell mock)

public struct PaywallView: View {
    @EnvironmentObject var store: SleepStore
    @Environment(\.dismiss) var dismiss
    public init() {}
    public var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("LUMEN PRO").font(.caption.weight(.bold)).foregroundStyle(.cyan).tracking(2)
                    Text("Sleep like it's\nyour superpower").font(.largeTitle.weight(.bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            FeatureRow(icon: "chart.bar.fill", text: "Unlimited sleep debt + 1-year trends")
                            FeatureRow(icon: "waveform.path.ecg", text: "Full circadian predictions + smart alarm")
                            FeatureRow(icon: "bell.badge.fill", text: "All 16 timed habit nudges")
                            FeatureRow(icon: "speaker.wave.2.fill", text: "Full sound library + offline mixes")
                            FeatureRow(icon: "calendar.badge.clock", text: "Calendar + widgets + Apple Watch")
                        }
                    }
                    VStack(spacing: 10) {
                        Button {
                            store.profile.isSubscribed = true
                            store.recompute()
                            haptic(.medium); dismiss()
                        } label: {
                            VStack(spacing: 2) {
                                Text("Start 7-day free trial").font(.headline.weight(.bold))
                                Text("Then $69.99/year · cancel anytime").font(.caption)
                            }
                            .frame(maxWidth: .infinity).padding()
                        }
                        .buttonStyle(.borderedProminent).tint(.cyan)
                        Button("Restore / Not now") { dismiss() }.font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }.padding(22)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.cyan).frame(width: 26)
            Text(text).font(.subheadline).foregroundStyle(.white)
        }
    }
}

// MARK: - Goals editor

struct GoalsSheet: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                Form {
                    Section("Body") {
                        Picker("Goal", selection: $health.goals.goal) {
                            ForEach(HealthGoals.BodyGoal.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Picker("Activity", selection: $health.goals.activityLevel) {
                            ForEach(HealthGoals.ActivityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                    Section("Targets") {
                        HStack { Text("Move"); Spacer(); Text("\(Int(health.goals.activeCalGoal)) kcal") }
                        Slider(value: $health.goals.activeCalGoal, in: 200...1200, step: 10)
                        HStack { Text("Steps"); Spacer(); Text("\(Int(health.goals.stepGoal))") }
                        Slider(value: $health.goals.stepGoal, in: 4000...20000, step: 500)
                    }
                    Section("Info") {
                        Text("Calorie target \(health.goals.calorieTarget()) kcal · Protein \(health.goals.proteinTarget())g — computed via Mifflin-St Jeor × activity, adjusted for goal.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("Goals").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { health.persist(); dismiss() } }
            }
        }
    }
}
