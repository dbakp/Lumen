import SwiftUI

struct ConfirmedEntryEditor: View {
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private let entryID: String
    private let initial: HealthLogDraft
    private let origin: HealthLogOrigin?
    @State private var draft: HealthLogDraft
    @State private var discarding = false
    @State private var saveError = false
    var hasEdits: Bool { draft != initial }

    init(water: HydrationLog) {
        var value = HealthLogDraft(kind: .water, date: water.date)
        value.id = water.id
        value.waterML = water.ml; value.note = water.note ?? ""
        entryID = water.id; initial = value; origin = water.logOrigin; _draft = State(initialValue: value)
    }
    init(workout: Workout) {
        var value = HealthLogDraft(kind: .workout, date: workout.start)
        value.id = workout.id
        value.name = workout.title; value.workoutKind = workout.kind; value.durationMinutes = workout.duration / 60
        value.energyKcal = workout.energyKcal; value.note = workout.note ?? ""
        entryID = workout.id; initial = value; origin = workout.logOrigin; _draft = State(initialValue: value)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("When it happened") { DatePicker("Recorded time", selection: $draft.date, in: ...Date()) }
                if draft.kind == .water {
                    Section("Water") {
                        LabeledContent("Amount (ml)") { HealthAmountField("Amount", value: $draft.waterML).multilineTextAlignment(.trailing).keyboardType(.decimalPad).accessibilityIdentifier("correctWaterML") }
                    }
                } else {
                    Section("Workout") {
                        Picker("Activity", selection: $draft.workoutKind) { ForEach(WorkoutKind.allCases, id: \.self) { Text($0.label).tag(Optional($0)) } }
                        LabeledContent("Workout name") { TextField("Optional", text: $draft.name).multilineTextAlignment(.trailing).accessibilityIdentifier("correctWorkoutTitle") }
                        LabeledContent("Duration (min)") { HealthAmountField("Minutes", value: $draft.durationMinutes).multilineTextAlignment(.trailing).keyboardType(.decimalPad).accessibilityIdentifier("correctWorkoutMinutes") }
                        LabeledContent("Energy (kcal)") { HealthAmountField("Optional", value: $draft.energyKcal).multilineTextAlignment(.trailing).keyboardType(.decimalPad).accessibilityIdentifier("correctWorkoutEnergy") }
                        Text("Leave energy empty when it wasn’t measured.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
                Section("Your notes") { TextField("Optional", text: $draft.note, axis: .vertical).lineLimit(3...6) }
                Section {
                    Text("Saves this Lumen entry only. No changes are sent to Apple Health.")
                    Text("Separate source records can still appear in your totals.").foregroundStyle(Theme.secondary)
                }.font(.footnote)
                if let message = draft.validationMessage { Section { Text(message).foregroundStyle(Theme.secondary) } }
                if let origin { Section { LogProvenanceView(origin: origin) } }
            }.scrollContentBackground(.hidden).background(Theme.bg)
                .navigationTitle(typeSize.isAccessibilitySize ? draft.kind.label : draft.kind == .water ? "Edit water" : "Edit workout").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasEdits { discarding = true } else { dismiss() } }.accessibilityIdentifier("cancelCorrectedEntry") }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold).disabled(!hasEdits || draft.validationMessage != nil).accessibilityIdentifier("saveCorrectedEntry") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.accessibilityIdentifier("dismissCorrectionKeyboard") }
                }
        }.tint(Theme.accent)
            .background(SheetDismissGuard(hasEdits: hasEdits) { discarding = true })
            .alert("Discard your changes?", isPresented: $discarding) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: { Text("The saved entry will keep its current values.") }
            .alert("Couldn’t save changes", isPresented: $saveError) { Button("Keep editing", role: .cancel) { } } message: { Text("Your draft is still here. Try saving again.") }
    }
    private func save() {
        do {
            if draft.kind == .water { try health.correctConfirmedWater(entryID, draft: draft) }
            else { try health.correctConfirmedWorkout(entryID, draft: draft) }
            dismiss(); AppRouter.shared.confirm("Entry updated")
        } catch { saveError = true }
    }
}
