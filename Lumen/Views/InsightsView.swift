import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var companion = CompanionStore.shared
    @State private var window = 7
    @State private var days: [ImportedHealthDay] = []
    @State private var loading = true
    @State private var connecting = false
    @State private var includePersonal = false
    @State private var summaryID: String?
    let labels = ["sleep":"Sleep", "steps":"Steps", "exercise":"Exercise", "activeEnergy":"Active energy", "restingHR":"Resting heart rate", "hrv":"Heart rate variability", "water":"Water logged"]
    var evidence: [MetricEvidence] { ["sleep", "steps", "exercise", "activeEnergy", "restingHR", "hrv", "water"].map { TrendEvidence.compare(days, metric: $0, window: window) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What has\nchanged?").font(.largeTitle.bold()).fontWidth(.expanded)
                Text("Compare completed days with the previous period. Today is excluded because it is still in progress.").font(.subheadline).foregroundStyle(Theme.secondary)
                Picker("Period", selection: $window) { Text("7 days").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented)
                if loading { ProgressView("Reading available history…") }
                GroupLabel("For your next appointment")
                Text("Create an editable summary of your symptom descriptions, check-ins and recorded activity. Review it before sharing.").font(.subheadline).foregroundStyle(Theme.secondary)
                Toggle("Include my personal context notes", isOn: $includePersonal)
                Button("Create appointment summary", systemImage: "doc.text") {
                    let doc = AppointmentSummary.make(symptoms: companion.symptoms, checkIns: companion.checkIns, workouts: health.workouts, days: window, context: includePersonal ? companion.personalContext : nil)
                    companion.save(doc); summaryID = doc.id
                }.buttonStyle(LumenPrimaryButtonStyle()).accessibilityIdentifier("createAppointmentSummary")
                if !loading && evidence.allSatisfy({ $0.current.isEmpty && $0.previous.isEmpty }) {
                    EmptyStateCard(icon: "chart.xyaxis.line", title: "Your history will help here", message: "Connect a source or import completed days to see changes over time. You can still prepare an appointment summary from your own logs.", actionTitle: "Connect or import") { connecting = true }
                }
                if evidence.contains(where: { !$0.current.isEmpty || !$0.previous.isEmpty }) {
                    GroupLabel("Recorded changes")
                    Text("A comparison needs at least 3 recorded days in each period. Gaps are not filled with zeros.").font(.footnote).foregroundStyle(Theme.secondary)
                }
                ForEach(evidence.filter { !$0.current.isEmpty || !$0.previous.isEmpty }) { metric in
                    NavigationLink { MetricEvidenceView(evidence: metric, title: labels[metric.metric] ?? metric.metric) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(labels[metric.metric] ?? metric.metric).font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondary)
                            }
                            if let mean = metric.currentMean {
                                Text("\(mean, specifier: "%.1f") \(metric.unit)").font(.title.bold()).monospacedDigit()
                                if let change = metric.changePercent { Text("\(change >= 0 ? "+" : "")\(change, specifier: "%.1f")% vs previous period").font(.subheadline).foregroundStyle(Theme.secondary) }
                                else if let change = metric.change { Text("Change: \(change, specifier: "%.1f") \(metric.unit)").font(.subheadline) }
                            } else { Text("No readings in this period").font(.subheadline).foregroundStyle(Theme.secondary) }
                            Text("\(metric.current.count)/\(window) current days · \(metric.previous.count)/\(window) previous days").font(.caption).foregroundStyle(Theme.secondary)
                        }.foregroundStyle(Theme.text).padding(20).surface()
                    }.buttonStyle(.plain)
                }
                Text("Comparisons describe available records. They cannot establish what caused a symptom or whether a change is medically important.").font(.footnote).foregroundStyle(Theme.secondary)
            }.padding(Theme.gutter)
        }.lumenScreen().navigationTitle("Insights").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
            .navigationDestination(isPresented: $connecting) { ConnectionsView() }
            .navigationDestination(item: $summaryID) { id in DocumentDetailView(documentID: id) }
    }
    func load() async { loading = true; days = await TrendEvidenceService.collect(health: health, sleep: sleep); loading = false }
}

struct MetricEvidenceView: View {
    let evidence: MetricEvidence
    let title: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.largeTitle.bold())
                if evidence.current.isEmpty && evidence.previous.isEmpty {
                    EmptyStateCard(icon: "chart.xyaxis.line", title: "More history will help", message: "Connect Apple Health, import history or keep logging to see this metric here.")
                } else {
                    Chart(evidence.previous + evidence.current) { day in
                        PointMark(x: .value("Day", day.date), y: .value(title, day.values[evidence.metric] ?? 0)).foregroundStyle(Theme.accent)
                    }.frame(height: 220).chartYAxisLabel(evidence.unit)
                    Text("Each dot is a recorded day; gaps are left empty. The chart excludes today.").font(.caption).foregroundStyle(Theme.secondary)
                }
                GroupLabel("Coverage and sources")
                Text("Current: \(evidence.current.count) of \(evidence.window) days. Previous: \(evidence.previous.count) of \(evidence.window) days. Averages use recorded days only.")
                Text(evidence.sources.isEmpty ? "No source readings available." : evidence.sources.joined(separator: "\n")).font(.subheadline).foregroundStyle(Theme.secondary)
                Text("Live Health readings take priority over imported readings for the same metric and date. Manual workouts are added to live Health totals because they are not written to Health. When overlap with imports is unknown, totals are not added together.").font(.footnote).foregroundStyle(Theme.secondary)
            }.padding(Theme.gutter)
        }.lumenScreen().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
