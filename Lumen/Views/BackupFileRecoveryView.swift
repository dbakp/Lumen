import SwiftUI

/// Completed Task handles retain their result. Returning closable owners keeps
/// those cached results from becoming permanent owners of temporary files.
final class BackupSelectedSourceSession: Sendable {
    struct Summary: Sendable { let name: String; let encrypted: Bool }
    let summary: Summary
    private let lease: BackupReviewLease<BackupService.Source>
    init(_ source: BackupService.Source) {
        summary = Summary(name: source.name, encrypted: source.encrypted)
        lease = BackupReviewLease(source)
    }
    func close() { lease.close() }
    func read(password: String, control: BackupOperationControl) throws -> BackupPreviewSession {
        let source = try lease.acquire(control: control)
        defer { withExtendedLifetime(source) {} }
        return BackupPreviewSession(try BackupService.read(source, password: password, control: control))
    }
    func convertReadable(control: BackupOperationControl) throws -> ReadableExport.Conversion {
        let source = try lease.acquire(control: control)
        defer { withExtendedLifetime(source) {} }
        return try BackupService.convertReadable(source, control: control)
    }
    @MainActor func readableReview(_ conversion: ReadableExport.Conversion, control: BackupOperationControl) throws -> BackupRecoveryReviewSession? {
        let source = try lease.acquire(control: control)
        return BackupService.recoveryInput(conversion, source: source).map(BackupRecoveryReviewSession.init)
    }
    @MainActor func restoreReadable(_ conversion: ReadableExport.Conversion, domains: Set<ReadableExport.Domain>,
                                    sleep: SleepStore, health: HealthStore, control: BackupOperationControl) async throws {
        let source = try lease.acquire(control: control)
        defer { withExtendedLifetime(source) {} }
        try await BackupService.restoreReadable(conversion, domains: domains, sleep: sleep, health: health, control: control, source: source)
    }
}

final class BackupPreviewSession: Sendable {
    struct Summary: Sendable {
        let createdAt: Date; let encrypted: Bool; let photoCount: Int
        let symptoms: Int; let checkIns: Int; let meals: Int; let water: Int
        let workouts: Int; let sleep: Int; let conversations: Int; let documents: Int; let importedDays: Int
    }
    let summary: Summary
    private let lease: BackupReviewLease<BackupService.Preview>
    init(_ preview: BackupService.Preview) {
        let snapshot = preview.snapshot
        summary = Summary(createdAt: preview.createdAt, encrypted: preview.encrypted, photoCount: preview.photos.count,
                          symptoms: snapshot.symptoms.count, checkIns: snapshot.checkIns.count, meals: snapshot.meals.count,
                          water: snapshot.water.count, workouts: snapshot.workouts.count, sleep: snapshot.sleep.count,
                          conversations: snapshot.conversations.count, documents: snapshot.documents.count, importedDays: snapshot.importedDays.count)
        lease = BackupReviewLease(preview)
    }
    func close() { lease.close() }
    func acquire(control: BackupOperationControl) throws -> BackupService.Preview { try lease.acquire(control: control) }
    @MainActor func restore(preferences: Bool, sleep: SleepStore, health: HealthStore, control: BackupOperationControl) async throws {
        let preview = try acquire(control: control)
        defer { withExtendedLifetime(preview) {} }
        try await BackupService.restore(preview, preferences: preferences, sleep: sleep, health: health, control: control)
    }
}

