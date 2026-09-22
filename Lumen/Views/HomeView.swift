import SwiftUI

// MARK: - Today / Home (Rise-parity hero)

public struct HomeView: View {
    @EnvironmentObject var store: SleepStore
    @State private var showLog = false

    public init() {}

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 0..<5: return "Deep night"; case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting + ", \(store.profile.name)")
                            .font(.title2.weight(.bold)).foregroundStyle(.white)
                        Text("Energy potential \(store.energyPotential) · Need \(SleepFormat.durationHM(store.profile.sleepNeed))")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    // Energy potential pill
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: 6)
                            .frame(width: 56, height: 56)
                        Circle().trim(from: 0, to: CGFloat(store.energyPotential)/100)
                            .stroke(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90)).frame(width: 56, height: 56)
                        Text("\(store.energyPotential)")
                            .font(.headline.weight(.bold)).foregroundStyle(.white)
                    }
                }
                .padding(.top, 8)

                // Hero debt card
                GlassCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SLEEP DEBT").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(1.2)
                            if let last = store.lastNight {
                                Text("Last night \(SleepFormat.durationHM(last.duration)) · in bed \(SleepFormat.time(last.bedtime))")
                                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                            }
                            Button {
                                haptic()
                                showLog = true
                            } label: {
                                Label("Log sleep", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                        }
                        Spacer()
                        DebtRingView(debt: store.debt, need: store.profile.sleepNeed)
                            .scaleEffect(0.82).frame(width: 170, height: 170)
                    }
                }

                // Energy preview
                if let pred = store.prediction {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Today's energy", subtitle: "Predicted from your rhythm + debt", systemImage: "waveform.path.ecg")
                            EnergyCurveView(points: pred.curve, now: Date())
                            HStack {
                                Label("Grogginess ends \(SleepFormat.time(pred.grogginessEnds))", systemImage: "alarm")
                                Spacer()
                                Label("Peak \(SleepFormat.time(pred.afternoonPeak))", systemImage: "bolt.fill")
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                            NavigationLink {
                                EnergyView()
                            } label: {
                                Text("See full energy schedule →").font(.subheadline.weight(.semibold)).foregroundStyle(.cyan)
                            }
                        }
                    }

                    // Today's schedule
                    GlassCard {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader("Your day, timed", subtitle: "Nudges synced to your clock", systemImage: "calendar")
                            TimelineRow(icon: "sunrise.fill", color: .orange, title: "Wake zone", time: SleepFormat.time(pred.wakeZone.lowerBound), detail: "Get light + water within 30 min.")
                            TimelineRow(icon: "brain.head.profile", color: .cyan, title: "Deep focus", time: SleepFormat.time(pred.morningPeak), detail: "Hardest tasks here — alertness is high.")
                            TimelineRow(icon: "cloud.sun.fill", color: .yellow, title: "Midday dip", time: SleepFormat.time(pred.middayDip), detail: "Light walk or 20-min nap, not a 4th coffee.")
                            TimelineRow(icon: "bolt.fill", color: .purple, title: "Second wind", time: SleepFormat.time(pred.afternoonPeak), detail: "Workouts + meetings shine here.")
                            TimelineRow(icon: "cup.and.saucer.fill", color: .brown, title: "Caffeine cutoff", time: SleepFormat.time(pred.caffeineCutoff), detail: "Last call — protects melatonin.")
                            TimelineRow(icon: "wind", color: .teal, title: "Wind down", time: SleepFormat.time(pred.windDown), detail: "Dim lights, screens down.")
                            TimelineRow(icon: "moon.fill", color: .indigo, title: "Melatonin window", time: SleepFormat.timeRange(pred.melatoninWindow), detail: "Easiest 60 min to fall asleep.")
                            Divider().background(.white.opacity(0.12))
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Suggested bedtime").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.6)).tracking(0.8)
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

                // Habits teaser
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Rituals", subtitle: "\(store.habits.filter(\.doneToday).count)/\(store.habits.filter(\.isEnabled).count) done", systemImage: "checklist")
                        ForEach(store.habits.filter(\.isEnabled).prefix(4)) { h in
                            HabitRowCompact(habit: h) { store.toggleHabitDone(h.id); haptic(.light) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .sheet(isPresented: $showLog) { LogSleepSheet() }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
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
