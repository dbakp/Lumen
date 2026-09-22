import WidgetKit
import SwiftUI

// MARK: - Lumen widgets: readiness + debt + fuel at a glance.

struct HealthEntry: TimelineEntry {
    var date: Date
    var readiness: Int
    var debtHours: Double
    var eaten: Int
    var target: Int
    var bedtime: Date
}

struct HealthProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthEntry {
        HealthEntry(date: Date(), readiness: 78, debtHours: 3.2, eaten: 980, target: 2400, bedtime: Date().addingTimeInterval(5*3600))
    }
    func getSnapshot(in context: Context, completion: @escaping (HealthEntry) -> Void) {
        completion(placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthEntry>) -> Void) {
        let debt = UserDefaults.standard.double(forKey: "lumen.widget.debt")
        let energy = UserDefaults.standard.integer(forKey: "lumen.widget.energy")
        let bed = UserDefaults.standard.object(forKey: "lumen.widget.bedtime") as? Date ?? Date().addingTimeInterval(4*3600)
        let entry = HealthEntry(
            date: Date(),
            readiness: energy == 0 ? 78 : energy,
            debtHours: debt == 0 ? 3.2 : debt,
            eaten: 0, target: 2400, bedtime: bed
        )
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30*60))))
    }
}

struct LumenHealthWidgetView: View {
    var entry: HealthEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("READINESS \(entry.readiness)").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(1)
            Text("\(entry.readiness)").font(.title.weight(.bold).monospacedDigit())
            Text("Debt \(String(format: "%.1f", entry.debtHours))h · Bed \(entry.bedtime, style: .time)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct LumenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.lumen.health", provider: HealthProvider()) { entry in
            LumenHealthWidgetView(entry: entry)
        }
        .configurationDisplayName("Readiness")
        .description("Readiness, sleep debt, and tonight's bedtime.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
