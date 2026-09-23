import SwiftUI

// MARK: - Today: the screen people fall in love with.
// Readiness dial + rings + calories + briefing + insights + quick log.
// One glance answers: "how am I, and what should I do?"

public struct TodayView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @State private var showCapture = false
    @State private var showChat = false
    @State private var ringsCelebrated = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let plan = health.plan {
                    BriefingCard(plan: plan, readiness: health.readiness)
                        .pressable()
                }
                readinessAndRings
                metricsGrid
                nutritionPreview
                workoutsPreview
                ForEach(health.insights) { InsightCard($0) }
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .background(AuroraBackground())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await health.syncAll() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .symbolEffect(.bounce, value: health.isSyncing)
                }.tint(.cyan)
            }
        }
        .sheet(isPresented: $showCapture) { MealCaptureView() }
        .navigationDestination(isPresented: $showChat) { CoachView() }
        .refreshable { await health.syncAll() }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting + ", \(sleep.profile.name)").font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text("Readiness \(health.readiness?.score ?? 70) · Debt \(SleepFormat.debtString(sleep.debt)) · \(health.caloriesRemaining) kcal left")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Button { showChat = true } label: {
                    Image(systemName: "sparkles").font(.headline).foregroundStyle(.white)
                        .frame(width: 46, height: 46).liquidGlass(cornerRadius: 23, tintOpacity: 0.22)
                }
            }
            HStack(spacing: 6) {
                DataPill(live: health.usingLiveData)
                if let sync = health.lastSync {
                    Text("Synced \(sync, style: .time)").font(.caption2).foregroundStyle(.white.opacity(0.45))
                } else if !health.usingLiveData {
                    Text("Connect Health for your real numbers").font(.caption2).foregroundStyle(.white.opacity(0.45))
                }
            }
        }.padding(.top, 8)
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 0..<5: return "Deep night"; case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" }
    }

    var readinessAndRings: some View {
        GlassCard {
            HStack(spacing: 8) {
                ReadinessDial(score: health.readiness?.score ?? 72)
                    .frame(width: 150, height: 150)
                Spacer()
                VStack(spacing: 10) {
                    TripleRingView(
                        move: health.moveProgress,
                        exercise: min(1, health.metrics.exerciseMin / max(1, health.goals.exerciseGoalMin)),
                        stand: Double(health.metrics.standHours) / Double(max(1, health.goals.standGoal))
                    ).scaleEffect(0.85).frame(width: 150, height: 150)
                    Text("Move \(Int(health.metrics.activeCalories))/\(Int(health.goals.activeCalGoal)) · Ex \(Int(health.metrics.exerciseMin))/\(Int(health.goals.exerciseGoalMin)) · Stand \(health.metrics.standHours)/\(health.goals.standGoal)")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.9)
                }
                Spacer()
            }
        }
    }

    var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(icon: "shoeprints.fill", tint: .cyan, title: "Steps", value: "\(Int(health.metrics.steps))", sub: "Goal \(Int(health.goals.stepGoal))")
            MetricTile(icon: "heart.fill", tint: .pink, title: "Heart", value: health.metrics.restingHR.map { "\(Int($0)) bpm" } ?? "—", sub: "Resting · HRV \(health.metrics.hrvMS.map { "\(Int($0)) ms" } ?? "—")")
            MetricTile(icon: "moon.fill", tint: .indigo, title: "Sleep", value: health.metrics.sleepSeconds.map { SleepFormat.durationHM($0) } ?? SleepFormat.durationHM(sleep.lastDuration), sub: "Debt \(SleepFormat.debtString(sleep.debt))")
            MetricTile(icon: "drop.fill", tint: .blue, title: "Water", value: "\(Int(health.waterTodayML)) ml", sub: "Goal \(health.plan?.waterTargetML ?? 2500) ml")
        }
    }

    var nutritionPreview: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Fuel", subtitle: "\(Int(health.caloriesEaten)) of \(health.goals.calorieTarget()) kcal · \(Int(health.proteinEaten))g protein", systemImage: "fork.knife")
                HStack {
                    MacroRingView(eaten: health.caloriesEaten, target: Double(health.goals.calorieTarget()), protein: health.proteinEaten, proteinTarget: Double(health.goals.proteinTarget()))
                        .frame(width: 150, height: 150)
                    VStack(spacing: 10) {
                        MacroBar(label: "Protein", grams: health.proteinEaten, target: Double(health.goals.proteinTarget()), color: .green)
                        MacroBar(label: "Carbs", grams: health.carbsEaten, target: Double(health.goals.calorieTarget()) * 0.45 / 4, color: .cyan)
                        MacroBar(label: "Fat", grams: health.fatEaten, target: Double(health.goals.calorieTarget()) * 0.3 / 9, color: .yellow)
                        Button { showCapture = true } label: {
                            Label("Snap a meal", systemImage: "camera.fill").font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent).tint(.orange).pressable()
                    }
                }
            }
        }
    }

    var workoutsPreview: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionHeader("Movement", subtitle: health.workoutsToday.isEmpty ? "Rest or move — your call" : "\(health.workoutsToday.count) session\(health.workoutsToday.count > 1 ? "s" : "") today", systemImage: "figure.run")
                    Spacer()
                    NavigationLink("All →") { ActivityView() }.font(.caption.weight(.bold)).foregroundStyle(.cyan)
                }
                if health.workoutsToday.isEmpty {
                    Text("No workouts yet. \(health.plan?.workoutSuggestion ?? "A walk counts.")")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7)).padding(.vertical, 4)
                } else {
                    ForEach(health.workoutsToday, id: \.id) { WorkoutRow($0) }
                }
                WeeklyLoadChart(workouts: health.workouts)
            }
        }
    }
}
