import SwiftUI

// MARK: - Sleep tab: last night → tonight → energy → more

public struct HomeView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var health: HealthStore
    @ObservedObject private var hk = HealthKitService.shared
    @ObservedObject private var notifications = NotificationManager.shared
    var router: AppRouter { .shared }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let last = store.lastNight {
                    LastNightHero(episode: last, need: store.profile.sleepNeed)
                    stats
                } else {
                    EmptyStateCard(icon: "moon.stars", title: "No sleep yet",
                                   message: hk.isAuthorized
                                   ? "Wear your Apple Watch to bed and last night appears here in the morning."
                                   : "Connect Apple Health to bring in your nights automatically, or add one yourself.",
                                   actionTitle: hk.isAuthorized ? "Add a night" : "Connect Apple Health") {
                        if hk.isAuthorized { router.show(.sleepLog) }
                        else { Task { if await hk.requestAuthorization() { await SyncCoordinator.syncEverything(sleep: store, health: health) } } }
                    }
                    .padding(.top, 12)
                }
                tonight
                if let pred = store.prediction, store.hasSleepData { energy(pred) }
                more
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 40)
        }
        .lumenScreen(Theme.sleep)
        .navigationTitle("Sleep")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.show(.sleepLog) } label: { Image(systemName: "plus") }.accessibilityLabel("Add a night")
            }
        }
        .refreshable { await SyncCoordinator.syncEverything(sleep: store, health: health) }
    }

    // MARK: Stats

    var stats: some View {
        HStack(spacing: 0) {
            stat(SleepFormat.debtString(store.debt).replacingOccurrences(of: " hr", with: "h"), "Sleep debt",
                 store.debt / 3600 < 5 ? Theme.steps : Theme.food)
            divider
            stat(store.lastNight?.efficiency.map { "\(Int($0 * 100))%" } ?? "—", "Restful")
            divider
            stat(SleepFormat.durationHM(store.avg7), "7-night avg")
        }
        .padding(.vertical, 16)
        .surface()
    }

    var divider: some View { Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 36) }

    func stat(_ value: String, _ label: String, _ color: Color = Theme.text) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.footnote).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Tonight

    var tonight: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Tonight")
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bedtime").font(.subheadline).foregroundStyle(Theme.secondary)
                        Text(SleepFormat.time(store.suggestedBedtime)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Text("Wake \(SleepFormat.time(store.wakeGoalTomorrow))").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 16)
                if let p = store.prediction {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    LumenRow("Wind down", value: SleepFormat.time(p.windDown), icon: "wind", color: Theme.calm, chevron: false)
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    LumenRow("Easiest time to fall asleep", value: SleepFormat.timeRange(p.melatoninWindow), icon: "moon", color: Theme.sleep, chevron: false)
                }
                if !notifications.authorized {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    Button {
                        Task { if await notifications.request() { notifications.reschedule(from: store); router.confirm("Bedtime reminders on") } }
                    } label: {
                        LumenRow("Remind me at bedtime", icon: "bell", color: Theme.food)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .surface()
            if store.hasSleepData {
                Text(store.bedtimeNote).font(.footnote).foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: Energy

    func energy(_ pred: CircadianPrediction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Your energy today")
            VStack(alignment: .leading, spacing: 12) {
                EnergyCurveView(points: pred.curve, now: Date())
                HStack {
                    Label("Peak \(SleepFormat.time(pred.morningPeak))", systemImage: "arrow.up.right")
                    Spacer()
                    Label("Dip \(SleepFormat.time(pred.middayDip))", systemImage: "arrow.down.right")
                }
                .font(.footnote).foregroundStyle(Theme.secondary)
            }
            .padding(16).surface()
        }
    }

    // MARK: More

    var more: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("More")
            RowGroup {
                NavigationLink { SleepLogView() } label: { LumenRow("Sleep history", value: store.episodes.isEmpty ? nil : "\(store.episodes.count)", icon: "calendar", color: Theme.sleep) }
                RowDivider()
                NavigationLink { TrendsView(metric: .sleep) } label: { LumenRow("Trends", icon: "chart.bar", color: Theme.sleep) }
                RowDivider()
                NavigationLink { HabitsView() } label: {
                    LumenRow("Daily habits", value: "\(store.habits.filter { $0.isEnabled && $0.doneToday }.count)/\(store.habits.filter(\.isEnabled).count)", icon: "checklist", color: Theme.steps)
                }
                RowDivider()
                NavigationLink { SoundsView() } label: { LumenRow("Sleep sounds", icon: "waveform", color: Theme.calm) }
                RowDivider()
                NavigationLink { LearnView() } label: { LumenRow("Learn about sleep", icon: "book", color: Theme.food) }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Last night hero

struct LastNightHero: View {
    let episode: SleepEpisode
    let need: TimeInterval
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                Text(SleepFormat.durationHM(episode.duration))
                    .font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
                Text("\(SleepFormat.time(episode.bedtime)) – \(SleepFormat.time(episode.wakeTime)) · \(delta)")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
            if episode.hasStages {
                SleepStagesBar(episode: episode)
            } else {
                Bar(episode.duration / need, color: Theme.sleep, height: 8)
            }
        }
        .padding(.top, 8)
    }

    var title: String {
        Calendar.current.isDateInToday(episode.wakeTime) ? "Last night" : episode.wakeTime.formatted(.dateTime.weekday(.wide))
    }

    var delta: String {
        let d = episode.duration - need
        if abs(d) < 10 * 60 { return "right on your need" }
        return d > 0 ? "\(SleepFormat.durationHM(d)) over your need" : "\(SleepFormat.durationHM(-d)) short"
    }
}

struct SleepStagesBar: View {
    let episode: SleepEpisode
    var stages: [(String, Double, Color)] {
        [("Awake", episode.awakeSeconds ?? 0, Theme.food),
         ("REM", episode.remSeconds ?? 0, Theme.calm),
         ("Light", episode.coreSeconds ?? 0, Theme.water),
         ("Deep", episode.deepSeconds ?? 0, Theme.sleep)].filter { $0.1 > 0 }
    }
    var body: some View {
        let total = max(1, stages.reduce(0) { $0 + $1.1 })
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(stages, id: \.0) { s in
                        Capsule().fill(s.2)
                            .frame(width: max(6, (geo.size.width - CGFloat(stages.count - 1) * 3) * s.1 / total))
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 0) {
                ForEach(stages, id: \.0) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(s.2).frame(width: 6, height: 6)
                            Text(s.0).font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        Text(SleepFormat.durationHM(s.1)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(habit.doneToday ? Theme.steps : Theme.tertiary)
                    .contentTransition(.symbolEffect(.replace))
                Text(habit.title).font(.body).foregroundStyle(habit.doneToday ? Theme.secondary : Theme.text)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
