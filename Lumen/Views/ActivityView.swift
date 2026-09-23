import SwiftUI

// MARK: - Activity: rings + workouts unified (HealthKit + Strava + manual).

public struct ActivityView: View {
    @EnvironmentObject var health: HealthStore
    @State private var showManual = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    HStack {
                        TripleRingView(
                            move: health.moveProgress,
                            exercise: min(1, health.metrics.exerciseMin / max(1, health.goals.exerciseGoalMin)),
                            stand: Double(health.metrics.standHours) / Double(max(1, health.goals.standGoal)))
                        VStack(alignment: .leading, spacing: 6) {
                            RingLegend(color: .pink, title: "Move", value: "\(Int(health.metrics.activeCalories))/\(Int(health.goals.activeCalGoal)) kcal")
                            RingLegend(color: .green, title: "Exercise", value: "\(Int(health.metrics.exerciseMin))/\(Int(health.goals.exerciseGoalMin)) min")
                            RingLegend(color: .cyan, title: "Stand", value: "\(health.metrics.standHours)/\(health.goals.standGoal) hr")
                            if let r = health.readiness {
                                Text("Target \(r.strainTarget.lowerBound)–\(r.strainTarget.upperBound) kcal")
                                    .font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1).minimumScaleFactor(0.85)
                            }
                        }
                        Spacer()
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            SectionHeader("Workouts", subtitle: health.usingLiveData ? "\(health.workouts.count) synced · Health + Strava" : "\(health.workouts.count) demo — connect for yours", systemImage: "flame.fill")
                            Spacer()
                            Button { showManual = true } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.cyan) }
                        }
                        if health.workouts.isEmpty {
                            Text("Connect Strava or Health to see training here.").font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        ForEach(health.workouts.sorted { $0.start > $1.start }.prefix(20), id: \.id) { WorkoutRow($0); Divider().background(.white.opacity(0.08)) }
                        WeeklyLoadChart(workouts: health.workouts)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Vitals", subtitle: "From Health · Watch optional, phone works", systemImage: "heart.text.square.fill")
                        VitalsGrid()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showManual) { ManualWorkoutSheet() }
    }
}

struct RingLegend: View {
    let color: Color; let title: String; let value: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.white)
        }
    }
}

struct VitalsGrid: View {
    @EnvironmentObject var health: HealthStore
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(icon: "heart.fill", tint: .pink, title: "Resting HR", value: health.metrics.restingHR.map { "\(Int($0))" } ?? "—", sub: "bpm")
            MetricTile(icon: "waveform.path.ecg", tint: .purple, title: "HRV", value: health.metrics.hrvMS.map { "\(Int($0)) ms" } ?? "—", sub: "SDNN")
            MetricTile(icon: "lungs.fill", tint: .cyan, title: "SpO₂", value: health.metrics.spo2.map { String(format: "%.0f%%", $0) } ?? "—", sub: "Saturation")
            MetricTile(icon: "scalemass.fill", tint: .orange, title: "Weight", value: (health.metrics.weightKg ?? health.goals.weightKg).map { String(format: "%.1f kg", $0) } ?? "—", sub: "From Health")
        }
    }
}

struct ManualWorkoutSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @State private var kind: WorkoutKind = .run
    @State private var minutes = 30.0
    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                VStack(spacing: 16) {
                    Picker("Type", selection: $kind) { ForEach(WorkoutKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
                    Text("\(Int(minutes)) min · ~\(Int(kind.met * (minutes/60) * (health.goals.weightKg ?? 75))) kcal")
                        .font(.title2.weight(.bold)).foregroundStyle(.white)
                    Slider(value: $minutes, in: 5...180, step: 5).tint(.cyan)
                    Button("Log workout") {
                        health.addManualWorkout(kind: kind, minutes: minutes)
                        haptic(.medium); dismiss()
                    }.buttonStyle(.borderedProminent).tint(.cyan).font(.headline)
                    Spacer()
                }.padding(22)
            }
            .navigationTitle("Log workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
