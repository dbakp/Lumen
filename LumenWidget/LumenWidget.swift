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

    static let preview = LumenEntry(date: Date(), readiness: 82, hasSleep: true, debtHours: 2.4, lastSleep: 7.4 * 3600,
                                    bedtime: Calendar.current.date(bySettingHour: 22, minute: 45, second: 0, of: Date()),
                                    eaten: 1240, target: 2350, protein: 92, proteinTarget: 140, steps: 6420, move: 0.62)

    static func load() -> LumenEntry {
        let d = suite ?? .standard
        let r = d.integer(forKey: "widget.readiness")
        return LumenEntry(
            date: Date(),
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
            move: d.double(forKey: "widget.move"))
    }
}

struct LumenProvider: TimelineProvider {
    func placeholder(in context: Context) -> LumenEntry { .preview }
    func getSnapshot(in context: Context, completion: @escaping (LumenEntry) -> Void) {
        completion(context.isPreview ? .preview : .load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LumenEntry>) -> Void) {
        completion(Timeline(entries: [.load()], policy: .after(Date().addingTimeInterval(30 * 60))))
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
            Circle().trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct SmallView: View {
    let e: LumenEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LUMEN").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundStyle(.cyan)
                Spacer()
            }
            ZStack {
                Ring(progress: Double(e.readiness ?? 0) / 100, tint: readinessTint(e.readiness), width: 9)
                VStack(spacing: 0) {
                    if let r = e.readiness {
                        Text("\(r)").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    } else {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(.white.opacity(0.8))
                    }
                    Text(e.readiness == nil ? "CALIBRATING" : "READY").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            Text(e.hasSleep ? "Slept \(hm(e.lastSleep))" : "No sleep yet")
                .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
        }
        .widgetURL(URL(string: "lumen://today"))
    }
}

struct MediumView: View {
    let e: LumenEntry
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Ring(progress: Double(e.readiness ?? 0) / 100, tint: readinessTint(e.readiness), width: 10)
                VStack(spacing: 0) {
                    Text(e.readiness.map(String.init) ?? "—").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("READINESS").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 9) {
                row("moon.fill", .indigo, e.hasSleep ? hm(e.lastSleep) : "—", e.hasSleep ? String(format: "Debt %.1fh", e.debtHours) : "Sleep")
                row("fork.knife", .orange, "\(e.eaten) / \(e.target)", "kcal · \(e.protein)g protein")
                if let bed = e.bedtime {
                    row("bed.double.fill", .purple, bed.formatted(date: .omitted, time: .shortened), "Bedtime tonight")
                } else {
                    row("shoeprints.fill", .cyan, Int(e.steps).formatted(), "steps")
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
            Text("Readiness \(e.readiness.map(String.init) ?? "—")").font(.headline)
            Text(e.hasSleep ? "Slept \(hm(e.lastSleep))" : "Lumen").font(.caption)
            if let bed = e.bedtime { Text("Bed \(bed.formatted(date: .omitted, time: .shortened))").font(.caption) }
        }
        .widgetURL(URL(string: "lumen://today"))
    }
}

struct AccessoryCircularView: View {
    let e: LumenEntry
    var body: some View {
        Gauge(value: Double(e.readiness ?? 0), in: 0...100) {
            Image(systemName: "sun.max.fill")
        } currentValueLabel: {
            Text(e.readiness.map(String.init) ?? "–")
        }
        .gaugeStyle(.accessoryCircularCapacity)
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
                    Color(red: 0.03, green: 0.04, blue: 0.09)
                    RadialGradient(colors: [.indigo.opacity(0.55), .clear], center: .topLeading, startRadius: 5, endRadius: 220)
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
            Text("\(max(0, entry.target - entry.eaten)) kcal left").font(.caption).foregroundStyle(.white.opacity(0.65))
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
            .description("Readiness, last night's sleep, fuel and tonight's bedtime.")
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
