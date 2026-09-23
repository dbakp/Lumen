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
        if let s = store.snapshot {
            NavigationStack {
            TabView(selection: $page) {
                ReadinessPage(s: s).tag(0).containerBackground(readinessColor(s.readiness).gradient.opacity(0.45), for: .tabView)
                SleepPage(s: s).tag(1).containerBackground(Color.indigo.gradient.opacity(0.45), for: .tabView)
                TonightPage(s: s).tag(2).containerBackground(Color.purple.gradient.opacity(0.4), for: .tabView)
                ActivityPage(s: s).tag(3).containerBackground(Color.pink.gradient.opacity(0.35), for: .tabView)
                FuelPage(s: s).tag(4).containerBackground(Color.orange.gradient.opacity(0.35), for: .tabView)
                RitualsPage(s: s).tag(5).containerBackground(Color.green.gradient.opacity(0.3), for: .tabView)
            }
            .tabViewStyle(.verticalPage)
            }
        } else {
            SetupPage()
        }
    }
}

func readinessColor(_ score: Int?) -> Color {
    guard let score else { return .gray }
    return score >= 85 ? .green : score >= 70 ? .cyan : score >= 55 ? .yellow : .orange
}

func hm(_ secs: Double) -> String {
    let m = Int(secs / 60); return "\(m / 60)h \(m % 60)m"
}

func clock(_ d: Date?) -> String { d?.formatted(date: .omitted, time: .shortened) ?? "—" }

struct Ring: View {
    let progress: Double; let color: Color; var width: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: width)
            Circle().trim(from: 0, to: max(0.015, min(1, progress)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8), value: progress)
        }
    }
}

// MARK: Setup

