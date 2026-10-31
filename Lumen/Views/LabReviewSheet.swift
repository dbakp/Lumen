import SwiftUI

struct LabReviewSheet: View {
    let documentID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var companion = CompanionStore.shared
    @State private var draft: LabReview.Draft?
    @State private var initial: [LabObservation] = []
    @State private var editing: LabObservation?
    @State private var acknowledged = false
    @State private var error: String?
    @State private var openingFailure: String?
    @State private var discard = false
    @State private var removing: LabObservation?
    private var current: HealthDocument? { companion.documents.first { $0.id == documentID } }
    private var hasEdits: Bool { (draft?.observations ?? []) != initial }
    private var acknowledgementTitle: String {
        draft?.observations.isEmpty == true && draft?.originalReport != nil ? "I want to remove the lab transcriptions" : "I checked every result and its source"
    }
    private var sourceChanged: Bool {
        guard let draft, let current else { return true }
        return current.body != draft.sourceBody || current.labReport != draft.originalReport || RecordRetrieval.fingerprint(current) != draft.originalFingerprint
    }
    private var canSave: Bool {
        guard acknowledged, let draft, let current, !sourceChanged else { return false }
        return (try? draft.applying(to: current, acknowledged: true)) != nil
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Keep each result\nwith its source.").font(.system(.largeTitle, weight: .bold)).fontWidth(.expanded).tracking(-1)
                    if let draft {
                        Text(current?.title ?? "Record no longer available").font(.subheadline).foregroundStyle(Theme.secondary)
                        if sourceChanged {
                            Text("This record changed. Close this review, reopen it and check the current text before saving.").foregroundStyle(Theme.secondary).accessibilityIdentifier("labReviewSourceChanged")
                        }
                        if let previous = draft.originalReport, !previous.isCurrent(body: draft.sourceBody) {
                            Text("Source text changed after the earlier review. Choose current source text for each result and check its fields again.").font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        if draft.observations.isEmpty {
                            Text(draft.originalReport == nil ? "Choose the source wording, then enter the test and result exactly as reported." : "Saving removes the earlier lab transcriptions. The source record stays in Library.").foregroundStyle(Theme.secondary).accessibilityIdentifier("labReviewEmpty")
                        } else {
                            Text("\(draft.observations.count) \(draft.observations.count == 1 ? "result" : "results")").font(.headline)
                            ForEach(draft.observations) { observation in
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top, spacing: 16) {
                                    Button { editing = observation } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(observation.test.isEmpty ? "Test name needed" : observation.test).font(.headline)
                                            Text(observation.result + (observation.unit.isEmpty ? "" : " " + observation.unit)).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                                            if !observation.source.matches(draft.sourceBody) { Text("Choose current source text").font(.footnote).foregroundStyle(Theme.secondary) }
                                            Text("Edit result").font(.subheadline).foregroundStyle(Theme.accent)
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("editLabResult-\(observation.id)")
                                    if !typeSize.isAccessibilitySize {
                                        Button(role: .destructive) { removing = observation } label: { Image(systemName: "trash").font(.system(size: 24)).frame(minWidth: 44, minHeight: 44) }.foregroundStyle(.red).accessibilityLabel("Remove \(observation.test) from draft")
                                    }
                                }
                                DisclosureGroup("Saved source excerpt") {
                                    Text(observation.source.excerpt).font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.top, 8).accessibilityIdentifier("labReviewSourceText-\(observation.id)")
                                }.accessibilityIdentifier("labReviewSource-\(observation.id)")
                                if typeSize.isAccessibilitySize {
                                    Button("Remove result", role: .destructive) { removing = observation }.buttonStyle(.plain).foregroundStyle(.red).frame(minHeight: 44, alignment: .leading).accessibilityLabel("Remove \(observation.test) from draft")
                                }
                            }
                                Divider()
                            }
                        }
                        Button("Add result", systemImage: "plus") {
                            editing = LabObservation(test: "", result: "", source: .init(start: 0, end: 0, excerpt: ""))
                        }.buttonStyle(LumenTonalButtonStyle()).disabled(draft.observations.count >= LabReport.maxObservations || sourceChanged).accessibilityIdentifier("addLabResult")
                        if draft.observations.count >= LabReport.maxObservations { Text("Up to 256 results per record. Keep another report as a separate record.").font(.footnote).foregroundStyle(Theme.secondary) }
                        Text("Check against the laboratory report. Lumen keeps the wording you enter; it doesn't convert units or decide whether a result is normal.").font(.footnote).foregroundStyle(Theme.secondary)
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(acknowledgementTitle)
                                Toggle(acknowledgementTitle, isOn: $acknowledged).labelsHidden().accessibilityLabel(acknowledgementTitle).accessibilityIdentifier("acknowledgeLabResults")
                            }
                        } else { Toggle(acknowledgementTitle, isOn: $acknowledged).accessibilityIdentifier("acknowledgeLabResults") }
                        Text("Saving keeps this record's sharing setting.").font(.footnote).foregroundStyle(Theme.secondary)
                    } else if let openingFailure { Text(openingFailure).foregroundStyle(Theme.secondary) }
                    else { ProgressView("Opening saved record") }
                }.padding(Theme.gutter).padding(.bottom, 24)
            }.lumenScreen().navigationTitle(typeSize.isAccessibilitySize ? "Lab results" : "Review lab results").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasEdits { discard = true } else { dismiss() } }.accessibilityIdentifier("cancelLabReview") }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold).disabled(!canSave).accessibilityIdentifier("saveLabResults") }
                }
                .sheet(item: $editing) { observation in
                    LabObservationEditor(observation: observation, sourceBody: draft?.sourceBody ?? "") { value in
                        guard var next = draft else { return }
                        if let index = next.observations.firstIndex(where: { $0.id == value.id }) { next.observations[index] = value }
                        else if next.observations.count < LabReport.maxObservations { next.observations.append(value) }
                        draft = next; acknowledged = false
                    }
                }
                .alert("Remove this result from the draft?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                    Button("Remove result", role: .destructive) {
                        guard let removing else { return }
                        draft?.observations.removeAll { $0.id == removing.id }; acknowledged = false; self.removing = nil
                    }
                    Button("Keep result", role: .cancel) { removing = nil }
                } message: { Text("The saved record changes only when you save this review.") }
                .alert("Discard your lab review?", isPresented: $discard) { Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep reviewing", role: .cancel) {} }
                .alert("Couldn't save lab review", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
                .background(SheetDismissGuard(hasEdits: hasEdits) { discard = true })
                .task {
                    guard draft == nil else { return }
                    do {
                        guard let current else { throw LabReview.Failure.sourceChanged }
                        let value = try LabReview.Draft(document: current); draft = value; initial = value.observations
                    } catch { openingFailure = error.localizedDescription }
                }
        }.tint(Theme.accent)
    }
    private func save() {
        do {
            guard let draft, let current else { throw LabReview.Failure.sourceChanged }
            let result = try draft.applying(to: current, acknowledged: acknowledged)
            try companion.saveChecked(result); dismiss(); AppRouter.shared.confirm(result.labReport == nil ? "Lab transcriptions removed" : "Reviewed lab results saved")
        } catch { self.error = error is LabReview.Failure ? error.localizedDescription : "Your review wasn't saved. Check available storage and try again." }
    }
}

