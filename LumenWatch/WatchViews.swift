import SwiftUI
import Charts

// MARK: - Watch root: vertical pages — Readiness · Sleep · Tonight · Activity · Fuel · Rituals

struct WatchRootView: View {
    @EnvironmentObject var store: WatchStore
    @State private var page: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-watchPage"), i + 1 < args.count, let p = Int(args[i + 1]) { return p }
        return 0
    }()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
        if let s = store.snapshot {
            NavigationStack {
            TabView(selection: $page) {
                ReadinessPage(s: s, now: context.date).tag(0).containerBackground(readinessColor(s.currentReadiness(at: context.date)).gradient.opacity(0.45), for: .tabView)
                SleepPage(s: s, now: context.date).tag(1).containerBackground(Color(red: 0.29, green: 0.48, blue: 0.55).gradient.opacity(0.45), for: .tabView)
                TonightPage(s: s, now: context.date).tag(2).containerBackground(Color(red: 0.0, green: 0.42, blue: 0.45).gradient.opacity(0.4), for: .tabView)
                ActivityPage(s: s, now: context.date).tag(3).containerBackground(Color.pink.gradient.opacity(0.35), for: .tabView)
                FuelPage(s: s, now: context.date).tag(4).containerBackground(Color.orange.gradient.opacity(0.35), for: .tabView)
                RitualsPage(s: s, now: context.date).tag(5).containerBackground(Color.green.gradient.opacity(0.3), for: .tabView)
            }
            .tabViewStyle(.verticalPage)
            }
        } else {
            SetupPage()
        }
        }
        .alert("Water wasn’t saved", isPresented: Binding(get: { store.waterError != nil }, set: { if !$0 { store.waterError = nil } })) { Button("OK", role: .cancel) { store.waterError = nil } } message: { Text(store.waterError ?? "Try again.") }
    }
}

func readinessColor(_ score: Int?) -> Color {
    guard let score else { return .gray }
    return score >= 85 ? .green : score >= 70 ? .cyan : score >= 55 ? .yellow : .orange
}

func hm(_ secs: Double) -> String {
    guard secs.isFinite, secs >= 0, secs < Double(Int.max / 2) else { return "Not available" }
    let m = Int(secs / 60); return "\(m / 60)h \(m % 60)m"
}

func clock(_ d: Date?) -> String { d?.formatted(date: .omitted, time: .shortened) ?? "Not available" }

struct Ring: View {
    let progress: Double; let color: Color; var width: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: width)
            Circle().trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8), value: progress)
        }
    }
}

func snapshotStamp(_ snapshot: WatchSnapshot) -> String {
    guard let date = snapshot.observations?.capturedAt, date.timeIntervalSince1970.isFinite else { return "Snapshot date unavailable" }
    return "iPhone snapshot · " + date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
}

// MARK: Setup

struct SetupPage: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.cyan.gradient)
                Text("Your iPhone snapshot").font(.headline)
                Text("Open Lumen on your iPhone to finish setup. Your saved readings and plan appear here.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Check again") { store.requestSnapshot() }.tint(.cyan)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: Readiness

