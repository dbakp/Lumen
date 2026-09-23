import SwiftUI

// MARK: - Settings: profile, body, goals, sleep, connections, coach, privacy

public struct SettingsView: View {
    @EnvironmentObject var sleep: SleepStore
    @EnvironmentObject var health: HealthStore
    @ObservedObject private var hk = HealthKitService.shared
    @ObservedObject private var strava = StravaService.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var llm = LLMConnectionService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var confirmErase = false
    @State private var showWeightLog = false
    @State private var showCoachSetup = false
    @State private var showStravaSetup = false
    @State private var syncing = false

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    public var body: some View {
        NavigationStack {
            Form {
                profileHeader
                bodySection
                goalsSection
                sleepSection
                connectionsSection
                coachSection
                privacySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .sheet(isPresented: $showWeightLog) { WeightLogSheet() }
            .sheet(isPresented: $showCoachSetup) { CoachSetupSheet() }
            .sheet(isPresented: $showStravaSetup) { StravaSetupSheet() }
            .confirmationDialog("Erase all Lumen data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { eraseAll() }
            } message: {
                Text("Your profile, logs and settings are removed from this iPhone and you'll start fresh. Data in Apple Health isn't touched.")
            }
            .task { await notifications.refreshAuthorization() }
        }
        .tint(.cyan)
    }

    // MARK: Profile

    var profileHeader: some View {
        Section {
            HStack(spacing: 14) {
                Text(String(sleep.profile.name.prefix(1)).uppercased())
                    .font(.title.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Name", text: $sleep.profile.name)
                        .font(.title3.weight(.bold))
                        .onSubmit { sleep.persist() }
                    if let created = sleep.profile.createdAt {
                        Text("Member since \(created.formatted(.dateTime.month(.wide).year()))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Body

    var bodySection: some View {
        Section("Body") {
            Picker("Units", selection: Binding(get: { units }, set: { sleep.profile.units = $0; sleep.persist() })) {
                ForEach(UnitSystem.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Sex", selection: goalBinding(\.sex)) {
                Text("Female").tag(HealthGoals.Sex.female)
                Text("Male").tag(HealthGoals.Sex.male)
                Text("Not specified").tag(HealthGoals.Sex.unspecified)
            }
            Picker("Birth year", selection: Binding(
                get: { sleep.profile.birthYear ?? (currentYear - (health.goals.age ?? 30)) },
                set: { y in
                    sleep.profile.birthYear = y; sleep.persist()
                    var g = health.goals; g.age = currentYear - y; health.updateGoals(g)
                })) {
                ForEach((1930...(currentYear - 13)).reversed(), id: \.self) { Text(String($0)).tag($0) }
            }
            Stepper(value: Binding(get: { health.goals.heightCm ?? 172 }, set: { v in var g = health.goals; g.heightCm = v; health.updateGoals(g) }),
                    in: 120...220, step: 1) {
                LabeledContent("Height", value: Units.height(health.goals.heightCm ?? 172, units))
            }
            Button { showWeightLog = true } label: {
                LabeledContent("Weight", value: health.goals.weightKg.map { Units.weight($0, units) } ?? "Add")
            }
            .foregroundStyle(.primary)
        }
    }

    func goalBinding<T>(_ kp: WritableKeyPath<HealthGoals, T>) -> Binding<T> {
        Binding(get: { health.goals[keyPath: kp] }, set: { v in var g = health.goals; g[keyPath: kp] = v; health.updateGoals(g) })
    }

    // MARK: Goals

    var goalsSection: some View {
        Section {
            Picker("Focus", selection: goalBinding(\.goal)) {
                ForEach(HealthGoals.BodyGoal.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Activity level", selection: goalBinding(\.activityLevel)) {
                ForEach(HealthGoals.ActivityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Stepper(value: goalBinding(\.activeCalGoal), in: 150...1500, step: 25) {
                LabeledContent("Move goal", value: "\(Int(health.goals.activeCalGoal)) kcal")
            }
            Stepper(value: goalBinding(\.exerciseGoalMin), in: 10...120, step: 5) {
                LabeledContent("Exercise goal", value: "\(Int(health.goals.exerciseGoalMin)) min")
            }
            Stepper(value: goalBinding(\.stepGoal), in: 2000...30000, step: 500) {
                LabeledContent("Step goal", value: Int(health.goals.stepGoal).formatted())
            }
            LabeledContent("Calories", value: "\(health.goals.calorieTarget()) kcal / day")
            LabeledContent("Protein", value: "\(health.goals.proteinTarget()) g / day")
        } header: {
            Text("Goals")
        } footer: {
            Text("Calories use Mifflin-St Jeor × your activity level, adjusted for your focus. Protein scales with body weight.")
        }
    }

    // MARK: Sleep

    var sleepSection: some View {
        Section {
            Stepper(value: Binding(get: { sleep.profile.sleepNeed }, set: { sleep.profile.sleepNeed = $0; sleep.recompute() }),
                    in: 5 * 3600...11.5 * 3600, step: 300) {
                LabeledContent("Sleep need", value: SleepFormat.durationHM(sleep.profile.sleepNeed))
            }
            Picker("Chronotype", selection: Binding(get: { sleep.profile.chronotype }, set: { sleep.profile.chronotype = $0; sleep.recompute() })) {
                ForEach(Chronotype.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            DatePicker("Wake goal", selection: Binding(
                get: { sleep.wakeGoalToday },
                set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    sleep.profile.wakeGoal.hour = c.hour; sleep.profile.wakeGoal.minute = c.minute
                    sleep.recompute(); NotificationManager.shared.reschedule(from: sleep)
                }), displayedComponents: .hourAndMinute)
        } header: {
            Text("Sleep")
        } footer: {
            Text("Confidence \(Int(sleep.profile.sleepNeedConfidence * 100))% — Lumen refines your need from the nights it sees.")
        }
    }

    // MARK: Connections

    var connectionsSection: some View {
        Section("Connections") {
            HStack {
                connectionIcon("heart.fill", .pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health")
                    Text(hk.isAuthorized ? (health.lastSync.map { "Synced \($0.formatted(.relative(presentation: .named)))" } ?? "Connected") : "Not connected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if hk.isAuthorized {
                    Button {
                        syncing = true
                        Task { await SyncCoordinator.syncEverything(sleep: sleep, health: health); syncing = false; haptic(.light) }
                    } label: {
                        if syncing { ProgressView() } else { Text("Sync now") }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button("Connect") {
                        Task {
                            if await hk.requestAuthorization() { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            HStack {
                connectionIcon("bell.fill", .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminders")
                    Text(notifications.authorized ? "Timed to your body clock" : "Off").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if notifications.authorized {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Turn on") {
                        Task {
                            if await notifications.request() { notifications.reschedule(from: sleep) }
                            else if let url = URL(string: UIApplication.openNotificationSettingsURLString) { await UIApplication.shared.open(url) }
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Button { showStravaSetup = true } label: {
                HStack {
                    connectionIcon("figure.outdoor.cycle", Color(red: 0.99, green: 0.32, blue: 0.0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strava").foregroundStyle(.primary)
                        Text(strava.isConnected ? (strava.athleteName.map { "Connected as \($0)" } ?? "Connected") : "Optional").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            if hk.isAuthorized {
                Text("To change what Lumen can read, open the Health app → Sharing → Apps → Lumen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func connectionIcon(_ name: String, _ tint: Color) -> some View {
        Image(systemName: name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Coach

    var coachSection: some View {
        Section {
            Button { showCoachSetup = true } label: {
                HStack {
                    connectionIcon("sparkles", .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coach brain").foregroundStyle(.primary)
                        Text(llm.mode.label + " · " + llm.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            if !health.chat.isEmpty {
                Button("Clear coach conversation", role: .destructive) { health.chat = []; health.persist() }
            }
        } header: {
            Text("Coach")
        } footer: {
            Text("The on-device coach is private and free. Optionally connect your own AI provider for richer answers and photo meal recognition.")
        }
    }

    // MARK: Privacy & data

    var privacySection: some View {
        Section {
            if AppLock.shared.isAvailable {
                Toggle("Lock with \(AppLock.shared.biometryName)", isOn: Binding(
                    get: { sleep.profile.appLock ?? false },
                    set: { on in
                        Task {
                            let ok = on ? await AppLock.shared.verify() : true
                            if ok { sleep.profile.appLock = on; sleep.persist() }
                        }
                    }))
            }
            Button {
                exportURL = LocalStore.exportBundle()
            } label: {
                Label("Export my data", systemImage: "square.and.arrow.up")
            }
            if let exportURL {
                ShareLink(item: exportURL) { Label("Share export file", systemImage: "doc.fill") }
            }
            Button(role: .destructive) { confirmErase = true } label: {
                Label("Erase all data", systemImage: "trash")
            }
        } header: {
            Text("Privacy & data")
        } footer: {
            Text("Everything Lumen stores lives on this iPhone. Secrets like API keys are kept in the Keychain.")
        }
    }

    var aboutSection: some View {
        Section {
            NavigationLink("How Lumen works") { ScienceView() }
            LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
        } footer: {
            Text("Lumen offers wellness guidance, not medical advice. If you suspect a sleep or health condition, talk to a clinician.")
        }
    }

    func eraseAll() {
        LocalStore.eraseAll()
        SecureStore.eraseAll()
        StravaService.shared.disconnect()
        UNUserNotificationCenterBridge.removeAll()
        HealthKitService.shared.disconnectLocally()
        health.resetAll()
        sleep.resetAll()
        dismiss()
    }
}

import UserNotifications
enum UNUserNotificationCenterBridge {
    static func removeAll() { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
}

// MARK: - Weight log

struct WeightLogSheet: View {
    @EnvironmentObject var sleep: SleepStore
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @State private var kg: Double = 72
    var units: UnitSystem { sleep.profile.unitSystem }
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(Units.weight(kg, units)).font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText()).foregroundStyle(.white)
                Slider(value: $kg, in: 35...200, step: units == .metric ? 0.1 : 0.04536).tint(.cyan)
                HStack(spacing: 24) {
                    Button { kg -= units == .metric ? 0.1 : 0.4536 } label: { Image(systemName: "minus.circle.fill").font(.largeTitle) }
                    Button { kg += units == .metric ? 0.1 : 0.4536 } label: { Image(systemName: "plus.circle.fill").font(.largeTitle) }
                }
                .foregroundStyle(.cyan)
                Text(HealthKitService.shared.isAuthorized ? "Saved to Apple Health too." : "Saved on this iPhone.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button("Save weight") { health.logWeight(kg: (kg * 10).rounded() / 10); haptic(.medium); dismiss() }
                    .buttonStyle(LumenPrimaryButtonStyle())
            }
            .padding(24)
            .background(AuroraBackground())
            .navigationTitle("Log weight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { kg = health.goals.weightKg ?? 72 }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Strava setup

struct StravaSetupSheet: View {
    @ObservedObject var strava = StravaService.shared
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @State private var clientID = ""
    @State private var secret = ""
    var body: some View {
        NavigationStack {
            Form {
                if strava.isConnected {
                    Section {
                        LabeledContent("Status", value: strava.status)
                        Button("Sync activities") { Task { await health.syncAll() } }
                        Button("Disconnect", role: .destructive) { strava.disconnect() }
                    }
                } else {
                    Section {
                        TextField("Client ID", text: $clientID).keyboardType(.numberPad)
                        SecureField("Client secret", text: $secret)
                        Button("Connect Strava") {
                            strava.clientID = clientID; strava.clientSecret = secret
                            Task { await strava.connect() }
                        }
                        .disabled(clientID.isEmpty || secret.isEmpty)
                    } header: {
                        Text("Your Strava API app")
                    } footer: {
                        Text("Create a free app at strava.com/settings/api and set the Authorization Callback Domain to “strava-callback”. Credentials stay in this iPhone's Keychain.\n\n\(strava.status)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Strava").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { clientID = strava.clientID; secret = strava.clientSecret }
        }
    }
}

// MARK: - Coach AI setup

struct CoachSetupSheet: View {
    @ObservedObject var llm = LLMConnectionService.shared
    @Environment(\.dismiss) var dismiss
    @State private var llmKey = ""
    @State private var googleID = ""
    @State private var oauthEndpoint = ""
    @State private var keyPreset: LLMConnectionService.Preset = .openAI

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Brain", selection: $llm.mode) {
                        ForEach(LLMConnectionService.Mode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: llm.mode) { _, m in llm.setMode(m) }
                } footer: {
                    Text(llm.mode == .onDevice ? "Runs fully on this iPhone with your real data — private and free." : llm.status)
                }

                if llm.mode == .key {
                    Section {
                        Picker("Provider", selection: $keyPreset) {
                            ForEach(LLMConnectionService.Preset.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .onChange(of: keyPreset) { _, p in llm.applyPreset(p); llmKey = llm.apiKey }
                        SecureField("API key", text: $llmKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: llmKey) { _, v in llm.apiKey = v }
                        LabeledContent("Model", value: llm.model)
                    } footer: {
                        Text("Stored in the Keychain and only ever sent to \(URL(string: llm.endpoint)?.host ?? "your provider").")
                    }
                }

                if llm.mode == .oauth {
                    Section {
                        TextField("Google Client ID", text: $googleID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: googleID) { _, v in llm.googleClientID = v }
                        TextField("OpenAI-compatible endpoint", text: $oauthEndpoint)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: oauthEndpoint) { _, v in llm.oauthEndpoint = v }
                        if llm.isOAuthConnected {
                            Button("Sign out", role: .destructive) { llm.disconnectOAuth() }
                        } else {
                            Button("Connect with Google") { llm.connectGoogle() }
                        }
                    } footer: {
                        Text("Register lumen://oauth-callback as a redirect URI on your OAuth client. PKCE; tokens stay on-device.")
                    }
                }

                if llm.mode != .onDevice {
                    Section {
                        Button {
                            Task { await llm.runTest() }
                        } label: {
                            HStack { Text("Test connection"); Spacer(); if llm.isBusy { ProgressView() } }
                        }
                        .disabled(llm.isBusy || !LLMClient.isConfigured())
                        if let result = llm.lastTestResult { Text(result).font(.caption) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Coach brain").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                llmKey = llm.apiKey; googleID = llm.googleClientID
                oauthEndpoint = llm.oauthEndpoint; keyPreset = llm.currentPreset
            }
        }
    }
}

// MARK: - How it works

struct ScienceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                item("moon.fill", "Personal sleep need", "Estimated from your longest, most natural nights — not a one-size-fits-all 8 hours.")
                item("chart.bar.fill", "14-night sleep debt", "What you needed versus what you got over two weeks, recent nights weighted more (last night ≈ 15%).")
                item("waveform.path.ecg", "Circadian energy", "A two-process model of sleep pressure and your body clock predicts peaks, dips and the melatonin window.")
                item("gauge.with.dots.needle.67percent", "Readiness", "Sleep debt, resting heart rate and HRV combine into a 0–100 score that sets today's training target.")
                item("fork.knife", "Fuel", "Mifflin-St Jeor energy needs × activity, protein-first targets scaled to your weight and goal.")
                Text("Lumen offers wellness guidance, not medical advice.").font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .padding(20)
        }
        .background(AuroraBackground())
        .navigationTitle("How Lumen works")
    }
    func item(_ icon: String, _ title: String, _ body: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(.cyan).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(body).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
        }
    }
}