struct LabObservationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State var observation: LabObservation
    let sourceBody: String
    let allowSourceChange: Bool
    var onDone: (LabObservation) -> Void
    private let original: LabObservation
    private enum Field: String, Identifiable {
        case test = "labTestName", result = "labReportedResult", unit = "labUnit", reference = "labReference", flag = "labFlag", timing = "labReportedTiming", status = "labReportedStatus", laboratory = "labLaboratory", specimen = "labSpecimen", method = "labMethod"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .test: return "Test name"
            case .result: return "Reported result"
            case .unit: return "Unit"
            case .reference: return "Reference wording"
            case .flag: return "Reported flag"
            case .timing: return "Reported collection wording"
            case .status: return "Reported status"
            case .laboratory: return "Laboratory"
            case .specimen: return "Specimen"
            case .method: return "Method"
            }
        }
        var limit: Int { switch self { case .test, .flag, .status: return 200; case .unit: return 100; case .reference: return 1000; default: return 500 } }
        var required: Bool { self == .test || self == .result }
    }
    @State private var editingText: Field?
    @State private var choosing = false
    @State private var discard = false
    init(observation: LabObservation, sourceBody: String, allowSourceChange: Bool = true, onDone: @escaping (LabObservation) -> Void) {
        _observation = State(initialValue: observation); original = observation; self.sourceBody = sourceBody; self.allowSourceChange = allowSourceChange; self.onDone = onDone
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(allowSourceChange ? "Source excerpt" : "Mapped source cells") {
                    if observation.source.isValid {
                        Text(observation.source.excerpt).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("labSelectedSource")
                        if !observation.source.matches(sourceBody) { Text("This excerpt no longer matches the saved text. Choose its current wording.").foregroundStyle(Theme.secondary) }
                    }
                    if allowSourceChange { Button("Choose source text", systemImage: "text.magnifyingglass") { choosing = true }.accessibilityIdentifier("chooseLabSource") }
                    if allowSourceChange && observation.source.matches(sourceBody) {
                        Button("Include previous line") { if let source = LabReview.extending(observation.source, in: sourceBody, forward: false) { observation.source = source } }.disabled(LabReview.extending(observation.source, in: sourceBody, forward: false) == nil).accessibilityIdentifier("labPreviousSourceLine")
                        Button("Include next line") { if let source = LabReview.extending(observation.source, in: sourceBody, forward: true) { observation.source = source } }.disabled(LabReview.extending(observation.source, in: sourceBody, forward: true) == nil).accessibilityIdentifier("labNextSourceLine")
                        Text("Source excerpts can include up to 2,000 characters.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    if !allowSourceChange { Text("These original cell values are arranged by Lumen. Your corrections below do not change them. Keep the original file separately.").font(.footnote).foregroundStyle(Theme.secondary) }
                }
                Section("Reported result") {
                    field(.test)
                    field(.result)
                    field(.unit)
                }
                Section {
                    field(.reference)
                    field(.flag)
                } footer: { Text("Copy the report's wording and signs, including < or >. Blank optional fields stay unknown.").foregroundStyle(Theme.secondary) }
                Section("Collection day") {
                    field(.timing)
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Set collection day").fixedSize(horizontal: false, vertical: true)
                            collectionToggle.labelsHidden().accessibilityLabel("Set collection day")
                        }
                    } else { collectionToggle }
                    if observation.collectedOn != nil {
                        DatePicker("Collection day", selection: Binding(get: { observation.collectedOn.flatMap { PlanDay.date($0) } ?? Date() }, set: { observation.collectedOn = PlanDay.string($0) }), displayedComponents: .date)
                            .labelsHidden().accessibilityLabel("Collection day")
                    }
                }
                Section("Optional report details") {
                    field(.status)
                    field(.laboratory)
                    field(.specimen)
                    field(.method)
                }
                if !observation.source.matches(sourceBody) { Section { Text(allowSourceChange ? "Choose current source text before saving this result." : "These source cells no longer match this draft. Go back to mapping and prepare the review again.").font(.footnote).foregroundStyle(Theme.secondary) } }
            }.scrollContentBackground(.hidden).background(Theme.bg)
                .navigationTitle(typeSize.isAccessibilitySize ? "Lab result" : "Edit lab result").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if observation != original { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(observation); dismiss() }.fontWeight(.bold).disabled(!observation.isValid || !observation.source.matches(sourceBody)).accessibilityIdentifier("finishLabResult") }
                }
                .sheet(item: $editingText) { field in
                    let binding = value(for: field)
                    LabTextEditor(text: binding.wrappedValue, title: field.title, limit: field.limit, required: field.required, identifier: field.id, doneIdentifier: "finishLabField") { binding.wrappedValue = $0 }
                }
                .sheet(isPresented: $choosing) { LabSourcePicker(body: sourceBody) { observation.source = $0 } }
                .background(SheetDismissGuard(hasEdits: observation != original) { discard = true })
                .alert("Discard this result's changes?", isPresented: $discard) { Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
        }.tint(Theme.accent)
    }
    private func field(_ field: Field) -> some View {
        let text = value(for: field).wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            Text(field.title).font(.subheadline).foregroundStyle(Theme.secondary)
            LabTextEditButton(text: text, title: field.title, identifier: field.id) { editingText = field }
            if let issue = LabReport.textIssue(text, limit: field.limit, required: field.required) {
                Text(issue.message(for: field.title)).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(field.id + "Issue")
            }
        }.padding(.vertical, 4)
    }
    private func value(for field: Field) -> Binding<String> {
        switch field {
        case .test: return $observation.test
        case .result: return $observation.result
        case .unit: return $observation.unit
        case .reference: return $observation.reference
        case .flag: return $observation.flag
        case .timing: return optional(\.reportedTiming)
        case .status: return optional(\.reportedStatus)
        case .laboratory: return $observation.laboratory
        case .specimen: return $observation.specimen
        case .method: return $observation.method
        }
    }
    private var collectionToggle: some View {
        Toggle("Set collection day", isOn: Binding(get: { observation.collectedOn != nil }, set: { observation.collectedOn = $0 ? PlanDay.string(Date()) : nil })).accessibilityIdentifier("labHasCollectionDay")
    }
    private func optional(_ key: WritableKeyPath<LabObservation, String?>) -> Binding<String> {
        Binding(get: { observation[keyPath: key] ?? "" }, set: { observation[keyPath: key] = $0.isEmpty ? nil : $0 })
    }
}

