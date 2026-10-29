import WidgetKit
import SwiftUI

// MARK: - Lumen widgets: readiness, sleep and fuel at a glance.
// Reads the snapshot the app writes to the shared App Group.

private let suite = UserDefaults(suiteName: "group.com.dbakp.lumen")

struct LumenEntry: TimelineEntry {
    var date: Date
    var readiness: Int?          // nil = calibrating
    var hasSleep: Bool
    var debtHours: Double
    var lastSleep: Double        // seconds
    var bedtime: Date?
    var eaten: Int
    var target: Int
    var protein: Int
    var proteinTarget: Int
    var steps: Double
    var move: Double
    var evidence: DisplayEvidence? = nil

    func value(_ key: String) -> Double? { evidence?.value(key, at: date) }
    var sleepLabel: String { evidence?.estimates.contains("sleep") == true ? "Time in bed" : "Sleep record" }
    var coveredDebt: Double? { value("sleepDebt") }
    var sleepSeconds: Double? { value("sleep").map { $0 * 3600 } }
    var currentReadiness: Int? {
        guard let value = value("readiness"), (0...100).contains(value), value == value.rounded() else { return nil }; return Int(value)
    }
    var snapshotTime: String {
        guard let date = evidence?.capturedAt, date.timeIntervalSince1970.isFinite else { return "Date unavailable" }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
    var planAvailable: Bool { evidence?.isCurrent(at: date) == true }

    static let preview = LumenEntry(date: Date(), readiness: 82, hasSleep: true, debtHours: 2.4, lastSleep: 7.4 * 3600,
                                    bedtime: Calendar.current.date(bySettingHour: 22, minute: 45, second: 0, of: Date()),
                                    eaten: 1240, target: 2350, protein: 92, proteinTarget: 140, steps: 6420, move: 0.62, evidence: .init(day: Calendar.current.startOfDay(for: Date()), capturedAt: Date(), values: ["readiness":82,"sleep":7.4,"sleepDebt":2.4,"calories":1240,"protein":92,"steps":6420], estimates:["readiness","sleepDebt","calories","protein"]))

    static func load(at date: Date = Date()) -> LumenEntry {
        let d = suite ?? .standard
        let r = d.integer(forKey: "widget.readiness")
        return LumenEntry(
            date: date,
            readiness: r > 0 ? r : nil,
            hasSleep: d.bool(forKey: "widget.hasSleep"),
            debtHours: d.double(forKey: "widget.debt"),
            lastSleep: d.double(forKey: "widget.lastSleep"),
            bedtime: d.object(forKey: "widget.bedtime") as? Date,
            eaten: d.integer(forKey: "widget.eaten"),
            target: max(1, d.integer(forKey: "widget.target")),
            protein: d.integer(forKey: "widget.protein"),
            proteinTarget: max(1, d.integer(forKey: "widget.proteinTarget")),
            steps: d.double(forKey: "widget.steps"),
            move: d.double(forKey: "widget.move"), evidence: DisplayEvidence.decode(d.data(forKey: DisplayEvidence.widgetKey)))
    }
}

struct LumenProvider: TimelineProvider {
    func placeholder(in context: Context) -> LumenEntry { .preview }
    func getSnapshot(in context: Context, completion: @escaping (LumenEntry) -> Void) {
        completion(context.isPreview ? .preview : .load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LumenEntry>) -> Void) {
        let now = Date(), midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        completion(Timeline(entries: [.load(at: now), .load(at: midnight)], policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: Views

private func readinessTint(_ s: Int?) -> Color {
    guard let s else { return .gray }
    return s >= 85 ? .green : s >= 70 ? .cyan : s >= 55 ? .yellow : .orange
}

private func hm(_ secs: Double) -> String {
    let m = Int(secs / 60); return "\(m / 60)h \(m % 60)m"
}

struct Ring: View {
    let progress: Double; let tint: Color; var width: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: width)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct SmallView: View {
    let e: LumenEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Readiness estimate").font(.caption2.weight(.semibold)).foregroundStyle(.cyan)
                Spacer()
            }
            ZStack {
                if e.currentReadiness != nil { Ring(progress: Double(e.currentReadiness ?? 0) / 100, tint: readinessTint(e.currentReadiness), width: 9) }
                VStack(spacing: 0) {
                    if let r = e.currentReadiness {
                        Text("\(r)").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    } else {
                        Text("Not available").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            Text(e.sleepSeconds.map { e.sleepLabel + " " + hm($0) } ?? "Sleep not recorded")
                .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
            Text(e.snapshotTime).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
        }
        .widgetURL(URL(string: "lumen://today"))
    }
}

struct MediumView: View {
    let e: LumenEntry
    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Readiness estimate").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                ZStack {
                    if e.currentReadiness != nil { Ring(progress: Double(e.currentReadiness ?? 0) / 100, tint: readinessTint(e.currentReadiness), width: 8) }
                    Text(e.currentReadiness.map(String.init) ?? "Not available")
                        .font(.system(size: e.currentReadiness == nil ? 12 : 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }.frame(width: 104, height: 70)
                Text("Snapshot\n" + e.snapshotTime).font(.system(size: 9)).lineLimit(2).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            }.frame(width: 104)
            VStack(alignment: .leading, spacing: 9) {
                row("moon.fill", .indigo, e.sleepSeconds.map(hm) ?? "Not recorded", e.coveredDebt.map { "Est. debt " + EvidenceFormat.amount($0, unit: "h") } ?? e.sleepLabel + " · debt unknown")
                row("fork.knife", .orange, EvidenceFormat.amount(e.value("calories"), unit: "kcal"), "Food records · " + EvidenceFormat.amount(e.value("protein"), unit: "g protein"))
                if e.planAvailable, let bed = e.bedtime {
                    row("bed.double.fill", .purple, bed.formatted(date: .omitted, time: .shortened), "Planned bedtime")
                } else {
                    row("shoeprints.fill", .cyan, EvidenceFormat.amount(e.value("steps"), unit: "steps"), "Snapshot readings")
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "lumen://today"))
    }
    func row(_ icon: String, _ tint: Color, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption.weight(.bold)).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

struct AccessoryRectView: View {
    let e: LumenEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Readiness estimate \(e.currentReadiness.map(String.init) ?? "—")").font(.headline)
            Text(e.sleepSeconds.map { e.sleepLabel + " " + hm($0) } ?? "Sleep not recorded").font(.caption)
            if e.planAvailable, let bed = e.bedtime { Text("Bed \(bed.formatted(date: .omitted, time: .shortened))").font(.caption) }
        }
        .widgetURL(URL(string: "lumen://today"))
    }
}

struct AccessoryCircularView: View {
    let e: LumenEntry
    var body: some View {
        Gauge(value: Double(e.currentReadiness ?? 0), in: 0...100) {
            Image(systemName: "sun.max.fill")
        } currentValueLabel: {
            Text(e.currentReadiness.map(String.init) ?? "–")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel("Readiness estimate").accessibilityValue(e.currentReadiness.map(String.init) ?? "Not available")
        .widgetURL(URL(string: "lumen://today"))
    }
}

struct LumenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LumenEntry
    var body: some View {
        Group {
            switch family {
            case .systemMedium: MediumView(e: entry)
            case .accessoryRectangular: AccessoryRectView(e: entry)
            case .accessoryCircular: AccessoryCircularView(e: entry)
            default: SmallView(e: entry)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                ZStack {
                    Color(red: 0.04, green: 0.11, blue: 0.14)
                    RadialGradient(colors: [.teal.opacity(0.28), .clear], center: .topLeading, startRadius: 5, endRadius: 220)
                    RadialGradient(colors: [.teal.opacity(0.3), .clear], center: .bottomTrailing, startRadius: 5, endRadius: 220)
                }
            } else {
                Color.clear
            }
        }
    }
}

// MARK: Snap widget (quick meal capture)

struct SnapWidgetView: View {
    let entry: LumenEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "camera.viewfinder").font(.title.weight(.bold)).foregroundStyle(.black)
                .frame(width: 50, height: 50)
                .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            Spacer()
            Text("Snap a meal").font(.headline).foregroundStyle(.white)
            Text(entry.value("calories").map { EvidenceFormat.amount($0, unit: "kcal recorded") } ?? "Food not recorded").font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(red: 0.06, green: 0.05, blue: 0.1) }
        .widgetURL(URL(string: "lumen://snap"))
    }
}

struct LumenReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dbakp.lumen.readiness", provider: LumenProvider()) { LumenWidgetView(entry: $0) }
            .configurationDisplayName("Readiness")
            .description("Available records and wellness estimates. Open Lumen for source details.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct LumenSnapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dbakp.lumen.snap", provider: LumenProvider()) { SnapWidgetView(entry: $0) }
            .configurationDisplayName("Snap a meal")
            .description("Log a meal from your Home Screen in one tap.")
            .supportedFamilies([.systemSmall])
    }
}

@main
struct LumenWidgets: WidgetBundle {
    var body: some Widget {
        LumenReadinessWidget()
        LumenSnapWidget()
    }
}