struct SetupPage: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.cyan.gradient)
                Text("Welcome to Lumen").font(.headline)
                Text("Open Lumen on your iPhone to finish setup — your plan appears here automatically.")
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
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Ring(progress: Double(s.readiness ?? 0) / 100, color: readinessColor(s.readiness), width: 11)
                VStack(spacing: -2) {
                    if let r = s.readiness {
                        Text("\(r)").font(.system(size: 44, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    } else {
                        Image(systemName: "sparkles").font(.title2)
                    }
                    Text(s.readiness == nil ? "CALIBRATING" : "READINESS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 118, height: 118)
            Text(s.readinessHeadline ?? "Sleep a night with your Watch to unlock readiness.")
                .font(.footnote.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
            if let lo = s.strainLow, let hi = s.strainHigh {
                Label("\(lo)–\(hi) kcal today", systemImage: "flame.fill").font(.caption2).foregroundStyle(.orange)
            }
        }
        .navigationTitle(s.name.isEmpty ? "Lumen" : "Hi, \(s.name)")
    }
}

// MARK: Sleep

struct SleepPage: View {
    let s: WatchSnapshot
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("LAST NIGHT").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Text(s.lastSleepSeconds.map(hm) ?? "No data").font(.system(size: 30, weight: .bold, design: .rounded))
                if let b = s.lastBedtime, let w = s.lastWake {
                    Text("\(clock(b)) → \(clock(w))").font(.caption).foregroundStyle(.secondary)
                }
                StagesBar(s: s)
                HStack {
                    stat("Debt", String(format: "%.1fh", s.debtHours), s.debtHours < 5 ? .green : .orange)
                    Spacer()
                    stat("Energy", "\(s.energyPotential)", .cyan)
                    Spacer()
                    stat("Need", hm(s.sleepNeedSeconds), .indigo)
                }
                .padding(.top, 4)
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
    var stages: [(String, Double, Color)] {
        [("Awake", s.awakeSeconds ?? 0, .orange), ("REM", s.remSeconds ?? 0, .cyan),
         ("Core", s.coreSeconds ?? 0, .blue), ("Deep", s.deepSeconds ?? 0, .indigo)].filter { $0.1 > 0 }
    }
    var body: some View {
        if stages.isEmpty {
            ProgressView(value: min(1, (s.lastSleepSeconds ?? 0) / max(1, s.sleepNeedSeconds))).tint(.indigo)
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("BEDTIME TONIGHT").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Text(clock(s.bedtime)).font(.system(size: 32, weight: .bold, design: .rounded))
                if !s.energyCurve.isEmpty {
                    Chart {
                        ForEach(Array(s.energyCurve.enumerated()), id: \.offset) { i, v in
                            AreaMark(x: .value("h", i), y: .value("e", v))
                                .foregroundStyle(LinearGradient(colors: [.purple.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("h", i), y: .value("e", v)).foregroundStyle(.purple).interpolationMethod(.catmullRom)
                        }
                        RuleMark(x: .value("now", Calendar.current.component(.hour, from: Date()))).foregroundStyle(.white.opacity(0.6))
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .frame(height: 44)
                }
                row("wind", .teal, "Wind down", clock(s.windDown))
                row("moon.fill", .indigo, "Melatonin", "\(clock(s.melatoninStart))–\(clock(s.melatoninEnd))")
                row("cup.and.saucer.fill", .brown, "Caffeine cutoff", clock(s.caffeineCutoff))
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
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Ring(progress: store.activeEnergy / max(1, s.moveGoal), color: .pink, width: 10).frame(width: 100, height: 100)
                Ring(progress: store.exerciseMin / max(1, s.exerciseGoal), color: .green, width: 10).frame(width: 76, height: 76)
                Ring(progress: store.standHours / Double(max(1, s.standGoal)), color: .cyan, width: 10).frame(width: 52, height: 52)
            }
            HStack(spacing: 10) {
                metric("\(Int(store.activeEnergy))", "kcal", .pink)
                metric("\(Int(store.exerciseMin))", "min", .green)
                metric("\(Int(store.standHours))", "hr", .cyan)
            }
            HStack {
                Label(Int(store.steps).formatted(), systemImage: "shoeprints.fill").font(.caption2)
                Spacer()
                if let hr = store.heartRate {
                    Label("\(Int(hr))", systemImage: "heart.fill").font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Activity")
        .task { await store.refreshActivity() }
    }
    func metric(_ v: String, _ u: String, _ c: Color) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.system(.footnote, design: .rounded).weight(.bold)).foregroundStyle(c)
            Text(u).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

// MARK: Fuel

struct FuelPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var water: Double { Double(s.waterML) + store.waterLoggedHere }
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Ring(progress: Double(s.caloriesEaten) / Double(max(1, s.calorieTarget)), color: .orange, width: 7)
                        VStack(spacing: -1) {
                            Text("\(s.caloriesEaten)").font(.system(.footnote, design: .rounded).weight(.bold))
                            Text("kcal").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(max(0, s.calorieTarget - s.caloriesEaten)) left").font(.footnote.weight(.semibold))
                        Text("Protein \(s.protein)/\(s.proteinTarget) g").font(.caption2).foregroundStyle(.green)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "drop.fill").foregroundStyle(.blue)
                        Text("\(Int(water)) / \(s.waterTargetML) ml").font(.caption.monospacedDigit())
                        Spacer()
                    }
                    ProgressView(value: min(1, water / Double(max(1, s.waterTargetML)))).tint(.blue)
                }
                HStack {
                    Button("+250") { store.logWater(250); WKHaptic.click() }.tint(.blue)
                    Button("+500") { store.logWater(500); WKHaptic.click() }.tint(.blue)
                }
                .font(.footnote.weight(.bold))
            }
        }
        .navigationTitle("Fuel")
    }
}

// MARK: Rituals

struct RitualsPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var body: some View {
        List {
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
                }
            }
        }
        .navigationTitle("Rituals \(s.rituals.filter(\.done).count)/\(s.rituals.count)")
    }
}

import WatchKit
enum WKHaptic {
    static func click() { WKInterfaceDevice.current().play(.click) }
    static func success(_ wasDone: Bool) { WKInterfaceDevice.current().play(wasDone ? .directionDown : .success) }
}