struct LabTextEditButton: View {
    let text: String
    let title: String
    let identifier: String
    var edit: () -> Void
    var body: some View {
        let preview = LabTable.displayPreview(text, maxCharacters: 80)
        VStack(alignment: .leading, spacing: 8) {
            Button(action: edit) {
                HStack(alignment: .top, spacing: 12) {
                    Text(text.isEmpty ? "Add text" : (preview.text.isEmpty ? "Open full text" : preview.text)).foregroundStyle(text.isEmpty ? Theme.accent : Theme.text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "square.and.pencil").foregroundStyle(Theme.accent)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Edit " + title.lowercased()).accessibilityValue(preview.text).accessibilityIdentifier("editFull-" + identifier)
            if preview.truncated { Text("Preview only. Open the full text to review or edit it.").font(.footnote).foregroundStyle(Theme.secondary) }
        }
    }
}

struct LabTextEditor: View {
    let title: String
    let limit: Int
    let required: Bool
    let identifier: String
    let doneIdentifier: String
    var onDone: (String) -> Void
    @State private var text: String
    @State private var selection: TextSelection?
    private let initial: String
    @State private var discard = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    init(text: String, title: String, limit: Int, required: Bool, identifier: String, doneIdentifier: String, onDone: @escaping (String) -> Void) {
        _text = State(initialValue: text); initial = text; self.title = title; self.limit = limit; self.required = required; self.identifier = identifier; self.doneIdentifier = doneIdentifier; self.onDone = onDone
    }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $text, selection: $selection).font(.body).foregroundStyle(Theme.text).scrollContentBackground(.hidden).focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel(title).accessibilityIdentifier(identifier)
                if let issue = LabReport.textIssue(text, limit: limit, required: required) { Text(issue.message(for: title)).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("activeLabTextIssue") }
            }.padding(Theme.gutter).background(Theme.bg).navigationTitle("Edit text").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if text != initial { discard = true } else { dismiss() } }.accessibilityIdentifier("cancelLabText") } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack {
                        Button { focused = true; selection = TextSelection(range: text.startIndex..<text.endIndex) } label: { Text("Select all").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.disabled(text.isEmpty).accessibilityIdentifier("selectAllLabText")
                        Spacer()
                        Button { focused = false; onDone(text); dismiss() } label: { Text("Done").fontWeight(.semibold).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier(doneIdentifier)
                    }.padding(.horizontal, Theme.gutter).background(.bar)
                }
                .background(SheetDismissGuard(hasEdits: text != initial) { discard = true })
                .alert("Discard this text edit?", isPresented: $discard) { Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
                .task { focused = true }
        }.tint(Theme.accent)
    }
}

