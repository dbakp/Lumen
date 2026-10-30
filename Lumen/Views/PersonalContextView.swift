import SwiftUI

struct PersonalContextView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CompanionStore.shared.personalContext
    var body: some View {
        Form {
            Section {
                Text("What should Lumen know about you?").font(.title2.bold())
                Text("Keep your goals and everyday constraints in one place. You decide whether they accompany your questions.").foregroundStyle(Theme.secondary)
            }.listRowBackground(Color.clear)
            Section("Your focus") { TextField("What would you like to work on?", text: $draft.focus, axis: .vertical).accessibilityIdentifier("personalFocus").lineLimit(2...4) }
            Section("Food and movement") {
                TextField("Food preferences", text: $draft.foodPreferences, axis: .vertical)
                TextField("Allergies you want to note", text: $draft.allergies, axis: .vertical)
                TextField("Injuries or activity limitations", text: $draft.limitations, axis: .vertical)
            }
            Section("Your everyday life") {
                TextField("Schedule and available time", text: $draft.schedule, axis: .vertical)
                TextField("Anything else to remember", text: $draft.notes, axis: .vertical).lineLimit(2...5)
            }
            Section {
                Toggle("Use this context in assistant", isOn: $draft.includeInAssistant)
            } footer: { Text("Off by default. When on, these notes are sent with your questions to your selected provider. They are your reference notes; Lumen does not verify allergies or diagnose injuries.") }
        }.scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Personal context").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Save") { CompanionStore.shared.personalContext = draft; AppRouter.shared.confirm("Personal context saved"); dismiss() }.fontWeight(.bold).accessibilityIdentifier("savePersonalContext")
            } }
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
