import SwiftUI

// MARK: - First-run onboarding
// Creates the local account, connects Apple Health (and prefills from it),
// captures body + goal + sleep basics, primes reminders, then reveals the plan.

public struct OnboardingView: View {
    @EnvironmentObject var sleep: SleepStore
    @EnvironmentObject var health: HealthStore

    enum Step: Int, CaseIterable { case welcome, name, health, body, goal, sleep, reminders, plan }

    @State private var step: Step = .welcome
    @State private var forward = true

    // Account
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    // Body
    @State private var units: UnitSystem = Locale.current.measurementSystem == .us ? .imperial : .metric
    @State private var sex: HealthGoals.Sex = .unspecified
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 30
    @State private var heightCm: Double = 172
    @State private var weightKg: Double = 72
    // Goal
    @State private var goal: HealthGoals.BodyGoal = .maintain
    @State private var activity: HealthGoals.ActivityLevel = .moderate
    // Sleep
    @State private var chronotype: Chronotype = .intermediate
    @State private var wake = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var needHours: Double = 8.0
    // Health import
    @State private var healthConnecting = false
    @State private var healthConnected = false
    @State private var importedNights: [SleepEpisode] = []
    @State private var prefilled: [String] = []
    // Reminders
    @State private var remindersOn = false
    // Plan reveal
    @State private var revealStage = 0

    public init() {}

