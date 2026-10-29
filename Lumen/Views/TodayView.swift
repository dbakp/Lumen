import SwiftUI

// MARK: - Today: how am I, and what should I do?
// One hero (readiness), three actions, four numbers, what's next.

public struct TodayView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var companion = CompanionStore.shared
    @ObservedObject private var hk = HealthKitService.shared
    @State private var showingEvidence = false
    public init() {}
    var perspective: DailyPerspective { companion.perspective(health: health) }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline).foregroundStyle(Theme.secondary)
                    Text("Your day, in context.").font(.system(.title2, weight: .bold)).fontWidth(.expanded).tracking(-1.2)
                }.padding(.top, 8)
                perspectiveCard
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { dailyActions }
                    VStack(spacing: 12) { dailyActions }
                }
                VStack(alignment: .leading, spacing: 0) {
                    GroupLabel("The whole picture").padding(.bottom, 12)
                    NavigationLink { HomeView() } label: {
                        LumenRow("Sleep", subtitle: "Rest, rhythm and tonight’s routine", value: health.metrics.sleepSeconds.map { SleepFormat.durationHM($0) } ?? "No recent night", icon: "moon", color: Theme.sleep)
                    }
                    Divider()
                    NavigationLink { ActivityView() } label: {
                        LumenRow("Activity", subtitle: "Movement, workouts and trends", value: health.hasActivityToday ? "\(Int(health.metrics.steps).formatted()) steps" : "No activity logged", icon: "figure.walk", color: Theme.move)
                    }
                    Divider()
                    NavigationLink { NutritionView() } label: {
                        LumenRow("Food", subtitle: "Meals, nutrients and your appetite", value: "\(health.mealsToday.count) logged", icon: "fork.knife", color: Theme.food)
                    }
                }.buttonStyle(.plain)
                waterRow
                if !companion.pendingActions.isEmpty {
                    GroupLabel("Your next steps")
                    ForEach(Array(companion.pendingActions.prefix(3))) { action in PlanActionRow(action: action) }
                    NavigationLink("View all plan steps", destination: PlanAgendaView()).frame(minHeight: 44)
                }
                if !companion.activeSymptoms.isEmpty {
                    Button { AppRouter.shared.tab = .journal } label: {
                        LumenRow("\(companion.activeSymptoms.count) ongoing symptom log\(companion.activeSymptoms.count == 1 ? "" : "s")", subtitle: "Update how you feel or mark a symptom resolved", icon: "bandage", color: Theme.heart)
                    }.buttonStyle(.plain)
                }
                let events = Array(companion.timeline(health: health, sleep: sleep, on: Date()).prefix(4))
                if !events.isEmpty {
                    GroupLabel("Today’s story", action: ("View journal", { AppRouter.shared.tab = .journal }))
                    TimelineList(events: events)
                }
                NavigationLink { ConnectionsView() } label: {
                    LumenRow("Your sources", subtitle: hk.isAuthorized ? "Apple Health access requested · review sync and imports" : "Connect Apple Health or import your history", icon: "externaldrive", color: Theme.accent)
                }.buttonStyle(.plain)
                Text("A daily perspective for your wellbeing. Your own sense of how you feel always matters alongside the numbers.").font(.footnote).foregroundStyle(Theme.secondary)
            }.padding(.horizontal, Theme.gutter).padding(.bottom, 32)
        }.lumenScreen().navigationTitle("Lumen").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { LogToolbarButton() }
                ToolbarItem(placement: .topBarTrailing) { Button { AppRouter.shared.show(.settings) } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Settings") }
            }
            .refreshable { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
    }
    var perspectiveCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Label("Your daily perspective", systemImage: "sun.horizon").font(.subheadline); Spacer() }
            Text(perspective.title).font(.system(.largeTitle, weight: .bold)).tracking(-0.7).fixedSize(horizontal: false, vertical: true)
            Text(perspective.body).font(.subheadline).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            ContextArc(sleepKnown: health.metrics.sleepSeconds != nil, activityKnown: health.hasActivityToday, foodKnown: !health.mealsToday.isEmpty || health.caloriesEaten > 0)
                .padding(.top, 6)
            Button {
                withAnimation(.snappy(duration: 0.25)) { showingEvidence.toggle() }
            } label: {
                HStack {
                    Text(showingEvidence ? "Hide evidence" : "Why this perspective").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showingEvidence ? "chevron.up" : "chevron.down").font(.footnote.weight(.semibold))
                }.foregroundStyle(Color.white).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityValue(showingEvidence ? "Expanded" : "Collapsed")
            if showingEvidence {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(perspective.evidence, id: \.self) { Text($0).font(.footnote) }
                    Text("From your available Health readings, imports and Lumen logs. Gaps and partial access can affect this summary.").font(.footnote)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.foregroundStyle(Color.white).padding(24)
            .background(LinearGradient(colors: [Color(hex: "087C83"), Color(hex: "005E68")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.2), lineWidth: 1))
            .shadow(color: Theme.accent.opacity(0.12), radius: 16, y: 8)
    }
    @ViewBuilder var dailyActions: some View {
        Button("Log how you feel", systemImage: "plus") { AppRouter.shared.show(.symptom) }.buttonStyle(LumenPrimaryButtonStyle())
        Button("Check in") { AppRouter.shared.show(.checkIn) }.buttonStyle(LumenTonalButtonStyle())
    }
    var waterRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "drop").font(.title2).foregroundStyle(Theme.water)
            VStack(alignment: .leading, spacing: 4) {
                Text("Water logged").font(.subheadline).foregroundStyle(Theme.secondary)
                Text(Units.water(health.waterTodayML, sleep.profile.unitSystem)).font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
            }
            Spacer()
            Button("+ 250 ml") { health.addWater(ml: 250); AppRouter.shared.confirm("Added 250 ml") }
                .font(.subheadline.bold()).padding(.horizontal, 16).frame(minHeight: 48).background(Theme.surfaceRaised, in: Capsule())
                .accessibilityLabel("Add 250 millilitres of water")
        }.padding(20).surface()
    }
}

