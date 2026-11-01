import SwiftUI

struct PersonalContextView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var companion = CompanionStore.shared
    @State private var draft = PersonalHealthContext()
    @State private var baseline = PersonalHealthContext()
    @State private var revision = UUID()
    @State private var ready = false
    @State private var alert: ContextAlert?
    @FocusState private var focusedField: String?
    private var dirty: Bool { ready && draft != baseline }
    var body: some View {
        Form {
            Section {
                Text("What should Lumen know about you?").font(.title2.bold())
                Text("Keep your goals and everyday constraints in one place. You decide whether they accompany your questions.").foregroundStyle(Theme.secondary)
            }.listRowBackground(Color.clear)
            Section("Your focus") { PersonalContextField("What would you like to work on?", text: $draft.focus, focus: $focusedField, lines: 2...4, identifier: "personalFocus") }
            Section("Food and movement") {
                PersonalContextField("Food preferences", text: $draft.foodPreferences, focus: $focusedField)
                PersonalContextField("Allergies you want to note", text: $draft.allergies, focus: $focusedField)
                PersonalContextField("Injuries or activity limitations", text: $draft.limitations, focus: $focusedField)
            }
            Section("Your everyday life") {
                PersonalContextField("Schedule and available time", text: $draft.schedule, focus: $focusedField)
                PersonalContextField("Anything else to remember", text: $draft.notes, focus: $focusedField, lines: 2...5)
            }
            Section {
                SettingsToggle("Use this context in the assistant", selection: $draft.includeInAssistant, identifier: "personalContextSharing")
                Text(companion.personalContext.includeInAssistant ? "Saved sharing: On" : "Saved sharing: Off")
                    .foregroundStyle(Theme.secondary).accessibilityIdentifier("personalContextSavedSharing")
                if dirty { Text("Changes not saved").foregroundStyle(Theme.secondary).accessibilityIdentifier("personalContextUnsaved") }
            } footer: { Text("Changes apply when you save. Sharing is off by default. When saved on, these notes accompany questions to your selected provider. These are your reference notes; Lumen does not verify allergies or diagnose injuries.").foregroundStyle(Theme.secondary).accessibilityIdentifier("personalContextDisclosure") }
        }.scrollDismissesKeyboard(.immediately).scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Personal context").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.fontWeight(.bold).accessibilityIdentifier("savePersonalContext").disabled(!dirty)
            }
                if focusedField != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { focusedField = nil }.accessibilityIdentifier("finishContextEditing")
                    }
                } else if dirty { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { alert = .discard } } }
            }
            .navigationBarBackButtonHidden(dirty || focusedField != nil)
            .interactiveDismissDisabled(dirty)
            .onAppear { if !ready { reload(); ready = true } }
            .onChange(of: companion.personalContextRevision) { _, _ in if !dirty { reload() } }
            .alert(item: $alert) { state in
                switch state {
                case .discard:
                    return Alert(title: Text("Discard context changes?"),
                                 message: Text("Your saved notes and sharing choice stay as they are."),
                                 primaryButton: .destructive(Text("Discard"), action: { dismiss() }),
                                 secondaryButton: .cancel(Text("Keep draft")))
                case .saving(let value):
                if value.stale {
                    return Alert(title: Text("Saved context changed"), message: Text(value.message),
                          primaryButton: .destructive(Text("Reload"), action: reload), secondaryButton: .cancel(Text("Keep draft")))
                } else {
                    return Alert(title: Text("Couldn’t save context"), message: Text(value.message),
                          primaryButton: .default(Text("Try again"), action: save), secondaryButton: .cancel(Text("Not now")))
                }
                }
            }
    }

    private func reload() {
        draft = companion.personalContext; baseline = draft; revision = companion.personalContextRevision
    }
    private func save() {
        focusedField = nil
        do {
            #if DEBUG && targetEnvironment(simulator)
            try PreferenceNativeProbe.changeContextIfRequested(companion)
            #endif
            try companion.savePersonalContextChecked(draft, expectedRevision: revision)
            AppRouter.shared.confirm("Personal context saved"); dismiss()
        } catch { alert = .saving(ContextSaveFailure(error)) }
    }
}

/// An empty placeholder cannot carry a long field label at large Dynamic Type.
/// Keep the complete label visible and accessible without reducing its type.
private struct PersonalContextField: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let text: Binding<String>
    let focus: FocusState<String?>.Binding
    let lines: ClosedRange<Int>?
    let identifier: String
    init(_ title: String, text: Binding<String>, focus: FocusState<String?>.Binding, lines: ClosedRange<Int>? = nil, identifier: String = "") {
        self.title = title; self.text = text; self.focus = focus; self.lines = lines; self.identifier = identifier
    }
    var body: some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
                input
            }
        } else { input }
    }
    @ViewBuilder private var input: some View {
        let placeholder = textSize.isAccessibilitySize ? "Add notes" : title
        let field = TextField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(Theme.secondary), axis: .vertical)
            .focused(focus, equals: title)
            .accessibilityLabel(title).accessibilityIdentifier(identifier)
        if let lines { field.lineLimit(lines) } else { field }
    }
}

private enum ContextAlert: Identifiable {
    case discard
    case saving(ContextSaveFailure)
    var id: String {
        switch self {
        case .discard: "discard"
        case .saving(let failure): failure.id.uuidString
        }
    }
}

private struct ContextSaveFailure: Identifiable {
    let id = UUID()
    let stale: Bool
    let message: String
    init(_ error: Error) {
        if let error = error as? BackupError, case .recordsChanged = error {
            stale = true
            message = "Your saved notes changed. Reload them to start a new draft. This replaces your unsaved edits."
        } else {
            stale = false
            message = "Your draft is still here. Saved notes and sharing haven’t changed. " + LocalSaveFailure.saving("context", error: error).message
        }
    }
}

struct PlanAgendaView: View {
    @ObservedObject private var companion = CompanionStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("One step\nat a time.").font(.largeTitle.bold()).fontWidth(.expanded)
                if companion.pendingActions.isEmpty {
                    EmptyStateCard(icon: "checkmark.circle", title: "Room for your next step", message: "Active plans with unfinished steps appear here. Create a plan with your assistant or add steps to an existing plan.")
                }
                ForEach(companion.pendingActions) { action in PlanActionRow(action: action) }
            }.padding(Theme.gutter)
        }.lumenScreen().navigationTitle("Your next steps").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlanActionRow: View {
    var action: PendingPlanAction
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { CompanionStore.shared.togglePlanStep(documentID: action.documentID, stepID: action.step.id) } label: {
                Image(systemName: "circle").font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel("Complete \(action.step.title)")
            NavigationLink { DocumentDetailView(documentID: action.documentID) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.step.title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(action.planTitle).font(.caption).foregroundStyle(Theme.secondary)
                    if let due = action.step.calendarDate {
                        Text((PlanSchedule.isOverdue(action.step) ? "Planned for " : "Due ") + due.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Theme.secondary)
                    } else { Text("No date set").font(.caption).foregroundStyle(Theme.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }.buttonStyle(.plain)
        }.padding(12).surface()
    }
}
