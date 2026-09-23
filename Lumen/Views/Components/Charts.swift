import SwiftUI
import Charts

// MARK: - Debt ring (hero)

public struct DebtRingView: View {
    let debt: TimeInterval
    let need: TimeInterval
    public init(debt: TimeInterval, need: TimeInterval) {
        self.debt = debt; self.need = need
    }
    public var body: some View {
        // Scale: 0h → full glow, 12h+ → drained.
        let progress = max(0, min(1, 1 - debt / (12 * 3600)))
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(
                    AngularGradient(colors: [.cyan, .teal, .indigo, .purple, .cyan], center: .center),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .cyan.opacity(0.5), radius: 12)
                .animation(.spring(response: 0.9, dampingFraction: 0.8), value: progress)
            VStack(spacing: 2) {
                Text(SleepFormat.debtString(debt))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("sleep debt")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                Text(debt < 5*3600 ? "In the green zone" : "Above 5h target")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background((debt < 5*3600 ? Color.green : Color.orange).opacity(0.22), in: Capsule())
                    .foregroundStyle(debt < 5*3600 ? .green : .orange)
                    .padding(.top, 4)
            }
        }
        .frame(width: 220, height: 220)
    }
}

// MARK: - Energy curve (Swift Charts)

public struct EnergyCurveView: View {
    let points: [EnergyPoint]
    let nowFraction: Double? // seconds since midnight for "now" marker
    public init(points: [EnergyPoint], now: Date? = nil) {
        self.points = points
        if let now {
            let c = Calendar.current.dateComponents([.hour, .minute], from: now)
            self.nowFraction = Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60)
        } else { self.nowFraction = nil }
    }
    public var body: some View {
        Chart(points) { p in
            AreaMark(
                x: .value("Time", p.time / 3600),
                y: .value("Energy", p.energy)
            )
            .foregroundStyle(
                LinearGradient(colors: [.cyan.opacity(0.55), .indigo.opacity(0.12)], startPoint: .top, endPoint: .bottom)
            )
            .interpolationMethod(.catmullRom)
            LineMark(
                x: .value("Time", p.time / 3600),
                y: .value("Energy", p.energy)
            )
            .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: 0...1.05)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { v in
                AxisValueLabel {
                    if let h = v.as(Double.self) {
                        Text("\(Int(h))h").font(.caption2).foregroundStyle(.white.opacity(0.55))
                    }
                }
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 170)
    }
}

// MARK: - 14-night debt bars

public struct DebtHistoryChart: View {
    let need: TimeInterval
    let episodes: [SleepEpisode]
    public init(need: TimeInterval, episodes: [SleepEpisode]) {
        self.need = need; self.episodes = episodes
    }
    struct Row: Identifiable {
        var id: Date { date }
        var date: Date; var slept: Double; var deficit: Double
    }
    var rows: [Row] {
        episodes.suffix(14).map { ep in
            Row(date: ep.bedtime, slept: ep.duration/3600, deficit: (need - ep.duration)/3600)
        }
    }
    public var body: some View {
        Chart(rows) { r in
            BarMark(
                x: .value("Night", r.date, unit: .day),
                y: .value("Slept", r.slept)
            )
            .foregroundStyle(r.deficit > 0 ? LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [.teal, .cyan], startPoint: .top, endPoint: .bottom))
            .cornerRadius(5)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption2).foregroundStyle(.white.opacity(0.55))
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
            }
        }
        .frame(height: 180)
    }
}

// MARK: - Timeline row

public struct TimelineRow: View {
    let icon: String
    let color: Color
    let title: String
    let time: String
    let detail: String
    public init(icon: String, color: Color, title: String, time: String, detail: String) {
        self.icon = icon; self.color = color; self.title = title; self.time = time; self.detail = detail
    }
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
            }
            Spacer()
            Text(time).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.vertical, 6)
    }
}