/// Navigation may cache destination values after Back. Those values keep only
/// this closable owner and display metadata; real workers acquire their own input.
final class BackupRecoveryReviewSession: Sendable {
    struct Summary: Sendable {
        let identity: BackupSourceIdentity
        let createdAt: Date
        let present: Set<HealthLocalFiles.Domain>
        let missingPhotos: Int
        let photoIDs: Set<String>
        let counts: [HealthLocalFiles.Domain: Int]
        func count(_ domain: HealthLocalFiles.Domain) -> Int { counts[domain] ?? 0 }
    }
    let id = UUID()
    private let origins = HealthRecoveryOriginReviewLease()
    var originMetadata: HealthLegacyRecoveryOrigin.ReviewMetadata? { origins.metadata }
    func beginOriginCapture(control: BackupOperationControl) throws { try origins.begin(control) }
    func suspendOriginCapture(control: BackupOperationControl) { origins.suspend(control) }
    /// Detached caller returns Void; completed tasks cannot retain raw snapshot results.
    func captureOrigins(domains: Set<HealthLocalFiles.Domain>, control: BackupOperationControl) throws {
        let input = try acquire(control: control)
        defer { withExtendedLifetime(input) {} }
        let snapshot = try LocalStore.captureLegacyRecoveryReview(domains, control: control)
        try origins.finish(snapshot, control: control)
    }
    func acquireOrigins(_ domains: Set<HealthLocalFiles.Domain>, control: BackupOperationControl) throws
        -> [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin] {
        try origins.acquire(domains, control: control)
    }
    let summary: Summary
    private let lease: BackupReviewLease<BackupService.RecoveryInput>
    #if DEBUG && targetEnvironment(simulator)
    private let verificationSource: URL
    #endif
    init(_ input: BackupService.RecoveryInput) {
        summary = Summary(identity: input.identity, createdAt: input.createdAt, present: input.present,
                          missingPhotos: input.missingPhotos, photoIDs: input.photoIDs,
                          counts: Dictionary(uniqueKeysWithValues: HealthLocalFiles.Domain.allCases.map { ($0, input.count($0)) }))
        lease = BackupReviewLease(input)
        #if DEBUG && targetEnvironment(simulator)
        verificationSource = input.verificationSource
        #endif
    }
    func acquire(control: BackupOperationControl) throws -> BackupService.RecoveryInput { try lease.acquire(control: control) }
    func close() {
        origins.close()
        lease.close()
        #if DEBUG && targetEnvironment(simulator)
        HealthReadUIFixture.didEndReview(file: verificationSource)
        #endif
    }
    func records(_ domain: HealthLocalFiles.Domain, control: BackupOperationControl) throws -> HealthRecoveryRecordReview.Document {
        let input = try acquire(control: control)
        defer { withExtendedLifetime(input) {} }
        let data = try input.records(domain, control: control)
        try control.checkCancellation()
        let document = try HealthRecoveryRecordReview.Document.decode(data, domain: domain, control: control)
        try control.checkCancellation()
        return document
    }
    func photoData(_ id: String, control: BackupOperationControl) throws -> Data {
        let input = try acquire(control: control)
        return try input.photoData(id, control: control)
    }
}

/// A separate replacement review; ordinary imports continue to merge records.
@MainActor
struct BackupFileRecoveryView: View {
    let session: BackupRecoveryReviewSession
    private var input: BackupRecoveryReviewSession.Summary { session.summary }
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<HealthLocalFiles.Domain> = []
    @State private var omitPhotos = false
    private struct ConfirmationSelection {
        let sessionID: UUID
        let domains: Set<HealthLocalFiles.Domain>
        let legacyDomains: Set<HealthLocalFiles.Domain>
        let omitPhotos: Bool
    }
    @State private var confirmation = false
    @State private var confirmationSelection: ConfirmationSelection?
    @State private var originMetadata: HealthLegacyRecoveryOrigin.ReviewMetadata?
    @State private var captureIssue = false
    @State private var captureVisible = false
    @State private var captureControl: BackupOperationControl?
    @State private var captureWork: Task<Void, Never>?
    @State private var captureReveal: Task<Void, Never>?
    @State private var committedLegacyDomains: Set<HealthLocalFiles.Domain> = []
    @State private var busy = false
    @State private var recovered = false
    private struct RecoveryIssue {
        let id = UUID()
        let message: String
    }
    @State private var issue: RecoveryIssue?
    @AccessibilityFocusState private var recoveryErrorFocused: UUID?
    @State private var errorReveal: Task<Void, Never>?
    @State private var busyReveal: Task<Void, Never>?
    @State private var reviewActive = false
    @State private var operation: BackupOperationControl?
    @State private var work: Task<Void, Never>?
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var cancelVerification = HealthRecoveryCancelUIState.shared
    @ObservedObject private var readVerification = HealthReadUIState.shared
    #endif

