import SwiftUI

struct LabHistoryComparisonDraft: Identifiable {
    let id = UUID()
    let selection: LabHistory.Selection
    let firstID: String
    let secondID: String
    let style: LabHistory.DecimalStyle?
}

struct LabComparisonReviewSheet: View {
    let draft: LabHistoryComparisonDraft
    @ObservedObject private var companion = CompanionStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var style: LabHistory.DecimalStyle?
    @State private var acknowledged = false
    @State private var stale = false
    @State private var saving = false
    @State private var committing = false
    @State private var saved: HealthDocument?
    @State private var error: String?
    @State private var epoch = UUID()
    @State private var control: BackupOperationControl?
    @State private var job: Task<Void, Never>?
    init(draft: LabHistoryComparisonDraft) { self.draft = draft; _style = State(initialValue: draft.style) }
    private var comparison: LabHistory.Comparison? {
        guard let a = draft.selection.points.first(where: { $0.id == draft.firstID }), let b = draft.selection.points.first(where: { $0.id == draft.secondID }) else { return nil }
        return LabHistory.compare(a, b, style: style, personChecked: true)
    }
    private var canSave: Bool {
        guard !saving, !stale, acknowledged, style != nil, saved == nil, let comparison else { return false }
        return comparison.first.id != comparison.second.id && (comparison.first.importedCellsID == nil || comparison.first.importedCellsID != comparison.second.importedCellsID)
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 1).id("comparisonTop")
                        if let saved { completion(saved) }
                        else if saving {
                            LabHistoryHeading(text: "Checking\ncurrent sources.")
                            ProgressView("Preparing the comparison snapshot")
                            Text("Saving creates a separate copy. Original records stay unchanged.").foregroundStyle(Theme.secondary)
                        } else if let comparison {
                            LabHistoryHeading(text: "Check both\nresults.")
                            if stale { Text("Saved records changed. Close this comparison and check the refreshed sources before saving.").foregroundStyle(Theme.secondary).accessibilityIdentifier("labComparisonSourceChanged") }
                            LabNumberStylePicker(style: $style)
                            Text(style?.explanation ?? "Choose a decimal mark, or keep the wording without a number calculation.").font(.footnote).foregroundStyle(Theme.secondary)
                            LabComparisonNumberView(comparison: comparison, captured: false)
                            ForEach(comparison.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                            LabCapturedResultView(point: comparison.first, label: comparison.chronological ? "Earlier result" : "First result", expandedSource: true)
                            Divider()
                            LabCapturedResultView(point: comparison.second, label: comparison.chronological ? "Later result" : "Second result", expandedSource: true)
                            LabHistoryToggle(title: "I checked both results, their sources and number interpretation", value: $acknowledged, identifier: "acknowledgeLabComparison")
                            Text("The selected records were checked as belonging to the intended person. Matching labels do not establish clinical comparability.").font(.footnote).foregroundStyle(Theme.secondary)
                            Text("Saves an independent snapshot with sharing off. Later source edits or deletion do not update that separate copy.").font(.footnote).foregroundStyle(Theme.secondary)
                        } else { Text("The selected results are no longer available. Close this comparison and choose them again.").foregroundStyle(Theme.secondary) }
                    }.padding(Theme.gutter).padding(.bottom, 24)
                }.lumenScreen().onChange(of: saved?.id) { _, _ in proxy.scrollTo("comparisonTop", anchor: .top) }
            }
            .navigationTitle(saved == nil ? "Review comparison" : "Saved comparison").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(saved == nil ? "Cancel" : "Done") { epoch = UUID(); control?.cancel(); job?.cancel(); dismiss() }.accessibilityIdentifier("cancelLabComparison") }
                if saved == nil { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave).accessibilityIdentifier("saveLabComparison") } }
            }
            .alert("Comparison wasn't saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .onChange(of: style) { _, _ in acknowledged = false }
            .onReceive(companion.$documents.dropFirst()) { _ in
                guard !committing, saved == nil else { return }
                epoch = UUID(); stale = true; acknowledged = false; control?.cancel(); job?.cancel(); saving = false
            }
            .onDisappear { epoch = UUID(); control?.cancel(); job?.cancel() }
        }.tint(Theme.accent)
    }
    @ViewBuilder private func completion(_ saved: HealthDocument) -> some View {
        LabHistoryHeading(text: "Comparison\nsaved.")
        Text(saved.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
        Text("Sharing is off. The separate snapshot keeps these captured source details when originals change.").foregroundStyle(Theme.secondary).accessibilityIdentifier("labComparisonSaved")
        NavigationLink { DocumentDetailView(documentID: saved.id) } label: {
            if typeSize.isAccessibilitySize {
                Text("View saved comparison").multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 20)
            } else {
                Label("View saved comparison", systemImage: "doc.text").frame(maxWidth: .infinity)
            }
        }.buttonStyle(LumenPrimaryButtonStyle()).accessibilityIdentifier("viewSavedLabComparison")
    }
    private func save() {
        guard canSave else { return }
        let next = BackupOperationControl(), token = epoch, documents = companion.documents, selection = draft.selection, first = draft.firstID, second = draft.secondID, interpretation = style
        saving = true; control = next
        job = Task { @MainActor in
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try next.checkCancellation()
                    let value = try LabHistory.snapshot(selection, firstID: first, secondID: second, style: interpretation, personChecked: true, acknowledged: true, currentDocuments: documents)
                    try next.checkCancellation(); return value
                }.value
                try next.checkCancellation(); guard epoch == token, !stale else { return }
                committing = true
                do { try companion.saveChecked(document); saved = document }
                catch { committing = false; throw error }
                committing = false
            } catch {
                guard epoch == token else { return }
                if !(error is CancellationError) { self.error = error is LabHistory.Failure ? error.localizedDescription : "The comparison wasn't saved. Check available storage and try again." }
            }
            guard epoch == token else { return }
            saving = false; control = nil; job = nil
        }
    }
}

