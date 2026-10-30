import SwiftUI
import UniformTypeIdentifiers

struct ConnectionsView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var companion = CompanionStore.shared
    @ObservedObject private var hk = HealthKitService.shared
    @ObservedObject private var delivery = HealthBackgroundSync.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var importing = false
    @State private var parsing = false
    @State private var cancelRequested = false
    @State private var activeImport: HealthImportControl?
    @State private var importTask: Task<Void, Never>?
    @State private var importStatus: String?
    @State private var preview: HealthImportPreview?
    @State private var filename = ""
    @State private var error: String?
    @State private var clear = false
    private var deliveryStatus: String { delivery.enabled && !hk.isAuthorized ? "Waiting for Apple Health connection" : delivery.registration }
    private var backgroundToggle: some View {
        Toggle("Background Health updates", isOn: Binding(get: { delivery.enabled }, set: { delivery.setEnabled($0) }))
            .accessibilityIdentifier("backgroundHealthUpdates")
    }
    var body: some View {
        Form {
            Section {
                HStack { Label("Apple Health", systemImage: "heart"); Spacer(); Text(hk.isAuthorized ? "Access requested" : "Not connected").foregroundStyle(Theme.secondary) }
                Button(hk.isAuthorized ? "Review Health access & sync" : "Connect Apple Health") {
                    Task { if await hk.requestAuthorization() { await SyncCoordinator.syncEverything(sleep: sleep, health: health) } }
                }
                if let last = health.lastSync { Text("Lumen refreshed: \(last.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary) }
                Text("Read access is private: completing Apple's permission sheet doesn't tell Lumen which types you allowed. Missing readings stay unknown.").font(.footnote).foregroundStyle(Theme.secondary)
            } header: { Text("Live sources") }
            Section {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Background Health updates").accessibilityHidden(true)
                        backgroundToggle.labelsHidden().accessibilityLabel("Background Health updates")
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("healthUpdatesControl")
                } else { backgroundToggle }
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Background status").font(.headline)
                            Text(deliveryStatus).foregroundStyle(Theme.secondary)
                        }
                    } else {
                        LabeledContent { Text(deliveryStatus).foregroundStyle(Theme.secondary) } label: { Text("Background status") }
                    }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("Health background status").accessibilityValue(deliveryStatus)
                .accessibilityIdentifier("healthDeliveryStatus")
                if let date = delivery.lastEvent {
                    LabeledContent { Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.secondary) } label: { Text("Health check triggered") }.font(.footnote)
                }
                if let date = delivery.lastApplied {
                    LabeledContent { Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.secondary) } label: { Text("Sleep & workout check") }.font(.footnote)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Sleep and workout check")
                        .accessibilityValue(date.formatted(date: .abbreviated, time: .shortened)).accessibilityIdentifier("healthHistoryCheck")
                }
                if let issue = delivery.issue { Text(issue).font(.footnote).foregroundStyle(Theme.text) }
                if hk.isAuthorized {
                    Button(delivery.issue == nil ? "Check Health now" : "Retry Health update") { Task { await SyncCoordinator.syncEverything(sleep: sleep, health: health) } }
                        .accessibilityIdentifier("checkHealthNow").disabled(health.isSyncing)
                }
                Text("iOS decides when to deliver changes. Updates may wait until you unlock your iPhone. Open Lumen to refresh at any time.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            } header: { Text("Between visits") } footer: {
                Text("Health changes are processed on this iPhone. This is not continuous monitoring.").foregroundStyle(Theme.secondary)
            }
            Section {
                NavigationLink { SettingsView() } label: { LabeledContent("Strava", value: StravaService.shared.isConnected ? "Connected" : "Set up") }
                Text("For Oura, Garmin and other sources, enable their Apple Health integration or import a compatible export. Lumen only reads the categories you share.").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Section {
                Button("Import health data", systemImage: "square.and.arrow.down") { importing = true }.disabled(parsing)
                if parsing, let control = activeImport {
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        let state = control.progress
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(cancelRequested ? "Stopping import" : state.title).font(.subheadline).foregroundStyle(Theme.text)
                                }
                                Text(cancelRequested ? "Finishing local cleanup" : state.detail).font(.footnote).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                if let importStatus { Text(importStatus).font(.footnote).foregroundStyle(Theme.secondary) }
                Text("Choose your Apple Health export ZIP, export.xml, or a metrics CSV/JSON. Lumen reads the health history locally. Preview dates and sources before adding anything.").font(.footnote).foregroundStyle(Theme.secondary)
                if let preview {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(filename).font(.headline)
                        Text("\(preview.coveredDays.count) day\(preview.coveredDays.count == 1 ? "" : "s") · \(preview.samples) supported sample\(preview.samples == 1 ? "" : "s")\n\(preview.skipped) unsupported, duplicate or invalid record\(preview.skipped == 1 ? "" : "s") skipped").font(.subheadline)
                        if let first = preview.coveredDays.first, let last = preview.coveredDays.last { Text("\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))").font(.footnote) }
                        if !preview.workouts.isEmpty {
                            Text("\(preview.workouts.count) workout\(preview.workouts.count == 1 ? "" : "s") · \(WorkoutReconciliation.matches(preview.workouts, current: health.workouts)) already recorded").font(.headline)
                            Text("Matching sessions are kept once. Live source copies take priority. Missing workout energy stays unknown.").font(.footnote).foregroundStyle(Theme.secondary)
                            ForEach(preview.workouts.suffix(3)) { workout in
                                Text("\(workout.title) · \(Int(workout.duration / 60)) min · \(workout.energyDescription)\n\(workout.sourceDescription)").font(.caption).foregroundStyle(Theme.secondary)
                            }
                            if preview.workoutFieldWarnings > 0 { Text("\(preview.workoutFieldWarnings) workout fields could not be read. Review imported sessions for details.").font(.footnote).foregroundStyle(Theme.secondary) }
                        }
                        Text("Sources: \(preview.sourceNames.joined(separator: ", "))").font(.footnote)
                        Text("For each metric/day, the source with the most samples wins; sources are never added together. Existing imported values for those dates will be replaced. Review sample sources below.").font(.footnote).foregroundStyle(Theme.secondary)
                        ForEach(preview.days.suffix(3)) { day in
                            Text(day.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                            ForEach(day.values.keys.sorted(), id: \.self) { key in
                                Text("\(ImportedMetrics.labels[key] ?? key): \(day.values[key]!, specifier: "%.1f") \(ImportedMetrics.displayUnit(key)) · \(day.sources[key] ?? "")").font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }
                        if filename.lowercased().hasSuffix(".zip") {
                            Text("Imports supported measurements and workout summaries. Clinical documents and workout routes aren’t included. Add PDF or text records separately in Library.")
                                .font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("zipImportScope")
                        }
                        Button("Import \(preview.coveredDays.count) day\(preview.coveredDays.count == 1 ? "" : "s")") { companion.commit(preview, filename: filename); self.preview = nil; AppRouter.shared.confirm("Health history imported") }.buttonStyle(.borderedProminent)
                        Button("Discard preview", role: .cancel) { self.preview = nil }
                    }.padding(.vertical, 12)
                }
            } header: { Text("Your exports") } footer: { Text("CSV columns: date,metric,value,unit,source. Example: 2026-10-28,steps,8421,count,Watch. Supported metrics: steps, sleep, exercise, activeEnergy, restingHR, hrv, weight, water, heartRate, respiratoryRate, spo2, vo2max, bodyFat, bmi, calories, protein, carbs, fat.") }
            Section("Import history") {
                if companion.imports.isEmpty { Text("Nothing imported yet").foregroundStyle(Theme.secondary) }
                ForEach(companion.imports) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.filename).font(.subheadline.weight(.semibold))
                        Text("\(receipt.days) day\(receipt.days == 1 ? "" : "s") · \(receipt.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Theme.secondary)
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
            .toolbar {
                if parsing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel import", role: .cancel) { cancelImport() }
                            .disabled(cancelRequested)
                            .accessibilityIdentifier("cancelHealthImport")
                    }
                }
            }
            .onDisappear { cancelImport(showMessage: false) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .xml, .commaSeparatedText, .json]) { result in read(result) }
            .alert("Couldn't import health data", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .confirmationDialog("Clear imported measurements and exported workouts?", isPresented: $clear, titleVisibility: .visible) { Button("Clear imported history", role: .destructive) { companion.clearImports() } }
    }
    func cancelImport(showMessage: Bool = true) {
        guard let activeImport else { return }
        activeImport.cancel()
        if showMessage {
            // Keep file selection disabled until the worker releases its stream and security scope.
            cancelRequested = true
        } else {
            self.activeImport = nil; importTask?.cancel(); importTask = nil
            parsing = false; cancelRequested = false
        }
    }
    func read(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { if case .failure(let e) = result, (e as NSError).code != NSUserCancelledError { error = e.localizedDescription }; return }
        cancelImport(showMessage: false)
        let control = HealthImportControl()
        activeImport = control; parsing = true; cancelRequested = false; preview = nil; importStatus = nil; filename = url.lastPathComponent
        importTask = Task { @MainActor in
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try HealthImportService.parse(url: url, control: control)
                }.value
                guard activeImport === control else { return }
                try control.checkCancellation()
                preview = parsed
            } catch is CancellationError {
                guard activeImport === control else { return }
                importStatus = "Import cancelled. No records were added."
            } catch {
                guard activeImport === control else { return }
                if cancelRequested { importStatus = "Import cancelled. No records were added." }
                else { self.error = error.localizedDescription }
            }
            guard activeImport === control else { return }
            activeImport = nil; importTask = nil; parsing = false; cancelRequested = false
        }
    }
}
