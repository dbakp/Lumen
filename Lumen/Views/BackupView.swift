import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject private var sleep: SleepStore
    @EnvironmentObject private var health: HealthStore
    @State private var shared: BackupService.Export?
    @State private var source: BackupService.Source?
    @State private var preview: BackupService.Preview?
    @State private var choosingFile = false
    @State private var creatingPassword = false
    @State private var password = ""
    @State private var operation: BackupOperationControl?
    @State private var cancellationRequested = false
    @State private var work: Task<Void, Never>?
    @State private var jobID = UUID()
    @State private var errorTitle = "Couldn’t open backup"
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var conflictCount = 0
    @State private var preferences = false
    @State private var confirmRestore = false
    @State private var restored = false
    private var busy: Bool { operation != nil }
    private var unavailable: Bool { busy || health.isSyncing }
    private var scrollTarget: String? {
        if busy { return "backupProgressSection" }
        if restored || statusMessage != nil { return "backupStatusSection" }
        if preview != nil { return "backupPreviewSection" }
        if source?.encrypted == true { return "backupUnlockSection" }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                Image(systemName: "externaldrive").font(.system(size: 38, weight: .light)).foregroundStyle(Theme.accent).padding(.bottom, 8)
                Text("Keep your\nhistory close.").font(.largeTitle.bold()).fontWidth(.expanded)
                Text("Create an encrypted copy of your records and meal photos. Bring it back when you need it.").foregroundStyle(Theme.secondary)
            }.listRowBackground(Color.clear)
            if let operation { BackupProgressView(control: operation) }
            if restored {
                Section { Label("Backup restored", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityIdentifier("backupRestored").id("backupStatusSection") }
            } else if let statusMessage {
                Section { Text(statusMessage).foregroundStyle(Theme.secondary).accessibilityIdentifier("backupStatus").id("backupStatusSection") }
            }
            Section {
                if let shared {
                    ShareLink(item: shared.url) { Label("Save or share backup", systemImage: "folder").fontWeight(.semibold) }.accessibilityIdentifier("shareBackup")
                    Button("Review this backup") { select(shared.url) }.accessibilityIdentifier("reviewBackup")
                }
                Button(shared == nil ? "Create backup" : "Create another backup", systemImage: "lock.shield") { creatingPassword = true }.accessibilityIdentifier("createBackup")
            } header: {
                if shared == nil { Text("Save a copy").foregroundStyle(Theme.secondary) }
                else { Label("Encrypted backup ready to save", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
            } footer: {
                Text(shared == nil ? "You’ll choose a password before creating the file. Saved connection details and device permissions are excluded." : "Save it to Files before leaving this screen. Lumen then removes this temporary copy.").foregroundStyle(Theme.secondary)
            }.disabled(unavailable)
            Section {
                Button("Choose backup", systemImage: "square.and.arrow.down") { choosingFile = true }.accessibilityIdentifier("chooseBackup")
            } header: { Text("Bring records back").foregroundStyle(Theme.secondary) } footer: {
                Text("Encrypted Lumen backups up to 2 GB, or older JSON backups up to 100 MB. Review the contents before restoring.").foregroundStyle(Theme.secondary)
            }.disabled(unavailable)
            if let source, source.encrypted, preview == nil {
                Section {
                    Label(source.name, systemImage: "lock.doc").font(.subheadline).lineLimit(3).id("backupUnlockSection")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backup password").font(.caption).foregroundStyle(Theme.secondary)
                        SecureField("Enter password", text: $password).textContentType(.password).submitLabel(.done).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityLabel("Backup password").accessibilityIdentifier("unlockBackupPassword")
                    }
                    Button("Unlock preview") { unlock() }.fontWeight(.semibold).disabled(password.isEmpty).accessibilityIdentifier("unlockBackup")
                    Button("Dismiss file", role: .cancel) { self.source = nil; password = "" }
                } header: { Text("Password needed").foregroundStyle(Theme.secondary) } footer: {
                    Text("Use the password chosen when this backup was made. Lumen can’t recover it. Your current records haven’t changed.").foregroundStyle(Theme.secondary)
                }.disabled(unavailable)
            }
            if let preview {
                Section {
                    Label(preview.encrypted ? "Encrypted backup" : "Older, unencrypted backup", systemImage: preview.encrypted ? "lock.shield" : "doc").accessibilityElement(children: .combine).accessibilityIdentifier("backupPreviewKind").id("backupPreviewSection")
                    LabeledContent("Created", value: preview.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Symptom logs", value: "\(preview.snapshot.symptoms.count.formatted())")
                    LabeledContent("Check-ins", value: "\(preview.snapshot.checkIns.count.formatted())")
                    LabeledContent("Meals & photos", value: "\(preview.snapshot.meals.count.formatted()) · \(preview.photos.count.formatted())")
                    LabeledContent("Water logs", value: "\(preview.snapshot.water.count.formatted())")
                        .accessibilityElement(children: .ignore).accessibilityLabel("Water logs")
                        .accessibilityValue(preview.snapshot.water.count.formatted()).accessibilityIdentifier("backupWaterCount")
                    LabeledContent("Workouts & sleep logs", value: "\(preview.snapshot.workouts.count.formatted()) · \(preview.snapshot.sleep.count.formatted())")
                    LabeledContent("Conversations", value: "\(preview.snapshot.conversations.count.formatted())")
                    LabeledContent("Plans & documents", value: "\(preview.snapshot.documents.count.formatted())")
                    LabeledContent("Imported health days", value: "\(preview.snapshot.importedDays.count.formatted())")
                    LabeledContent("Already on this iPhone", value: "\(conflictCount.formatted())")
                } header: { Text("Backup preview").foregroundStyle(Theme.secondary) } footer: {
                    Text("Your current versions of these records will be kept. Missing records and measurements will be added. Photos won’t overwrite current photos. Counts are records, not individual messages or measurements.").foregroundStyle(Theme.secondary)
                }.foregroundStyle(Theme.text, Theme.secondary)
                Section {
                    Toggle("Restore profile & preferences", isOn: $preferences)
                    Button("Restore missing records") { confirmRestore = true }.fontWeight(.semibold).accessibilityIdentifier("restoreBackup")
                    Button("Dismiss preview", role: .cancel) { clearPreview() }
                } footer: {
                    Text("Profile restore replaces your name, body goals, sleep settings, habits and personal notes. Your app lock, connections and reminders stay as they are. Restored documents and personal notes start with assistant sharing off. Restore doesn’t write to Apple Health.").foregroundStyle(Theme.secondary)
                }.disabled(unavailable)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Backup & restore").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if busy {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(cancellationRequested ? "Cancelling…" : "Cancel", role: .cancel) { cancelOperation() }
                        .disabled(cancellationRequested).accessibilityIdentifier("cancelBackupOperation")
                }
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data, .json]) { result in
            switch result { case .success(let url): select(url); case .failure(let error): errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $creatingPassword) {
            BackupPasswordView { password in creatingPassword = false; createBackup(password: password) }
        }
        .alert(errorTitle, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("Restore missing records?", isPresented: $confirmRestore) {
            Button("Restore records") { restore() }
            Button("Keep reviewing", role: .cancel) { }
        } message: {
            Text(preferences ? "Missing records will be added and your profile and preferences will be replaced. Your current versions of existing records will be kept." : "Missing records will be added. Your current records, profile and preferences will be kept.")
        }
        .overlay(alignment: .bottom) {
            if health.isSyncing { Text("Health is syncing. Backup will be available shortly.").font(.footnote).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding() }
        }
        .task(id: scrollTarget) {
            guard let target = scrollTarget else { return }
            // Let the new Form rows finish layout before resolving their scroll target.
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            proxy.scrollTo(target, anchor: .top)
        }
        .onDisappear {
            cancelOperation(); clearPreview(); shared = nil; password = ""
        }
        }
    }
    private func clearPreview() { preview = nil; source = nil; password = ""; preferences = false; conflictCount = 0 }
    private func begin(errorTitle: String) -> (UUID, BackupOperationControl) {
        self.errorTitle = errorTitle
        let control = BackupOperationControl(), id = UUID()
        operation = control; jobID = id; statusMessage = nil; restored = false; cancellationRequested = false
        return (id, control)
    }
    private func finish(_ id: UUID, error: Error? = nil) {
        guard jobID == id else { return }
        operation = nil; work = nil
        if error is CancellationError { statusMessage = "Cancelled. Your records haven’t changed." }
        else if let error { errorMessage = error.localizedDescription }
    }
    private func cancelOperation() {
        guard let operation else { return }
        cancellationRequested = true
        operation.cancel(); work?.cancel()
        // Keep the operation visible until its worker has cleaned up; no second job can race it.
    }
    private func createBackup(password: String) {
        clearPreview()
        let (id, control) = begin(errorTitle: "Couldn’t create backup")
        work = Task { @MainActor in
            do {
                let value = try await BackupService.export(password: password, sleep: sleep, health: health, control: control)
                guard jobID == id, !Task.isCancelled else { throw CancellationError() }
                shared = value; finish(id)
            } catch { finish(id, error: error) }
        }
    }
    private func select(_ url: URL) {
        clearPreview()
        let (id, control) = begin(errorTitle: "Couldn’t open backup")
        work = Task { @MainActor in
            do {
                let selected = try await Task.detached(priority: .userInitiated) { try BackupService.select(url, control: control) }.value
                try control.checkCancellation()
                guard jobID == id else { throw CancellationError() }
                source = selected
                if !selected.encrypted {
                    let value = try await Task.detached(priority: .userInitiated) { try BackupService.read(selected, password: "", control: control) }.value
                    try show(value, id: id, control: control)
                }
                finish(id)
            } catch { finish(id, error: error) }
        }
    }
    private func unlock() {
        guard let source else { return }
        let entered = password; password = ""
        let (id, control) = begin(errorTitle: "Couldn’t unlock backup")
        work = Task { @MainActor in
            do {
                let value = try await Task.detached(priority: .userInitiated) { try BackupService.read(source, password: entered, control: control) }.value
                try show(value, id: id, control: control); finish(id)
            } catch { finish(id, error: error) }
        }
    }
    private func show(_ value: BackupService.Preview, id: UUID, control: BackupOperationControl) throws {
        try control.checkCancellation()
        guard jobID == id else { throw CancellationError() }
        conflictCount = value.snapshot.conflicts(with: try BackupService.snapshot(sleep: sleep, health: health))
        preview = value; source = nil
    }
    private func restore() {
        guard let preview else { return }
        let restorePreferences = preferences
        let (id, control) = begin(errorTitle: "Couldn’t restore backup")
        work = Task { @MainActor in
            do {
                try await BackupService.restore(preview, preferences: restorePreferences, sleep: sleep, health: health, control: control)
                // The short commit has completed; show its outcome even if navigation cancelled afterward.
                guard jobID == id else { return }
                clearPreview(); restored = true; finish(id)
            } catch { finish(id, error: error) }
        }
    }
}

