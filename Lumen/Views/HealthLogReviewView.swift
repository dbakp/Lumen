import SwiftUI

struct HealthLogReviewView: View {
    let selection: HealthLogSelection
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var companion = CompanionStore.shared
    @State private var drafts: [HealthLogDraft] = []
    @State private var request: Task<Void, Never>?
    @State private var working = false
    @State private var error: String?
    @State private var notice: String?
    @State private var loaded = false
    @State private var discarding = false
    var pending: [HealthLogDraft] { drafts.filter { !HealthLogConfirmation.contains($0.recordID, health: health) } }
    var hasEditedDrafts: Bool { pending.contains { $0.isEdited } }
    var saved: [SavedChatLog] { HealthLogConfirmation.saved(from: selection, health: health) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Keep what happened.").font(.title.bold()).foregroundStyle(Theme.text)
                    Text("\(saved.count) saved · \(pending.count) to review").font(.subheadline.bold()).foregroundStyle(Theme.accent)
                    Text("Save entries one at a time. Closing discards unsaved drafts; saved entries stay in your history.").font(.subheadline).foregroundStyle(Theme.secondary)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section("Your message") {
                    Text(selection.message.text).font(.subheadline).textSelection(.enabled)
                    Text(selection.message.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.secondary)
                }
                if !saved.isEmpty {
                    Section("Saved from this message") {
                        ForEach(saved) { log in
                            Label { VStack(alignment: .leading, spacing: 4) { Text(log.title); Text(log.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.secondary) } } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                        }
                        Text("These entries are in your health history. Closing this review keeps saved entries.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
                Section("Entries to review") {
                    if pending.isEmpty { Text(saved.isEmpty ? "Choose a log type below, or ask your available AI provider for suggestions." : "All reviewed entries are saved. Add another entry if you need one.").font(.subheadline).foregroundStyle(Theme.secondary) }
                    ForEach($drafts) { $entry in
                        if !HealthLogConfirmation.contains(entry.recordID, health: health) {
                            NavigationLink { HealthLogDraftEditor(draft: $entry, selection: selection) } label: {
                                Label { VStack(alignment: .leading, spacing: 4) { Text(entry.name.isEmpty ? entry.kind.label : entry.name); Text(entry.validationMessage == nil ? "Ready to review" : "Needs your details").font(.caption).foregroundStyle(Theme.secondary) } } icon: { Image(systemName: entry.kind.icon).foregroundStyle(Theme.accent) }
                            }
                        }
                    }.onDelete { offsets in
                        let visible = drafts.filter { !HealthLogConfirmation.contains($0.recordID, health: health) }
                        let ids = Set(offsets.map { visible[$0].id }); drafts.removeAll { ids.contains($0.id) }
                    }
                    Menu {
                        ForEach(HealthLogKind.allCases) { kind in Button(kind.label, systemImage: kind.icon) { let draft = HealthLogDraft(kind: kind, date: selection.message.date); drafts.append(draft) } }
                    } label: { Label("Add an entry", systemImage: "plus") }.disabled(working || drafts.count >= 12)
                }
                if saved.isEmpty { Section {
                    if working {
                        HStack { ProgressView(); Text("Preparing suggestions…") }
                        Button("Stop suggestions") { stop() }
                    } else {
                        Button("Suggest entries with AI", systemImage: "sparkles") { suggest() }
                            .disabled(!AIService.shared.brain.isAI || !drafts.isEmpty || !saved.isEmpty || selection.message.text.count > 8000)
                    }
                    Text(AIService.shared.brain.isAI ? "Provider: \(AIService.shared.brain.label). Only this message is sent for suggestions. AI can miss details; review every field. To use AI instead of local drafts, remove the unsaved drafts first." : "Local drafts work without AI. An available AI provider can suggest entries; configure one in Settings.").font(.footnote).foregroundStyle(Theme.secondary)
                    if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.secondary) }
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.heart) }
                } footer: { Text("Entries stay in Lumen. This review does not write to Apple Health. Unsaved drafts are discarded when you close it.") } }
            }.scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
                .navigationTitle("Review health entries").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { if hasEditedDrafts { discarding = true } else { dismiss() } } } }
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    if saved.isEmpty { drafts = HealthLogDrafting.local(selection.message.text, date: selection.message.date) }
                }
                .onDisappear { stop() }
        }
        .background(SheetDismissGuard(hasEdits: hasEditedDrafts) { discarding = true })
        .alert("Discard your unsaved changes?", isPresented: $discarding) {
            Button("Discard unsaved drafts", role: .destructive) { dismiss() }
            Button("Keep reviewing", role: .cancel) { }
        } message: { Text("Saved entries will stay. Your \(pending.count) unsaved drafts will be discarded.") }
    }
    func stop() { request?.cancel(); request = nil; working = false }
    func suggest() {
        guard !working, drafts.isEmpty, saved.isEmpty, AIService.shared.brain.isAI else { return }
        error = nil; notice = nil; working = true
        let provider = AIService.shared.brain.label
        request = Task { @MainActor in
            let answer = await AIService.shared.chat(instructions: HealthLogDrafting.instructions, history: [], user: selection.message.text)
            guard !Task.isCancelled else { return }
            defer { working = false; request = nil }
            guard let answer else { error = "The provider couldn't prepare suggestions. You can add an entry yourself."; return }
            do {
                drafts = try HealthLogDrafting.suggestions(answer, statement: selection.message.text, date: selection.message.date, provider: provider)
                if drafts.isEmpty { notice = "No observations were found to log. You can add an entry yourself." }
            } catch { self.error = "The suggestions could not be read. You can add an entry yourself." }
        }
    }
}