struct ReadinessPage: View {
    let s: WatchSnapshot
    let now: Date
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Ring(progress: Double(s.currentReadiness(at: now) ?? 0) / 100, color: readinessColor(s.currentReadiness(at: now)), width: 11)
                VStack(spacing: -2) {
                    if let r = s.currentReadiness(at: now) {
                        Text("\(r)").font(.system(size: 44, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    } else {
                        Image(systemName: "sparkles").font(.title2)
                    }
                    Text(s.currentReadiness(at: now) == nil ? "NOT AVAILABLE" : "ESTIMATE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 118, height: 118)
            Text(s.currentReadiness(at: now) == nil ? (s.planningAvailable(at: now) ? "More evidence needed" : "Open Lumen on iPhone") : (s.readinessHeadline ?? "Unvalidated wellness estimate"))
                .font(.footnote.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
            if s.planningAvailable(at: now), let lo = s.strainLow, let hi = s.strainHigh {
                Label("\(lo)–\(hi) kcal today", systemImage: "flame.fill").font(.caption2).foregroundStyle(.orange)
            }
        }
        .navigationTitle("Readiness")
    }
}

// MARK: Sleep

struct SleepPage: View {
    let s: WatchSnapshot
    let now: Date
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(s.observations?.estimates.contains("sleep") == true ? "TIME IN BED" : "TODAY’S SLEEP RECORD").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Text(s.reading("sleep", at: now).map { hm($0 * 3600) } ?? "Not recorded").font(.system(size: 30, weight: .bold, design: .rounded))
                if s.reading("sleep", at: now) != nil, let b = s.lastBedtime, let w = s.lastWake {
                    Text("\(clock(b)) → \(clock(w))").font(.caption).foregroundStyle(.secondary)
                }
                if s.reading("sleep", at: now) != nil { StagesBar(s: s, now: now) }
                HStack {
                    stat("Est. debt", s.reading("sleepDebt", at: now).map { EvidenceFormat.amount($0, unit: "h") } ?? "Not available", .secondary)
                    Spacer()
                    stat("Est. energy", s.reading("energyEstimate", at: now).map(EvidenceFormat.number) ?? "Unknown", .cyan)
                    Spacer()
                    stat("Target", s.planningAvailable(at: now) ? hm(s.sleepNeedSeconds) : "Unknown", .indigo)
                }
                .padding(.top, 4)
                Text(snapshotStamp(s)).font(.caption2).foregroundStyle(.secondary)
                Text("Targets and model outputs are estimates.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sleep")
    }
    func stat(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.system(.footnote, design: .rounded).weight(.bold)).foregroundStyle(c)
            Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

struct StagesBar: View {
    let s: WatchSnapshot
    let now: Date
    var stages: [(String, Double, Color)] {
        [("Awake", s.awakeSeconds ?? 0, .orange), ("REM", s.remSeconds ?? 0, .cyan),
         ("Core", s.coreSeconds ?? 0, .blue), ("Deep", s.deepSeconds ?? 0, .indigo)].filter { $0.1 > 0 }
    }
    var body: some View {
        if stages.isEmpty {
            ProgressView(value: min(1, ((s.reading("sleep", at: now) ?? 0) * 3600) / max(1, s.sleepNeedSeconds))).tint(.indigo)
        } else {
            let total = stages.reduce(0) { $0 + $1.1 }
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { g in
                    HStack(spacing: 1.5) {
                        ForEach(stages, id: \.0) { st in
                            RoundedRectangle(cornerRadius: 3).fill(st.2.gradient)
                                .frame(width: max(3, (g.size.width - CGFloat(stages.count - 1) * 1.5) * st.1 / total))
                        }
                    }
                }
                .frame(height: 9)
                HStack(spacing: 6) {
                    ForEach(stages, id: \.0) { st in
                        HStack(spacing: 2) {
                            Circle().fill(st.2).frame(width: 5, height: 5)
                            Text(st.0).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Tonight

struct TonightPage: View {
    let s: WatchSnapshot
    let now: Date
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("BEDTIME TONIGHT").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Text(clock(s.planningAvailable(at: now) ? s.bedtime : nil)).font(.system(size: 32, weight: .bold, design: .rounded))
                if s.planningAvailable(at: now), !s.energyCurve.isEmpty {
                    Chart {
                        ForEach(Array(s.energyCurve.enumerated()), id: \.offset) { i, v in
                            AreaMark(x: .value("h", i), y: .value("e", v))
                                .foregroundStyle(LinearGradient(colors: [.teal.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("h", i), y: .value("e", v)).foregroundStyle(.teal).interpolationMethod(.catmullRom)
                        }
                        RuleMark(x: .value("now", Calendar.current.component(.hour, from: Date()))).foregroundStyle(.white.opacity(0.6))
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .frame(height: 44)
                }
                if s.planningAvailable(at: now) {
                    if s.windDown != nil { row("wind", .teal, "Wind down", clock(s.windDown)) }
                    if let start = s.melatoninStart, let end = s.melatoninEnd {
                        row("moon.fill", .blue, "Estimated sleep window", "\(clock(start))–\(clock(end))")
                    } else { Text("Sleep timing estimate not available").font(.footnote).foregroundStyle(.secondary) }
                    if s.caffeineCutoff != nil { row("cup.and.saucer.fill", .brown, "Caffeine cutoff", clock(s.caffeineCutoff)) }
                }
                Text(snapshotStamp(s)).font(.caption2).foregroundStyle(.secondary)
                Text("Optional plan from profile targets and available sleep timing. It does not measure alertness or melatonin.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tonight")
    }
    func row(_ icon: String, _ c: Color, _ t: String, _ v: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(c).frame(width: 18)
            Text(t).font(.caption)
            Spacer()
            Text(v).font(.caption.monospacedDigit().weight(.semibold))
        }
    }
}

// MARK: Activity

struct ActivityPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    let now: Date
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Ring(progress: (store.activityValue("activeEnergy", at: now) ?? 0) / max(1, s.moveGoal), color: .pink, width: 10).frame(width: 100, height: 100)
                    Ring(progress: (store.activityValue("exercise", at: now) ?? 0) / max(1, s.exerciseGoal), color: .green, width: 10).frame(width: 76, height: 76)
                    Ring(progress: (store.activityValue("stand", at: now) ?? 0) / Double(max(1, s.standGoal)), color: .cyan, width: 10).frame(width: 52, height: 52)
                }.accessibilityHidden(true)
                reading("Move", key: "activeEnergy", unit: "kcal")
                reading("Exercise", key: "exercise", unit: "min")
                reading("Stand or roll", key: "stand", unit: "h")
                reading("Steps", key: "steps", unit: "steps")
                if let heart = store.activityValue("heartRate", at: now) {
                    Label(EvidenceFormat.amount(heart, unit: "bpm"), systemImage: "heart.fill").font(.footnote)
                    if let time = store.heartRateDate { Text("Recorded " + time.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                }
                Text("Today's watch readings. Empty results can mean no data or no access.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Activity").task { await store.refreshActivity() }
    }
    func reading(_ label: String, key: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(EvidenceFormat.amount(store.activityValue(key, at: now), unit: unit)).font(.footnote.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: Fuel

struct FuelPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    let now: Date
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("From iPhone").font(.headline)
                Text(snapshotStamp(s)).font(.caption2).foregroundStyle(.secondary)
                reading("Food energy", s.reading("calories", at: now), unit: "kcal")
                reading("Protein", s.reading("protein", at: now), unit: "g")
                reading("Water", s.reading("water", at: now), unit: "ml")
                if s.planningAvailable(at: now) { Text("Estimated food target: \(EvidenceFormat.number((Double(s.calorieTarget) / 10).rounded() * 10)) kcal").font(.footnote).foregroundStyle(.secondary) }
                Divider()
                Text("Water logged on this Watch").font(.headline)
                Text(EvidenceFormat.amount(store.savedWatchWater?.value("water", at: now), unit: "ml water")).font(.footnote)
                Text("These totals can overlap. They are kept separate here.").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("+250 ml") { store.logWater(250); WKHaptic.click() }.tint(.blue)
                    Button("+500 ml") { store.logWater(500); WKHaptic.click() }.tint(.blue)
                }.font(.footnote.weight(.semibold)).disabled(store.savingWater)
                if store.savingWater { ProgressView("Saving to Health") }
            }
        }.navigationTitle("Food & water")
    }
    func reading(_ label: String, _ value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(EvidenceFormat.amount(value, unit: unit)).font(.footnote.weight(.semibold))
        }
    }
}

// MARK: Rituals

struct RitualsPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    let now: Date
    var body: some View {
        List {
            if !s.planningAvailable(at: now) { Text("Saved iPhone snapshot. Open Lumen on iPhone to refresh today’s habit status.").font(.footnote).foregroundStyle(.secondary) }
            if s.rituals.isEmpty {
                Text("Turn on rituals in Lumen on your iPhone.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(s.rituals) { r in
                Button {
                    store.toggleRitual(r.id); WKHaptic.success(r.done)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: r.done ? "checkmark.circle.fill" : r.icon)
                            .foregroundStyle(r.done ? .green : .white)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.title).font(.footnote.weight(.semibold)).strikethrough(r.done).lineLimit(2)
                            if let t = r.time { Text(clock(t)).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }.disabled(!s.planningAvailable(at: now))
            }
        }
        .navigationTitle(s.planningAvailable(at: now) ? "Habits \(s.rituals.filter(\.done).count)/\(s.rituals.count)" : "Saved habits")
    }
}

import WatchKit
enum WKHaptic {
    static func click() { WKInterfaceDevice.current().play(.click) }
    static func success(_ wasDone: Bool) { WKInterfaceDevice.current().play(wasDone ? .directionDown : .success) }
}
