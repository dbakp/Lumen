import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class ReadableTransferSession: ObservableObject {
    enum Action { case exporting, reading, restoring }
    @Published var conversion: ReadableExport.Conversion?
    @Published var selection = Set<ReadableExport.Domain>()
    @Published var shared: BackupService.Export?
    @Published var control: BackupOperationControl?
    @Published var action = Action.reading
    @Published var cancellationRequested = false
    @Published var message: String?
    @Published var error: String?
    @Published var filename = ""
    @Published var recovered = false
    private var work: Task<Void, Never>?
    private var closed = false
    var busy: Bool { control != nil }
    func open() { closed = false }
    func close() {
        closed = true; cancel()
        if !busy { releaseFiles() }
    }
    private func releaseFiles() { shared?.cleanup(); shared = nil; conversion = nil; selection = [] }
    func cancel() { guard let control else { return }; cancellationRequested = true; control.cancel(); work?.cancel() }
    private func begin(_ action: Action) -> BackupOperationControl? {
        guard !busy, !closed else { return nil }
        let value = BackupOperationControl(); self.action = action; control = value
        message = nil; error = nil; cancellationRequested = false; recovered = false
        return value
    }
    private func finish(_ failure: Error? = nil) {
        control = nil; work = nil
        if closed { releaseFiles(); return }
        if failure is CancellationError { message = "Cancelled. Your saved data hasn't changed." }
        else if let failure { error = failure.localizedDescription }
    }
    func create(sleep: SleepStore, health: HealthStore) {
        guard let control = begin(.exporting) else { return }
        work = Task {
            do {
                let value = try await BackupService.exportReadable(sleep: sleep, health: health, control: control)
                guard !closed, !Task.isCancelled else { value.cleanup(); throw CancellationError() }
                shared?.cleanup(); shared = value; finish()
            } catch { finish(error) }
        }
    }
    func read(_ url: URL) {
        guard let control = begin(.reading) else { return }
        conversion = nil; selection = []; filename = url.lastPathComponent
        work = Task {
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    try BackupService.selectReadable(url, control: control)
                }.value
                do {
                    let value = try await Task.detached(priority: .userInitiated) { try BackupService.convertReadable(source, control: control) }.value
                    source.cleanup()
                    try control.checkCancellation()
                    guard !closed, !Task.isCancelled else { throw CancellationError() }
                    conversion = value; selection = value.defaultSelection; finish()
                } catch { source.cleanup(); throw error }
            } catch { finish(error) }
        }
    }
    func restore(sleep: SleepStore, health: HealthStore) {
        guard let conversion, !selection.isEmpty, let control = begin(.restoring) else { return }
        let selected = selection
        work = Task {
            do {
                try await BackupService.restoreReadable(conversion, domains: selected, sleep: sleep, health: health, control: control)
                self.conversion = nil; selection = []
                if !closed { recovered = true; message = "Selected data is saved. Current matching records were kept." }
                finish()
            } catch { finish(error) }
        }
    }
}

