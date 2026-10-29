import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject private var sleep: SleepStore
    @EnvironmentObject private var health: HealthStore
    @State private var shareURL: URL?
    @State private var choosingFile = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var preview: BackupSnapshot?
    @State private var backupDate: Date?
    @State private var conflictCount = 0
    @State private var preferences = false
    @State private var confirmRestore = false
    @State private var restored = false

    var body: some View {
        Form {
            Section {
                Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 38, weight: .light)).foregroundStyle(Theme.accent).padding(.bottom, 8)
                Text("Keep your\nhistory close.").font(.largeTitle.bold()).fontWidth(.expanded)
                Text("Save a copy of your Lumen records to Files, then bring them back when you need them.").foregroundStyle(Theme.secondary)
            }.listRowBackground(Color.clear)
            if busy { Section { ProgressView("Preparing your records…") } }
            if restored { Section { Label("Backup restored", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityIdentifier("backupRestored") } }
            Section {
                Button("Create backup", systemImage: "square.and.arrow.up") { createBackup() }.accessibilityIdentifier("createBackup")
                if let shareURL {
                    ShareLink(item: shareURL) { Label("Save or share backup", systemImage: "folder") }
                    Button("Review this backup") { read(shareURL) }.accessibilityIdentifier("reviewBackup")
                }
            } header: { Text("Save a copy") } footer: {
                Text("Includes journals, meal photos, conversations, plans, imported health history and preferences. Save the file somewhere private: it contains readable health data and isn’t encrypted by Lumen. API keys and connection credentials are excluded.")
            }
            Section {
                Button("Choose backup", systemImage: "square.and.arrow.down") { choosingFile = true }.accessibilityIdentifier("chooseBackup")
            } header: { Text("Bring records back") } footer: {
                Text("Choose a Lumen backup up to 100 MB. You’ll review its contents before restoring. Older data exports are for reading and can’t be restored here.")
            }
            if let preview {
                Section {
                    if let backupDate { LabeledContent("Created", value: backupDate.formatted(date: .abbreviated, time: .shortened)) }
                    LabeledContent("Symptom logs", value: "\(preview.symptoms.count)")
                    LabeledContent("Check-ins", value: "\(preview.checkIns.count)")
                    LabeledContent("Meals & photos", value: "\(preview.meals.count) · \(preview.photos.count)")
                    LabeledContent("Water logs", value: "\(preview.water.count)")
                    LabeledContent("Workouts & sleep logs", value: "\(preview.workouts.count) · \(preview.sleep.count)")
                    LabeledContent("Conversations", value: "\(preview.conversations.count)")
                    LabeledContent("Plans & documents", value: "\(preview.documents.count)")
                    LabeledContent("Imported health days", value: "\(preview.importedDays.count)")
                    LabeledContent("Already on this iPhone", value: "\(conflictCount)")
                } header: { Text("Backup preview") } footer: {
                    Text("Your current versions of these records will be kept. Missing records and measurements will be added. Photos won’t overwrite current photos. Counts are records, not individual messages or measurements.")
                }
                Section {
                    Toggle("Restore profile & preferences", isOn: $preferences)
                    Button("Restore missing records") { confirmRestore = true }.fontWeight(.semibold).accessibilityIdentifier("restoreBackup")
                    Button("Dismiss preview", role: .cancel) { clearPreview() }
                } footer: {
                    Text("Profile restore replaces your name, body goals, sleep settings, habits and personal notes. Your app lock, connections and reminders stay as they are. Restored documents and personal notes start with assistant sharing off. Restore doesn’t write to Apple Health.")
                }
            }
        }
        .disabled(busy || health.isSyncing)
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Backup & restore").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): read(url); case .failure(let error): errorMessage = error.localizedDescription }
        }
        .alert("Couldn’t complete backup", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog("Restore missing records?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore records") { restore() }
        } message: {
            Text(preferences ? "Missing records will be added and your profile and preferences will be replaced. Your current versions of existing records will be kept." : "Missing records will be added. Your current records, profile and preferences will be kept.")
        }
        .overlay(alignment: .bottom) {
            if health.isSyncing { Text("Health is syncing. Backup will be available shortly.").font(.footnote).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding() }
        }
    }
    private func clearPreview() { preview = nil; backupDate = nil; preferences = false; conflictCount = 0 }
    private func createBackup() {
        busy = true; shareURL = nil; restored = false
        Task { @MainActor in
            defer { busy = false }
            do { shareURL = try await BackupService.export(sleep: sleep, health: health) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func read(_ url: URL) {
        busy = true; restored = false; clearPreview()
        Task { @MainActor in
            defer { busy = false }
            do {
                let (archive, snapshot) = try await Task.detached(priority: .userInitiated) { try BackupService.read(url) }.value
                conflictCount = snapshot.conflicts(with: try BackupService.snapshot(sleep: sleep, health: health))
                backupDate = archive.createdAt; preview = snapshot
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private func restore() {
        guard let preview else { return }
        busy = true
        Task { @MainActor in
            await Task.yield()
            defer { busy = false }
            do {
                try BackupService.restore(preview, preferences: preferences, sleep: sleep, health: health)
                clearPreview(); shareURL = nil; restored = true
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
