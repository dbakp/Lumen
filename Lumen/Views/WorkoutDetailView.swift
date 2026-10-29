import SwiftUI

struct WorkoutDetailView: View {
    private let original: Workout
    let units: UnitSystem
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var deleteError = false
    init(workout: Workout, units: UnitSystem) { original = workout; self.units = units }
    var workout: Workout { health.workouts.first { $0.id == original.id } ?? original }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: workout.kind.icon).font(.largeTitle).foregroundStyle(Theme.move)
                Text(workout.title).font(.largeTitle.bold())
                Text(workout.start.formatted(date: .complete, time: .shortened)).foregroundStyle(Theme.secondary)
                if let edited = workout.lastEditedAt { Text("Edited \(edited.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary) }
                RowGroup {
                    LumenRow("Duration", value: "\(Int(workout.duration / 60)) min", icon: "clock", color: Theme.move, chevron: false)
                    RowDivider()
                    LumenRow("Energy", value: workout.energyDescription, icon: "flame", color: Theme.move, chevron: false)
                    if let distance = workout.distanceM { RowDivider(); LumenRow("Distance", value: Units.distance(distance, units), icon: "point.topleft.down.to.point.bottomright.curvepath", color: Theme.move, chevron: false) }
                    if let hr = workout.avgHR { RowDivider(); LumenRow("Average heart rate", value: "\(Int(hr)) bpm", icon: "heart", color: Theme.move, chevron: false) }
                }
                if let note = workout.note, !note.isEmpty { GroupLabel("Your notes"); Text(note) }
                if LocalHealthCorrection.canEdit(workout) {
                    Button("Edit entry", systemImage: "pencil") { editing = true }.buttonStyle(LumenPrimaryButtonStyle()).accessibilityIdentifier("editWorkoutEntry")
                    Text("This workout stays in Lumen. Corrections aren’t sent to Apple Health.").font(.footnote).foregroundStyle(Theme.secondary)
                }
                if let origin = workout.logOrigin { LogProvenanceView(origin: origin) }
                GroupLabel("Source")
                Text(workout.sourceDescription).font(.headline)
                if let origin = workout.importOrigin {
                    if let filename = origin.filename { Text(filename).font(.subheadline).foregroundStyle(Theme.secondary) }
                    Text("Ended \(origin.end.formatted(date: .abbreviated, time: .shortened))").font(.subheadline)
                    Text(origin.durationWasReported == false ? "Duration uses the elapsed time because this export did not report a duration." : "Duration is reported by the source and can exclude pauses.").font(.footnote).foregroundStyle(Theme.secondary)
                    Text("Export activity: \(origin.activityType.replacingOccurrences(of: "HKWorkoutActivityType", with: ""))").font(.footnote).foregroundStyle(Theme.secondary)
                    ForEach(Array((origin.warnings ?? []).enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote).foregroundStyle(Theme.secondary) }
                }
                if workout.energyKcal == nil { Text("This source did not provide usable workout energy. Lumen leaves it unknown.").font(.footnote).foregroundStyle(Theme.secondary) }
                if LocalHealthCorrection.canEdit(workout) {
                    Button(role: .destructive) { deleting = true } label: { Label("Delete entry", systemImage: "trash").foregroundStyle(Theme.destructive) }.frame(minHeight: 44).accessibilityIdentifier("deleteWorkoutEntry")
                } else if workout.source != .manual || workout.importOrigin != nil {
                    Text("Managed by its source. Lumen keeps this record separate from local corrections.").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }.padding(Theme.gutter)
        }.lumenScreen().navigationTitle("Workout").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { ConfirmedEntryEditor(workout: workout) }
            .alert("Delete this workout entry?", isPresented: $deleting) {
                Button("Delete entry", role: .destructive) { do { try health.correctConfirmedWorkout(workout.id, draft: nil); dismiss() } catch { deleteError = true } }
                Button("Keep entry", role: .cancel) { }
            } message: { Text("Deletes this entry from Lumen. Its original conversation and separate source records remain.") }
            .alert("Couldn’t delete entry", isPresented: $deleteError) { Button("OK", role: .cancel) { } } message: { Text("The entry is still saved. Try again.") }
    }
}
