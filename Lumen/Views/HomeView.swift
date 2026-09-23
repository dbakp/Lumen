import SwiftUI

// MARK: - Sleep tab: last night, debt, energy curve, bedtime plan, tools

public struct HomeView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var health: HealthStore
    @ObservedObject private var hk = HealthKitService.shared
    @State private var showLog = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let last = store.lastNight {
                    LastNightCard(episode: last, need: store.profile.sleepNeed)
                    debtCard
                } else {
                    EmptyStateCard(icon: "moon.stars.fill", title: "Your first night",
                                   message: hk.isAuthorized
                                   ? "Sleep with your Apple Watch (or any app that writes sleep to Health) and it appears here in the morning. You can also log a night yourself."
                                   : "Connect Apple Health to import your nights automatically, or log one yourself.",
                                   actionTitle: "Log a night") { showLog = true }
                    if !hk.isAuthorized {
                        Button {
                            Task { if await hk.requestAuthorization() { await SyncCoordinator.syncEverything(sleep: store, health: health) } }
                        } label: { Label("Connect Apple Health", systemImage: "heart.fill") }
                        .buttonStyle(LumenPrimaryButtonStyle(colors: [Color(red: 1, green: 0.38, blue: 0.5), Color(red: 1, green: 0.55, blue: 0.4)]))
                    }
                }
                if let pred = store.prediction { energyCard(pred); scheduleCard(pred) }
                toolsGrid
                ritualsTeaser
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground())
        .sheet(isPresented: $showLog) { LogSleepSheet() }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showLog = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log sleep")
            }
        }
        .refreshable { await SyncCoordinator.syncEverything(sleep: store, health: health) }
    }

    var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Need \(SleepFormat.durationHM(store.profile.sleepNeed)) · \(store.profile.chronotype.label)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                Text("Bedtime tonight \(SleepFormat.time(store.suggestedBedtime))")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if store.hasSleepData {
                ZStack {
                    GlowRing(progress: Double(store.energyPotential) / 100, colors: [.cyan, .purple], lineWidth: 6)
                    VStack(spacing: 0) {
                        Text("\(store.energyPotential)").font(.headline.weight(.bold)).foregroundStyle(.white)
                        Text("ENERGY").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.55)).tracking(0.8)
                    }
                }
                .frame(width: 58, height: 58)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Energy potential \(store.energyPotential)")
            }
        }
    }

    var debtCard: some View {
        GlassCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SLEEP DEBT").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(1.2)
                    Text(debtMessage).font(.subheadline).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    NavigationLink { SleepLogView() } label: {
                        Text("Sleep journal →").font(.subheadline.weight(.semibold)).foregroundStyle(.cyan)
                    }
                }
                Spacer()
                DebtRingView(debt: store.debt, need: store.profile.sleepNeed)
                    .scaleEffect(0.78).frame(width: 150, height: 150)
            }
        }
    }

    var debtMessage: String {
        let h = store.debt / 3600
        if store.episodes.count < 5 { return "Based on \(store.episodes.count) night\(store.episodes.count == 1 ? "" : "s") so far — sharper after a week." }
        if h < 1 { return "Fully rested. Keep your wake time steady to stay here." }
        if h < 5 { return "Manageable. A few nights 20–30 min earlier pays it down." }
        return "High. An earlier bedtime and a short early-afternoon nap help most."
    }

    func energyCard(_ pred: CircadianPrediction) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Today's energy", subtitle: "Predicted from your rhythm and debt", systemImage: "waveform.path.ecg")
                EnergyCurveView(points: pred.curve, now: Date())
                HStack {
                    Label("Groggy until \(SleepFormat.time(pred.grogginessEnds))", systemImage: "alarm")
                    Spacer()
                    Label("Peak \(SleepFormat.time(pred.afternoonPeak))", systemImage: "bolt.fill")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    func scheduleCard(_ pred: CircadianPrediction) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader("Your day, timed", subtitle: "Synced to your body clock", systemImage: "calendar")
                TimelineRow(icon: "sunrise.fill", color: .orange, title: "Wake zone", time: SleepFormat.time(pred.wakeZone.lowerBound), detail: "Get light and water within 30 min.")
                TimelineRow(icon: "brain.head.profile", color: .cyan, title: "Deep focus", time: SleepFormat.time(pred.morningPeak), detail: "Hardest tasks here — alertness is high.")
                TimelineRow(icon: "cloud.sun.fill", color: .yellow, title: "Midday dip", time: SleepFormat.time(pred.middayDip), detail: "Light walk or 20-min nap, not a fourth coffee.")
                TimelineRow(icon: "bolt.fill", color: .purple, title: "Second wind", time: SleepFormat.time(pred.afternoonPeak), detail: "Workouts and meetings shine here.")
                TimelineRow(icon: "cup.and.saucer.fill", color: .brown, title: "Caffeine cutoff", time: SleepFormat.time(pred.caffeineCutoff), detail: "Last call — protects melatonin.")
                TimelineRow(icon: "wind", color: .teal, title: "Wind down", time: SleepFormat.time(pred.windDown), detail: "Dim lights, screens down.")
                TimelineRow(icon: "moon.fill", color: .indigo, title: "Melatonin window", time: SleepFormat.timeRange(pred.melatoninWindow), detail: "Easiest 60 min to fall asleep.")
                Divider().background(.white.opacity(0.12))
                HStack {
                    VStack(alignment: .leading) {
                        Text("SUGGESTED BEDTIME").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6)).tracking(0.8)
                        Text(SleepFormat.time(store.suggestedBedtime)).font(.title3.weight(.bold)).foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("to wake \(SleepFormat.time(store.wakeGoalToday))").font(.caption).foregroundStyle(.white.opacity(0.6))
                        Text(store.bedtimeNote).font(.caption2).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: 190, alignment: .trailing).lineLimit(3)
                    }
                }
            }
        }
    }

    var toolsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tool("bed.double.fill", .purple, "Journal", "Every night, editable") { SleepLogView() }
            tool("waveform.path.ecg", .cyan, "Energy", "Peaks & dips") { EnergyView() }
            tool("checklist", .green, "Rituals", "\(store.habits.filter { $0.isEnabled && $0.doneToday }.count)/\(store.habits.filter(\.isEnabled).count) today") { HabitsView() }
            tool("speaker.wave.2.fill", .teal, "Sounds", "Rain, ocean, noise") { SoundsView() }
            tool("book.fill", .yellow, "Learn", "The science, short") { LearnView() }
            tool("chart.xyaxis.line", .indigo, "Trends", "Weeks & months") { TrendsView() }
        }
    }

    func tool<D: View>(_ icon: String, _ tint: Color, _ title: String, _ sub: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.headline).foregroundStyle(tint)
                    .frame(width: 38, height: 38).background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(sub).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .liquidGlass(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }

    var ritualsTeaser: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Rituals", subtitle: "\(store.habits.filter { $0.isEnabled && $0.doneToday }.count)/\(store.habits.filter(\.isEnabled).count) done today", systemImage: "checklist")
                ForEach(store.habits.filter(\.isEnabled).prefix(4)) { h in
                    HabitRowCompact(habit: h) { store.toggleHabitDone(h.id); haptic(.light) }
                }
            }
        }
    }
}

