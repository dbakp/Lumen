import SwiftUI

// MARK: - Activity: rings → this week → workouts → heart & body

public struct ActivityView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var hk = HealthKitService.shared
    var router: AppRouter { .shared }

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }
    var recent: [Workout] { Array(health.workouts.sorted { $0.start > $1.start }.prefix(5)) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                rings
                if let r = health.readiness {
                    Text("Aim for \(r.strainTarget.lowerBound)–\(r.strainTarget.upperBound) active calories today, based on how recovered you are.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                week
                workouts
                body_
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 40)
        }
        .lumenScreen(Theme.move)
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.show(.workout) } label: { Image(systemName: "plus") }.accessibilityLabel("Log a workout")
            }
        }
        .refreshable { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
    }

    // MARK: Rings

    var rings: some View {
        HStack(spacing: 24) {
            TripleRingView(
                move: health.moveProgress,
                exercise: health.metrics.exerciseMin / max(1, health.goals.exerciseGoalMin),
                stand: Double(health.metrics.standHours) / Double(max(1, health.goals.standGoal)))
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 14) {
                ringStat("Move", "\(Int(health.metrics.activeCalories))", "/\(Int(health.goals.activeCalGoal)) kcal", Theme.move)
                ringStat("Exercise", "\(Int(health.metrics.exerciseMin))", "/\(Int(health.goals.exerciseGoalMin)) min", Theme.steps)
                ringStat("Stand", "\(health.metrics.standHours)", "/\(health.goals.standGoal) hours", Theme.calm)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    func ringStat(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.subheadline).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                Text(unit).font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    // MARK: Week

    var week: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("This week")
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    NavigationLink { TrendsView(metric: .steps) } label: { weekStat(Int(health.metrics.steps).formatted(), "steps today") }
                    Spacer()
                    weekStat("\(health.workouts.filter { $0.start > Date().addingTimeInterval(-7 * 86400) }.count)", "workouts")
                    Spacer()
                    weekStat("\(Int(health.workouts.filter { $0.start > Date().addingTimeInterval(-7 * 86400) }.reduce(0) { $0 + $1.duration } / 60))", "active min")
                }
                .buttonStyle(.plain)
                WeeklyLoadChart(workouts: health.workouts).frame(height: 120)
            }
            .padding(16).surface()
        }
    }

    func weekStat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
            Text(l).font(.footnote).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: Workouts

    @ViewBuilder var workouts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                GroupLabel("Workouts")
                if health.workouts.count > 5 {
                    NavigationLink { AllWorkoutsView() } label: { Text("See all").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary) }
                }
            }
            if recent.isEmpty {
                EmptyStateCard(icon: "figure.run", title: "No workouts yet",
                               message: hk.isAuthorized ? "Workouts from your Apple Watch and fitness apps show up here." : "Connect Apple Health to bring in workouts, or log one yourself.",
                               actionTitle: "Log a workout") { router.show(.workout) }
            } else {
                RowGroup {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { i, w in
                        if i > 0 { RowDivider() }
                        WorkoutRow(w, units: units)
                            .contextMenu {
                                if w.source == .manual {
                                    Button("Delete", systemImage: "trash", role: .destructive) { health.deleteWorkout(w.id) }
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: Heart & body

    var body_: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Heart & body")
            RowGroup {
                NavigationLink { TrendsView(metric: .restingHR) } label: {
                    LumenRow("Resting heart rate", value: health.metrics.restingHR.map { "\(Int($0)) bpm" } ?? "—", icon: "heart.fill", color: Theme.heart)
                }
                RowDivider()
                NavigationLink { TrendsView(metric: .hrv) } label: {
                    LumenRow("Heart rate variability", subtitle: "Higher usually means well recovered", value: health.metrics.hrvMS.map { "\(Int($0)) ms" } ?? "—", icon: "waveform.path.ecg", color: Theme.calm)
                }
                RowDivider()
                NavigationLink { TrendsView(metric: .weight) } label: {
                    LumenRow("Weight", value: health.metrics.weightKg.map { Units.weight($0, units) } ?? "—", icon: "scalemass.fill", color: Theme.food)
                }
                RowDivider()
                NavigationLink { TrendsView(metric: .activeEnergy) } label: {
                    LumenRow("Active energy", value: "\(Int(health.metrics.activeCalories)) kcal", icon: "flame.fill", color: Theme.move)
                }
                if let spo2 = health.metrics.spo2 {
                    RowDivider()
                    LumenRow("Blood oxygen", value: String(format: "%.0f%%", spo2), icon: "lungs.fill", color: Theme.water, chevron: false)
                }
                if let vo2 = health.metrics.vo2max {
                    RowDivider()
                    LumenRow("Cardio fitness", subtitle: "VO₂ max", value: String(format: "%.0f", vo2), icon: "figure.run.circle", color: Theme.steps, chevron: false)
                }
            }
            .buttonStyle(.plain)
            if !hk.isAuthorized {
                Text("Connect Apple Health in Settings to see these.").font(.footnote).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

// MARK: - All workouts

struct AllWorkoutsView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    var groups: [(day: Date, items: [Workout])] {
        let g = Dictionary(grouping: health.workouts) { Calendar.current.startOfDay(for: $0.start) }
        return g.map { ($0.key, $0.value.sorted { $0.start > $1.start }) }.sorted { $0.day > $1.day }
    }
    var body: some View {
        List {
            ForEach(groups, id: \.day) { group in
                Section(group.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(group.items, id: \.id) { w in
                        WorkoutRow(w, units: sleep.profile.unitSystem)
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                if w.source == .manual { Button("Delete", role: .destructive) { health.deleteWorkout(w.id) } }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AuroraBackground(Theme.move))
        .navigationTitle("Workouts")
    }
}

struct RingLegend: View {
    let color: Color; let title: String; let value: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.footnote).foregroundStyle(Theme.secondary)
            Text(value).font(.footnote.monospacedDigit()).foregroundStyle(Theme.text)
        }
    }
}

// MARK: - Log workout

struct ManualWorkoutSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @State private var kind: WorkoutKind = .walk
    @State private var minutes = 30.0
    @State private var start = Date().addingTimeInterval(-1800)

    var kcal: Int { Int(kind.met * (minutes / 60) * (health.goals.weightKg ?? 75)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(WorkoutKind.allCases, id: \.self) { k in
                            Button { kind = k; haptic(.light) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.icon).font(.title3)
                                    Text(k.label).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .foregroundStyle(kind == k ? .black : .white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(kind == k ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    VStack(spacing: 4) {
                        Text("\(Int(minutes)) min").font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.text)
                            .contentTransition(.numericText())
                        Text("About \(kcal) active calories").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Slider(value: $minutes, in: 5...240, step: 5).tint(.white)
                    DatePicker("Started", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .padding(14).surface(16)
                }
                .padding(Theme.gutter)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save \(kind.label.lowercased())") {
                    health.addManualWorkout(kind: kind, minutes: minutes, start: start)
                    dismiss()
                    AppRouter.shared.confirm("\(kind.label) saved")
                }
                .buttonStyle(LumenPrimaryButtonStyle())
                .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Log a workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(.white)
    }
}