    private var canRecover: Bool {
        !busy && !recovered && !health.isSyncing && !selected.isEmpty
        && selected.allSatisfy { input.present.contains($0) && !health.localHealthAvailable($0) && targetEligible($0) }
        && (!selected.contains(.meals) || input.missingPhotos == 0 || omitPhotos)
    }
    private func targetEligible(_ domain: HealthLocalFiles.Domain) -> Bool {
        guard let originMetadata else { return false }
        return originMetadata.fileDomains.contains(domain) || originMetadata.legacyDomains.contains(domain)
    }
    private var selectedLegacyDomains: Set<HealthLocalFiles.Domain> {
        selected.intersection(originMetadata?.legacyDomains ?? [])
    }
    private var preservation: String {
        let legacy = recovered ? committedLegacyDomains : selectedLegacyDomains
        guard !legacy.isEmpty else { return "Replaced files stay in a private copy on this iPhone. For meal recovery, this includes any old photos." }
        let allLegacy = recovered ? committedLegacyDomains.count == committedDomains.count : legacy == selected
        return allLegacy
            ? "Older saved data will stay in a private recovery copy on this iPhone. For meal recovery, this includes any old photos."
            : "Replaced data will stay in a private recovery copy on this iPhone. For meal recovery, this includes any old photos."
    }
    @State private var committedDomains: Set<HealthLocalFiles.Domain> = []
    private func confirmationMessage(_ selection: ConfirmationSelection) -> String {
        guard !selection.legacyDomains.isEmpty else { return "Selected data will be replaced by records from this file. Damaged originals will stay on this iPhone." }
        return selection.legacyDomains == selection.domains
            ? "Selected data will be replaced by records from this file. The older saved data will stay in a private recovery copy on this iPhone."
            : "Selected data will be replaced by records from this file. The replaced data will stay in a private recovery copy on this iPhone."
    }
    private var format: String {
        switch input.identity.format {
        case .encryptedBackup: return "Encrypted backup"
        case .legacyJSONBackup: return "Older JSON backup"
        case .readableExport: return "Readable export"
        }
    }
    var body: some View {
        ScrollViewReader { scroll in
        Form {
            Section {
                Text(input.identity.fileName).textSelection(.enabled).accessibilityIdentifier("recoveryFileName")
                LabeledContent("Format", value: format)
                LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: input.identity.byteCount, countStyle: .file))
                LabeledContent("Created", value: input.createdAt.formatted(date: .abbreviated, time: .shortened))
            } header: { Text("File to review") }
            if recovered {
                Section {
                    Label("Selected data recovered", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("fileHealthRecovered")
                        #if DEBUG && targetEnvironment(simulator)
                        .accessibilityValue(cancelVerification.successPhase)
                        .task { await HealthRecoveryCancelUIFixture.observeSuccess() }
                        #endif
                }
            }
            if captureVisible {
                Section { ProgressView("Checking saved data…").accessibilityIdentifier("fileRecoveryCaptureProgress") }
            }
            if captureIssue {
                Section {
                    Text("Saved data couldn't be checked. Check again to retry.")
                    Button("Check again") { captureIssue = false; startOriginCapture() }
                        .accessibilityIdentifier("retryFileRecoveryCapture")
                }
            }
            ForEach(HealthLocalFiles.Domain.allCases, id: \.self) { domain in
                Section {
                    if input.present.contains(domain) {
                        Text(domain == .goals ? "Saved snapshot" : input.count(domain) == 1 ? "1 record" : "\(input.count(domain)) records")
                        NavigationLink("Review records") { BackupFileRecordsView(session: session, domain: domain) }
                            .accessibilityIdentifier("reviewFile-" + domain.rawValue)
                        if health.localHealthAvailable(domain) { Text("Current data opens").foregroundStyle(.secondary) }
                        else if originMetadata?.ineligibleDomains.contains(domain) == true {
                            Text("This saved data can't be replaced here.").foregroundStyle(.secondary)
                        } else {
                            if originMetadata?.legacyDomains.contains(domain) == true {
                                Text("Older saved data couldn't be opened.").foregroundStyle(.secondary)
                            }
                            Toggle("Recover \(recoveryLabel(domain).lowercased())", isOn: Binding(
                                get: { selected.contains(domain) },
                                set: { if $0 { selected.insert(domain) } else { selected.remove(domain) } }
                            )).accessibilityIdentifier("recoverFile-" + domain.rawValue)
                                .disabled(!targetEligible(domain))
                        }
                        if domain == .meals && (input.missingPhotos > 0 || !input.photoIDs.isEmpty) {
                            if input.missingPhotos > 0 { Text("\(input.missingPhotos) meal photos aren't included.").foregroundStyle(.secondary) }
                            Toggle("Recover without meal photos", isOn: $omitPhotos)
                                .disabled(!targetEligible(.meals))
                            Text("Photos kept for recovery receive a final image check.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not included").foregroundStyle(.secondary)
                        if domain == .today {
                            Text("Daily readings aren't included in this file.").font(.footnote).foregroundStyle(.secondary)
                            NavigationLink("Manage daily readings") { HealthDailyCacheView() }
                                .accessibilityIdentifier("manageFileDailyCache")
                        }
                    }
                } header: { Text(recoveryLabel(domain)) }.disabled(busy || recovered)
            }
            Section {
                Text(preservation)
                Text("Recovered entries won't be added to Apple Health. Earlier pending Health saves won't restart; pending removals can finish.")
                if let issue {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recovery couldn't finish").font(.headline)
                        Text(issue.message)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("fileHealthRecoveryError")
                    .accessibilityFocused($recoveryErrorFocused, equals: issue.id)
                    .id("fileHealthRecoveryError")
                }
                if busy {
                    recoveryProgress
                    Button("Cancel") {
                        busyReveal?.cancel(); busyReveal = nil
                        operation?.cancel(); work?.cancel()
                    }
                    .accessibilityIdentifier("cancelFileRecovery")
                    .id("fileHealthRecoveryCancel")
                } else if recovered { Button("Done") { dismiss() } }
                else {
                    Button("Recover selected data") {
                        confirmationSelection = ConfirmationSelection(sessionID: session.id, domains: selected,
                            legacyDomains: selectedLegacyDomains, omitPhotos: omitPhotos)
                        confirmation = true
                    }.disabled(!canRecover)
                        .accessibilityIdentifier("confirmFileRecovery")
                }
            }
        }
        .onChange(of: busy) { _, active in
            busyReveal?.cancel(); busyReveal = nil
            guard active, reviewActive, let activeOperation = operation else { return }
            busyReveal = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, reviewActive, busy, operation === activeOperation else { return }
                do { try activeOperation.checkCancellation() } catch { return }
                scroll.scrollTo("fileHealthRecoveryCancel", anchor: .bottom)
            }
        }
        .onChange(of: issue?.id) { _, failureID in
            errorReveal?.cancel()
            guard let failureID, reviewActive else { return }
            errorReveal = Task { @MainActor in
                // Insert the native Form row before revealing it. Do this only
                // for a new failure, so subsequent reading never snaps back.
                await Task.yield()
                guard !Task.isCancelled, reviewActive, issue?.id == failureID else { return }
                scroll.scrollTo("fileHealthRecoveryError", anchor: .top)
                await Task.yield()
                guard !Task.isCancelled, reviewActive, issue?.id == failureID else { return }
                recoveryErrorFocused = failureID
            }
        }
        }
        .navigationTitle("Review recovery").navigationBarTitleDisplayMode(.inline)
        #if DEBUG && targetEnvironment(simulator)
        .toolbar {
            if HealthReadUIFixture.requested {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Read check").accessibilityIdentifier("healthReadControlState").accessibilityValue(readVerification.phase)
                }
            }
        }
        #endif
        .alert("Replace selected data?", isPresented: $confirmation, presenting: confirmationSelection) { selection in
            Button("Recover") { recover(selection) }
            Button("Not now", role: .cancel) { }
        } message: { selection in Text(confirmationMessage(selection)) }
        .onAppear { reviewActive = true; startOriginCapture() }
        .onDisappear {
            reviewActive = false
            if let captureControl { session.suspendOriginCapture(control: captureControl) }
            captureWork?.cancel(); captureReveal?.cancel()
            captureControl = nil; captureWork = nil; captureReveal = nil; captureVisible = false
            busyReveal?.cancel(); busyReveal = nil
            errorReveal?.cancel(); errorReveal = nil; recoveryErrorFocused = nil
            operation?.cancel(); work?.cancel()
        }
    }

    private func startOriginCapture() {
        guard reviewActive, captureControl == nil, !captureIssue else { return }
        if let ready = session.originMetadata { originMetadata = ready; return }
        let control = BackupOperationControl(), session = session
        do { try session.beginOriginCapture(control: control) } catch { return }
        captureControl = control
        let domains = input.present.filter { !health.localHealthAvailable($0) }
        captureReveal = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled, reviewActive, captureControl === control else { return }
            captureVisible = true
        }
        captureWork = Task { @MainActor in
            defer {
                if captureControl === control {
                    captureControl = nil; captureWork = nil
                    captureReveal?.cancel(); captureReveal = nil; captureVisible = false
                }
            }
            do {
                try await withTaskCancellationHandler {
                    try await Task.detached { try session.captureOrigins(domains: domains, control: control) }.value
                } onCancel: { control.cancel() }
                try Task.checkCancellation(); try control.checkCancellation()
                guard reviewActive, captureControl === control else { return }
                originMetadata = session.originMetadata
            } catch is CancellationError { session.suspendOriginCapture(control: control) }
            catch {
                session.suspendOriginCapture(control: control)
                guard reviewActive, captureControl === control, !Task.isCancelled else { return }
                captureIssue = true
            }
        }
    }

    private func recover(_ selection: ConfirmationSelection) {
        guard canRecover, selection.sessionID == session.id, selection.domains == selected,
              selection.omitPhotos == omitPhotos, selection.legacyDomains == selectedLegacyDomains else { return }
        errorReveal?.cancel(); errorReveal = nil
        busy = true; issue = nil; recoveryErrorFocused = nil
        #if DEBUG && targetEnvironment(simulator)
        let control = HealthRecoveryCancelUIFixture.makeControl()
        #else
        let control = BackupOperationControl()
        #endif
        let input: BackupService.RecoveryInput
        let origins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin]
        do {
            origins = try session.acquireOrigins(selection.legacyDomains, control: control)
            input = try session.acquire(control: control)
        }
        catch { busy = false; return }
        let domains = selection.domains, omit = selection.omitPhotos
        operation = control
        work = Task { @MainActor in
            defer { withExtendedLifetime(input) {}; busy = false; operation = nil; work = nil }
            do {
                let payload = try await Task.detached {
                    let payload = try input.payload(domains: domains, omitPhotos: omit, control: control)
                    return try HealthRecoverySelection.bindingLegacyOrigins(origins, to: payload)
                }.value
                try Task.checkCancellation(); try control.checkCancellation()
                try await health.recoverUnavailableHealth(payload, control: control)
                committedLegacyDomains = selection.legacyDomains; committedDomains = domains
                recovered = true; selected = []
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, operation === control else { return }
                do { try control.checkCancellation() } catch { return }
                let changed: Bool
                if case HealthLocalFiles.Failure.changed = error { changed = true } else { changed = false }
                issue = RecoveryIssue(message: selection.legacyDomains.isEmpty
                    ? "Your current files haven't been replaced. Check the file and try again."
                    : changed ? "Your saved data changed. Go back and review it again."
                    : "Lumen hasn't replaced your saved data. Check the file and try again.")
            }
        }
    }
    @ViewBuilder private var recoveryProgress: some View {
        #if DEBUG && targetEnvironment(simulator)
        if HealthRecoveryCancelUIFixture.requested {
            ProgressView("Recovering selected data…").accessibilityIdentifier("fileHealthRecoveryBusy")
                .accessibilityValue(cancelVerification.phase)
        } else { ProgressView("Recovering selected data…").accessibilityIdentifier("fileHealthRecoveryBusy") }
        #else
        ProgressView("Recovering selected data…").accessibilityIdentifier("fileHealthRecoveryBusy")
        #endif
    }
}