struct LabComparisonNumberView: View {
    let comparison: LabHistory.Comparison
    let captured: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let difference = comparison.difference {
                Text(captured ? "Captured number difference" : "Number difference").font(.headline)
                Text(difference).font(.title.bold()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(captured ? "capturedLabDifference" : "labComparisonDifference")
                Text("Later minus earlier · reported unit: " + comparison.first.observation.unit).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Arithmetic in the reported units. This is not a relative percentage or a clinical assessment.").font(.footnote).foregroundStyle(Theme.secondary)
            } else {
                Text("Literal comparison").font(.headline)
                Text("No numeric difference calculated.").foregroundStyle(Theme.secondary).accessibilityIdentifier("labComparisonNoArithmetic")
                ForEach(Array(comparison.reasons.enumerated()), id: \.offset) { _, reason in Text(reason).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

struct LabHistoryContext: View {
    let observation: LabObservation
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabHistoryField(label: "Laboratory", value: observation.laboratory)
            LabHistoryField(label: "Specimen", value: observation.specimen)
            LabHistoryField(label: "Method", value: observation.method)
            LabHistoryField(label: "Reported status", value: observation.reportedStatus ?? "")
        }.padding(.top, 12)
    }
}
struct LabHistoryField: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(Theme.secondary)
            Text(value.isEmpty ? "Not recorded" : value).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct LabCapturedResultView: View {
    let point: LabHistory.Point
    let label: String
    var expandedSource = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(label).font(.title2.bold())
            Text(point.observation.test).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(point.observation.result).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("capturedLabValue-" + point.id)
            LabHistoryField(label: "Collection day", value: point.collectionDay ?? "")
            LabHistoryField(label: "Reported unit", value: point.observation.unit)
            LabHistoryField(label: "Reported reference", value: point.observation.reference)
            LabHistoryField(label: "Reported flag", value: point.observation.flag)
            LabHistoryField(label: "Laboratory", value: point.observation.laboratory)
            DisclosureGroup("More reported fields") {
                VStack(alignment: .leading, spacing: 12) {
                    LabHistoryField(label: "Specimen", value: point.observation.specimen)
                    LabHistoryField(label: "Method", value: point.observation.method)
                    LabHistoryField(label: "Reported status", value: point.observation.reportedStatus ?? "")
                    LabHistoryField(label: "Reported collection wording", value: point.observation.reportedTiming ?? "")
                }.padding(.top, 12)
            }
            if expandedSource { sourceText }
            else { DisclosureGroup("Captured source excerpt") { sourceText.padding(.top, 12) }.accessibilityIdentifier("historySourceDisclosure-" + point.id) }
            LabHistoryField(label: "Source record", value: point.record.title)
            Text("Source review captured: " + point.record.reviewedAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(Theme.secondary)
            LabHistoryField(label: "Original person label", value: point.record.personLabel)
            LabSourceStateView(source: LabComparisonSource(point))
            DisclosureGroup("File and content identity") {
                VStack(alignment: .leading, spacing: 12) {
                    LabHistoryField(label: "Record ID", value: point.record.id)
                    LabHistoryField(label: "Result ID", value: point.observation.id)
                    LabHistoryField(label: "Saved source content SHA-256", value: point.record.fingerprint)
                    if let origin = point.record.origin {
                        Text(origin.referenceText).font(.footnote).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }.padding(.top, 12)
            }
        }
    }
    private var sourceText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured source excerpt").font(.headline)
            Text(point.observation.source.excerpt).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("historySourceExcerpt-" + point.id)
        }
    }
}

