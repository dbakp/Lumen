import SwiftUI
import Charts

// MARK: - Trends: weeks and months of sleep, heart and activity.

public struct TrendsView: View {
    @EnvironmentObject var sleep: SleepStore
    @EnvironmentObject var health: HealthStore
    @ObservedObject private var hk = HealthKitService.shared

    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self { case .week: return "7D"; case .month: return "30D"; case .quarter: return "90D"; case .year: return "1Y" }
        }
    }

    @State private var metric: TrendMetric = .sleep
    @State private var range: Range = .month
    @State private var series: [DailyValue] = []
    @State private var previous: [DailyValue] = []
    @State private var loading = false
    @State private var selected: DailyValue?

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                metricPicker
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        summary
                        chart.frame(height: 220)
                    }
                }
                if !series.isEmpty { statsRow }
                insightCard
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground())
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(metric.rawValue)-\(range.rawValue)-\(sleep.episodes.count)") { await load() }
    }

    // MARK: Picker

    var metricPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(TrendMetric.allCases) { m in
                    Button {
                        haptic(.light); withAnimation(.spring) { metric = m; selected = nil }
                    } label: {
                        Label(m.label, systemImage: m.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(metric == m ? .black : .white)
                            .background(metric == m ? AnyShapeStyle(tint(m)) : AnyShapeStyle(.white.opacity(0.1)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 8)
    }

    func tint(_ m: TrendMetric) -> Color {
        switch m {
        case .sleep: return .indigo; case .steps: return .cyan; case .activeEnergy: return .pink; case .exercise: return .green
        case .restingHR: return .red; case .hrv: return .purple; case .weight: return .orange
        }
    }

    // MARK: Data

    func load() async {
        loading = true; defer { loading = false }
        if metric == .sleep {
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -(range.rawValue * 2 - 1), to: cal.startOfDay(for: Date())) ?? Date()
            let byDay = Dictionary(grouping: sleep.episodes.filter { $0.wakeTime >= start }) { cal.startOfDay(for: $0.wakeTime) }
            let all = byDay.map { DailyValue(date: $0.key, value: $0.value.reduce(0) { $0 + $1.duration } / 3600) }.sorted { $0.date < $1.date }
            let cut = cal.date(byAdding: .day, value: -(range.rawValue - 1), to: cal.startOfDay(for: Date())) ?? Date()
            series = all.filter { $0.date >= cut }
            previous = all.filter { $0.date < cut }
        } else {
            let all = await hk.dailySeries(metric, days: range.rawValue * 2)
            let cut = Calendar.current.date(byAdding: .day, value: -(range.rawValue - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
            series = all.filter { $0.date >= cut }.map(convert)
            previous = all.filter { $0.date < cut }.map(convert)
        }
    }

    func convert(_ v: DailyValue) -> DailyValue {
        metric == .weight && units == .imperial ? DailyValue(date: v.date, value: Units.lbFromKg(v.value)) : v
    }

    var unitLabel: String { metric == .weight ? (units == .imperial ? "lb" : "kg") : metric.unit }

    func format(_ v: Double) -> String {
        switch metric {
        case .sleep: return SleepFormat.durationHM(v * 3600)
        case .weight: return String(format: "%.1f %@", v, unitLabel)
        case .steps: return Int(v).formatted()
        default: return "\(Int(v.rounded())) \(unitLabel)"
        }
    }

    var average: Double? { series.isEmpty ? nil : series.map(\.value).reduce(0, +) / Double(series.count) }
    var previousAverage: Double? { previous.isEmpty ? nil : previous.map(\.value).reduce(0, +) / Double(previous.count) }

    // MARK: Summary + chart

    var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.map { $0.date.formatted(.dateTime.weekday(.abbreviated).month().day()) } ?? (metric == .weight ? "LATEST" : "DAILY AVERAGE"))
                    .font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(1)
                Text(selected.map { format($0.value) } ?? (metric == .weight ? series.last.map { format($0.value) } : average.map(format)) ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white).contentTransition(.numericText())
            }
            Spacer()
            if selected == nil, let a = average, let p = previousAverage, p > 0 {
                let delta = (a - p) / p * 100
                let good = metric.lowerIsBetter ? delta <= 0 : delta >= 0
                Label(String(format: "%+.0f%%", delta), systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(metric == .weight ? .white.opacity(0.8) : (good ? .green : .orange))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: Capsule())
                    .accessibilityLabel("Change versus previous period")
            }
        }
    }

    @ViewBuilder var chart: some View {
        if series.isEmpty {
            VStack(spacing: 10) {
                if loading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: metric.icon).font(.title).foregroundStyle(tint(metric).opacity(0.8))
                    Text(emptyMessage).font(.subheadline).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                    if !hk.isAuthorized && metric != .sleep {
                        Button("Connect Apple Health") { Task { if await hk.requestAuthorization() { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }; await load() } }
                            .font(.subheadline.weight(.bold)).tint(.cyan).buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let c = tint(metric)
            let useBars = metric.cumulative || metric == .sleep
            Chart {
                ForEach(series) { d in
                    if useBars {
                        BarMark(x: .value("Day", d.date, unit: .day), y: .value(metric.label, d.value))
                            .foregroundStyle(LinearGradient(colors: [c, c.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                            .cornerRadius(range.rawValue >= 90 ? 1 : 4)
                            .opacity(selected == nil || selected?.date == d.date ? 1 : 0.35)
                    } else {
                        AreaMark(x: .value("Day", d.date, unit: .day), y: .value(metric.label, d.value))
                            .foregroundStyle(LinearGradient(colors: [c.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Day", d.date, unit: .day), y: .value(metric.label, d.value))
                            .foregroundStyle(c).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                }
                if let a = average, metric != .weight {
                    RuleMark(y: .value("Average", a))
                        .foregroundStyle(.white.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if metric == .sleep {
                    RuleMark(y: .value("Need", sleep.profile.sleepNeed / 3600))
                        .foregroundStyle(.cyan.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Need").font(.caption2.weight(.bold)).foregroundStyle(.cyan.opacity(0.8))
                        }
                }
                if let s = selected {
                    RuleMark(x: .value("Selected", s.date, unit: .day)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .chartYScale(domain: .automatic(includesZero: useBars))
            .chartXAxis {
                AxisMarks(values: .stride(by: range == .year ? .month : .day, count: range == .week ? 1 : range == .month ? 7 : range == .quarter ? 21 : 2)) { _ in
                    AxisValueLabel(format: range == .week ? .dateTime.weekday(.narrow) : range == .year ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard let plot = proxy.plotFrame else { return }
                                let x = v.location.x - geo[plot].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    let nearest = series.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                                    if nearest?.date != selected?.date { UISelectionFeedbackGenerator().selectionChanged() }
                                    selected = nearest
                                }
                            }
                            .onEnded { _ in withAnimation(.easeOut.delay(1.2)) { selected = nil } })
                }
            }
            .animation(.spring(response: 0.5), value: series)
        }
    }

    var emptyMessage: String {
        if metric == .sleep { return "No nights in this range yet. Sleep with your Watch or log a night to see your pattern." }
        if !hk.isAuthorized { return "Connect Apple Health to see \(metric.label.lowercased()) over time." }
        return "No \(metric.label.lowercased()) data in Apple Health for this range."
    }

    // MARK: Stats

    var statsRow: some View {
        let values = series.map(\.value)
        let best = metric.lowerIsBetter ? series.min { $0.value < $1.value } : series.max { $0.value < $1.value }
        return HStack(spacing: 10) {
            StatChip(title: metric.lowerIsBetter ? "LOWEST" : "BEST", value: best.map { format($0.value) } ?? "—")
            StatChip(title: "DAYS", value: "\(series.count)")
            StatChip(title: metric.cumulative ? "TOTAL" : "RANGE",
                     value: metric.cumulative ? format(values.reduce(0, +)).replacingOccurrences(of: " \(unitLabel)", with: "")
                        : "\(format(values.min() ?? 0).components(separatedBy: " ").first ?? "")–\(format(values.max() ?? 0).components(separatedBy: " ").first ?? "")")
        }
    }

    @ViewBuilder var insightCard: some View {
        if let text = insightText {
            GlassCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    var insightText: String? {
        guard let a = average else { return nil }
        switch metric {
        case .sleep:
            let need = sleep.profile.sleepNeed / 3600
            let gap = need - a
            if gap > 0.5 { return "You're averaging \(SleepFormat.durationHM(gap * 3600)) under your need. Moving bedtime 20 minutes earlier for a week closes most of that." }
            if series.count >= 5 { return "You're sleeping close to your need — protect a consistent wake time to keep it that way." }
            return nil
        case .steps:
            return a >= 8000 ? "A strong walking base. Steps are the most underrated recovery tool you have." : "Short walks after meals are the easiest way to lift your daily average."
        case .restingHR:
            guard let p = previousAverage else { return "Resting heart rate trending down over weeks usually signals improving fitness." }
            return a < p ? "Resting HR is trending down — a classic sign of improving fitness and recovery." : "Resting HR is up versus last period. Sleep, stress, alcohol and illness all push it higher."
        case .hrv:
            return "HRV is personal — compare with your own baseline, not other people's. Consistent sleep lifts it most."
        default: return nil
        }
    }
}