@MainActor
private struct BackupFileRecordsView: View {
    let session: BackupRecoveryReviewSession
    let domain: HealthLocalFiles.Domain
    @State private var document: HealthRecoveryRecordReview.Document?
    @State private var issue: String?
    @State private var operation: BackupOperationControl?
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var readVerification = HealthReadUIState.shared
    #endif
    var body: some View {
        List {
            if let issue { Text(issue).foregroundStyle(.secondary) }
            else if let document {
                if document.count == 0 { Text("No records in this file.").foregroundStyle(.secondary) }
                ForEach(0..<document.count, id: \.self) { index in
                    if let page = document.page(at: index) {
                        NavigationLink { HealthRecoveryRecordPageView(session: session, page: page) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(page.title).lineLimit(2)
                                if !page.subtitle.isEmpty { Text(page.subtitle).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }.accessibilityIdentifier("recoveryRecord-\(index)")
                    }
                }
            } else { readProgress }
        }.navigationTitle(recoveryLabel(domain)).navigationBarTitleDisplayMode(.inline)
        .task {
            let control = BackupOperationControl(); operation = control
            #if DEBUG && targetEnvironment(simulator)
            HealthReadUIFixture.register(control, scope: "selected-record")
            #endif
            defer { if operation === control { operation = nil } }
            do {
                let session = session, domain = domain
                let result = try await withTaskCancellationHandler {
                    try await Task.detached {
                        try session.records(domain, control: control)
                    }.value
                } onCancel: { control.cancel() }
                try Task.checkCancellation(); try control.checkCancellation()
                guard operation === control else { return }
                document = result
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, operation === control else { return }
                do { try control.checkCancellation() } catch { return }
                issue = "This file changed or couldn't be opened. Return to choose the file again."
            }
        }
        .onDisappear { operation?.cancel() }
    }
    @ViewBuilder private var readProgress: some View {
        #if DEBUG && targetEnvironment(simulator)
        if HealthReadUIFixture.requested {
            ProgressView("Opening records…").accessibilityIdentifier("fileRecordsLoading").accessibilityValue(readVerification.phase)
        } else { ProgressView("Opening records…") }
        #else
        ProgressView("Opening records…")
        #endif
    }
}
