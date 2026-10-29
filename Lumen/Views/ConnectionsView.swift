import SwiftUI
import UniformTypeIdentifiers

struct ConnectionsView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var companion = CompanionStore.shared
    @ObservedObject private var hk = HealthKitService.shared
    @State private var importing = false
    @State private var parsing = false
    @State private var preview: HealthImportPreview?
    @State private var filename = ""
    @State private var error: String?
    @State private var clear = false
    var body: some View {
        Form {
            Section {
                HStack { Label("Apple Health", systemImage: "heart"); Spacer(); Text(hk.isAuthorized ? "Access requested" : "Not connected").foregroundStyle(Theme.secondary) }
                Button(hk.isAuthorized ? "Review Health access & sync" : "Connect Apple Health") {
                    Task { if await hk.requestAuthorization() { await SyncCoordinator.syncEverything(sleep: sleep, health: health) } }
                }
                if let last = health.lastSync { Text("Last refresh: \(last.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary) }
                Text("Read access is private: completing Apple's permission sheet doesn't tell Lumen which types you allowed. Missing readings stay unknown.").font(.footnote).foregroundStyle(Theme.secondary)
            } header: { Text("Live sources") }
            Section {
                NavigationLink { SettingsView() } label: { LabeledContent("Strava", value: StravaService.shared.isConnected ? "Connected" : "Set up") }
                Text("For Oura, Garmin and other sources, enable their Apple Health integration or import a compatible export. Lumen only reads the categories you share.").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Section {
                Button("Import health data", systemImage: "square.and.arrow.down") { importing = true }.disabled(parsing)
                if parsing { ProgressView("Reading measurements locally…") }
                Text("Choose export.xml from an unzipped Apple Health export, or a metrics CSV/JSON. Preview dates and sources before adding anything.").font(.footnote).foregroundStyle(Theme.secondary)
                if let preview {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(filename).font(.headline)
                        Text("\(preview.days.count) days · \(preview.samples) supported samples\n\(preview.skipped) unsupported, duplicate or invalid records skipped").font(.subheadline)
                        if let first = preview.days.first, let last = preview.days.last { Text("\(first.date.formatted(date: .abbreviated, time: .omitted)) – \(last.date.formatted(date: .abbreviated, time: .omitted))").font(.footnote) }
                        Text("Sources: \(preview.sourceNames.joined(separator: ", "))").font(.footnote)
                        Text("For each metric/day, the source with the most samples wins; sources are never added together. Existing imported values for those dates will be replaced. Review sample sources below.").font(.footnote).foregroundStyle(Theme.secondary)
                        ForEach(preview.days.suffix(3)) { day in
                            Text(day.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                            ForEach(day.values.keys.sorted(), id: \.self) { key in
                                Text("\(key): \(day.values[key]!, specifier: "%.1f") \(HealthImportService.units[key] ?? "") · \(day.sources[key] ?? "")").font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }
                        Button("Import \(preview.days.count) days") { companion.commit(preview, filename: filename); self.preview = nil; AppRouter.shared.confirm("Health history imported") }.buttonStyle(.borderedProminent)
                        Button("Discard preview", role: .cancel) { self.preview = nil }
                    }.padding(.vertical, 12)
                }
            } header: { Text("Your exports") } footer: { Text("CSV columns: date,metric,value,unit,source. Example: 2026-10-28,steps,8421,count,Watch. Supported metrics: steps, sleep, exercise, activeEnergy, restingHR, hrv, weight, water, calories, protein, carbs, fat.") }
            Section("Import history") {
                if companion.imports.isEmpty { Text("Nothing imported yet").foregroundStyle(Theme.secondary) }
                ForEach(companion.imports) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.filename).font(.subheadline.weight(.semibold))
                        Text("\(receipt.days) days · \(receipt.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                if !companion.imports.isEmpty { Button("Clear imported history", role: .destructive) { clear = true } }
            }
            Section {
                Toggle("Contextual check-ins", isOn: $companion.reminders.enabled)
                    .onChange(of: companion.reminders.enabled) { _, on in
                        if on { Task { if !(await NotificationManager.shared.request()) { companion.reminders.enabled = false }; NotificationManager.shared.refreshContext(health: health) } }
                    }
                Picker("Quiet hours start", selection: $companion.reminders.quietStart) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker("Quiet hours end", selection: $companion.reminders.quietEnd) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Toggle("Show health details on lock screen", isOn: $companion.reminders.showDetails)
            } header: { Text("Fewer, more useful reminders") } footer: { Text("At most one contextual check-in a day, only when your current logs suggest a useful action. Today's pending check-in is updated when you log or sync. No repeating generic nudges. Lumen must run to read new data; a scheduled check-in may not reflect changes made elsewhere afterwards. Equal start and end means quiet all day. Health details stay hidden by default.") }
        }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Connections").navigationBarTitleDisplayMode(.inline).tint(Theme.accent)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.xml, .commaSeparatedText, .json]) { result in read(result) }
            .alert("Couldn't import health data", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .confirmationDialog("Clear all imported daily measurements?", isPresented: $clear, titleVisibility: .visible) { Button("Clear imported history", role: .destructive) { companion.clearImports() } }
    }
    func read(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { if case .failure(let e) = result { error = e.localizedDescription }; return }
        parsing = true; preview = nil; filename = url.lastPathComponent
        Task {
            do {
                preview = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try HealthImportService.parse(url: url)
                }.value
            } catch { self.error = error.localizedDescription }
            parsing = false
        }
    }
}
