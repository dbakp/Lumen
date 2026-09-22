import SwiftUI

// MARK: - Full circadian / energy schedule + smart bedtime planner

public struct EnergyView: View {
    @EnvironmentObject var store: SleepStore
    @State private var wakeGoal: Date = Date()
    @State private var extraPayback: Double = 0 // minutes

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let pred = store.prediction {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Energy schedule", subtitle: "Your predicted alertness today", systemImage: "chart.line.uptrend.xyaxis")
                            EnergyCurveView(points: pred.curve, now: Date())
                            HStack(spacing: 8) {
                                LegendDot(color: .cyan, label: "Peak")
                                LegendDot(color: .yellow, label: "Dip")
                                LegendDot(color: .indigo, label: "Melatonin")
                            }
                            .font(.caption2).foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 2) {
                            SectionHeader("Hour by hour", subtitle: "Plan around your biology", systemImage: "clock.fill")
                            TimelineRow(icon: "alarm.fill", color: .orange, title: "Sleep inertia lifts", time: SleepFormat.time(pred.grogginessEnds), detail: inertiaDetail)
                            TimelineRow(icon: "star.fill", color: .cyan, title: "Morning peak", time: "\(SleepFormat.time(pred.morningPeak))", detail: "Best window for deep work.")
                            TimelineRow(icon: "tortoise.fill", color: .yellow, title: "Afternoon dip", time: SleepFormat.time(pred.middayDip), detail: "Low alertness — walk, sunlight, or nap.")
                            TimelineRow(icon: "flame.fill", color: .purple, title: "Afternoon peak", time: SleepFormat.time(pred.afternoonPeak), detail: "Second-best window. Train here.")
                            TimelineRow(icon: "lamp.floor.fill", color: .teal, title: "Dim lights", time: SleepFormat.time(pred.windDown), detail: "Overheads off to let melatonin rise.")
                            TimelineRow(icon: "moon.stars.fill", color: .indigo, title: "Melatonin window", time: SleepFormat.timeRange(pred.melatoninWindow), detail: "Fall-asleep sweet spot. Don't miss it scrolling.")
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Smart bedtime", subtitle: "Debt-aware, rhythm-safe", systemImage: "bed.double.fill")
                            DatePicker("Wake goal", selection: $wakeGoal, displayedComponents: .hourAndMinute)
                                .colorScheme(.dark)
                                .onAppear { wakeGoal = store.wakeGoalToday }
                            VStack(alignment: .leading) {
                                Text("Extra payback: \(Int(extraPayback)) min")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                                Slider(value: $extraPayback, in: 0...60, step: 5)
                                    .tint(.cyan)
                            }
                            let plan = CircadianModel.suggestedBedtime(
                                wakeGoal: wakeGoal,
                                sleepNeed: store.profile.sleepNeed,
                                sleepDebt: store.debt,
                                habitualBedtime: habitualBed,
                                payExtraMin: extraPayback
                            )
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("BE IN BED BY").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(1)
                                    Text(SleepFormat.time(plan.bedtime)).font(.largeTitle.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                                }
                                Spacer()
                                Image(systemName: "moon.fill").font(.largeTitle).foregroundStyle(.indigo.opacity(0.9))
                            }
                            .padding().liquidGlass(cornerRadius: 18, tintOpacity: 0.2)
                            Text(plan.note).font(.caption).foregroundStyle(.white.opacity(0.65))
                            if willAddDebt(planBed: plan.bedtime) {
                                Label("That wake time would add debt — move bedtime earlier or wake later.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            } else {
                                Label("That wake time protects your debt.", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader("Why this works", subtitle: "Two-process science", systemImage: "book.fill")
                            Text("Alertness = circadian drive − sleep pressure − inertia. Light anchors the sine wave; consistent wake anchors everything. Paying debt 20–30 min/night beats weekend crashes.")
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .navigationTitle("Energy")
        .navigationBarTitleDisplayMode(.inline)
    }

    var habitualBed: Date {
        let secs = CircadianModel.circularMean(store.episodes.suffix(7).map { CircadianModel.secondsSinceMidnight($0.bedtime, calendar: .current) }) ?? (23*3600)
        return Calendar.current.startOfDay(for: Date()).addingTimeInterval(secs)
    }

    var inertiaDetail: String {
        guard let pred = store.prediction else { return "" }
        let mins = max(0, pred.grogginessEnds.timeIntervalSince(pred.wakeZone.lowerBound) / 60)
        return "Groggy for ~\(Int(mins)) min after waking — light + movement shortens it."
    }

    func willAddDebt(planBed: Date) -> Bool {
        let sleepWindow = wakeGoal.timeIntervalSince(planBed)
        if sleepWindow < 0 { return true }
        return sleepWindow < store.profile.sleepNeed - 15*60
    }
}

struct LegendDot: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