struct HealthLogDraftEditor: View {
    @Binding var draft: HealthLogDraft
    let selection: HealthLogSelection
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                DatePicker("When it happened", selection: $draft.date, in: ...Date())
                Text("Starts at your message time. Change it if the event happened earlier.").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Section(draft.kind.label) {
                switch draft.kind {
                case .symptom:
                    TextField("Symptom", text: $draft.name)
                    TextField("Body location", text: $draft.location)
                    rating("Severity", value: $draft.severity, maximum: 10)
                    LabeledContent("Duration (min)") { TextField("Optional", value: $draft.durationMinutes, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                case .checkIn:
                    rating("Energy", value: $draft.energy, maximum: 5)
                    rating("Mood", value: $draft.mood, maximum: 5)
                    rating("Stress", value: $draft.stress, maximum: 5)
                case .water:
                    LabeledContent("Water (ml)") { TextField("Amount", value: $draft.waterML, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).accessibilityIdentifier("draftWaterML") }
                case .workout:
                    Picker("Activity", selection: $draft.workoutKind) { Text("Choose").tag(Optional<WorkoutKind>.none); ForEach(WorkoutKind.allCases, id: \.self) { Text($0.label).tag(Optional($0)) } }
                    TextField("Title (optional)", text: $draft.name)
                    LabeledContent("Duration (min)") { TextField("Minutes", value: $draft.durationMinutes, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                    LabeledContent("Energy (kcal)") { TextField("Optional", value: $draft.energyKcal, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                    Text("Leave energy empty if it wasn't measured. Lumen won't estimate it here.").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            Section("Your notes") { TextField("Anything to add? (optional)", text: $draft.note, axis: .vertical).lineLimit(3...8) }
            Section { DisclosureGroup("Read original message") { Text(selection.message.text).font(.subheadline).textSelection(.enabled) } }
            Section("Before saving") {
                ForEach(draft.fieldWarnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.secondary) }
                Text("Prepared by: \(draft.preparedBy)").font(.footnote).foregroundStyle(Theme.secondary)
                Text("Confirm these values describe what happened to you. The original message is kept with this entry, even if you delete the conversation.").font(.subheadline)
                if let message = draft.validationMessage { Text(message).font(.footnote).foregroundStyle(Theme.secondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.heart) }
                Button("Confirm and save entry", systemImage: "checkmark.circle") { confirm() }
                    .disabled(saving || draft.validationMessage != nil || HealthLogConfirmation.contains(draft.recordID, health: health)).accessibilityIdentifier("confirmChatHealthLog")
            }
        }.onChange(of: draft) { _, _ in if !draft.isEdited { draft.isEdited = true } }
            .scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
            .navigationTitle("Review \(draft.kind.label.lowercased())").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
    }
    func rating(_ label: String, value: Binding<Int?>, maximum: Int) -> some View {
        Picker(label, selection: value) { Text("Choose").tag(Optional<Int>.none); ForEach(1...maximum, id: \.self) { Text("\($0)/\(maximum)").tag(Optional($0)) } }
    }
    func confirm() {
        guard !saving else { return }; saving = true
        defer { saving = false }
        do { try HealthLogConfirmation.confirm(draft, selection: selection, health: health); dismiss(); AppRouter.shared.confirm("Health entry saved") }
        catch { self.error = "Couldn't save this entry. Your draft is still here; try again." }
    }
}
