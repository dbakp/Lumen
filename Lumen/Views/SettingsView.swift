import SwiftUI
import UIKit

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
    @State private var eraseFailed = false
    @State private var eraseFailureMessage = ""
    @State private var confirmHealthDeviceSetup = false
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
        #if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .bottom) { HealthImportReadUIProbe() }
        .overlay(alignment: .bottom) { HealthLegacyResetUIProbe() }
        #endif
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
                Text("Your profile, logs and settings are removed from this iPhone and you'll start fresh. Apple Health data stays there, apart from removals you've already requested.")
            }
            .alert("Couldn't erase Lumen", isPresented: $eraseFailed) {
                Button("Retry erasure", role: .destructive) { eraseAll() }
                Button("Not now", role: .cancel) { }
            } message: {
                Text(eraseFailureMessage)
            }
            .confirmationDialog("Start new Health updates here?", isPresented: $confirmHealthDeviceSetup, titleVisibility: .visible) {
                Button("Start new updates") { startHealthDeviceSetup() }
            } message: {
                Text("The old pending updates won't be sent. Your saved entries stay here. Only new changes will be queued for Apple Health.")
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
                    Text(hk.isAuthorized ? (health.lastSync.map { "Checked \($0.formatted(.relative(presentation: .named)))" } ?? "Access requested") : "Not connected")
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
            if let status = health.healthWriteStatus {
                VStack(alignment: .leading, spacing: 8) {
                    Text(status).font(.footnote).accessibilityIdentifier("healthWriteStatus")
                    if health.healthWriteNeedsDeviceSetup {
                        Button("Start Health updates on this iPhone") { confirmHealthDeviceSetup = true }
                            .accessibilityIdentifier("startHealthWritesOnThisDevice")
                    } else {
                        Button("Retry Apple Health updates") { health.retryHealthWrites() }
                            .accessibilityIdentifier("retryHealthWrites")
                    }
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

    func startHealthDeviceSetup() {
        do { try health.startHealthWritesOnThisDeviceChecked() }
        catch { settingsFailure = .init("Apple Health updates", error: error, retry: startHealthDeviceSetup) }
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
            NavigationLink("Recover health data") { HealthRecoveryView() }.accessibilityIdentifier("healthRecoverySettings")
            NavigationLink { ReadableExportView() } label: {
                Label("Export my data", systemImage: "square.and.arrow.up")
            }.accessibilityIdentifier("readableExportSettings")
            Button(role: .destructive) { confirmErase = true } label: {
                Label("Erase all data", systemImage: "trash")
            }.accessibilityIdentifier("eraseAllLumenData")
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
        do {
            try AccountReset.eraseAll(health: health, sleep: sleep)
            #if DEBUG && targetEnvironment(simulator)
            ProviderConnectionUIFixture.capture(dirty: false)
            #endif
            dismiss()
        } catch {
            eraseFailureMessage = error is SecureStore.Failure
                ? "Credentials couldn't be removed. Your profile and logs are still here. AI connections are paused until removal finishes."
                : "Local data couldn't be erased. Your saved profile and logs haven't been replaced. Retry to finish erasure."
            eraseFailed = true
            #if DEBUG && targetEnvironment(simulator)
            ProviderConnectionUIFixture.capture(dirty: false)
            #endif
        }
    }
}

/// Credentials are the first destructive phase. A failed Keychain removal must
/// retain both the durable removal intent and all local records/defaults.
@MainActor enum AccountReset {
    static func eraseAll(health: HealthStore, sleep: SleepStore) throws {
        try SecureStore.eraseAllChecked()
        #if DEBUG && targetEnvironment(simulator)
        try AccountResetNativeFixture.interruptAfterCredentialsIfArmed()
        #endif
        try LocalStore.eraseAllChecked()
        HealthBackgroundSync.shared.resetUserState()
        HealthKitService.shared.disconnectLocally()
        SemanticSearchService.shared.removeModel()
        StravaService.shared.disconnect()
        UNUserNotificationCenterBridge.removeAll()
        health.resetAll()
        sleep.resetAll()
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
                Text(HealthKitService.shared.isAuthorized ? "Save on this iPhone, then update Apple Health. Retry pending updates in Settings." : "Save on this iPhone.")
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

/// Literal identifiers must wrap without inserting typographic hyphens.
/// UIKit owns editing and selection; the sheet still owns its detached draft.
private struct ConnectionLiteralInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let label: String
    let identifier: String
    let keyboardType: UIKeyboardType
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var contentSizeCategory: UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byCharWrapping
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.tintColor = UIColor(Theme.accent)
        let selectAll = UIBarButtonItem(title: "Select all", style: .plain, target: context.coordinator, action: #selector(Coordinator.selectAllText))
        selectAll.accessibilityIdentifier = "selectAllConnectionText"
        context.coordinator.selectAllButton = selectAll
        toolbar.items = [
            selectAll,
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Done", style: .plain, target: context.coordinator, action: #selector(Coordinator.finishEditing))
        ]
        view.inputAccessoryView = toolbar
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.accessibilityLabel = label
        view.accessibilityIdentifier = identifier
        context.coordinator.selectAllButton?.isEnabled = !text.isEmpty
        if view.isEditable != context.environment.isEnabled { view.isEditable = context.environment.isEnabled }
        if view.keyboardType != keyboardType { view.keyboardType = keyboardType }
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.hyphenationFactor = 0
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
        let fontChanged = view.font != font
        let textChanged = view.text != text
        if textChanged {
            let selection = view.selectedRange
            view.attributedText = NSAttributedString(string: text, attributes: attributes)
            let location = min(selection.location, view.text.utf16.count)
            view.selectedRange = NSRange(location: location, length: min(selection.length, view.text.utf16.count - location))
        } else if fontChanged {
            view.textStorage.addAttributes(attributes, range: NSRange(location: 0, length: view.text.utf16.count))
        }
        if fontChanged { view.font = font }
        if textChanged || fontChanged {
            view.textColor = .label
            view.typingAttributes = attributes
        }
        if isFocused && view.isEditable && !view.isFirstResponder && view.window != nil { view.becomeFirstResponder() }
        if !isFocused && view.isFirstResponder { view.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(44, size.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ConnectionLiteralInput
        weak var view: UITextView?
        weak var selectAllButton: UIBarButtonItem?
        init(_ parent: ConnectionLiteralInput) { self.parent = parent }
        @objc func selectAllText() { view?.selectAll(nil) }
        @objc func finishEditing() {
            parent.isFocused = false
            view?.resignFirstResponder()
        }
        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            view.invalidateIntrinsicContentSize()
        }
        func textViewDidBeginEditing(_ view: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }
        func textViewDidEndEditing(_ view: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}

struct CoachSetupSheet: View {
    @ObservedObject var ai = AIService.shared
    @ObservedObject var llm = LLMConnectionService.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft = ProviderConnectionStore.Record()
    @State private var baseline: ProviderConnectionStore.Record?
    @State private var expected: LLMConnectionService.Configuration?
    @State private var loaded = false
    @State private var appeared = false
    @State private var issue: String?
    @State private var stale = false
    @State private var retrySave = false
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    private enum Confirmation: String, Identifiable { case discard, reload, remove; var id: String { rawValue } }
    @State private var confirmation: Confirmation?
    private enum Input: Hashable { case endpoint, model, key, client, scope, oauthEndpoint, oauthModel }
    @FocusState private var focused: Input?
    @State private var literalFocused: Input?

    private var dirty: Bool { loaded && draft != baseline }
    private var cleanupPending: Bool { (try? llm.connectionDraft())?.legacyCleanupPending == true }
    private var removalPending: Bool { SecureStore.erasurePending || OAuthCredentialStore.removalPending || ProviderConnectionStore.removalPending }
    private var canUseSaved: Bool { loaded && !dirty && !retrySave && !stale && !cleanupPending && !testing && !llm.isAuthorizing }

    var body: some View {
        NavigationStack {
            ScrollViewReader { position in
            Form {
                Section {
                    Text(llm.mode.label).font(.headline)
                    if llm.mode != .onDevice {
                        Text(verbatim: llm.providerLabel).textSelection(.enabled).accessibilityIdentifier("savedAIOrigin")
                    }
                    if issue == nil && !cleanupPending { Text(verbatim: llm.status).font(.footnote).accessibilityIdentifier("savedAIStatus") }
                    if cleanupPending {
                        Text("Connection saved; cleanup pending").foregroundStyle(Theme.accent).accessibilityIdentifier("aiCleanupPending")
                        Button("Retry cleanup") { save() }.disabled(dirty || stale || testing || llm.isAuthorizing).accessibilityIdentifier("retryAIConnectionCleanup")
                    }
                    if dirty { Text("Changes not saved").foregroundStyle(Theme.accent).accessibilityIdentifier("aiConnectionDirty") }
                } header: { Text("Saved connection") }

                if let issue {
                    Section {
                        Text(verbatim: issue).accessibilityIdentifier("aiConnectionIssue")
                        Button("Reload saved connection") { finishInputs(); if dirty || retrySave { confirmation = .reload } else { load() } }
                            .accessibilityIdentifier("reloadAIConnection")
                    }
                }
                if removalPending {
                    Section {
                        Button("Retry removal") { removeCredentials() }.accessibilityIdentifier("retryAICredentialRemoval")
                    } footer: { Text("Retries the pending device credential removal.") }
                }
                if loaded {
                    Section {
                        if dynamicTypeSize.isAccessibilitySize {
                            Menu {
                                Picker("Connection", selection: $draft.mode) {
                                    ForEach(LLMConnectionService.Mode.allCases, id: \.rawValue) { mode in Text(mode.label).tag(mode.rawValue) }
                                }
                            } label: {
                                connectionChoiceLabel("Connection", value: LLMConnectionService.Mode(rawValue: draft.mode)?.label ?? draft.mode)
                            }
                            .accessibilityLabel("Connection")
                            .accessibilityValue(LLMConnectionService.Mode(rawValue: draft.mode)?.label ?? draft.mode)
                            .accessibilityIdentifier("aiConnectionMode")
                        } else {
                            Picker("Connection", selection: $draft.mode) {
                                ForEach(LLMConnectionService.Mode.allCases, id: \.rawValue) { mode in Text(mode.label).tag(mode.rawValue) }
                            }.accessibilityIdentifier("aiConnectionMode")
                        }
                        if draft.mode == "onDevice" {
                            Text("Uses available Apple Intelligence or built-in coaching. Saved external credentials stay on this device until you remove them.").font(.footnote)
                        } else {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Prefer this connection").lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                    HStack {
                                        Spacer()
                                        Toggle("Prefer this connection", isOn: $draft.preferExternal).labelsHidden()
                                            .accessibilityLabel("Prefer this connection").accessibilityIdentifier("preferAIConnection")
                                    }
                                }
                            } else {
                                Toggle("Prefer this connection", isOn: $draft.preferExternal).accessibilityIdentifier("preferAIConnection")
                            }
                        }
                    }

                    if draft.mode == "key" {
                        Section {
                            if dynamicTypeSize.isAccessibilitySize {
                                Menu {
                                    Picker("Provider", selection: Binding(get: { draft.preset }, set: choosePreset)) {
                                        ForEach(LLMConnectionService.Preset.allCases, id: \.rawValue) { preset in Text(preset.label).tag(preset.rawValue) }
                                    }
                                } label: {
                                    connectionChoiceLabel("Provider", value: LLMConnectionService.Preset(rawValue: draft.preset)?.label ?? draft.preset)
                                }
                                .accessibilityLabel("Provider")
                                .accessibilityValue(LLMConnectionService.Preset(rawValue: draft.preset)?.label ?? draft.preset)
                                .accessibilityIdentifier("aiConnectionPreset")
                            } else {
                                Picker("Provider", selection: Binding(get: { draft.preset }, set: choosePreset)) {
                                    ForEach(LLMConnectionService.Preset.allCases, id: \.rawValue) { preset in Text(preset.label).tag(preset.rawValue) }
                                }.accessibilityIdentifier("aiConnectionPreset")
                            }
                            field("Endpoint", text: $draft.endpoint, input: .endpoint, identifier: "aiEndpoint", url: true)
                            field("Model", text: $draft.model, input: .model, identifier: "aiModel")
                            VStack(alignment: .leading, spacing: 6) {
                                Text("API key").font(.caption).foregroundStyle(.secondary)
                                SecureField("API key", text: Binding(get: { draft.apiKey ?? "" }, set: { draft.apiKey = $0.isEmpty ? nil : $0 }))
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .key).accessibilityIdentifier("aiAPIKey")
                            }.padding(.vertical, 3)
                            if ["gpt-4o-mini", "gpt-4.1-mini", "gemini-2.0-flash"].contains(draft.model) {
                                Text("This saved model is deprecated. Check the models available in your provider account.").font(.footnote)
                            }
                            Link("OpenAI models", destination: URL(string: "https://developers.openai.com/api/docs/models")!)
                            Link("Google AI Studio models", destination: URL(string: "https://aistudio.google.com/docs/models")!)
                        } header: { Text("API connection draft") } footer: {
                            Text("The key stays in Keychain. Requests go to the saved endpoint.")
                        }
                    }
                    if draft.mode == "oauth" {
                        Section {
                            field("iOS client ID", text: $draft.clientID, input: .client, identifier: "aiGoogleClient")
                            field("Requested scopes", text: $draft.scope, input: .scope, identifier: "aiGoogleScopes")
                            field("Endpoint", text: $draft.oauthEndpoint, input: .oauthEndpoint, identifier: "aiOAuthEndpoint", url: true)
                            field("Model", text: $draft.oauthModel, input: .oauthModel, identifier: "aiOAuthModel")
                            Button(llm.isOAuthConnected ? "Sign in again" : "Sign in with Google") {
                                finishInputs(); llm.connectGoogle(); load()
                            }.disabled(!canUseSaved || llm.mode != .oauth).accessibilityIdentifier("connectGoogleAI")
                        } header: { Text("Google connection draft") } footer: {
                            Text("Use an iOS client configured for this app. The endpoint must accept that client's tokens and requested scopes. Google sign-in alone doesn't grant access to every AI service.")
                        }
                    }
                    if draft.mode != "onDevice" {
                        Section {
                            Button {
                                finishInputs(); testing = true
                                let original = llm.configuration()
                                testTask = Task { await llm.runTest(expectedConfiguration: original); testing = false; testTask = nil }
                            } label: { HStack { Text("Test connection"); Spacer(); if testing { ProgressView() } } }
                                .disabled(!canUseSaved || !LLMClient.isConfigured()).accessibilityIdentifier("testSavedAIConnection")
                            if let result = llm.lastTestResult { Text(verbatim: result).font(.footnote).accessibilityIdentifier("aiConnectionTestResult") }
                        } footer: {
                            Text("Requests can include health summaries, selected messages, shared notes and Library excerpts, depending on the feature. Photo requests also depend on your provider and model.")
                        }
                    }
                }
                Section {
                    Button("Remove AI credentials", role: .destructive) { finishInputs(); confirmation = .remove }
                        .disabled(testing || llm.isAuthorizing || SecureStore.erasurePending).accessibilityIdentifier("removeAICredentials")
                }
                Section {
                    Text(ai.brain.label).font(.headline)
                    Text(ai.brain.detail).font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Photo recognition", value: ai.canSeePhotos ? "Available to try" : "Not available")
                } header: { Text("Available assistant") }
            }
            .disabled(llm.isAuthorizing)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("AI connection").navigationBarTitleDisplayMode(.inline)
            .onChange(of: literalFocused) { _, input in
                if let input { withAnimation { position.scrollTo(input, anchor: .center) } }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                if let input = literalFocused { withAnimation { position.scrollTo(input, anchor: .center) } }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { finishInputs(); if dirty || retrySave { confirmation = .discard } else { dismiss() } }.accessibilityIdentifier("closeAIConnection")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!loaded || stale || (!dirty && !retrySave) || (cleanupPending && !dirty) || testing || llm.isAuthorizing)
                        .accessibilityIdentifier("saveAIConnection")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { finishInputs() } }
            }
            .alert(item: $confirmation) { value in
                switch value {
                case .discard:
                    return Alert(title: Text("Discard connection edits?"), message: Text("Edits in this form will be discarded."), primaryButton: .destructive(Text("Discard"), action: { dismiss() }), secondaryButton: .cancel(Text("Keep draft")))
                case .reload:
                    return Alert(title: Text("Reload saved connection?"), message: Text("Edits in this form will be discarded."), primaryButton: .destructive(Text("Reload"), action: load), secondaryButton: .cancel(Text("Keep draft")))
                case .remove:
                    return Alert(title: Text("Remove AI credentials?"), message: Text("Removes the saved API key and Google tokens from this device. Your health records stay here." + (dirty || retrySave ? " Edits in this form will also be discarded." : "")), primaryButton: .destructive(Text("Remove"), action: removeCredentials), secondaryButton: .cancel())
                }
            }
            .onAppear { if !appeared { appeared = true; load() } }
            #if DEBUG && targetEnvironment(simulator)
            .onChange(of: draft) { _, _ in
                ProviderConnectionUIFixture.capture(dirty: dirty)
                ProviderConnectionUIFixture.changeSavedConnectionIfRequested(dirty: dirty)
            }
            .onChange(of: issue) { _, _ in ProviderConnectionUIFixture.capture(dirty: dirty) }
            .onChange(of: llm.lastTestResult) { _, _ in ProviderConnectionUIFixture.capture(dirty: dirty) }
            #endif
            .onDisappear { testTask?.cancel(); testTask = nil; testing = false }
            }
        }
        .interactiveDismissDisabled(dirty || retrySave)
        .tint(Theme.accent)
    }

    private func connectionChoiceLabel(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundStyle(.primary).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text(value).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.caption).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ label: String, text: Binding<String>, input: Input, identifier: String, url: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ConnectionLiteralInput(text: text, isFocused: Binding(
                get: { literalFocused == input },
                set: { active in if active { literalFocused = input } else if literalFocused == input { literalFocused = nil } }
            ), label: label, identifier: identifier, keyboardType: url ? .URL : .default)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { literalFocused = input })
        .id(input)
    }
    private func choosePreset(_ raw: String) {
        guard let preset = LLMConnectionService.Preset(rawValue: raw) else { return }
        draft.preset = raw
        if preset != .custom { draft.endpoint = preset.endpoint; draft.model = preset.defaultModel }
    }
    private func finishInputs() { focused = nil; literalFocused = nil }
    private func load() {
        do {
            let saved = try llm.connectionDraft(), configuration = llm.configuration()
            guard saved.id == configuration.connectionID else { throw ProviderConnectionStore.Failure.corrupt }
            draft = saved; baseline = saved; expected = configuration
            loaded = true; issue = nil; stale = false; retrySave = false
        } catch { loaded = false; issue = error.localizedDescription }
    }
    private func save() {
        finishInputs()
        guard let expected else { return }
        do { try llm.saveConnectionChecked(draft, expected: expected); load(); AppRouter.shared.confirm("AI connection saved") }
        catch ProviderConnectionStore.Failure.changed { stale = true; issue = ProviderConnectionStore.Failure.changed.localizedDescription }
        catch {
            self.expected = llm.configuration(); issue = error.localizedDescription; retrySave = true
            if let saved = try? llm.connectionDraft(), saved.legacyCleanupPending {
                var committed = draft; committed.id = saved.id; committed.legacyCleanupPending = true
                if committed == saved {
                    baseline = saved; draft = saved
                    issue = "Your connection was saved, but old credential cleanup couldn't finish. Retry cleanup before sending."
                }
            }
        }
    }
    private func removeCredentials() {
        finishInputs()
        do { try llm.removeAICredentialsChecked(); load(); AppRouter.shared.confirm("AI credentials removed") }
        catch { issue = "AI credentials couldn't be fully removed. Retry removal."; loaded = false; retrySave = false }
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