private struct LabSourceStateView: View {
    let source: LabComparisonSource
    @ObservedObject private var companion = CompanionStore.shared
    @State private var state: LabComparisonSource.State?
    @State private var epoch = UUID()
    @State private var job: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state { Text(message(state)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("comparisonSourceState-" + source.id) }
            else { ProgressView("Checking saved source") }
            if state != .removed { NavigationLink("Open saved record") { DocumentDetailView(documentID: source.documentID) }.frame(minHeight: 44).foregroundStyle(Theme.accent).accessibilityIdentifier("comparisonOpenSource-" + source.id) }
        }
        .onAppear { check(companion.documents) }
        .onReceive(companion.$documents.dropFirst()) { check($0) }
        .onDisappear { epoch = UUID(); job?.cancel() }
    }
    private func message(_ state: LabComparisonSource.State) -> String {
        switch state {
        case .matching: return "Saved source content matches"
        case .changed: return "Source record changed after this capture"
        case .removed: return "Source record removed; this captured copy remains"
        case .needsReview: return "Source record needs lab review"
        }
    }
    private func check(_ documents: [HealthDocument]) {
        job?.cancel(); let token = UUID(), captured = source; epoch = token
        job = Task { @MainActor in
            let result = await Task.detached(priority: .utility) { captured.state(in: documents) }.value
            guard epoch == token, !Task.isCancelled else { return }; state = result
        }
    }
}

struct LabComparisonSection: View {
    let document: HealthDocument
    var body: some View {
        if let snapshot = document.labComparison, snapshot.isValid(in: document) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Lab comparison snapshot").font(.title2.bold())
                Text("Captured " + snapshot.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(Theme.secondary)
                Text("This independent copy keeps the captured values when original records change or are removed.").foregroundStyle(Theme.secondary)
                if !snapshot.isCurrent(body: document.body) {
                    Text("The document text was edited after this capture. The earlier structured comparison stays separate.").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).accessibilityIdentifier("labComparisonEditedText")
                    DisclosureGroup("Earlier captured comparison") { captured(snapshot).padding(.top, 12) }
                } else {
                    captured(snapshot)
                    DisclosureGroup("Portable saved text") { DocumentBodyView(text: document.body).padding(.top, 12) }
                }
            }
        } else if document.labComparison != nil {
            Text("Comparison metadata is unavailable. Review the saved text and original records.").foregroundStyle(Theme.secondary)
        }
    }
    private func captured(_ snapshot: LabComparisonSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            let comparison = snapshot.capturedComparison
            LabComparisonNumberView(comparison: comparison, captured: true)
            Text(LabHistory.DecimalStyle(rawValue: snapshot.decimalStyle)?.capturedExplanation ?? "Number interpretation unavailable").font(.footnote).foregroundStyle(Theme.secondary)
            ForEach(snapshot.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.secondary) }
            LabCapturedResultView(point: comparison.first, label: comparison.chronological ? "Captured earlier result" : "Captured first result")
            Divider()
            LabCapturedResultView(point: comparison.second, label: comparison.chronological ? "Captured later result" : "Captured second result")
        }
    }
}
