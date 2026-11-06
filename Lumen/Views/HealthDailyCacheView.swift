import SwiftUI

@MainActor
struct HealthDailyCacheView: View {
    @EnvironmentObject private var health: HealthStore
    @StateObject private var model = HealthDailyCacheReviewModel()
    @ObservedObject private var appleHealth = HealthKitService.shared
    @State private var confirmation = false
    @State private var showingReadings = false
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var verification = HealthRecoveryCancelUIState.shared
    #endif

    var body: some View {
        Form {
            if let issue = model.issue {
                Section { Text(issue).accessibilityIdentifier("dailyCacheIssue") }
            }
            if !health.conversationReady {
                Section {
                    Text(health.conversationStorageIssue ?? "Saved history is still opening.")
                    if health.conversationStorageIssue != nil {
                        Button("Retry opening history") { Task { await health.openConversationsChecked() } }
                            .accessibilityIdentifier("retryDailyCacheHistory")
                    }
                }
            }
            if model.phase == .saved {
                Section {
                    Label(model.savedClear ? "Saved snapshot cleared" : "Saved snapshot rebuilt", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("dailyCacheSaved")
                    Text("Local logs, imported days and sleep history aren't deleted.")
                    if let issue = health.localHealthStorageIssue { Text(issue) }
                }
                Section { Button("Check saved readings") { model.inspect(health) } }
            } else if let preview = model.preview {
                review(preview)
            } else {
                Section {
                    if let state = model.fileState {
                        Text(stateLabel(state)).accessibilityIdentifier("dailyCacheFileState")
                    }
                    Text("Backups and readable exports don't include daily readings.")
                        .accessibilityIdentifier("dailyCacheBackupScope")
                    Button("Check saved readings") { model.inspect(health) }.disabled(model.busy)
                        .accessibilityIdentifier("inspectDailyCache")
                } header: { Text("Saved readings") }
                Section {
                    if !appleHealth.isAvailable { Text("Apple Health isn't available on this device.") }
                    else if !appleHealth.isAuthorized { Text("Connect Apple Health in Settings to rebuild readings.") }
                    Button("Check Apple Health") { model.review(.rebuild, health: health) }
                        .disabled(model.busy || model.fileState == nil || !health.conversationReady || health.isSyncing || !appleHealth.isAvailable || !appleHealth.isAuthorized)
                        .accessibilityIdentifier("checkDailyCacheHealth")
                } header: { Text("Rebuild readings") }
                Section {
                    Button("Review clearing readings") { model.review(.clear, health: health) }
                        .disabled(model.busy || model.fileState == nil || !health.conversationReady || health.isSyncing)
                        .accessibilityIdentifier("reviewClearDailyCache")
                } header: { Text("Clear saved readings") }
            }
            if model.busy {
                Section {
                    progress
                    Button("Cancel") { model.cancel(health, showMessage: true) }
                        .accessibilityIdentifier("cancelDailyCache")
                }
            } else if health.isSyncing && model.phase != .saved {
                Section { Text("Syncing is in progress. Wait for it to finish before replacing readings.") }
            }
        }
        .navigationTitle("Daily readings").navigationBarTitleDisplayMode(.inline)
        .task { model.open(health) }
        .onDisappear {
            #if DEBUG && targetEnvironment(simulator)
            if model.phase == .saved && HealthDailyCacheRecordedFixture.requested {
                Task { await HealthDailyCacheRecordedFixture.cleanup() }
            }
            #endif
            if !showingReadings { model.close(health) }
        }
        .navigationDestination(isPresented: $showingReadings) {
            if let preview = model.preview {
                HealthDailyCacheReadingsView(metrics: preview.replacement.metrics)
            }
        }
        .alert(model.isClear ? "Clear saved readings?" : "Replace saved readings?", isPresented: $confirmation) {
            if model.isClear {
                Button("Clear readings", role: .destructive) { model.save(health) }
            } else { Button("Rebuild") { model.save(health) } }
            Button("Not now", role: .cancel) { }
        } message: { Text("This changes the saved daily snapshot only. Your records and settings stay.") }
    }

    @ViewBuilder private var progress: some View {
        #if DEBUG && targetEnvironment(simulator)
        if HealthRecoveryCancelUIFixture.requested {
            ProgressView(model.progressLabel).accessibilityIdentifier("dailyCacheProgress").accessibilityValue(verification.phase)
        } else { ProgressView(model.progressLabel).accessibilityIdentifier("dailyCacheProgress") }
        #else
        ProgressView(model.progressLabel).accessibilityIdentifier("dailyCacheProgress")
        #endif
    }

    @ViewBuilder private func review(_ preview: HealthStore.DailyCachePreview) -> some View {
        Section {
            Text(model.isClear
                 ? "The saved daily snapshot will become unknown. This doesn't delete local logs, imported days or sleep history."
                 : "These Apple Health results will replace the saved daily snapshot.")
                .accessibilityIdentifier("dailyCacheConsequence")
            Text("Replaced files stay in a private copy on this iPhone.")
                .accessibilityIdentifier("dailyCacheRetainedConsequence")
        } header: { Text(model.isClear ? "Clear saved readings" : "Replace saved readings") }
        if let readings = preview.readings {
            Section {
                LabeledContent("Returned", value: String(count(.recorded, readings: readings)))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("dailyCacheReturnedCount")
                LabeledContent("No data", value: String(count(.noData, readings: readings)))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("dailyCacheNoDataCount")
                LabeledContent("Couldn't check", value: String(count(.failed, readings: readings)))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("dailyCacheFailedCount")
                LabeledContent("From", value: readings.raw.start.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("dailyCacheQueryFrom")
                LabeledContent("Through", value: readings.raw.end.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("dailyCacheQueryThrough")
                Button("Review readings") { showingReadings = true }.disabled(model.busy)
                    .accessibilityIdentifier("reviewDailyCacheReadings")
                if count(.noData, readings: readings) > 0 || count(.failed, readings: readings) > 0 {
                    Text("Empty or failed queries stay unknown. Empty results don't reveal read permission.")
                        .accessibilityIdentifier("dailyCacheQueryScope")
                }
            } header: { Text("Apple Health results") }
        }
        if !model.busy {
            Section {
                if model.isClear {
                    Button("Clear saved readings", role: .destructive) { confirmation = true }
                        .disabled(!health.conversationReady || health.isSyncing).accessibilityIdentifier("confirmClearDailyCache")
                } else {
                    Button("Rebuild saved readings") { confirmation = true }
                        .disabled(!health.conversationReady || health.isSyncing).accessibilityIdentifier("confirmRebuildDailyCache")
                }
                Button("Not now") { model.cancel(health, showMessage: false); model.inspect(health) }
                    .accessibilityIdentifier("discardDailyCacheReview")
            }
        }
    }

    private func count(_ outcome: HealthMetricQuery.Outcome, readings: HealthTodayReadCoordinator.Readings) -> Int {
        readings.raw.metrics.readings?.values.filter { $0.healthQuery?.outcome == outcome }.count ?? 0
    }
    private func stateLabel(_ state: HealthDailyCache.Boundary.State) -> String {
        switch state {
        case .missing: return "No saved snapshot"
        case .healthy: return "Saved snapshot opens"
        case .unavailable: return "Saved snapshot couldn't be opened"
        }
    }
}

@MainActor
private struct HealthDailyCacheReadingsView: View {
    let metrics: DayMetrics
    private var keys: [String] { HealthMetricCatalog.keys.filter { HealthDailyCache.queryKeys.contains($0) } }
    var body: some View {
        Form {
            ForEach(keys, id: \.self) { key in
                let reading = metrics.reading(key)
                Section {
                    Text(HealthMetricCatalog.display(reading.value, key: key)).accessibilityIdentifier("dailyCacheValue-" + key)
                    if !reading.sourceLabel.isEmpty { Text(reading.sourceLabel).accessibilityIdentifier("dailyCacheSource-" + key) }
                    if let query = reading.healthQuery {
                        Text(outcomeLabel(query.outcome)).accessibilityIdentifier("dailyCacheOutcome-" + key)
                        LabeledContent("Checked", value: query.checkedAt.formatted(date: .abbreviated, time: .shortened))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("dailyCacheChecked-" + key)
                        LabeledContent("Query from", value: query.start.formatted(date: .abbreviated, time: .shortened))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("dailyCacheStart-" + key)
                        LabeledContent("Query through", value: query.end.formatted(date: .abbreviated, time: .shortened))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("dailyCacheEnd-" + key)
                    }
                    ForEach(Array(reading.components.enumerated()), id: \.offset) { offset, component in
                        Text(component.periodDescription).accessibilityIdentifier("dailyCachePeriod-" + key + "-" + String(offset))
                    }
                } header: { Text(HealthMetricCatalog.labels[key] ?? key).accessibilityIdentifier("dailyCacheHeading-" + key) }
            }
        }
        .navigationTitle("Review readings").navigationBarTitleDisplayMode(.inline)
    }
    private func outcomeLabel(_ outcome: HealthMetricQuery.Outcome) -> String {
        switch outcome {
        case .recorded: return "Reading returned"
        case .noData: return "No data returned"
        case .failed: return "Couldn't check"
        }
    }
}

@MainActor
private final class HealthDailyCacheReviewModel: ObservableObject {
    enum Phase { case idle, inspecting, querying, reviewing, saving, saved }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fileState: HealthDailyCache.Boundary.State?
    @Published private(set) var preview: HealthStore.DailyCachePreview?
    @Published private(set) var issue: String?
    @Published private(set) var savedClear = false
    private var generation = UUID()
    private var control: BackupOperationControl?
    private var work: Task<Void, Never>?
    var busy: Bool { phase == .inspecting || phase == .querying || phase == .saving }
    var isClear: Bool {
        guard let preview else { return false }
        if case .clear = preview.replacement { return true }
        return false
    }
    var progressLabel: String {
        switch phase {
        case .querying: return "Checking Apple Health…"
        case .saving: return "Saving daily readings…"
        default: return "Checking saved readings…"
        }
    }

    deinit { control?.cancel(); work?.cancel() }
    func open(_ health: HealthStore) { if phase == .idle && fileState == nil && work == nil { inspect(health) } }
    func close(_ health: HealthStore) { cancel(health, showMessage: false); fileState = nil }
    func cancel(_ health: HealthStore, showMessage: Bool) {
        guard phase != .saved else { return }
        generation = UUID(); work?.cancel(); work = nil
        if let control { health.cancelDailyCacheReview(control: control) }
        control = nil; preview = nil; phase = .idle
        if showMessage { issue = "Cancelled. Saved readings haven't changed." }
    }
    func inspect(_ health: HealthStore) {
        guard !busy else { return }
        cancel(health, showMessage: false)
        let operation = BackupOperationControl(), token = UUID()
        generation = token; control = operation; phase = .inspecting; issue = nil; preview = nil
        work = Task { [weak self] in
            do {
                let state = try await health.inspectDailyCache(control: operation)
                try Task.checkCancellation(); try operation.checkCancellation()
                guard let self, self.generation == token else { return }
                self.fileState = state; self.phase = .idle; self.control = nil; self.work = nil
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fileState = nil; self.phase = .idle; self.control = nil; self.work = nil
                self.issue = "Saved readings couldn't be checked safely. Nothing was replaced. Check saved readings to retry."
            }
        }
    }
    func review(_ action: HealthStore.DailyCacheAction, health: HealthStore) {
        guard !busy, fileState != nil else { return }
        cancel(health, showMessage: false)
        let operation = makeControl(), token = UUID()
        generation = token; control = operation; issue = nil
        switch action { case .clear: phase = .inspecting; case .rebuild: phase = .querying }
        work = Task { [weak self] in
            do {
                let preview = try await health.reviewDailyCache(action, control: operation)
                try Task.checkCancellation(); try operation.checkCancellation()
                guard let self, self.generation == token else { return }
                self.preview = preview; self.fileState = preview.boundary.state; self.phase = .reviewing; self.work = nil
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail(error, health: health, operation: operation,
                          fallback: "Readings couldn't be checked. Your saved readings haven't changed. Check saved readings to retry.")
            }
        }
    }
    func save(_ health: HealthStore) {
        guard phase == .reviewing, let preview, let operation = control else { return }
        let token = generation, clearing = isClear
        phase = .saving; issue = nil
        work = Task { [weak self] in
            do {
                try await health.installDailyCache(preview, control: operation) { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.savedClear = clearing; self.phase = .saved; self.preview = nil
                    self.control = nil; self.work = nil; self.issue = nil
                }
            } catch {
                guard let self, self.generation == token, self.phase != .saved, !Task.isCancelled else { return }
                self.fail(error, health: health, operation: operation,
                          fallback: "Readings couldn't be saved. Your saved readings haven't been replaced. Check saved readings to retry.")
            }
        }
    }
    private func fail(_ error: Error, health: HealthStore, operation: BackupOperationControl, fallback: String) {
        health.cancelDailyCacheReview(control: operation)
        preview = nil; fileState = nil; phase = .idle; control = nil; work = nil
        switch error {
        case HealthStore.DailyCacheFailure.opening:
            issue = health.conversationStorageIssue ?? "Saved history is still opening. Wait, then check saved readings again."
        case HealthStore.DailyCacheFailure.busy:
            issue = "Syncing is in progress. Wait for it to finish, then check saved readings again."
        case HealthStore.DailyCacheFailure.changed, HealthTodayReadCoordinator.Failure.changed, BackupError.recordsChanged:
            issue = "Saved readings or their source changed. Check saved readings before replacing them."
        case HealthTodayReadCoordinator.Failure.unavailable:
            issue = "Apple Health isn't connected or available. Your saved readings haven't changed."
        default: issue = fallback
        }
    }
    private func makeControl() -> BackupOperationControl {
        #if DEBUG && targetEnvironment(simulator)
        return HealthRecoveryCancelUIFixture.makeControl()
        #else
        return BackupOperationControl()
        #endif
    }
}
