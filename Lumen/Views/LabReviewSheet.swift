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

private struct LabObservationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State var observation: LabObservation
    let sourceBody: String
    var onDone: (LabObservation) -> Void
    private let original: LabObservation
    private enum Field: Hashable { case test, result, unit, reference, flag, laboratory, specimen, method }
    @FocusState private var focused: Field?
    @State private var choosing = false
    @State private var discard = false
    init(observation: LabObservation, sourceBody: String, onDone: @escaping (LabObservation) -> Void) {
        _observation = State(initialValue: observation); original = observation; self.sourceBody = sourceBody; self.onDone = onDone
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Source excerpt") {
                    if observation.source.isValid {
                        Text(observation.source.excerpt).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("labSelectedSource")
                        if !observation.source.matches(sourceBody) { Text("This excerpt no longer matches the saved text. Choose its current wording.").foregroundStyle(Theme.secondary) }
                    }
                    Button("Choose source text", systemImage: "text.magnifyingglass") { focused = nil; choosing = true }.accessibilityIdentifier("chooseLabSource")
                    if observation.source.matches(sourceBody) {
                        Button("Include previous line") { if let source = LabReview.extending(observation.source, in: sourceBody, forward: false) { observation.source = source } }.disabled(LabReview.extending(observation.source, in: sourceBody, forward: false) == nil).accessibilityIdentifier("labPreviousSourceLine")
                        Button("Include next line") { if let source = LabReview.extending(observation.source, in: sourceBody, forward: true) { observation.source = source } }.disabled(LabReview.extending(observation.source, in: sourceBody, forward: true) == nil).accessibilityIdentifier("labNextSourceLine")
                        Text("Source excerpts can include up to 2,000 characters.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
                Section("Reported result") {
                    field("Test name", value: $observation.test, focus: .test, identifier: "labTestName")
                    field("Reported result", value: $observation.result, focus: .result, identifier: "labReportedResult")
                    field("Unit", value: $observation.unit, focus: .unit, identifier: "labUnit")
                }
                Section {
                    field("Reference wording", value: $observation.reference, focus: .reference, identifier: "labReference")
                    field("Reported flag", value: $observation.flag, focus: .flag, identifier: "labFlag")
                } footer: { Text("Copy the report's wording and signs, including < or >. Blank optional fields stay unknown.").foregroundStyle(Theme.secondary) }
                Section("Collection day") {
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
                    field("Laboratory", value: $observation.laboratory, focus: .laboratory, identifier: "labLaboratory")
                    field("Specimen", value: $observation.specimen, focus: .specimen, identifier: "labSpecimen")
                    field("Method", value: $observation.method, focus: .method, identifier: "labMethod")
                }
                if !observation.isValid { Section { Text("Add a test name, reported result and source text. Keep names within 200 characters, results within 500, units within 100 and reference wording within 1,000.").font(.footnote).foregroundStyle(Theme.secondary) } }
            }.scrollContentBackground(.hidden).background(Theme.bg).scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    if focused != nil { HStack { Spacer(); Button("Done") { focused = nil }.fontWeight(.semibold).accessibilityIdentifier("finishLabField") }.padding(.horizontal, Theme.gutter).padding(.vertical, 10).background(Theme.surface) }
                }
                .navigationTitle(typeSize.isAccessibilitySize ? "Lab result" : "Edit lab result").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if observation != original { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { focused = nil; onDone(observation); dismiss() }.fontWeight(.bold).disabled(!observation.isValid || !observation.source.matches(sourceBody)).accessibilityIdentifier("finishLabResult") }
                }
                .sheet(isPresented: $choosing) { LabSourcePicker(body: sourceBody) { observation.source = $0 } }
                .background(SheetDismissGuard(hasEdits: observation != original) { discard = true })
                .alert("Discard this result's changes?", isPresented: $discard) { Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
        }.tint(Theme.accent)
    }
    private func field(_ title: String, value: Binding<String>, focus: Field, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
            TextField(title, text: value, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled(true).focused($focused, equals: focus).accessibilityIdentifier(identifier)
        }.padding(.vertical, 4)
    }
    private var collectionToggle: some View {
        Toggle("Set collection day", isOn: Binding(get: { observation.collectedOn != nil }, set: { observation.collectedOn = $0 ? PlanDay.string(Date()) : nil })).accessibilityIdentifier("labHasCollectionDay")
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
                ForEach(report.observations) { observation in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(observation.test).font(.headline)
                        Text(observation.result + (observation.unit.isEmpty ? "" : " " + observation.unit)).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        if !observation.reference.isEmpty { Text("Reported reference: " + observation.reference).font(.subheadline).foregroundStyle(Theme.secondary) }
                        if !observation.flag.isEmpty { Text("Reported flag: " + observation.flag).font(.subheadline).foregroundStyle(Theme.secondary) }
                        Text("Collection day: " + (observation.collectedOn ?? "Not recorded")).font(.footnote).foregroundStyle(Theme.secondary)
                        if !observation.laboratory.isEmpty { Text("Laboratory: " + observation.laboratory).font(.footnote).foregroundStyle(Theme.secondary) }
                        if !observation.specimen.isEmpty { Text("Specimen: " + observation.specimen).font(.footnote).foregroundStyle(Theme.secondary) }
                        if !observation.method.isEmpty { Text("Method: " + observation.method).font(.footnote).foregroundStyle(Theme.secondary) }
                        DisclosureGroup("Saved source excerpt") { Text(observation.source.excerpt).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.top, 8).accessibilityIdentifier("labSavedSourceText-\(observation.id)") }
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("savedLabResult-\(observation.id)")
                    Divider()
                }
                Text("Transcribed after review. Reported ranges and flags are copied wording; Lumen has not interpreted these results.").font(.footnote).foregroundStyle(Theme.secondary)
                Button("Review lab results", systemImage: "pencil") { onReview() }.buttonStyle(LumenTonalButtonStyle()).accessibilityIdentifier("reviewSavedLabResults")
            } else {
                Text("Keep reported values beside their exact source wording. Review each result before saving.").font(.subheadline).foregroundStyle(Theme.secondary)
                Button("Add lab results", systemImage: "text.badge.plus") { onReview() }.buttonStyle(LumenTonalButtonStyle()).accessibilityIdentifier("reviewSavedLabResults")
            }
        }
    }
}
