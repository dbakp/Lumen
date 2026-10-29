import SwiftUI

struct JournalView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @ObservedObject private var companion = CompanionStore.shared
    @State private var day = Date()
    @State private var deleting: SymptomEntry?
    @State private var editing: SymptomEntry?
    @State private var editingCheckIn: WellbeingCheckIn?
    @State private var selectedWorkout: Workout?
    @State private var selectedWater: HydrationLog?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("How you feel\nbelongs here.").font(.system(.largeTitle, design: .default, weight: .bold)).fontWidth(.expanded).tracking(-1)
                HStack(spacing: 12) {
                    Button("Log a symptom", systemImage: "bandage") { AppRouter.shared.show(.symptom) }.buttonStyle(LumenPrimaryButtonStyle())
                    Button("Check in") { AppRouter.shared.show(.checkIn) }.buttonStyle(LumenTonalButtonStyle())
                }
                if !companion.activeSymptoms.isEmpty {
                    GroupLabel("Ongoing symptoms")
                    ForEach(companion.activeSymptoms) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(entry.name).font(.headline)
                                Spacer()
                                Text("\(entry.severity)/10").font(.headline.monospacedDigit()).foregroundStyle(Theme.heart)
                            }
                            Text("\(entry.location) · \(entry.date.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary)
                            if !entry.note.isEmpty { Text(entry.note).font(.body) }
                            if let duration = entry.durationMinutes { Text("Duration at logging: \(duration) min").font(.footnote).foregroundStyle(Theme.secondary) }
                            if !entry.triggers.isEmpty { Text("Possible triggers you noted: \(entry.triggers.joined(separator: ", "))").font(.footnote).foregroundStyle(Theme.secondary) }
                            VStack(alignment: .leading, spacing: 8) {
                                Button("Mark resolved", systemImage: "checkmark.circle") { companion.resolve(entry.id) }
                                    .frame(minHeight: 44)
                                HStack(spacing: 24) {
                                    Button("Edit") { editing = entry }.frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                    Spacer()
                                    Button("Delete", role: .destructive) { deleting = entry }.frame(minWidth: 44, minHeight: 44)
                                }
                            }.font(.subheadline)
                        }.padding(20).surface()
                    }
                }
                DatePicker("Your timeline", selection: $day, in: ...Date(), displayedComponents: .date).font(.headline)
                let events = companion.timeline(health: health, sleep: sleep, on: day)
                if events.isEmpty {
                    EmptyStateCard(icon: "book.closed", title: "A page for your day", message: "Meals, movement, sleep and how you feel will appear together here.", actionTitle: "Add a check-in") { AppRouter.shared.show(.checkIn) }
                } else { TimelineList(events: events, onSelect: { event in
                    if event.id.hasPrefix("symptom-") { editing = companion.symptoms.first { "symptom-" + $0.id == event.id } }
                    if event.id.hasPrefix("water-") { selectedWater = health.waterLogs.first { "water-" + $0.id == event.id } }
                    if event.id.hasPrefix("workout-") { selectedWorkout = health.workouts.first { "workout-" + $0.id == event.id } }
                    if event.id.hasPrefix("check-") { editingCheckIn = companion.checkIns.first { "check-" + $0.id == event.id } }
                }) }
                Text("Your notes can help you describe patterns to a clinician. They don't tell us what caused a symptom.").font(.footnote).foregroundStyle(Theme.secondary)
            }.padding(Theme.gutter).padding(.bottom, 24)
        }.lumenScreen().navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { LogToolbarButton() } }
            .sheet(item: $editing) { SymptomLogSheet(entry: $0) }
            .sheet(item: $selectedWater) { WaterLogDetailView(log: $0) }
            .sheet(item: $selectedWorkout) { workout in NavigationStack { WorkoutDetailView(workout: workout, units: sleep.profile.unitSystem) } }
            .sheet(item: $editingCheckIn) { CheckInSheet(entry: $0) }
            .confirmationDialog("Delete this symptom log?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete log", role: .destructive) { if let deleting { companion.deleteSymptom(deleting.id) }; deleting = nil }
            }
    }
}

struct TimelineList: View {
    let events: [TimelineEvent]
    var onSelect: ((TimelineEvent) -> Void)? = nil
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: event.icon).font(.body).foregroundStyle(Theme.accent).frame(width: 24, height: 28)
                        Rectangle().fill(Theme.hairline).frame(width: 1).frame(maxHeight: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(event.title).font(.headline)
                            Spacer()
                            Text(event.date, style: .time).font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Text(event.detail).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 24)
                }.accessibilityElement(children: .combine)
                    .accessibilityIdentifier(event.id)
                    .contentShape(Rectangle()).onTapGesture { onSelect?(event) }
                    .accessibilityAddTraits(onSelect != nil && (event.id.hasPrefix("symptom-") || event.id.hasPrefix("check-") || event.id.hasPrefix("workout-") || event.id.hasPrefix("water-")) ? .isButton : [])
            }
        }
    }
}