struct ReadableExportView: View {
    @EnvironmentObject private var sleep: SleepStore
    @EnvironmentObject private var health: HealthStore
    @StateObject private var session = ReadableTransferSession()
    @State private var showingError = false
    var body: some View {
        Form {
            Section {
                Text("Your data,\nin plain text.").font(.largeTitle.bold()).fontWidth(.expanded)
                Text("This JSON file isn't encrypted and doesn't include meal photos.").foregroundStyle(Theme.secondary)
            }.listRowBackground(Color.clear)
            if health.isSyncing { Section { Text("Health is syncing. Try again shortly.").foregroundStyle(Theme.secondary) } }
            if let control = session.control { ReadableTransferProgress(control: control, exporting: true) }
            if let shared = session.shared {
                Section {
                    Label("Readable export ready", systemImage: "doc.text").font(.headline).accessibilityIdentifier("readableExportReady")
                    ShareLink(item: shared.url) { Label("Save or share export", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("shareReadableExport")
                } footer: { Text("Save it to Files before leaving. Lumen removes this temporary share copy when you leave.").foregroundStyle(Theme.secondary) }.disabled(session.busy)
            }
            Section {
                Button("Create export", systemImage: "doc.badge.plus") { session.create(sleep: sleep, health: health) }.accessibilityIdentifier("createReadableExport")
                NavigationLink("Recover an earlier export") { ReadableRecoveryView() }.accessibilityIdentifier("readableRecovery")
            }.disabled(session.busy || health.isSyncing)
            Section {
                Text("For a password-protected transfer with meal photos, use Backup & restore.").foregroundStyle(Theme.secondary)
            }
            if let message = session.message { Section { Text(message).foregroundStyle(Theme.secondary).accessibilityIdentifier("readableStatus") } }
        }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Readable export").navigationBarTitleDisplayMode(.inline)
            .toolbar { if session.busy { ToolbarItem(placement: .topBarTrailing) { ReadableCancelButton(session: session) } } }
            .alert("Couldn't create export", isPresented: $showingError) { Button("OK", role: .cancel) { session.error = nil } } message: { Text(session.error ?? "") }
            .onChange(of: session.error) { _, value in showingError = value != nil }
            .onAppear { session.open() }.onDisappear { session.close() }
    }
}

struct ReadableRecoveryView: View {
    @EnvironmentObject private var sleep: SleepStore
    @EnvironmentObject private var health: HealthStore
    @StateObject private var session = ReadableTransferSession()
    @State private var showingError = false
    @State private var choosing = false
    @State private var confirming = false
    @State private var reviewing: ReadableExport.Domain?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            if session.recovered {
                Section {
                    Text("Recovery\ncomplete.").font(.largeTitle.bold()).fontWidth(.expanded)
                    Text(session.message ?? "Selected data is saved.").foregroundStyle(Theme.secondary).accessibilityIdentifier("readableStatus")
                    Button("Done") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("finishReadableRecovery")
                    Button("Choose another export", systemImage: "doc.badge.plus") { choosing = true }.accessibilityIdentifier("chooseReadableExport")
                }.listRowBackground(Color.clear).id("status")
            } else {
                Section {
                    Text("Review before\nadding.").font(.largeTitle.bold()).fontWidth(.expanded)
                    Text("Bring back data from a readable Lumen export. Choose what to add before anything changes.").foregroundStyle(Theme.secondary)
                    Button("Choose export", systemImage: "doc.badge.plus") { choosing = true }.accessibilityIdentifier("chooseReadableExport")
                }.listRowBackground(Color.clear).disabled(session.busy || health.isSyncing)
            }
            if health.isSyncing { Section { Text("Health is syncing. Try again shortly.").foregroundStyle(Theme.secondary) } }
            if let control = session.control { ReadableTransferProgress(control: control, exporting: false).id("progress") }
            if let value = session.conversion {
                Section {
                    Text(verbatim: session.filename).font(.headline)
                    LabeledContent("Exported") { Text(value.exportedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.secondary) }
                    Text("Lumen checks the file format but can’t confirm who created or edited it.").font(.footnote).foregroundStyle(Theme.secondary)
                } header: { Text("File to review").foregroundStyle(Theme.secondary) }.id("review")
                Section {
                    ForEach(ReadableExport.Domain.allCases.filter { $0.preference.isEmpty && value.present.contains($0) }) { domain in
                        VStack(alignment: .leading, spacing: 8) {
                            selection(domain, count: value.count(domain)).disabled(value.count(domain) == 0)
                            if value.count(domain) > 0 { Button("Review records", systemImage: "text.magnifyingglass") { reviewing = domain }.accessibilityIdentifier("reviewReadable-\(domain.rawValue)") }
                        }
                    }
                } header: { Text("Records to add").foregroundStyle(Theme.secondary) } footer: {
                    Text("Current matching records are kept. Imported health days add only missing values. Review saved values in their original units.").foregroundStyle(Theme.secondary)
                }.disabled(session.busy || health.isSyncing)
                if !value.present.filter({ !$0.preference.isEmpty }).isEmpty {
                    Section {
                        ForEach(ReadableExport.Domain.allCases.filter { !$0.preference.isEmpty && value.present.contains($0) }) { domain in
                            VStack(alignment: .leading, spacing: 8) {
                                selection(domain, count: value.count(domain))
                                Button("Review settings", systemImage: "text.magnifyingglass") { reviewing = domain }.accessibilityIdentifier("reviewReadable-\(domain.rawValue)")
                            }
                        }
                    } header: { Text("Optional replacements").foregroundStyle(Theme.secondary) } footer: {
                        Text("Off by default. Selected settings replace their current values. Device lock, subscription, connections and permissions stay as they are. Replaced personal notes start with assistant sharing off.").foregroundStyle(Theme.secondary)
                    }.disabled(session.busy || health.isSyncing)
                }
                Section {
                    if value.present.contains(.meals) { Text("Meal photos aren't in readable exports. Meal text is kept without those photos.").foregroundStyle(Theme.secondary) }
                    if value.missingPhotos > 0 { LabeledContent("Meals with missing photos") { Text(value.missingPhotos.formatted()).foregroundStyle(Theme.secondary) }.accessibilityElement(children: .combine).accessibilityIdentifier("readableMissingPhotos") }
                    if value.mirroredMessages > 0 && !value.recoveredChat { Text("The active chat repeats \(value.mirroredMessages.formatted()) archived messages. Those copies won't create another conversation.").foregroundStyle(Theme.secondary) }
                    if value.recoveredChat { Text("The full active chat is kept as a separate recovered conversation. Messages already in the archive may appear in both.").foregroundStyle(Theme.secondary) }
                    if value.omittedSampleMeals > 0 { Text("\(value.omittedSampleMeals.formatted()) demo meals are excluded.").foregroundStyle(Theme.secondary) }
                    if value.omittedSampleWorkouts > 0 { Text("\(value.omittedSampleWorkouts.formatted()) demo workouts are excluded.").foregroundStyle(Theme.secondary) }
                    if value.omittedKeys.contains("today") { Text("Temporary daily totals aren't recreated as individual records.").foregroundStyle(Theme.secondary) }
                    if !value.omittedKeys.isEmpty {
                        Text("Not added from this file").font(.headline).foregroundStyle(Theme.secondary)
                        ForEach(value.omittedKeys, id: \.self) { key in
                            Text(verbatim: ["today": "Temporary daily totals", "healthSync": "Background Health state", "reminder-preferences": "Reminder settings" ][key] ?? "Unrecognized section: " + key)
                                .font(.footnote).foregroundStyle(Theme.secondary)
                        }
                    }
                    Text("Added Library documents start with assistant sharing off. Recovery doesn't write to Apple Health.").foregroundStyle(Theme.secondary)
                } header: { Text("What to expect").foregroundStyle(Theme.secondary) }
                Section {
                    Button("Add selected data") { confirming = true }.fontWeight(.semibold).disabled(session.selection.isEmpty || session.busy || health.isSyncing).accessibilityIdentifier("recoverReadableData")
                }
            }
            if let message = session.message, !session.recovered { Section { Text(message).foregroundStyle(Theme.secondary).accessibilityIdentifier("readableStatus") }.id("status") }
        }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Recover export").navigationBarTitleDisplayMode(.inline)
            .toolbar { if session.busy { ToolbarItem(placement: .topBarTrailing) { ReadableCancelButton(session: session) } } }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): session.read(url)
                case .failure(let error): if (error as NSError).code != NSUserCancelledError { session.error = error.localizedDescription }
                }
            }
            .sheet(item: $reviewing) { domain in if let value = session.conversion { ReadableRecordsReview(conversion: value, domain: domain) } }
            .alert(session.action == .restoring ? "Couldn't recover data" : "Couldn't read export", isPresented: $showingError) { Button("OK", role: .cancel) { session.error = nil } } message: { Text(session.error ?? "") }
            .onChange(of: session.error) { _, value in showingError = value != nil }
            .alert("Add selected data?", isPresented: $confirming) {
                Button("Add data") { session.restore(sleep: sleep, health: health) }
                Button("Keep reviewing", role: .cancel) {}
            } message: { Text("The selected records will be added. Records already saved are kept. Selected settings replace their current values.") }
            .onAppear { session.open() }.onDisappear { session.close() }
            .task(id: scrollTarget) {
                guard let target = scrollTarget else { return }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }
    private var scrollTarget: String? { session.busy ? "progress" : session.conversion != nil ? "review" : session.message != nil ? "status" : nil }
    @ViewBuilder private func selection(_ domain: ReadableExport.Domain, count: Int) -> some View {
        let binding = Binding(get: { session.selection.contains(domain) }, set: { if $0 { session.selection.insert(domain) } else { session.selection.remove(domain) } })
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(domain.title).font(.headline)
                if domain.preference.isEmpty || domain == .habits { Text("\(count.formatted()) saved").font(.subheadline).foregroundStyle(Theme.secondary) }
                Toggle(domain.title, isOn: binding).labelsHidden().accessibilityIdentifier("recoverReadable-\(domain.rawValue)")
            }
        } else {
            Toggle(isOn: binding) {
                VStack(alignment: .leading, spacing: 4) { Text(domain.title); if domain.preference.isEmpty || domain == .habits { Text("\(count.formatted()) saved").font(.caption).foregroundStyle(Theme.secondary) } }
            }.accessibilityIdentifier("recoverReadable-\(domain.rawValue)")
        }
    }
}

private struct ReadableCancelButton: View {
    @ObservedObject var session: ReadableTransferSession
    var body: some View {
        Button(session.cancellationRequested ? "Cancelling…" : "Cancel", role: .cancel) { session.cancel() }
            .disabled(session.cancellationRequested).accessibilityIdentifier("cancelReadableOperation")
    }
}
private struct ReadableTransferProgress: View {
    let control: BackupOperationControl
    let exporting: Bool
    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                let state = control.progress
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.stage == .restoring ? "Preparing recovery" : exporting ? "Creating readable export" : "Checking export").font(.headline)
                    if let detail = state.detail { Text(detail).font(.subheadline).foregroundStyle(Theme.secondary) }
                    if state.total > 0 {
                        ProgressView(value: Double(state.completed), total: Double(state.total))
                        Text("\(state.completed.formatted()) of \(state.total.formatted()) items").font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
                    } else { ProgressView() }
                    if state.bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: state.bytes, countStyle: .file) + " processed").font(.footnote).foregroundStyle(Theme.secondary) }
                }.accessibilityIdentifier("readableProgress")
            }
        }
    }
}