private struct BackupPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @FocusState private var field: Int?
    let create: (String) -> Void
    private var longEnough: Bool { (try? BackupPackage.validateNewPassword(password)) != nil }
    private var matches: Bool { password.utf8.elementsEqual(confirmation.utf8) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(systemName: "lock.shield").font(.system(size: 38, weight: .light)).foregroundStyle(Theme.accent).padding(.bottom, 8)
                    Text("Protect your\nhistory.").font(.largeTitle.bold()).fontWidth(.expanded)
                    Text("Choose a password for this backup. You’ll need it to bring your records back.").foregroundStyle(Theme.secondary)
                }.listRowBackground(Color.clear)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password").font(.caption).foregroundStyle(Theme.secondary)
                        SecureField("Enter password", text: $password).textContentType(.newPassword).focused($field, equals: 1).submitLabel(.next).onSubmit { field = 2 }.accessibilityLabel("Password").accessibilityIdentifier("newBackupPassword")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Repeat password").font(.caption).foregroundStyle(Theme.secondary)
                        SecureField("Enter it again", text: $confirmation).textContentType(.newPassword).focused($field, equals: 2).submitLabel(.done).onSubmit { field = nil }.accessibilityLabel("Repeat password").accessibilityIdentifier("confirmBackupPassword")
                    }
                } header: { Text("At least 12 characters").foregroundStyle(Theme.secondary) } footer: {
                    if !confirmation.isEmpty, !matches { Text("The passwords don’t match.").foregroundStyle(Theme.secondary) }
                    else if password.utf8.count > 256 { Text("Use a shorter password.").foregroundStyle(Theme.secondary) }
                    else { Text("A few unrelated words can make a memorable password.").foregroundStyle(Theme.secondary) }
                }
                Section {
                    Label("Keep your password somewhere safe. Lumen can’t recover it.", systemImage: "key").foregroundStyle(Theme.secondary)
                }
                Section {
                    Button("Create encrypted backup") {
                        let entered = password; password = ""; confirmation = ""; field = nil; create(entered)
                    }.fontWeight(.semibold).disabled(!longEnough || !matches).accessibilityIdentifier("confirmCreateBackup")
                }
            }
            .autocorrectionDisabled().textInputAutocapitalization(.never)
            .onDisappear { password = ""; confirmation = "" }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Backup password").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { password = ""; confirmation = ""; dismiss() } } }
        }
    }
}

private struct BackupProgressView: View {
    let control: BackupOperationControl
    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                let progress = control.progress
                VStack(alignment: .leading, spacing: 10) {
                    Text(title(progress.stage)).font(.headline)
                    if progress.total > 0 {
                        ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        Text("\(progress.completed) of \(progress.total) items").font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
                    } else { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                    if progress.bytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: progress.bytes, countStyle: .file) + " processed").font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
                    }
                }.accessibilityIdentifier("backupProgress").id("backupProgressSection")
            }
        }
    }
    private func title(_ stage: BackupOperationControl.Stage) -> String {
        switch stage {
        case .preparing: return "Preparing files"
        case .writing: return "Encrypting backup"
        case .unlocking: return "Unlocking backup"
        case .reading: return "Checking records"
        case .checkingPhotos: return "Checking photos"
        case .restoring: return "Preparing restore"
        }
    }
}
