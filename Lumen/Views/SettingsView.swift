import SwiftUI

// MARK: - Settings: profile, body, goals, sleep, connections, coach, privacy

public struct SettingsView: View {
    @EnvironmentObject var sleep: SleepStore
    @EnvironmentObject var health: HealthStore
    @ObservedObject private var hk = HealthKitService.shared
    @ObservedObject private var strava = StravaService.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var companion = CompanionStore.shared
    @ObservedObject private var llm = LLMConnectionService.shared
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lumen.appearance") private var appearance = "light"
    @State private var confirmErase = false
    @State private var confirmClearConversation = false
    @State private var showWeightLog = false
    @State private var showCoachSetup = false
    @State private var showStravaSetup = false
    @State private var syncing = false
    @State private var settingsFailure: SettingsSaveFailure?
    @State private var savingProfilePair = false
    @State private var nameDraft = ""
    @State private var nameReady = false
    @State private var reminderOwner = UUID()

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var nameDirty: Bool { nameReady && nameDraft != sleep.profile.name }

    public var body: some View {
        NavigationStack {
            Form {
                profileHeader
                Section { NavigationLink("Personal context") { PersonalContextView() } }
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Light").tag("light"); Text("Dark").tag("dark"); Text("System").tag("system")
                    }
                }
                bodySection
                goalsSection
                sleepSection
                Section { NavigationLink("Health imports & contextual reminders") { ConnectionsView() } }
                connectionsSection
                coachSection
                privacySection
                aboutSection
            }
            .disabled(savingProfilePair)
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { saveName(close: true) }.fontWeight(.semibold).disabled(savingProfilePair) }
                ToolbarItem(placement: .topBarTrailing) {
                    if savingProfilePair { ProgressView().accessibilityLabel("Saving birth year") }
                }
            }
            .sheet(isPresented: $showWeightLog) { WeightLogSheet() }
            .sheet(isPresented: $showCoachSetup) { CoachSetupSheet() }
            .sheet(isPresented: $showStravaSetup) { StravaSetupSheet() }
            .confirmationDialog("Erase all Lumen data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { eraseAll() }
            } message: {
                Text("Your profile, logs and settings are removed from this iPhone and you'll start fresh. Data in Apple Health isn't touched.")
            }
            .sheet(isPresented: $confirmClearConversation) {
                ConversationRemovalSheet(action: "Clear", scope: "Messages and any unsaved reply in this conversation will be removed.",
                                         failureTitle: "Couldn’t clear chat",
                                         failureMessage: "Your saved messages are unchanged. Try clearing again.") {
                    try await health.clearConversationChecked()
                }
            }
            .task { await notifications.refreshAuthorization() }
            .onAppear { if !nameReady { nameDraft = sleep.profile.name; nameReady = true } }
            .onDisappear { companion.cancelReminderEnable(owner: reminderOwner) }
            .onChange(of: sleep.profile.name) { old, new in if nameDraft == old { nameDraft = new } }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(savingProfilePair || nameDirty)
        .settingsSaveAlert($settingsFailure)
    }

    // MARK: Profile

    var profileHeader: some View {
        Section {
            Group {
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) { profileAvatar; profileDetails }
                } else {
                    HStack(spacing: 14) { profileAvatar; profileDetails }
                }
            }
            .padding(.vertical, 4)
        }
    }

    var profileAvatar: some View {
        Text(String(sleep.profile.name.prefix(1)).uppercased())
            .font(.title.weight(.bold)).foregroundStyle(Theme.text)
            .frame(width: 60, height: 60)
            .background(Theme.surfaceRaised, in: Circle())
    }

    var profileDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField("Name", text: $nameDraft)
                .font(.title3.weight(.bold))
                .onSubmit { saveName() }
                .accessibilityIdentifier("settingsNameDraft")
            if nameDirty {
                Text("Name not saved").font(.footnote).foregroundStyle(Theme.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { nameActions }
                    VStack(alignment: .leading, spacing: 4) { nameActions }
                }
            }
            if let created = sleep.profile.createdAt {
                Text("Member since \(created.formatted(.dateTime.month(.wide).year()))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Body

    var bodySection: some View {
        Section("Body") {
            Picker("Units", selection: Binding(get: { units }, set: { value in profileSetting("units") { $0.units = value } })) {
                ForEach(UnitSystem.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            SettingsPicker("Sex", value: health.goals.sex == .female ? "Female" : health.goals.sex == .male ? "Male" : "Not specified",
                selection: goalBinding(\.sex, "sex"), identifier: "settingsSex") {
                Text("Female").tag(HealthGoals.Sex.female)
                Text("Male").tag(HealthGoals.Sex.male)
                Text("Not specified").tag(HealthGoals.Sex.unspecified)
            }
            SettingsPicker("Birth year", value: sleep.profile.birthYear.map { String($0) } ?? "Not recorded",
                selection: Binding<Int?>(get: { sleep.profile.birthYear }, set: { saveBirthYear($0) }), identifier: "settingsBirthYear") {
                Text("Not recorded").tag(Int?.none)
                ForEach((1930...(currentYear - 13)).reversed(), id: \.self) { Text(String($0)).tag(Optional($0)) }
            }
            SettingsStepper("Height", value: Units.height(health.goals.heightCm ?? 172, units),
                selection: Binding(get: { health.goals.heightCm ?? 172 }, set: { value in goalSetting("height") { $0.heightCm = value } }),
                in: 120...220, step: 1, identifier: "settingsHeight")
            Button { showWeightLog = true } label: {
                SettingsValueRow("Weight", value: health.goals.weightKg.map { Units.weight($0, units) } ?? "Add")
            }
            .foregroundStyle(.primary)
        }
    }

    func goalBinding<T>(_ kp: WritableKeyPath<HealthGoals, T>, _ label: String) -> Binding<T> {
        Binding(get: { health.goals[keyPath: kp] }, set: { value in goalSetting(label) { $0[keyPath: kp] = value } })
    }

    @ViewBuilder var nameActions: some View {
        Button("Save name") { saveName() }.buttonStyle(.borderless).frame(minHeight: 44)
        Button("Discard") { nameDraft = sleep.profile.name }.buttonStyle(.borderless).frame(minHeight: 44)
    }

    func saveName(close: Bool = false) {
        guard nameDirty else { if close { dismiss() }; return }
        do {
            let value = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            try sleep.updateProfileChecked { $0.name = value }
            nameDraft = sleep.profile.name
            if close { dismiss() }
        } catch { settingsFailure = .init("name", error: error, retainedDraft: true, retry: { saveName(close: close) }) }
    }

    func goalSetting(_ label: String, _ change: @escaping (inout HealthGoals) -> Void) {
        do { try health.updateGoalsChecked(change) }
        catch { settingsFailure = .init(label, error: error, retry: { goalSetting(label, change) }) }
    }

    func profileSetting(_ label: String, _ change: @escaping (inout UserProfile) -> Void) {
        do {
            try sleep.updateProfileChecked(change)
            SyncCoordinator.propagate(sleep: sleep, health: health)
        } catch { settingsFailure = .init(label, error: error, retry: { profileSetting(label, change) }) }
    }

    func saveBirthYear(_ year: Int?) {
        guard !savingProfilePair else { return }
        savingProfilePair = true
        Task {
            do { try await ProfileSettingsCommit.birthYear(year, sleep: sleep, health: health) }
            catch { settingsFailure = .init("birth year", error: error, retry: { saveBirthYear(year) }) }
            savingProfilePair = false
        }
    }

    // MARK: Goals

    var goalsSection: some View {
        Section {
            Picker("Focus", selection: goalBinding(\.goal, "focus")) {
                ForEach(HealthGoals.BodyGoal.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Activity level", selection: goalBinding(\.activityLevel, "activity level")) {
                ForEach(HealthGoals.ActivityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            SettingsStepper("Move goal", value: "\(Int(health.goals.activeCalGoal)) kcal", selection: goalBinding(\.activeCalGoal, "move goal"),
                in: 150...1500, step: 25, identifier: "settingsMoveGoal")
            SettingsStepper("Exercise goal", value: "\(Int(health.goals.exerciseGoalMin)) min", selection: goalBinding(\.exerciseGoalMin, "exercise goal"),
                in: 10...120, step: 5, identifier: "settingsExerciseGoal")
            SettingsStepper("Step goal", value: Int(health.goals.stepGoal).formatted(), selection: goalBinding(\.stepGoal, "step goal"),
                in: 2000...30000, step: 500, identifier: "settingsStepGoal")
            SettingsValueRow("Calories", value: "\(health.goals.calorieTarget()) kcal / day")
                .accessibilityIdentifier("settingsCalorieTarget")
            SettingsValueRow("Protein", value: "\(health.goals.proteinTarget()) g / day")
        } header: {
            Text("Goals")
        } footer: {
            Text("Targets are estimates from your settings. Missing values use defaults.")
        }
    }

    // MARK: Sleep

    var sleepSection: some View {
        Section {
            SettingsStepper("Sleep need", value: SleepFormat.durationHM(sleep.profile.sleepNeed),
                selection: Binding(get: { sleep.profile.sleepNeed }, set: { value in profileSetting("sleep need") { $0.sleepNeed = value } }),
                in: 5 * 3600...11.5 * 3600, step: 300, identifier: "settingsSleepNeed")
            Picker("Body clock", selection: Binding(get: { sleep.profile.chronotype }, set: { value in profileSetting("body clock") { $0.chronotype = value } })) {
                ForEach(Chronotype.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            DatePicker("Wake goal", selection: Binding(
                get: { sleep.wakeGoalToday },
                set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    profileSetting("wake goal") { $0.wakeGoal.hour = c.hour; $0.wakeGoal.minute = c.minute }
                }), displayedComponents: .hourAndMinute)
        } header: {
            Text("Sleep")
        } footer: {
            Text("Lumen fine-tunes your sleep need automatically from the nights it sees.")
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
                    .buttonStyle(.borderedProminent).controlSize(.small).foregroundStyle(.black)
                }
            }
            HStack {
                connectionIcon("bell.fill", .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminders")
                    Text(companion.requestingReminderAccess ? "Requesting access…" : notifications.authorized && companion.reminders.enabled ? "Contextual check-ins" : "Off").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if notifications.authorized && companion.reminders.enabled {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Turn on") {
                        enableReminders()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(companion.requestingReminderAccess).accessibilityIdentifier("settingsEnableReminders")
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
    func enableReminders() {
        Task {
            do {
                if try await companion.enableReminders(owner: reminderOwner) == .denied,
                   let url = URL(string: UIApplication.openNotificationSettingsURLString) { await UIApplication.shared.open(url) }
            } catch { settingsFailure = .init("reminders", error: error, retry: enableReminders) }
        }
    }

    func connectionIcon(_ name: String, _ tint: Color) -> some View {
        Image(systemName: name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            .frame(width: 30, height: 30).background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Coach

    var coachSection: some View {
        Section {
            Button { showCoachSetup = true } label: {
                HStack {
                    connectionIcon("sparkles", .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI").foregroundStyle(.primary)
                        Text(AIService.shared.brain.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            NavigationLink { LibrarySearchSettingsView() } label: {
                Label("Library search", systemImage: "text.magnifyingglass")
            }.accessibilityIdentifier("librarySearchSettings")
            if !health.chat.isEmpty {
                Button("Clear coach conversation", role: .destructive) { confirmClearConversation = true }
                    .disabled(health.isConversationSaving || !health.conversationReady)
            }
        } header: {
            Text("Coach")
        } footer: {
            Text("The assistant uses the provider shown above. With a cloud provider, your current health summary and any shared record excerpts are sent with your question. Use the built-in guide or on-device model to keep processing local.")
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
                            if ok { profileSetting("app lock") { $0.appLock = on } }
                        }
                    }))
            }
            NavigationLink("Backup & restore") { BackupView() }.accessibilityIdentifier("backupSettings")
            NavigationLink { ReadableExportView() } label: {
                Label("Export my data", systemImage: "square.and.arrow.up")
            }.accessibilityIdentifier("readableExportSettings")
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
            NavigationLink("Open-source licenses") { OpenSourceLicensesView() }
            LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
        } footer: {
            Text("Lumen offers wellness guidance, not medical advice. If you suspect a sleep or health condition, talk to a clinician.")
        }
    }

    func eraseAll() {
        HealthBackgroundSync.shared.resetUserState()
        HealthKitService.shared.disconnectLocally()
        LocalStore.eraseAll()
        SemanticSearchService.shared.removeModel()
        SecureStore.eraseAll()
        StravaService.shared.disconnect()
        UNUserNotificationCenterBridge.removeAll()
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
    @State private var saving = false
    @State private var saveFailure: LocalSaveFailure?
    var units: UnitSystem { sleep.profile.unitSystem }
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 24) {
                Text(Units.weight(kg, units)).font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                    .accessibilityIdentifier("weightDraftValue")
                    .contentTransition(.numericText()).foregroundStyle(Theme.text)
                Slider(value: $kg, in: 35...200, step: units == .metric ? 0.1 : 0.04536).tint(Theme.accent)
                HStack(spacing: 24) {
                    Button { kg -= units == .metric ? 0.1 : 0.4536 } label: { Image(systemName: "minus.circle.fill").font(.largeTitle).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Decrease weight").accessibilityIdentifier("decreaseWeight")
                    Button { kg += units == .metric ? 0.1 : 0.4536 } label: { Image(systemName: "plus.circle.fill").font(.largeTitle).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Increase weight").accessibilityIdentifier("increaseWeight")
                }
                .foregroundStyle(Theme.text)
                Text(HealthKitService.shared.isAuthorized ? "Save on this iPhone, then try Apple Health. Check Health to confirm it was added." : "Save on this iPhone.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }.padding(24) }
            .disabled(saving)
            .safeAreaInset(edge: .bottom) {
                Button(saving ? "Saving…" : "Save weight") {
                    guard !saving else { return }
                    let value = (kg * 10).rounded() / 10
                    saving = true
                    Task {
                        do { try await health.logWeight(kg: value); haptic(.medium); dismiss() }
                        catch { saveFailure = .saving("weight", error: error, draft: true) }
                        saving = false
                    }
                }
                .buttonStyle(LumenPrimaryButtonStyle()).disabled(saving)
                .accessibilityValue(saving ? "Saving" : health.isSyncing ? "Health is syncing" : "Ready to save")
                .padding(.horizontal, 24).padding(.bottom, 8)
            }
            .background(AuroraBackground())
            .navigationTitle("Log weight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
            .onAppear { kg = health.goals.weightKg ?? 72 }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(saving)
        .localSaveAlert($saveFailure)
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

// MARK: - AI setup

struct CoachSetupSheet: View {
    @ObservedObject var ai = AIService.shared
    @ObservedObject var llm = LLMConnectionService.shared
    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: ai.brain.isAI ? "sparkles" : "cpu").font(.title2).foregroundStyle(Theme.calm).frame(width: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ai.brain.label).font(.headline)
                            Text(ai.brain.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    LabeledContent("Photo recognition", value: ai.canSeePhotos ? "On" : "Not available")
                } footer: {
                    if !ai.brain.isAI {
                        Text("To turn it on: iPhone Settings → Apple Intelligence & Siri → Apple Intelligence.")
                    }
                }

                Section {
                    SecureField("sk-…", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: key) { _, v in
                            llm.applyPreset(.openAI)
                            llm.apiKey = v.trimmingCharacters(in: .whitespacesAndNewlines)
                            llm.setMode(v.isEmpty ? .onDevice : .key)
                        }
                    if !key.isEmpty {
                        Toggle("Use OpenAI instead of Apple", isOn: Binding(get: { ai.preferOpenAI }, set: { ai.preferOpenAI = $0 }))
                        Button {
                            testing = true
                            Task { await llm.runTest(); testing = false }
                        } label: { HStack { Text("Test key"); Spacer(); if testing { ProgressView() } } }
                        if let r = llm.lastTestResult { Text(r).font(.footnote) }
                        Button("Remove key", role: .destructive) { key = ""; ai.preferOpenAI = false }
                    }
                    Link("Get an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                } header: {
                    Text("Advanced · your own OpenAI key")
                } footer: {
                    Text("Optional. OpenAI doesn't offer sign-in for other apps yet, so this uses an API key from your OpenAI account. It's stored in the Keychain and only sent to OpenAI.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("AI").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { key = llm.mode == .key ? llm.apiKey : "" }
        }
        .tint(Theme.accent)
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
                Text("Lumen offers wellness guidance, not medical advice.").font(.caption).foregroundStyle(Theme.text.opacity(0.5))
            }
            .padding(20)
        }
        .background(AuroraBackground())
        .navigationTitle("How Lumen works")
    }
    func item(_ icon: String, _ title: String, _ body: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.text).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Theme.text)
                    Text(body).font(.subheadline).foregroundStyle(Theme.text.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
        }
    }
}
