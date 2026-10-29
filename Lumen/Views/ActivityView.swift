import SwiftUI

// MARK: - Activity: rings → this week → workouts → heart & body

public struct ActivityView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var hk = HealthKitService.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    var router: AppRouter { .shared }

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }
    var recent: [Workout] { Array(health.workouts.sorted { $0.start > $1.start }.prefix(5)) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                rings
                NavigationLink("Review today's readings", destination: CurrentReadingsView()).frame(minHeight: 44)
                if let r = health.readiness {
                    Text("Estimated activity range: \(r.strainTarget.lowerBound)–\(r.strainTarget.upperBound) kcal. This wellness heuristic cannot establish recovery; check how you feel before exercising.")
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

    @ViewBuilder var rings: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 24) { ringGraphic; ringValues }
        } else {
            HStack(spacing: 24) { ringGraphic; ringValues; Spacer(minLength: 0) }.padding(.top, 8)
        }
    }
    var ringGraphic: some View {
        TripleRingView(move: health.moveProgress,
                       exercise: health.metrics.exerciseMin / max(1, health.goals.exerciseGoalMin),
                       stand: Double(health.metrics.standHours) / Double(max(1, health.goals.standGoal)))
            .frame(width: 150, height: 150).accessibilityHidden(true)
    }
    var ringValues: some View {
        VStack(alignment: .leading, spacing: 14) {
            ringStat("Move", value("activeEnergy"), health.metrics.reading("activeEnergy").value == nil ? "" : "/\(Int(health.goals.activeCalGoal)) kcal", Theme.move)
            ringStat("Exercise", value("exercise"), health.metrics.reading("exercise").value == nil ? "" : "/\(Int(health.goals.exerciseGoalMin)) min", Theme.steps)
            ringStat("Stand / roll", value("stand"), health.metrics.reading("stand").value == nil ? "" : "/\(health.goals.standGoal) hours", Theme.calm, id: "stand")
        }
    }
    func value(_ key: String) -> String { health.metrics.reading(key).value.map(HealthMetricCatalog.number) ?? "No reading" }

    func ringStat(_ label: String, _ value: String, _ unit: String, _ color: Color, id: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.subheadline).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                Text(unit).font(.footnote).foregroundStyle(Theme.secondary)
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("activity-stat-" + (id ?? label.lowercased()))
    }

    // MARK: Week

    var week: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Past 7 days")
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 16) { weekStats } }
                    else { HStack(alignment: .top, spacing: 12) { weekStats } }
                }.buttonStyle(.plain)
                WeeklyLoadChart(workouts: health.workouts)
            }
            .padding(16).surface()
        }
    }
    @ViewBuilder var weekStats: some View {
        NavigationLink { TrendsView(metric: .steps) } label: { weekStat(value("steps"), "steps today") }.frame(maxWidth: .infinity, alignment: .leading)
        weekStat("\(CurrentHealthEvidence.recentWorkouts(health.workouts).count)", "workouts").frame(maxWidth: .infinity, alignment: .leading)
        weekStat("\(Int(CurrentHealthEvidence.recentWorkouts(health.workouts).reduce(0) { $0 + $1.duration } / 60))", "logged min").frame(maxWidth: .infinity, alignment: .leading)
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
                        NavigationLink { WorkoutDetailView(workout: w, units: units) } label: { WorkoutRow(w, units: units) }.buttonStyle(.plain)
                            .contextMenu {
                                if w.source == .manual && w.importOrigin == nil && w.logOrigin == nil {
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
                    LumenRow("Resting heart rate", value: HealthMetricCatalog.display(health.metrics.reading("restingHR").value, key: "restingHR"), icon: "heart.fill", color: Theme.heart)
                }
                RowDivider()
                NavigationLink { TrendsView(metric: .hrv) } label: {
                    LumenRow("Heart rate variability", subtitle: "Compare with your own recorded history", value: HealthMetricCatalog.display(health.metrics.reading("hrv").value, key: "hrv"), icon: "waveform.path.ecg", color: Theme.calm)
                }
                RowDivider()
                NavigationLink { TrendsView(metric: .weight) } label: {
                    LumenRow("Weight", value: health.metrics.weightKg.map { Units.weight($0, units) } ?? "Not recorded", icon: "scalemass.fill", color: Theme.food)
                }
                RowDivider()
                NavigationLink { TrendsView(metric: .activeEnergy) } label: {
                    LumenRow("Active energy", value: HealthMetricCatalog.display(health.metrics.reading("activeEnergy").value, key: "activeEnergy"), icon: "flame.fill", color: Theme.move)
                }
                if let spo2 = health.metrics.spo2 {
                    RowDivider()
                    LumenRow("Blood oxygen", value: HealthMetricCatalog.display(spo2, key: "spo2"), icon: "lungs.fill", color: Theme.water, chevron: false)
                }
                if let vo2 = health.metrics.vo2max {
                    RowDivider()
                    LumenRow("Cardio fitness", subtitle: "VO₂ max", value: HealthMetricCatalog.display(vo2, key: "vo2max"), icon: "figure.run.circle", color: Theme.steps, chevron: false)
                }
            }
            .buttonStyle(.plain)
            if !hk.isAuthorized {
                Text("Connect Apple Health or import recordings to add readings. Availability varies by data type.").font(.footnote).foregroundStyle(Theme.tertiary)
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
                        NavigationLink { WorkoutDetailView(workout: w, units: sleep.profile.unitSystem) } label: { WorkoutRow(w, units: sleep.profile.unitSystem) }
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                if w.source == .manual && w.importOrigin == nil && w.logOrigin == nil { Button("Delete", role: .destructive) { health.deleteWorkout(w.id) } }
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
                                .foregroundStyle(kind == k ? Theme.onAccent : Theme.text)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(kind == k ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    Slider(value: $minutes, in: 5...240, step: 5).tint(Theme.accent)
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
        .tint(Theme.accent)
    }
}