struct SymptomLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Headache"
    @State private var location = "Head"
    @State private var severity = 3.0
    @State private var onset = Date()
    @State private var duration = ""
    @State private var note = ""
    @State private var triggers: Set<String> = []
    @State private var resolved = false
    @State private var deleting = false
    private var original: SymptomEntry?
    init(entry: SymptomEntry? = nil) {
        original = entry
        _name = State(initialValue: entry?.name ?? "Headache")
        _location = State(initialValue: entry?.location ?? "Head")
        _severity = State(initialValue: Double(entry?.severity ?? 3))
        _onset = State(initialValue: entry?.date ?? Date())
        _duration = State(initialValue: entry?.durationMinutes.map(String.init) ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _triggers = State(initialValue: Set(entry?.triggers ?? []))
        _resolved = State(initialValue: entry?.resolvedAt != nil)
    }
    let locations = ["Head", "Neck", "Shoulder", "Chest", "Back", "Abdomen", "Arm", "Hand", "Hip", "Leg", "Knee", "Foot", "Other"]
    var body: some View {
        NavigationStack {
            Form {
                Section("What are you feeling?") {
                    TextField("Symptom", text: $name).accessibilityIdentifier("symptomName")
                    Picker("Where", selection: $location) { ForEach(locations, id: \.self) { Text($0) } }
                    Text("Severity: \(Int(severity))/10").font(.headline).accessibilityIdentifier("symptomSeverity")
                    Slider(value: $severity, in: 1...10, step: 1).accessibilityLabel("Symptom severity")
                    Text("1 · Mild                    10 · Worst imaginable").font(.caption).foregroundStyle(Theme.secondary)
                }
                Section("Timing") {
                    DatePicker("Started", selection: $onset, in: ...Date())
                    TextField("Duration in minutes (optional)", text: $duration).keyboardType(.numberPad)
                    Toggle("Already resolved", isOn: $resolved)
                }
                Section("Describe it in your own words") {
                    TextField("What does it feel like? What helps?", text: $note, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    ForEach(["Poor sleep", "Stress", "Exercise", "Meal timing", "Caffeine", "Alcohol", "Unsure"], id: \.self) { trigger in
                        Toggle(trigger, isOn: Binding(get: { triggers.contains(trigger) }, set: { if $0 { triggers.insert(trigger) } else { triggers.remove(trigger) } }))
                    }
                } header: { Text("Possible triggers you noticed") } footer: { Text("These are your observations, not confirmed causes.") }
                if let origin = original?.logOrigin { Section { LogProvenanceView(origin: origin) } }
                if original != nil { Section { Button("Delete symptom log", role: .destructive) { deleting = true } } }
                Section {
                    Text("For sudden severe symptoms, chest pain, breathing difficulty, fainting, or new weakness, seek urgent medical help. Lumen cannot assess emergencies.").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }.scrollContentBackground(.hidden).background(Theme.bg)
                .navigationTitle("Log a symptom").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold).disabled(!valid).accessibilityIdentifier("saveSymptom") }
                }
        }.tint(Theme.accent)
            .confirmationDialog("Delete this symptom log?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let original { CompanionStore.shared.deleteSymptom(original.id) }; dismiss() }
            }
    }
    var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (duration.isEmpty || (Int(duration).map { $0 > 0 && $0 <= 525600 } ?? false)) }
    func save() {
        CompanionStore.shared.log(SymptomEntry(logOrigin: original?.logOrigin, id: original?.id ?? UUID().uuidString, date: onset, name: name.trimmingCharacters(in: .whitespacesAndNewlines), location: location, severity: Int(severity), durationMinutes: Int(duration), note: note, triggers: triggers.sorted(), resolvedAt: resolved ? (original?.resolvedAt ?? Date()) : nil))
        dismiss(); AppRouter.shared.confirm("Symptom saved")
    }
}

struct CheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var energy = 3
    @State private var mood = 3
    @State private var stress = 2
    @State private var note = ""
    @State private var deleting = false
    private var original: WellbeingCheckIn?
    init(entry: WellbeingCheckIn? = nil) {
        original = entry
        _energy = State(initialValue: entry?.energy ?? 3)
        _mood = State(initialValue: entry?.mood ?? 3)
        _stress = State(initialValue: entry?.stress ?? 2)
        _note = State(initialValue: entry?.note ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("How is your energy today?").font(.title2.bold()).listRowBackground(Color.clear) }
                Section {
                    scale("Energy", value: $energy, endpoints: "Low to high")
                    scale("Mood", value: $mood, endpoints: "Low to high")
                    scale("Stress", value: $stress, endpoints: "Low to high")
                }
                Section("Anything else?") { TextField("What's on your mind?", text: $note, axis: .vertical).lineLimit(3...6) }
                if let origin = original?.logOrigin { Section { LogProvenanceView(origin: origin) } }
                if original != nil { Section { Button("Delete check-in", role: .destructive) { deleting = true } } }
            }.scrollContentBackground(.hidden).background(Theme.bg)
                .navigationTitle("Daily check-in").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            CompanionStore.shared.checkIn(WellbeingCheckIn(logOrigin: original?.logOrigin, id: original?.id ?? UUID().uuidString, date: original?.date ?? Date(), energy: energy, mood: mood, stress: stress, note: note))
                            dismiss(); AppRouter.shared.confirm("Check-in saved")
                        }.fontWeight(.bold)
                    }
                }
        }.tint(Theme.accent)
            .confirmationDialog("Delete this check-in?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let original { CompanionStore.shared.deleteCheckIn(original.id) }; dismiss() }
            }
    }
    func scale(_ title: String, value: Binding<Int>, endpoints: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.headline); Spacer(); Text("\(value.wrappedValue)/5").monospacedDigit() }
            Picker(title, selection: value) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
            Text(endpoints).font(.caption).foregroundStyle(Theme.secondary)
        }.padding(.vertical, 8)
    }
}
