import SwiftUI

// MARK: - Today: how am I, and what should I do?
// One hero (readiness), three actions, four numbers, what's next.

public struct TodayView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var hk = HealthKitService.shared
    var router: AppRouter { .shared }

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !hk.isAuthorized { connectBanner }
                hero
                focus
                tiles
                upNext
                tip
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 40)
        }
        .lumenScreen(Theme.readiness(health.readiness?.score))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { LogToolbarButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.show(.settings) } label: {
                    Text(String(sleep.profile.name.prefix(1)).uppercased().ifEmpty("•"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.surfaceRaised, in: Circle())
                }
                .accessibilityLabel("Settings")
            }
        }
        .refreshable { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
    }

    // MARK: Header

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
            Text(greeting + (sleep.profile.name.isEmpty ? "" : ", \(sleep.profile.name)"))
                .font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<5: return "Still up"; case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening"
        }
    }

    var connectBanner: some View {
        Button {
            Task { if await hk.requestAuthorization() { await SyncCoordinator.syncEverything(sleep: sleep, health: health) } }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill").font(.title3).foregroundStyle(Theme.heart)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Apple Health").font(.headline).foregroundStyle(Theme.text)
                    Text("See your sleep, steps and heart here automatically.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(16).surface()
        }
        .buttonStyle(.plain)
    }

    // MARK: Hero

    var hero: some View {
        let score = health.readiness?.score
        let color = Theme.readiness(score)
        return Button { if score != nil { router.show(.readiness) } } label: {
            VStack(spacing: 18) {
                ZStack {
                    ThinRing(progress: Double(score ?? 0) / 100, color: color, width: 12)
                    VStack(spacing: 2) {
                        Text(score.map(String.init) ?? "–")
                            .font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Theme.text).contentTransition(.numericText())
                        Text(score == nil ? "Getting to know you" : "Readiness")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                    }
                }
                .frame(width: 200, height: 200)
                VStack(spacing: 6) {
                    Text(score == nil ? "Your score appears after your first night" : readinessLine)
                        .font(.title3.weight(.semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                    if score != nil {
                        Text("Based on your sleep and heart · Tap for details").font(.footnote).foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(score.map { "Readiness \($0) out of 100. \(readinessLine)" } ?? "Readiness not available yet")
    }

    var readinessLine: String {
        guard let s = health.readiness?.score else { return "" }
        switch s {
        case 80...: return "You're ready for a big day"
        case 65..<80: return "Good to go — steady effort"
        case 50..<65: return "Take it a little easier today"
        default: return "A rest day will pay off"
        }
    }

    // MARK: Focus

    @ViewBuilder var focus: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Today's focus")
            VStack(alignment: .leading, spacing: 0) {
                let items = focusItems
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 34) }
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(i + 1)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.tertiary).frame(width: 20)
                        Text(item).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 13)
                }
            }
            .padding(.horizontal, 16)
            .surface()
        }
    }

    var focusItems: [String] {
        if health.isCalibrating {
            var out: [String] = []
            if !hk.isAuthorized { out.append("Connect Apple Health so Lumen can read your sleep and steps.") }
            out.append(sleep.hasSleepData ? "Wear your Watch to bed tonight for sleep stages." : "Log last night's sleep — tap + at the top.")
            out.append("Snap your next meal to track calories and protein.")
            return out
        }
        return health.plan?.bullets ?? []
    }

    // MARK: Tiles

    var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink { TrendsView(metric: .sleep) } label: {
                StatTile("Sleep", value: sleep.lastNight.map { SleepFormat.durationHM($0.duration) } ?? "—",
                         caption: sleep.hasSleepData ? "Need \(SleepFormat.durationHM(sleep.profile.sleepNeed))" : "No nights yet",
                         color: Theme.sleep, progress: sleep.lastNight.map { $0.duration / sleep.profile.sleepNeed })
            }
            NavigationLink { TrendsView(metric: .steps) } label: {
                StatTile("Steps", value: Int(health.metrics.steps).formatted(), caption: "Goal \(Int(health.goals.stepGoal).formatted())",
                         color: Theme.steps, progress: health.metrics.steps / max(1, health.goals.stepGoal))
            }
            Button { router.tab = .food } label: {
                StatTile("Food", value: "\(health.caloriesRemaining)", caption: "kcal left · \(Int(health.proteinEaten)) g protein",
                         color: Theme.food, progress: health.caloriesEaten / Double(max(1, health.goals.calorieTarget())))
            }
            waterTile
        }
        .buttonStyle(.plain)
    }

    var waterTile: some View {
        let target = Double(health.plan?.waterTargetML ?? 2500)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Theme.water).frame(width: 7, height: 7)
                Text("Water").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
            Text(Units.water(health.waterTodayML, units)).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7).contentTransition(.numericText())
            Bar(health.waterTodayML / target, color: Theme.water, height: 4)
            HStack {
                Text("of \(Units.water(target, units))").font(.footnote).foregroundStyle(Theme.secondary)
                Spacer()
                Button {
                    health.addWater(ml: 250)
                    router.confirm("Added 250 ml")
                } label: {
                    Image(systemName: "plus").font(.footnote.weight(.bold)).foregroundStyle(.black)
                        .frame(width: 28, height: 28).background(Theme.water, in: Circle())
                }
                .accessibilityLabel("Add a glass of water")
            }
        }
        .padding(16).surface()
    }

    // MARK: Up next

    struct Moment: Identifiable { let id = UUID(); let icon: String; let title: String; let detail: String; let time: Date; let color: Color }

    var moments: [Moment] {
        guard let p = sleep.prediction else { return [] }
        let all = [
            Moment(icon: "brain.head.profile", title: "Best focus", detail: "Do your hardest task", time: p.morningPeak, color: Theme.calm),
            Moment(icon: "cloud.sun", title: "Energy dip", detail: "A short walk helps more than coffee", time: p.middayDip, color: Theme.food),
            Moment(icon: "cup.and.saucer", title: "Last coffee", detail: "Caffeine after this can hurt your sleep", time: p.caffeineCutoff, color: Theme.food),
            Moment(icon: "figure.run", title: "Best time to train", detail: "Your body is warmed up", time: p.afternoonPeak, color: Theme.move),
            Moment(icon: "wind", title: "Wind down", detail: "Dim the lights, put screens away", time: p.windDown, color: Theme.calm),
            Moment(icon: "moon", title: "Bedtime", detail: "For \(SleepFormat.durationHM(sleep.profile.sleepNeed)) of sleep", time: sleep.suggestedBedtime, color: Theme.sleep),
        ].sorted { $0.time < $1.time }
        return Array(all.filter { $0.time > Date() }.prefix(2))
    }

    @ViewBuilder var upNext: some View {
        if !moments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GroupLabel("Coming up")
                RowGroup {
                    ForEach(Array(moments.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { RowDivider() }
                        HStack(spacing: 14) {
                            Image(systemName: m.icon).font(.body.weight(.medium)).foregroundStyle(m.color).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(.body).foregroundStyle(Theme.text)
                                Text(m.detail).font(.footnote).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Text(SleepFormat.time(m.time)).font(.body.monospacedDigit()).foregroundStyle(Theme.text)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: Tip

    @ViewBuilder var tip: some View {
        if !health.isCalibrating, let insight = health.insights.first {
            Button { router.tab = .coach } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.calm).frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.title).font(.headline).foregroundStyle(Theme.text)
                        Text(insight.body).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("Ask your coach").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16).surface()
            }
            .buttonStyle(.plain)
        }
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
        .tint(.white)
    }

    static func plain(_ label: String) -> String {
        if label.hasPrefix("HRV") { return "Heart rate variability" }
        if label == "Yesterday's load" { return "Recent training" }
        return label
    }
}