// MARK: - Last night

struct LastNightCard: View {
    let episode: SleepEpisode
    let need: TimeInterval
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(1.2)
                        Text(SleepFormat.durationHM(episode.duration))
                            .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(SleepFormat.time(episode.bedtime)) → \(SleepFormat.time(episode.wakeTime))")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        Text(delta).font(.caption.weight(.semibold)).foregroundStyle(episode.duration >= need - 1800 ? .green : .orange)
                    }
                }
                if episode.hasStages {
                    SleepStagesBar(episode: episode)
                } else {
                    ProgressView(value: min(1, episode.duration / need)).tint(.indigo)
                }
                HStack(spacing: 10) {
                    if let e = episode.efficiency { StatChip(title: "EFFICIENCY", value: "\(Int(e * 100))%") }
                    StatChip(title: "IN BED", value: SleepFormat.durationHM(episode.timeInBed))
                    StatChip(title: "SOURCE", value: episode.source.label)
                }
            }
        }
    }

    var title: String {
        Calendar.current.isDateInToday(episode.wakeTime) ? "LAST NIGHT" : episode.wakeTime.formatted(.dateTime.weekday(.wide)).uppercased()
    }

    var delta: String {
        let d = episode.duration - need
        return d >= 0 ? "+\(SleepFormat.durationHM(d)) vs need" : "−\(SleepFormat.durationHM(-d)) vs need"
    }
}

struct SleepStagesBar: View {
    let episode: SleepEpisode
    var stages: [(String, Double, Color)] {
        [("Awake", episode.awakeSeconds ?? 0, .orange),
         ("REM", episode.remSeconds ?? 0, .cyan),
         ("Core", episode.coreSeconds ?? 0, .blue),
         ("Deep", episode.deepSeconds ?? 0, .indigo)].filter { $0.1 > 0 }
    }
    var body: some View {
        let total = max(1, stages.reduce(0) { $0 + $1.1 })
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(stages, id: \.0) { s in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(s.2.gradient)
                            .frame(width: max(4, (geo.size.width - CGFloat(stages.count - 1) * 2) * s.1 / total))
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: 12) {
                ForEach(stages, id: \.0) { s in
                    HStack(spacing: 4) {
                        Circle().fill(s.2).frame(width: 7, height: 7)
                        Text(s.0).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6))
                        Text(SleepFormat.durationHM(s.1)).font(.caption2.monospacedDigit()).foregroundStyle(.white)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct HabitRowCompact: View {
    let habit: SleepHabit
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack {
                Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(habit.doneToday ? .green : .white.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
                Text(habit.title).font(.subheadline).foregroundStyle(.white.opacity(habit.doneToday ? 0.55 : 0.9))
                    .strikethrough(habit.doneToday)
                Spacer()
                Image(systemName: habit.icon).font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
