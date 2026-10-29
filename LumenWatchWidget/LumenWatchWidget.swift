import WidgetKit
import SwiftUI

// MARK: - Watch complications: readiness + bedtime, from the snapshot the Watch app stores.

struct SnapEntry: TimelineEntry {
    var date: Date
    var s: WatchSnapshot?
}

struct SnapProvider: TimelineProvider {
    func load() -> WatchSnapshot? {
        WatchSnapshot.decode(UserDefaults(suiteName: "group.com.dbakp.lumen")?.data(forKey: WatchSnapshot.storeKey))
    }
    func placeholder(in context: Context) -> SnapEntry { SnapEntry(date: Date(), s: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (SnapEntry) -> Void) {
        completion(SnapEntry(date: Date(), s: context.isPreview ? .preview : load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapEntry>) -> Void) {
        let now = Date(), midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let snapshot = load()
        completion(Timeline(entries: [SnapEntry(date: now, s: snapshot), SnapEntry(date: midnight, s: snapshot)], policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

private func readinessTint(_ s: Int?) -> Color {
    guard let s else { return .gray }
    return s >= 85 ? .green : s >= 70 ? .cyan : s >= 55 ? .yellow : .orange
}

private func hm(_ secs: Double) -> String { let m = Int(secs / 60); return "\(m / 60)h\(String(format: "%02d", m % 60))" }

struct ReadinessComplication: View {
    @Environment(\.widgetFamily) var family
    let e: SnapEntry
    var score: Int? { e.s?.currentReadiness(at: e.date) }
    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(score ?? 0), in: 0...100) {
                Image(systemName: "sun.max.fill")
            } currentValueLabel: {
                Text(score.map(String.init) ?? "–").font(.system(.title3, design: .rounded).weight(.bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(readinessTint(score))
        case .accessoryCorner:
            Text(score.map(String.init) ?? "–").font(.system(.title3, design: .rounded).weight(.bold))
                .widgetLabel {
                    Gauge(value: Double(score ?? 0), in: 0...100) { Text("Estimate") }.tint(readinessTint(score))
                }
        case .accessoryInline:
            if let s = e.s {
                Text("Est. \(score.map(String.init) ?? "–") · Plan \(s.planningAvailable(at: e.date) ? s.bedtime?.formatted(date: .omitted, time: .shortened) ?? "—" : "—")")
            } else {
                Text("Lumen")
            }
        default:
            HStack(spacing: 8) {
                Gauge(value: Double(score ?? 0), in: 0...100) { EmptyView() } currentValueLabel: {
                    Text(score.map(String.init) ?? "–").font(.system(.body, design: .rounded).weight(.bold))
                }
                .gaugeStyle(.accessoryCircularCapacity).tint(readinessTint(score))
                VStack(alignment: .leading, spacing: 1) {
                    Text("LUMEN").font(.system(size: 10, weight: .heavy)).foregroundStyle(.cyan)
                    if let s = e.s {
                        Text(s.reading("sleep", at: e.date).map { (s.observations?.estimates.contains("sleep") == true ? "Time in bed " : "Sleep ") + hm($0 * 3600) } ?? "Sleep not recorded").font(.caption2)
                        Text("Plan \(s.planningAvailable(at: e.date) ? s.bedtime?.formatted(date: .omitted, time: .shortened) ?? "—" : "—")").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Open Lumen").font(.caption2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct BedtimeComplication: View {
    @Environment(\.widgetFamily) var family
    let e: SnapEntry
    var body: some View {
        let bed = e.s?.planningAvailable(at: e.date) == true ? e.s?.bedtime?.formatted(date: .omitted, time: .shortened) ?? "—" : "—"
        switch family {
        case .accessoryInline:
            Label("Bed \(bed)", systemImage: "moon.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "moon.fill").font(.caption)
                    Text(bed).font(.system(size: 12, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                }
            }
        }
    }
}

struct LumenReadinessComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dbakp.lumen.watch.readiness", provider: SnapProvider()) { e in
            ReadinessComplication(e: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Readiness")
        .description("Recorded sleep and optional wellness estimates from the current iPhone snapshot.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

struct LumenBedtimeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dbakp.lumen.watch.bedtime", provider: SnapProvider()) { e in
            BedtimeComplication(e: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Bedtime")
        .description("A planned bedtime from the current iPhone snapshot.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

@main
struct LumenWatchWidgets: WidgetBundle {
    var body: some Widget {
        LumenReadinessComplication()
        LumenBedtimeComplication()
    }
}
