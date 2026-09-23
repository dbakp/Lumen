import SwiftUI

// MARK: - Today: one glance answers "how am I, and what should I do?"
// Readiness + rings, coach briefing, vitals, fuel, movement, insights.

public struct TodayView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var hk = HealthKitService.shared
    @State private var showCapture = false
    @State private var showSettings = false
    @State private var showLogSleep = false
    @State private var showReadiness = false

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if !hk.isAuthorized { connectHealthCard }
                readinessAndRings
                if let plan = health.plan, !health.isCalibrating {
                    BriefingCard(plan: plan, readiness: health.readiness)
                }
                metricsGrid
                NavigationLink { TrendsView() } label: { trendsTeaser }.buttonStyle(.plain)
                nutritionPreview
                workoutsPreview
                if !health.isCalibrating {
                    ForEach(health.insights) { InsightCard($0) }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCapture) { MealCaptureView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogSleep) { LogSleepSheet() }
        .sheet(isPresented: $showReadiness) { ReadinessDetailSheet() }
        .refreshable { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
    }

    // MARK: Header

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date().formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.5)).tracking(1.2)
                    Text(greeting + (sleep.profile.name.isEmpty ? "" : ", \(sleep.profile.name)"))
                        .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer()
                Button { showSettings = true } label: {
                    Text(String(sleep.profile.name.prefix(1)).uppercased().ifEmpty("•"))
                        .font(.headline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .accessibilityLabel("Settings")
            }
            HStack(spacing: 8) {
                DataPill(live: hk.isAuthorized)
                if health.isSyncing {
                    ProgressView().controlSize(.mini).tint(.white)
                } else if let sync = health.lastSync, hk.isAuthorized {
                    Text("Updated \(sync.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(.top, 12)
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 0..<5: return "Still up"; case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" }
    }

    var connectHealthCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill").font(.title2).foregroundStyle(.pink)
                    .frame(width: 48, height: 48).background(Color.pink.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Apple Health").font(.headline).foregroundStyle(.white)
                    Text("Unlock readiness, sleep stages and activity from your iPhone and Watch.").font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task { if await hk.requestAuthorization() { await SyncCoordinator.syncEverything(sleep: sleep, health: health) } }
            }
        }
    }

    // MARK: Readiness + rings

    var readinessAndRings: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button { if !health.isCalibrating { showReadiness = true } } label: {
                        ReadinessDial(score: health.readiness?.score).frame(width: 150, height: 150)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    VStack(spacing: 10) {
                        TripleRingView(
                            move: health.moveProgress,
                            exercise: min(1, health.metrics.exerciseMin / max(1, health.goals.exerciseGoalMin)),
                            stand: Double(health.metrics.standHours) / Double(max(1, health.goals.standGoal))
                        ).scaleEffect(0.85).frame(width: 150, height: 150)
                    }
                    Spacer()
                }
                if health.isCalibrating {
                    VStack(spacing: 8) {
                        Text("Readiness appears after your first night of sleep or a heart-rate reading.")
                            .font(.caption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                        Button { showLogSleep = true } label: {
                            Label("Log last night", systemImage: "bed.double.fill").font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered).tint(.cyan).controlSize(.small)
                    }
                } else if let r = health.readiness {
                    Text(r.headline).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }
                HStack(spacing: 14) {
                    ringLegend(.pink, "Move", "\(Int(health.metrics.activeCalories))/\(Int(health.goals.activeCalGoal))")
                    ringLegend(.green, "Exercise", "\(Int(health.metrics.exerciseMin))/\(Int(health.goals.exerciseGoalMin))")
                    ringLegend(.cyan, "Stand", "\(health.metrics.standHours)/\(health.goals.standGoal)")
                }
            }
        }
    }

    func ringLegend(_ c: Color, _ t: String, _ v: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6))
            Text(v).font(.caption2.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
        }
    }

    // MARK: Metrics

    var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(icon: "shoeprints.fill", tint: .cyan, title: "Steps", value: Int(health.metrics.steps).formatted(), sub: "Goal \(Int(health.goals.stepGoal).formatted())")
            MetricTile(icon: "heart.fill", tint: .pink, title: "Resting HR", value: health.metrics.restingHR.map { "\(Int($0)) bpm" } ?? "—", sub: "HRV \(health.metrics.hrvMS.map { "\(Int($0)) ms" } ?? "—")")
            Button { if sleep.lastNight == nil { showLogSleep = true } } label: {
                MetricTile(icon: "moon.fill", tint: .indigo, title: "Last night", value: sleep.lastNight.map { SleepFormat.durationHM($0.duration) } ?? "Log it",
                           sub: sleep.hasSleepData ? "Debt \(SleepFormat.debtString(sleep.debt))" : "No nights yet")
            }
            .buttonStyle(.plain)
            Button { health.addWater(ml: 250); haptic(.light) } label: {
                MetricTile(icon: "drop.fill", tint: .blue, title: "Water · tap +250", value: Units.water(health.waterTodayML, units),
                           sub: "Goal \(Units.water(Double(health.plan?.waterTargetML ?? 2500), units))")
            }
            .buttonStyle(.plain)
        }
    }

    var trendsTeaser: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line").font(.title3).foregroundStyle(.purple)
                    .frame(width: 44, height: 44).background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trends").font(.headline).foregroundStyle(.white)
                    Text("Sleep, heart and activity over weeks and months").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: Fuel

    var nutritionPreview: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader("Fuel", subtitle: "\(Int(health.caloriesEaten)) of \(health.goals.calorieTarget()) kcal · \(Int(health.proteinEaten)) g protein", systemImage: "fork.knife")
                    NavigationLink { NutritionView() } label: {
                        Text("Journal").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                    }
                }
                HStack {
                    MacroRingView(eaten: health.caloriesEaten, target: Double(health.goals.calorieTarget()), protein: health.proteinEaten, proteinTarget: Double(health.goals.proteinTarget()))
                        .frame(width: 140, height: 140)
                    VStack(spacing: 10) {
                        MacroBar(label: "Protein", grams: health.proteinEaten, target: Double(health.goals.proteinTarget()), color: .green)
                        MacroBar(label: "Carbs", grams: health.carbsEaten, target: Double(health.goals.calorieTarget()) * 0.45 / 4, color: .cyan)
                        MacroBar(label: "Fat", grams: health.fatEaten, target: Double(health.goals.calorieTarget()) * 0.3 / 9, color: .yellow)
                        Button { showCapture = true } label: {
                            Label("Snap a meal", systemImage: "camera.fill").font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent).tint(.orange)
                    }
                }
            }
        }
    }

    // MARK: Movement

    var workoutsPreview: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionHeader("Movement", subtitle: health.workoutsToday.isEmpty ? (health.isCalibrating ? "Rest or move — your call" : health.plan?.workoutSuggestion ?? "") : "\(health.workoutsToday.count) session\(health.workoutsToday.count > 1 ? "s" : "") today", systemImage: "figure.run")
                }
                if health.workoutsToday.isEmpty {
                    Text("No sessions yet today. Workouts from your Watch, Strava or logged here show up automatically.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65)).padding(.vertical, 4)
                } else {
                    ForEach(health.workoutsToday, id: \.id) { WorkoutRow($0) }
                }
                if !health.workouts.isEmpty { WeeklyLoadChart(workouts: health.workouts) }
            }
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - Readiness breakdown

struct ReadinessDetailSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ReadinessDial(score: health.readiness?.score).frame(width: 180, height: 180).padding(.top, 10)
                    if let r = health.readiness {
                        Text(r.headline).font(.title3.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeader("What's driving it", systemImage: "slider.horizontal.3")
                                ForEach(r.factors) { f in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.label).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                            Text(f.detail).font(.caption).foregroundStyle(.white.opacity(0.65))
                                        }
                                        Spacer()
                                        Text(f.delta >= 0 ? "+\(f.delta)" : "\(f.delta)")
                                            .font(.headline.monospacedDigit()).foregroundStyle(f.delta >= 0 ? .green : .orange)
                                    }
                                }
                            }
                        }
                        GlassCard {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionHeader("Today's training window", systemImage: "flame.fill")
                                Text("\(r.strainTarget.lowerBound)–\(r.strainTarget.upperBound) active kcal").font(.title3.weight(.bold)).foregroundStyle(.white)
                                Text("Staying inside this range builds fitness without digging a recovery hole.").font(.caption).foregroundStyle(.white.opacity(0.65))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }
            .background(AuroraBackground())
            .navigationTitle("Readiness").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
