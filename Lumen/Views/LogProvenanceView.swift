import SwiftUI

struct LogProvenanceView: View {
    let origin: HealthLogOrigin
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirmed from Assistant").font(.headline)
            Text("\(HealthLogDrafting.preparationDescription(origin.preparedBy))\nConfirmed \(origin.confirmedAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary)
            DisclosureGroup("Original message") { Text(origin.statement).font(.subheadline).textSelection(.enabled).padding(.top, 8) }.tint(Theme.accent)
        }
    }
}

struct WaterLogDetailView: View {
    let log: HydrationLog
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var deleteError = false
    var record: HydrationLog { health.waterLogs.first { $0.id == log.id } ?? log }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "drop").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text("\(Int(record.ml)) ml").font(.largeTitle.bold()).monospacedDigit().accessibilityIdentifier("waterEntryValue")
                    Text(record.date.formatted(date: .complete, time: .shortened)).foregroundStyle(Theme.secondary)
                    if let note = record.note, !note.isEmpty { Text(note) }
                    if let edited = record.lastEditedAt { Text("Edited \(edited.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary) }
                    if let origin = record.logOrigin {
                        Button("Edit entry", systemImage: "pencil") { editing = true }.buttonStyle(LumenPrimaryButtonStyle()).accessibilityIdentifier("editWaterEntry")
                        Text("This entry stays in Lumen. Corrections aren’t sent to Apple Health.").font(.footnote).foregroundStyle(Theme.secondary)
                        LogProvenanceView(origin: origin)
                        Button(role: .destructive) { deleting = true } label: { Label("Delete entry", systemImage: "trash").foregroundStyle(Theme.destructive) }.frame(minHeight: 44).accessibilityIdentifier("deleteWaterEntry")
                    }
                }.padding(Theme.gutter)
            }.lumenScreen().navigationTitle("Water").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $editing) { ConfirmedEntryEditor(water: record) }
                .alert("Delete this water entry?", isPresented: $deleting) {
                    Button("Delete entry", role: .destructive) { do { try health.correctConfirmedWater(record.id, draft: nil); dismiss() } catch { deleteError = true } }
                    Button("Keep entry", role: .cancel) { }
                } message: { Text("Deletes this entry from Lumen. Its original conversation and separate source records remain.") }
                .alert("Couldn’t delete entry", isPresented: $deleteError) { Button("OK", role: .cancel) { } } message: { Text("The entry is still saved. Try again.") }
        }
    }
}