    public var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                if step != .welcome && step != .plan { topBar }
                ZStack {
                    content
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: step)
    }

    // MARK: Chrome

    var topBar: some View {
        let total = Step.allCases.count - 2
        let idx = step.rawValue - 1
        return HStack(spacing: 14) {
            Button { go(back: true) } label: {
                Image(systemName: "chevron.left").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).liquidGlass(cornerRadius: 20, tintOpacity: 0.12)
            }
            .accessibilityLabel("Back")
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule().fill(i <= idx ? Color.cyan : .white.opacity(0.15)).frame(height: 4)
                }
            }
            .animation(.spring, value: idx)
            Text("\(idx + 1)/\(total)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    @ViewBuilder var content: some View {
        switch step {
        case .welcome: welcome
        case .name: nameStep
        case .health: healthStep
        case .body: bodyStep
        case .goal: goalStep
        case .sleep: sleepStep
        case .reminders: remindersStep
        case .plan: planStep
        }
    }

    func page<Content: View, Footer: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle).font(.body).foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 24)
                    content()
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            footer().padding(.horizontal, 24).padding(.bottom, 16)
        }
    }

    func continueButton(_ title: String = "Continue", enabled: Bool = true, action: (() -> Void)? = nil) -> some View {
        Button(title) {
            haptic(.medium)
            if let action { action() } else { go() }
        }
        .buttonStyle(LumenPrimaryButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    func go(back: Bool = false) {
        nameFocused = false
        forward = !back
        let next = step.rawValue + (back ? -1 : 1)
        if let s = Step(rawValue: next) { step = s }
    }

    // MARK: 0 · Welcome

    var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            LumenOrb(size: 220)
            Spacer().frame(height: 28)
            Text("LUMEN").font(.caption.weight(.heavy)).foregroundStyle(.cyan).tracking(6)
            Text("Feel your best,\nevery day.")
                .font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .multilineTextAlignment(.center).padding(.top, 10)
            Text("Sleep, energy, movement and fuel — one calm coach built around your body and your rhythm.")
                .font(.body).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                .padding(.horizontal, 32).padding(.top, 12)
            Spacer()
            VStack(spacing: 10) {
                continueButton("Get started")
                Label("Private by design · your data stays on this iPhone", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
    }

    // MARK: 1 · Name (local account)

    var nameStep: some View {
        page(title: "Let's set up your profile", subtitle: "What should Lumen call you?") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("", text: $name, prompt: Text("First name").foregroundStyle(.white.opacity(0.35)))
                    .font(.title2.weight(.semibold)).foregroundStyle(.white)
                    .textContentType(.givenName).textInputAutocapitalization(.words).autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($nameFocused)
                    .onSubmit { if !trimmedName.isEmpty { go() } }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .liquidGlass(cornerRadius: 18, tintOpacity: 0.1)
                Label("No email, no password. Your profile lives only on this device.", systemImage: "iphone.gen3")
                    .font(.footnote).foregroundStyle(.white.opacity(0.55))
            }
        } footer: {
            continueButton(enabled: !trimmedName.isEmpty)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nameFocused = true } }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: 2 · Apple Health

    var healthStep: some View {
        page(title: "Connect Apple Health", subtitle: "Lumen reads your sleep, activity and heart data to personalise everything — and saves the meals and water you log.") {
            VStack(spacing: 12) {
                benefit("bed.double.fill", .indigo, "Sleep & stages", "Nightly sleep, deep and REM from your Watch")
                benefit("flame.fill", .orange, "Activity & workouts", "Steps, active energy, exercise and sessions")
                benefit("heart.fill", .pink, "Recovery signals", "Resting heart rate and HRV shape readiness")
                benefit("scalemass.fill", .teal, "Body basics", "Height, weight and age prefill your plan")
            }
            if healthConnected {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Connected", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
                        Text(importSummary).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.scale.combined(with: .opacity))
            }
        } footer: {
            VStack(spacing: 6) {
                if healthConnected {
                    continueButton()
                } else {
                    Button {
                        Task { await connectHealth() }
                    } label: {
                        HStack(spacing: 8) {
                            if healthConnecting { ProgressView().tint(.black) } else { Image(systemName: "heart.fill") }
                            Text(healthConnecting ? "Reading your data…" : "Connect Apple Health")
                        }
                    }
                    .buttonStyle(LumenPrimaryButtonStyle(colors: [Color(red: 1, green: 0.38, blue: 0.5), Color(red: 1, green: 0.55, blue: 0.4)]))
                    .disabled(healthConnecting)
                    Button("Not now") { go() }.buttonStyle(LumenSecondaryButtonStyle())
                }
            }
        }
    }

    var importSummary: String {
        var parts: [String] = []
        if !importedNights.isEmpty { parts.append("\(importedNights.count) nights of sleep") }
        parts.append(contentsOf: prefilled)
        return parts.isEmpty ? "You're all set — new data will flow in automatically." : "Imported " + parts.joined(separator: ", ") + "."
    }

    func benefit(_ icon: String, _ tint: Color, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.headline).foregroundStyle(tint)
                .frame(width: 42, height: 42).background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(sub).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    func connectHealth() async {
        healthConnecting = true
        defer { healthConnecting = false }
        let hk = HealthKitService.shared
        guard await hk.requestAuthorization() else { return }
        let c = await hk.characteristics()
        var filled: [String] = []
        if let y = c.birthYear { birthYear = y; filled.append("age") }
        if let s = c.sex { sex = s; filled.append("sex") }
        if let h = c.heightCm { heightCm = h; filled.append("height") }
        if let w = c.weightKg { weightKg = w; filled.append("weight") }
        let nights = await hk.fetchSleep(days: HealthKitService.historyDays)
        if nights.count >= 3 {
            let est = SleepNeedEstimator.estimate(episodes: Array(nights.suffix(120)), age: currentYear - birthYear, chronotype: chronotype)
            needHours = (est.need / 3600 * 12).rounded() / 12
            if let wakeSecs = CircadianModel.circularMean(nights.suffix(14).map { CircadianModel.secondsSinceMidnight($0.wakeTime, calendar: .current) }) {
                let rounded = (wakeSecs / 900).rounded() * 900
                wake = Calendar.current.startOfDay(for: Date()).addingTimeInterval(rounded)
            }
        }
        withAnimation(.spring) {
            importedNights = nights
            prefilled = filled
            healthConnected = true
        }
        haptic(.heavy)
    }

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    // MARK: 3 · Body

    var bodyStep: some View {
        page(title: "About your body", subtitle: prefilled.isEmpty ? "Used for calorie, protein and sleep-need estimates." : "Prefilled from Apple Health — adjust anything that's off.") {
            Picker("Units", selection: $units) {
                ForEach(UnitSystem.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            fieldCard("Sex") {
                Picker("Sex", selection: $sex) {
                    Text("Female").tag(HealthGoals.Sex.female)
                    Text("Male").tag(HealthGoals.Sex.male)
                    Text("Prefer not").tag(HealthGoals.Sex.unspecified)
                }
                .pickerStyle(.segmented)
            }
            fieldCard("Birth year", value: "\(birthYear) · \(currentYear - birthYear) yrs") {
                Picker("Birth year", selection: $birthYear) {
                    ForEach((1930...(currentYear - 13)).reversed(), id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.wheel).frame(height: 110).clipped()
            }
            fieldCard("Height", value: Units.height(heightCm, units)) {
                Slider(value: $heightCm, in: 130...215, step: units == .metric ? 1 : 1.27).tint(.cyan)
            }
            fieldCard("Weight", value: Units.weight(weightKg, units, decimals: units == .metric ? 1 : 0)) {
                Slider(value: $weightKg, in: 35...200, step: units == .metric ? 0.5 : 0.4536).tint(.cyan)
            }
        } footer: {
            continueButton()
        }
    }

    func fieldCard<Content: View>(_ label: String, value: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if let value { Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white).contentTransition(.numericText()) }
            }
            content()
        }
        .padding(16)
        .liquidGlass(cornerRadius: 20, tintOpacity: 0.08)
    }

    // MARK: 4 · Goal

    var goalStep: some View {
        page(title: "What's your focus?", subtitle: "Lumen tunes calories, protein and training advice to it.") {
            VStack(spacing: 10) {
                ChoiceCard(icon: "arrow.down.right", title: "Lose fat", subtitle: "Gentle deficit, high protein", selected: goal == .lose) { goal = .lose }
                ChoiceCard(icon: "equal", title: "Maintain & feel great", subtitle: "Energy, sleep and consistency", selected: goal == .maintain) { goal = .maintain }
                ChoiceCard(icon: "arrow.up.right", title: "Build strength", subtitle: "Small surplus, recovery first", selected: goal == .gain) { goal = .gain }
            }
            Text("How active are you on a typical week?").font(.headline).foregroundStyle(.white).padding(.top, 6)
            VStack(spacing: 10) {
                ForEach(HealthGoals.ActivityLevel.allCases, id: \.self) { a in
                    ChoiceCard(icon: activityIcon(a), title: a.label, subtitle: activityDetail(a), selected: activity == a) { activity = a }
                }
            }
        } footer: {
            continueButton()
        }
    }

    func activityIcon(_ a: HealthGoals.ActivityLevel) -> String {
        switch a { case .sedentary: return "chair.lounge.fill"; case .light: return "figure.walk"; case .moderate: return "figure.run"; case .active: return "figure.strengthtraining.traditional"; case .athlete: return "trophy.fill" }
    }
    func activityDetail(_ a: HealthGoals.ActivityLevel) -> String {
        switch a {
        case .sedentary: return "Mostly sitting, little exercise"
        case .light: return "Walks, 1–2 light sessions a week"
        case .moderate: return "3–4 workouts a week"
        case .active: return "5+ workouts or an active job"
        case .athlete: return "Training daily, sometimes twice"
        }
    }

    // MARK: 5 · Sleep

    var sleepStep: some View {
        page(title: "Your rhythm", subtitle: importedNights.count >= 3
             ? "Based on your last \(importedNights.count) nights in Apple Health."
             : "Lumen refines these automatically as it learns your nights.") {
            VStack(spacing: 10) {
                ForEach([Chronotype.morning, .intermediate, .evening], id: \.self) { c in
                    ChoiceCard(icon: c == .morning ? "sunrise.fill" : c == .evening ? "moon.stars.fill" : "circle.lefthalf.filled",
                               title: c.label, subtitle: c.description, selected: chronotype == c) { chronotype = c }
                }
            }
            fieldCard("Usual wake time", value: SleepFormat.time(wake)) {
                DatePicker("Wake time", selection: $wake, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity).frame(height: 120).clipped()
                    .colorScheme(.dark)
            }
            fieldCard("Sleep you need", value: SleepFormat.durationHM(needHours * 3600)) {
                Slider(value: $needHours, in: 6...10.5, step: 0.25).tint(.purple)
                Text(importedNights.count >= 3 ? "Estimated from your longest, most natural nights." : "Most adults need 7–9 hours; about half need 8 or more.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        } footer: {
            continueButton()
        }
    }

    // MARK: 6 · Reminders

    var remindersStep: some View {
        page(title: "Gentle, well-timed nudges", subtitle: "Lumen times reminders to your body clock — never spammy, always skippable.") {
            VStack(spacing: 12) {
                benefit("wind", .teal, "Wind-down", "An hour before your melatonin window opens")
                benefit("moon.fill", .indigo, "Bedtime", "When falling asleep is easiest")
                benefit("sun.max.fill", .yellow, "Morning light", "Anchor your clock within 30 minutes of waking")
                benefit("cup.and.saucer.fill", .brown, "Caffeine cutoff", "Protect tonight's sleep")
            }
            if remindersOn {
                Label("Reminders on — tune them anytime in Rituals.", systemImage: "bell.badge.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
        } footer: {
            VStack(spacing: 6) {
                if remindersOn {
                    continueButton()
                } else {
                    continueButton("Turn on reminders") {
                        Task {
                            let ok = await NotificationManager.shared.request()
                            withAnimation { remindersOn = ok }
                            go()
                        }
                    }
                    Button("Maybe later") { go() }.buttonStyle(LumenSecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: 7 · Plan reveal

    var draftGoals: HealthGoals {
        var g = health.goals
        g.weightKg = (weightKg * 10).rounded() / 10
        g.heightCm = heightCm.rounded()
        g.age = currentYear - birthYear
        g.sex = sex
        g.goal = goal
        g.activityLevel = activity
        switch activity {
        case .sedentary: g.activeCalGoal = 300; g.stepGoal = 6000
        case .light: g.activeCalGoal = 400; g.stepGoal = 8000
        case .moderate: g.activeCalGoal = 550; g.stepGoal = 10000
        case .active: g.activeCalGoal = 700; g.stepGoal = 11000
        case .athlete: g.activeCalGoal = 900; g.stepGoal = 12000
        }
        return g
    }

    var bedtimeTonight: Date {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: wake)
        let tomorrowWake = Calendar.current.date(bySettingHour: comps.hour ?? 7, minute: comps.minute ?? 0, second: 0,
                                                 of: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date()
        return tomorrowWake.addingTimeInterval(-(needHours * 3600) - 15 * 60)
    }

    var planStep: some View {
        let g = draftGoals
        let checks = ["Reading your profile", "Estimating your energy needs", "Mapping your circadian rhythm", "Personalising your coach"]
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    LumenOrb(size: revealStage >= checks.count ? 120 : 170)
                        .padding(.top, 30)
                        .animation(.spring(response: 0.7), value: revealStage)
                    if revealStage < checks.count {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(checks.indices, id: \.self) { i in
                                HStack(spacing: 12) {
                                    Image(systemName: i < revealStage ? "checkmark.circle.fill" : "circle.dotted")
                                        .foregroundStyle(i < revealStage ? .cyan : .white.opacity(0.35))
                                        .contentTransition(.symbolEffect(.replace))
                                    Text(checks[i]).foregroundStyle(.white.opacity(i <= revealStage ? 0.9 : 0.4))
                                }
                                .font(.headline)
                            }
                        }
                        .padding(.top, 10)
                    } else {
                        VStack(spacing: 6) {
                            Text("Your plan is ready\(trimmedName.isEmpty ? "" : ", \(trimmedName)")")
                                .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text("A starting point — Lumen adapts it daily from your data.")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            planTile("flame.fill", .orange, "\(g.calorieTarget())", "kcal / day")
                            planTile("fork.knife", .green, "\(g.proteinTarget()) g", "protein")
                            planTile("moon.fill", .indigo, SleepFormat.durationHM(needHours * 3600), "sleep need")
                            planTile("bed.double.fill", .purple, SleepFormat.time(bedtimeTonight), "bedtime tonight")
                            planTile("shoeprints.fill", .cyan, "\(Int(g.stepGoal).formatted())", "steps")
                            planTile("drop.fill", .blue, Units.water(Double(Int((g.weightKg ?? 75) * 35)), units), "water")
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
            }
            if revealStage >= checks.count {
                continueButton("Start using Lumen") { finish() }
                    .padding(.horizontal, 24).padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .task {
            revealStage = 0
            for i in 1...checks.count {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.spring) { revealStage = i }
                haptic(.light)
            }
            haptic(.heavy)
        }
    }

    func planTile(_ icon: String, _ tint: Color, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.headline).foregroundStyle(tint)
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlass(cornerRadius: 20, tintOpacity: 0.1)
    }

    func finish() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: wake)
        health.updateGoals(draftGoals)
        sleep.completeOnboarding(
            need: (needHours * 3600 / 300).rounded() * 300,
            chronotype: chronotype,
            wakeHour: comps.hour ?? 7,
            wakeMinute: comps.minute ?? 0,
            name: trimmedName,
            birthYear: birthYear,
            units: units
        )
        if !importedNights.isEmpty {
            sleep.mergeHealthSleep(importedNights)
            HealthKitService.shared.sleepBackfilled = true
        }
        haptic(.heavy)
        Task { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
    }
}
