import SwiftUI

struct LogProvenanceView: View {
    let origin: HealthLogOrigin
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirmed from Assistant").font(.headline)
            Text("Prepared by: \(origin.preparedBy)\nConfirmed \(origin.confirmedAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary)
            DisclosureGroup("Original message") { Text(origin.statement).font(.subheadline).textSelection(.enabled).padding(.top, 8) }.tint(Theme.accent)
        }
    }
}

struct WaterLogDetailView: View {
    let log: HydrationLog
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "drop").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text("\(Int(log.ml)) ml").font(.largeTitle.bold()).monospacedDigit()
                    Text(log.date.formatted(date: .complete, time: .shortened)).foregroundStyle(Theme.secondary)
                    if let note = log.note, !note.isEmpty { Text(note) }
                    if let origin = log.logOrigin { LogProvenanceView(origin: origin) }
                }.padding(Theme.gutter)
            }.lumenScreen().navigationTitle("Water").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
