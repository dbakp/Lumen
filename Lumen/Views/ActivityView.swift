import SwiftUI

// MARK: - Activity: rings, training load, workouts (Health + Strava + manual), vitals.

public struct ActivityView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var hk = HealthKitService.shared
    @State private var showManual = false
    @State private var showAll = false

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }

    var groupedWorkouts: [(day: Date, items: [Workout])] {
        let recent = health.workouts.sorted { $0.start > $1.start }.prefix(showAll ? 200 : 15)
        let groups = Dictionary(grouping: recent) { Calendar.current.startOfDay(for: $0.start) }
        return groups.map { ($0.key, $0.value.sorted { $0.start > $1.start }) }.sorted { $0.day > $1.day }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ringsCard
                NavigationLink { TrendsView() } label: {
                    HStack {
                        Label("Trends", systemImage: "chart.xyaxis.line").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("Steps, energy, heart, weight").font(.caption).foregroundStyle(.white.opacity(0.55))
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(16).liquidGlass(cornerRadius: 20)
                }
                .buttonStyle(.plain)

                if health.workouts.isEmpty {
                    EmptyStateCard(icon: "figure.run", title: "No workouts yet",
                                   message: hk.isAuthorized
                                   ? "Sessions recorded on your Apple Watch or any fitness app that saves to Health appear here automatically."
                                   : "Connect Apple Health in Settings to import workouts, or log one yourself.",
                                   actionTitle: "Log a workout") { showManual = true }
                } else {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Training load", subtitle: "Active energy from sessions, last 7 days", systemImage: "chart.bar.fill")
                            WeeklyLoadChart(workouts: health.workouts)
                        }
                    }
                    workoutsCard
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Vitals", subtitle: hk.isAuthorized ? "Latest from Apple Health" : "Connect Apple Health for vitals", systemImage: "heart.text.square.fill")
                        VitalsGrid()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground())
        .navigationTitle("Activity").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showManual = true } label: { Image(systemName: "plus") }.accessibilityLabel("Log workout")
            }
        }
        .sheet(isPresented: $showManual) { ManualWorkoutSheet() }
        .refreshable { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
    }

    var ringsCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                TripleRingView(
                    move: health.moveProgress,
                    exercise: min(1, health.metrics.exerciseMin / max(1, health.goals.exerciseGoalMin)),
                    stand: Double(health.metrics.standHours) / Double(max(1, health.goals.standGoal)))
                .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    RingLegend(color: .pink, title: "Move", value: "\(Int(health.metrics.activeCalories))/\(Int(health.goals.activeCalGoal)) kcal")
                    RingLegend(color: .green, title: "Exercise", value: "\(Int(health.metrics.exerciseMin))/\(Int(health.goals.exerciseGoalMin)) min")
                    RingLegend(color: .cyan, title: "Stand", value: "\(health.metrics.standHours)/\(health.goals.standGoal) hr")
                    RingLegend(color: .white, title: "Steps", value: Int(health.metrics.steps).formatted())
                    if let r = health.readiness {
                        Text("Today's window \(r.strainTarget.lowerBound)–\(r.strainTarget.upperBound) kcal")
                            .font(.caption2.weight(.bold)).foregroundStyle(.cyan.opacity(0.9))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    var workoutsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Workouts", subtitle: sourceSummary, systemImage: "flame.fill")
                ForEach(groupedWorkouts, id: \.day) { group in
                    Text(dayTitle(group.day)).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.5)).tracking(0.8)
                        .padding(.top, 8)
                    ForEach(group.items, id: \.id) { w in
                        WorkoutRow(w, units: units)
                            .contextMenu {
                                if w.source == .manual {
                                    Button(role: .destructive) { health.deleteWorkout(w.id) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        Divider().background(.white.opacity(0.08))
                    }
                }
                if health.workouts.count > 15 {
                    Button(showAll ? "Show recent" : "Show all") { withAnimation { showAll.toggle() } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.cyan).padding(.top, 4)
                }
            }
        }
    }

    var sourceSummary: String {
        let sources = Set(health.workouts.map(\.source)).map(\.label).sorted()
        return "\(health.workouts.count) sessions · " + sources.joined(separator: " + ")
    }

    func dayTitle(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "TODAY" }
        if Calendar.current.isDateInYesterday(d) { return "YESTERDAY" }
        return d.formatted(.dateTime.weekday(.wide).month().day()).uppercased()
    }
}

struct RingLegend: View {
    let color: Color; let title: String; let value: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.white)
        }
    }
}

struct VitalsGrid: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    var body: some View {
        let u = sleep.profile.unitSystem
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(icon: "heart.fill", tint: .pink, title: "Resting HR", value: health.metrics.restingHR.map { "\(Int($0)) bpm" } ?? "—", sub: "Lower usually = fitter")
            MetricTile(icon: "waveform.path.ecg", tint: .purple, title: "HRV", value: health.metrics.hrvMS.map { "\(Int($0)) ms" } ?? "—", sub: "SDNN · higher = recovered")
            MetricTile(icon: "lungs.fill", tint: .cyan, title: "Blood oxygen", value: health.metrics.spo2.map { String(format: "%.0f%%", $0) } ?? "—", sub: health.metrics.respiratoryRate.map { "Resp. \(Int($0))/min" } ?? "SpO₂")
            MetricTile(icon: "scalemass.fill", tint: .orange, title: "Weight", value: health.metrics.weightKg.map { Units.weight($0, u) } ?? "—", sub: health.metrics.vo2max.map { String(format: "VO₂ max %.0f", $0) } ?? "Log in Settings")
        }
    }
}

struct ManualWorkoutSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @State private var kind: WorkoutKind = .run
    @State private var minutes = 30.0
    @State private var start = Date().addingTimeInterval(-1800)

    var kcal: Int { Int(kind.met * (minutes / 60) * (health.goals.weightKg ?? 75)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(WorkoutKind.allCases, id: \.self) { k in
                            Button { kind = k; haptic(.light) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.icon).font(.title3)
                                    Text(k.label).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .foregroundStyle(kind == k ? .black : .white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(kind == k ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    VStack(spacing: 4) {
                        Text("\(Int(minutes)) min").font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("≈ \(kcal) active kcal").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }
                    Slider(value: $minutes, in: 5...240, step: 5).tint(.cyan)
                    DatePicker("Started", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .colorScheme(.dark).foregroundStyle(.white)
                        .padding(14).liquidGlass(cornerRadius: 16, tintOpacity: 0.08)
                }
                .padding(22)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Log \(kind.label.lowercased())") {
                    health.addManualWorkout(kind: kind, minutes: minutes, start: start)
                    haptic(.medium); dismiss()
                }
                .buttonStyle(LumenPrimaryButtonStyle())
                .padding(.horizontal, 22).padding(.bottom, 8)
            }
            .background(AuroraBackground())
            .navigationTitle("Log workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
