import SwiftUI

struct CurrentReadingsView: View {
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var sleep: SleepStore
    private let groups: [(String, [String])] = [("Sleep and movement", ["sleep", "steps", "activeEnergy", "restingEnergy", "exercise", "stand"]), ("Heart and body", ["restingHR", "hrv", "heartRate", "respiratoryRate", "spo2", "vo2max", "weight", "bodyFat", "bmi"]), ("Food and water", ["calories", "protein", "carbs", "fat", "water"])]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What was\nrecorded?").font(.largeTitle.bold()).fontWidth(.expanded)
                    Text("A zero is a reading. Missing data stays unknown.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        GroupLabel(group.0)
                        ForEach(group.1, id: \.self) { key in
                            let reading = health.metrics.reading(key)
                            NavigationLink { CurrentReadingDetailView(key: key) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(HealthMetricCatalog.labels[key] ?? key).font(.headline)
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondary)
                                    }
                                    Text(HealthMetricCatalog.display(reading.value, key: key)).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(reading.value == nil ? Theme.secondary : Theme.accent)
                                    if reading.value != nil { Text(reading.sourceLabel).font(.caption).foregroundStyle(Theme.secondary).lineLimit(2) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("current-reading-" + key)
                            Divider()
                        }
                    }
                }
            }.padding(Theme.gutter)
        }.lumenScreen().navigationTitle("Today's readings").navigationBarTitleDisplayMode(.inline)
            .refreshable { await SyncCoordinator.syncEverything(sleep: sleep, health: health) }
    }
}

struct CurrentReadingDetailView: View {
    let key: String
    @EnvironmentObject private var health: HealthStore
    var reading: HealthMetricReading { health.metrics.reading(key) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(HealthMetricCatalog.labels[key] ?? key).font(.headline).foregroundStyle(Theme.secondary)
                    Text(HealthMetricCatalog.display(reading.value, key: key)).font(.largeTitle.bold()).monospacedDigit().accessibilityIdentifier("currentReadingValue")
                    Text(health.metrics.date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(Theme.secondary)
                    if reading.isEstimate { Text("Includes an estimate").font(.subheadline).foregroundStyle(Theme.secondary) }
                }
                if reading.value == nil { Text("No \(HealthMetricCatalog.labels[key]?.lowercased() ?? key) reading is available for today.").foregroundStyle(Theme.secondary) }
                if key == "stand" { Text("Counts hours containing a stand or roll record.").font(.subheadline).foregroundStyle(Theme.secondary) }
                ForEach(Array(reading.components.enumerated()), id: \.offset) { _, component in
                    VStack(alignment: .leading, spacing: 10) {
                        GroupLabel(component.origin == .healthImport ? "Imported source" : component.origin == .legacyCache ? "Cached total" : "Recorded source")
                        Text(String(component.source.prefix(120))).font(.headline)
                        if reading.components.count > 1 { Text(HealthMetricCatalog.display(component.value, key: key)).font(.title2.weight(.semibold)).monospacedDigit() }
                        Text(component.periodDescription).font(.subheadline).foregroundStyle(Theme.secondary).accessibilityIdentifier("readingPeriod")
                        if component.isEstimate { Text("This amount is estimated.").font(.footnote).foregroundStyle(Theme.secondary) }
                        if component.origin == .legacyCache { Text("The original source and check time were not saved.").font(.footnote).foregroundStyle(Theme.secondary) }
                    }
                }
                if let query = reading.healthQuery {
                    VStack(alignment: .leading, spacing: 10) {
                        GroupLabel("Apple Health check")
                        Text(query.outcome == .failed ? "Couldn’t refresh this reading" : query.outcome == .noData ? "No reading returned" : "Reading returned").font(.headline)
                        Text(query.checkedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(Theme.secondary)
                        Text("Read access is private. An empty result can mean no data or no access.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
                if reading.overlapKeptSeparate { Text("Imports and local logs may overlap. The larger recorded total is shown instead of adding them.").font(.footnote).foregroundStyle(Theme.secondary) }
            }.padding(Theme.gutter)
        }.lumenScreen().navigationTitle("Reading details").navigationBarTitleDisplayMode(.inline)
    }
}