/// Three labelled signals, not a synthetic composite score. Unavailable signals stay hollow.
struct ContextArc: View {
    var sleepKnown: Bool
    var activityKnown: Bool
    var foodKnown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ForEach(0..<3) { i in
                    let available = [sleepKnown, activityKnown, foodKnown][i]
                    Circle().trim(from: 0.52 + Double(i) * 0.16, to: 0.64 + Double(i) * 0.16)
                        .stroke(Color.white.opacity(available ? 0.85 : 0.22), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: 194, height: 194)
                }
            }.offset(y: 8).padding(.horizontal, 10).frame(height: 112, alignment: .top).clipped()
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { signalLabels }
            } else {
                HStack(alignment: .top, spacing: 12) { signalLabels }
            }
        }.frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .spring(response: 0.3), value: sleepKnown)
            .accessibilityElement(children: .combine)
    }
    @ViewBuilder var signalLabels: some View {
        signal("Sleep", sleepKnown)
        signal("Movement", activityKnown)
        signal("Food", foodKnown)
    }
    func signal(_ title: String, _ known: Bool) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: known ? "checkmark.circle.fill" : "circle.dashed").font(.caption)
            Text(known ? "Recorded" : "No data").font(.caption2).opacity(0.85)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(known ? "recorded" : "no data")")
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - Readiness breakdown (plain language)

struct ReadinessDetailSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let r = health.readiness {
                        HStack(spacing: 18) {
                            ZStack {
                                ThinRing(progress: Double(r.score) / 100, color: Theme.readiness(r.score), width: 8)
                                Text("\(r.score)").font(.system(size: 30, weight: .semibold, design: .rounded))
                            }
                            .frame(width: 84, height: 84)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Readiness").font(.subheadline).foregroundStyle(Theme.secondary)
                                Text(r.headline).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                            }
                        }
                        Text("A 0–100 estimate of how recovered you are, from your recent sleep and your heart's overnight signals. Higher means your body can take on more today.")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        VStack(alignment: .leading, spacing: 12) {
                            GroupLabel("What's affecting it")
                            RowGroup {
                                ForEach(Array(r.factors.enumerated()), id: \.element.id) { i, f in
                                    if i > 0 { RowDivider() }
                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: f.delta >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                            .foregroundStyle(f.delta >= 0 ? Theme.steps : Theme.food).frame(width: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(Self.plain(f.label)).font(.body).foregroundStyle(Theme.text)
                                            Text(f.detail).font(.footnote).foregroundStyle(Theme.secondary)
                                        }
                                        Spacer()
                                        Text(f.delta >= 0 ? "+\(f.delta)" : "\(f.delta)").font(.body.monospacedDigit()).foregroundStyle(Theme.secondary)
                                    }
                                    .padding(.vertical, 12)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            GroupLabel("Activity target today")
                            Text("\(r.strainTarget.lowerBound)–\(r.strainTarget.upperBound) active calories")
                                .font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("Staying in this range builds fitness without wearing you out.").font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Readiness").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Theme.accent)
    }

    static func plain(_ label: String) -> String {
        if label.hasPrefix("HRV") { return "Heart rate variability" }
        if label == "Yesterday's load" { return "Recent training" }
        return label
    }
}