private struct LabSourcePicker: View {
    @Environment(\.dismiss) private var dismiss
    let sources: [LabTextSource]
    var onSelect: (LabTextSource) -> Void
    @State private var search = ""
    @State private var limit = 200
    init(body: String, onSelect: @escaping (LabTextSource) -> Void) { sources = LabReview.sources(in: body); self.onSelect = onSelect }
    private var filtered: [LabTextSource] { sources.filter { search.isEmpty || $0.excerpt.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the saved text for this result. Keep the original laboratory report separately.").foregroundStyle(Theme.secondary)
                    if filtered.isEmpty { Text("No matching source lines. Open and correct the record text if it is missing or the line exceeds 2,000 characters.") }
                    ForEach(Array(filtered.prefix(limit)), id: \.start) { source in
                        Button { onSelect(source); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(source.excerpt).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                                Text("Use this text").font(.footnote).foregroundStyle(Theme.accent)
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("labSource-\(source.start)")
                    }
                    if filtered.count > limit { Button("Show more source lines") { limit += 200 } }
                }
            }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Saved record text").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a test or result").onChange(of: search) { _, _ in limit = 200 }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(Theme.accent)
    }
}

struct LabResultsSection: View {
    let document: HealthDocument
    var onReview: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupLabel("Lab results")
            if let report = document.labReport {
                if !report.isCurrent(body: document.body) {
                    Text("Source text changed").font(.headline).accessibilityIdentifier("labSavedSourceChanged")
                    Text("These earlier transcriptions need review. Their structured values are withheld from future assistant search until checked again.").font(.footnote).foregroundStyle(Theme.secondary)
                }
                Text("\(report.observations.count) \(report.observations.count == 1 ? "result" : "results") · reviewed \(report.reviewedAt.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(Theme.secondary)
                if let origin = report.importedFrom {
                    DisclosureGroup("Original lab-file import") { Text(origin.referenceText).font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.top, 8) }.accessibilityIdentifier("labImportReceipt")
                }
                ForEach(report.observations) { observation in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(observation.test).font(.headline)
                        Text(observation.result + (observation.unit.isEmpty ? "" : " " + observation.unit)).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        if !observation.reference.isEmpty { Text("Reported reference: " + observation.reference).font(.subheadline).foregroundStyle(Theme.secondary) }
                        if !observation.flag.isEmpty { Text("Reported flag: " + observation.flag).font(.subheadline).foregroundStyle(Theme.secondary) }
                        Text("Collection day: " + (observation.collectedOn ?? "Not recorded")).font(.footnote).foregroundStyle(Theme.secondary)
                        if let timing = observation.reportedTiming { Text("Reported collection wording: " + timing).font(.footnote).foregroundStyle(Theme.secondary) }
                        if let status = observation.reportedStatus { Text("Reported status: " + status).font(.footnote).foregroundStyle(Theme.secondary) }
                        if let row = observation.importRow { Text("Original import data row \(row)").font(.footnote).foregroundStyle(Theme.secondary) }
                        if !observation.laboratory.isEmpty { Text("Laboratory: " + observation.laboratory).font(.footnote).foregroundStyle(Theme.secondary) }
                        if !observation.specimen.isEmpty { Text("Specimen: " + observation.specimen).font(.footnote).foregroundStyle(Theme.secondary) }
                        if !observation.method.isEmpty { Text("Method: " + observation.method).font(.footnote).foregroundStyle(Theme.secondary) }
                        DisclosureGroup(observation.importRow != nil && report.matchesOriginalImportLayout(body: document.body) ? "Original source cells" : "Saved source excerpt") { Text(observation.source.excerpt).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.top, 8).accessibilityIdentifier("labSavedSourceText-\(observation.id)") }
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("savedLabResult-\(observation.id)")
                    Divider()
                }
                Text("Transcribed after review. Reported ranges and flags are copied wording; Lumen has not interpreted these results.").font(.footnote).foregroundStyle(Theme.secondary)
                Button("Review lab results", systemImage: "pencil") { onReview() }.buttonStyle(LumenTonalButtonStyle()).accessibilityIdentifier("reviewSavedLabResults")
            } else {
                if let origin = document.labImportOrigin, origin.isValid {
                    DisclosureGroup("Original lab-file import") { Text(origin.referenceText).font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.top, 8) }.accessibilityIdentifier("labImportReceipt")
                    Text("No lab transcriptions. The original import receipt remains with this record.").font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("labImportSourceOnly")
                }
                Text("Keep reported values beside their exact source wording. Review each result before saving.").font(.subheadline).foregroundStyle(Theme.secondary)
                Button("Add lab results", systemImage: "text.badge.plus") { onReview() }.buttonStyle(LumenTonalButtonStyle()).accessibilityIdentifier("reviewSavedLabResults")
            }
        }
    }
}
