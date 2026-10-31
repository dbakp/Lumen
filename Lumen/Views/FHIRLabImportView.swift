import SwiftUI
import UniformTypeIdentifiers

struct FHIRLabImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var companion = CompanionStore.shared
    var onSaved: () -> Void
    private enum Step { case coverage, person, results }
    @State private var step = Step.coverage
    @State private var choosing = false
    @State private var preparation: FHIRLabPreparation?
    @State private var coverageReviewed = false
    @State private var subjectKey: String?
    @State private var personChecked = false
    @State private var draft: FHIRLabDraft?
    @State private var acknowledged = false
    @State private var page = 0
    @State private var editing: LabObservation?
    @State private var editingTitle = false
    @State private var saved: HealthDocument?
    @State private var control: BackupOperationControl?
    @State private var job: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var workTitle = "Reading FHIR file."
    @State private var stopping = false
    @State private var status: String?
    @State private var error: String?
    @State private var discard = false
    @State private var changePerson = false
    @State private var duplicate = false
    private var hasDraft: Bool { saved == nil && (preparation != nil || control != nil) }
    private var subjects: [FHIRLabPreparation.Subject] {
        var seen = Set<String>()
        return preparation?.results.compactMap { seen.insert($0.subject.key).inserted ? $0.subject : nil } ?? []
    }
    private var canSave: Bool {
        guard control == nil, saved == nil, acknowledged, let draft else { return false }
        return LabReport.bounded(draft.title, limit: 500, required: true) && (1...256).contains(draft.includedCount) && draft.results.filter(\.included).allSatisfy { $0.sourceIssue == nil && $0.observation.isValid }
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 1).id("fhirImportTop")
                        if let saved { completion(saved) }
                        else if control != nil {
                            LabHistoryHeading(text: stopping ? "Stopping." : workTitle)
                            ProgressView(stopping ? "Stopping local work" : "Working on this device")
                            Text("No record is saved until you review and confirm.").foregroundStyle(Theme.secondary)
                        } else if let preparation {
                            switch step {
                            case .coverage: coverage(preparation)
                            case .person: personSelection
                            case .results: resultReview
                            }
                        } else { landing }
                        if let status { Text(status).font(.subheadline).foregroundStyle(Theme.secondary).accessibilityIdentifier("fhirImportStatus") }
                    }.padding(Theme.gutter).padding(.bottom, 24)
                }.lumenScreen().scrollDismissesKeyboard(.interactively)
                    .onChange(of: step) { _, _ in proxy.scrollTo("fhirImportTop", anchor: .top) }
                    .onChange(of: page) { _, _ in proxy.scrollTo("fhirImportTop", anchor: .top) }
                    .onChange(of: control != nil) { _, _ in proxy.scrollTo("fhirImportTop", anchor: .top) }
            }
            .navigationTitle(saved == nil ? "Import FHIR labs" : "Saved lab results").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved != nil ? "Done" : (stopping ? "Stopping…" : "Cancel")) {
                        if let control { stopping = true; control.cancel() }
                        else if hasDraft { discard = true } else { close() }
                    }.disabled(stopping).accessibilityIdentifier("cancelFHIRImport")
                }
                if step == .results && draft != nil && saved == nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold).disabled(!canSave).accessibilityIdentifier("saveFHIRImport") }
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): read(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(item: $editing) { observation in
                if let row = draft?.results.first(where: { $0.observation.id == observation.id }) {
                    LabObservationEditor(observation: observation, sourceBody: row.sourceText, allowSourceChange: false) { corrected in
                        guard let index = draft?.results.firstIndex(where: { $0.observation.id == corrected.id }) else { return }
                        draft?.results[index].observation = corrected; acknowledged = false
                    }
                }
            }
            .sheet(isPresented: $editingTitle) {
                LabTextEditor(text: draft?.title ?? "", title: "Record title", limit: 500, required: true, identifier: "fhirImportTitle", doneIdentifier: "finishFHIRTitle") { draft?.title = $0; acknowledged = false }
            }
            .alert("Check the FHIR import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .alert("Discard this FHIR import?", isPresented: $discard) { Button("Discard draft", role: .destructive) { close() }; Button("Keep reviewing", role: .cancel) {} } message: { Text("The original file stays unchanged. No record has been saved.") }
            .alert("Change the person group?", isPresented: $changePerson) { Button("Discard result review", role: .destructive) { draft = nil; acknowledged = false; personChecked = false; page = 0; step = .person }; Button("Keep reviewing", role: .cancel) {} } message: { Text("This discards result corrections, exclusions and the record title. Check the intended person again.") }
            .alert("Save another copy?", isPresented: $duplicate) { Button("Save another copy") { save(allowDuplicate: true) }; Button("Keep reviewing", role: .cancel) {} } message: { Text("A record from this exact file is already in Library. Saving adds a separate record.") }
            .background(SheetDismissGuard(hasEdits: hasDraft) { if let control { stopping = true; control.cancel() } else { discard = true } })
            // Pushing an original-field reader can make this surface disappear.
            // Its unsaved corrections must survive the return navigation. The
            // explicit close path releases input; remaining state has no files
            // and is released with the sheet itself.
            .onDisappear { generation = UUID(); control?.cancel(); job?.cancel() }
        }.tint(Theme.accent)
    }
    private var landing: some View {
        Group {
            LabHistoryHeading(text: "Bring in a\nclinical export.")
            Text("Review its coverage, person and original fields before saving lab results.").foregroundStyle(Theme.secondary)
            Button { choosing = true } label: {
                if typeSize.isAccessibilitySize { Text("Choose a FHIR file").multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 20) }
                else { Label("Choose a FHIR file", systemImage: "doc.badge.plus") }
            }.buttonStyle(FHIRPrimaryButtonStyle()).accessibilityIdentifier("chooseFHIRFile")
            Text("FHIR R4 JSON · up to 2 MB and 1,024 entries/resources. Read on this device. No links are downloaded.").font(.footnote).foregroundStyle(Theme.secondary)
            Text("Keep the original file separately. Lumen doesn't interpret these results or add them to Apple Health.").font(.footnote).foregroundStyle(Theme.secondary)
        }
    }
    private func coverage(_ prepared: FHIRLabPreparation) -> some View {
        Group {
            LabHistoryHeading(text: "Check what\ncame in.")
            Text(prepared.archive.filename).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text("\(prepared.coverage.entries) \(prepared.coverage.entries == 1 ? "entry" : "entries") · \(prepared.coverage.resources) \(prepared.coverage.resources == 1 ? "resource" : "resources") · \(prepared.results.count) \(prepared.results.count == 1 ? "result proposal" : "result proposals")").foregroundStyle(Theme.secondary).accessibilityIdentifier("fhirCoverageCounts")
            Text(prepared.coverage.resourceTypes.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")).font(.subheadline)
            Text("\(prepared.coverage.deletedEntries.count) \(prepared.coverage.deletedEntries.count == 1 ? "deletion entry" : "deletion entries") · \(prepared.coverage.requestResponseOnly.count) \(prepared.coverage.requestResponseOnly.count == 1 ? "request/response-only entry" : "request/response-only entries") · \(prepared.coverage.panelsWithoutOwnValue.count) \(prepared.coverage.panelsWithoutOwnValue.count == 1 ? "panel without its own result" : "panels without their own result")").font(.footnote).foregroundStyle(Theme.secondary)
            let unresolved = prepared.coverage.links.filter { if case .found = $0.resolution { return false }; return true }.count
            Text("\(unresolved) unresolved result links. \(prepared.coverage.omittedResourceFields.values.reduce(0) { $0 + $1.count }) fields not retained in full.").foregroundStyle(Theme.secondary)
            Text(prepared.coverage.hasNextPage ? "This export reports another page. It has not been downloaded." : "No next-page link was supplied. This does not prove the export is complete.").font(.footnote).foregroundStyle(Theme.secondary)
            FHIRReaderLink("File coverage details") { FHIRCoverageView(preparation: prepared) }.accessibilityIdentifier("fhirCoverageDetails")
            FHIRReaderLink("Read original JSON") { FHIRTextReader(title: "Original JSON", text: String(decoding: prepared.archive.json.source, as: UTF8.self), subtitle: "Temporary input. Keep your original file separately.") }.accessibilityIdentifier("fhirOriginalJSON")
            LabHistoryToggle(title: "I checked the file coverage and what will be left out", value: $coverageReviewed, identifier: "acknowledgeFHIRCoverage")
            if prepared.results.isEmpty { Text("No lab result proposals are available in this file. Nothing can be saved.").foregroundStyle(Theme.secondary) }
            Button("Continue") { page = 0; step = .person }.buttonStyle(FHIRPrimaryButtonStyle()).disabled(!coverageReviewed || prepared.results.isEmpty).accessibilityIdentifier("continueFHIRCoverage")
        }
    }
    private var personSelection: some View {
        Group {
            LabHistoryHeading(text: "Whose results?")
            Text("Choose whose results to review. Check the original person reference; names alone do not establish identity.").foregroundStyle(Theme.secondary)
            Button("Back to coverage", systemImage: "chevron.left") { step = .coverage; personChecked = false }.frame(minHeight: 44).foregroundStyle(Theme.accent)
            ForEach(Array(subjects.dropFirst(page * 10).prefix(10)), id: \.key) { subject in
                VStack(alignment: .leading, spacing: 12) {
                    Button { subjectKey = subject.key; personChecked = false; acknowledged = false } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: subjectKey == subject.key ? "checkmark.circle.fill" : "circle")
                            Text(LabTable.displayPreview(subject.label, maxCharacters: 140).text).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.accessibilityAddTraits(subjectKey == subject.key ? .isSelected : []).accessibilityIdentifier("fhirPerson-" + subject.key)
                    let count = preparation?.results.filter { $0.subject.key == subject.key }.count ?? 0
                    Text("\(count) \(count == 1 ? "result proposal" : "result proposals")").font(.footnote).foregroundStyle(Theme.secondary)
                    FHIRReaderLink("Read person reference") { FHIRTextReader(title: "Person reference", text: personReferenceText(subject), subtitle: subject.suppliedIdentity ? "Supplied source identity; not independently authenticated." : "No linkable person identity was supplied. Check the original file.") }
                }
                Divider()
            }
            LabHistoryPager(page: page, count: subjects.count, size: 10) { page = $0 }
            LabHistoryToggle(title: "I checked this is the intended person", value: $personChecked, identifier: "acknowledgeFHIRPerson")
            Button("Review results") { prepareDraft() }.buttonStyle(FHIRPrimaryButtonStyle()).disabled(subjectKey == nil || !personChecked).accessibilityIdentifier("reviewFHIRResults")
        }
    }
    @ViewBuilder private var resultReview: some View {
        if let draft {
            LabHistoryHeading(text: "Check each\nresult.")
            Text("\(draft.includedCount) included of \(draft.results.count) \(draft.results.count == 1 ? "result" : "results")").foregroundStyle(Theme.secondary).accessibilityIdentifier("fhirIncludedCount")
            GroupLabel("Record title")
            LabTextEditButton(text: draft.title, title: "Record title", identifier: "fhirImportTitle") { editingTitle = true }
            Button("Change person", systemImage: "chevron.left") { changePerson = true }.frame(minHeight: 44).foregroundStyle(Theme.accent)
            Menu("Result selection") {
                Button("Include all results") { for index in self.draft?.results.indices ?? 0..<0 { self.draft?.results[index].included = true }; acknowledged = false }
                Button("Exclude all results") { for index in self.draft?.results.indices ?? 0..<0 { self.draft?.results[index].included = false }; acknowledged = false }
            }.frame(minHeight: 44)
            ForEach(Array(draft.results.enumerated().dropFirst(page * 10).prefix(10)), id: \.element.id) { index, row in
                resultRow(row, index: index)
                Divider()
            }
            LabHistoryPager(page: page, count: draft.results.count, size: 10) { page = $0 }
            Text("Keep up to 256 results. Missing fields stay unknown. Collection days must be checked separately; effective timestamps do not establish collection days.").font(.footnote).foregroundStyle(Theme.secondary)
            LabHistoryToggle(title: "I checked the included results and original FHIR fields", value: $acknowledged, identifier: "acknowledgeFHIRResults")
            Text("Assistant sharing starts off. Saving creates a separate reviewed record; keep the original file.").font(.footnote).foregroundStyle(Theme.secondary)
        }
    }
    private func resultRow(_ row: FHIRLabDraft.Result, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LabTable.displayPreview(row.observation.test, maxCharacters: 200).text).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text("Reviewed result").font(.footnote).foregroundStyle(Theme.secondary)
            Text(LabTable.displayPreview(row.observation.result, maxCharacters: 500).text).font(row.original?.permitsScalar == false ? .headline : .title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let original = row.original {
                FHIRResultProvenanceView(source: original, identifier: "fhirResultFields-\(index)")
            } else {
                Text("Original result type: " + FHIRValueForm.label(row.proposal.valueKind)).font(.footnote).foregroundStyle(Theme.secondary)
                FHIRReaderLink("Original FHIR fields") { FHIRSourceFieldsView(fields: row.proposal.fields.map { .init(path: $0.path, token: $0.token, byteStart: $0.byteStart, byteEnd: $0.byteEnd) }) }.accessibilityIdentifier("fhirResultFields-\(index)")
            }
            LabHistoryField(label: "Reported unit", value: row.observation.unit)
            Text("Reported status: " + (row.observation.reportedStatus ?? "Not recorded")).font(.subheadline).foregroundStyle(Theme.secondary)
            DisclosureGroup("More reviewed fields") {
                VStack(alignment: .leading, spacing: 12) {
                    LabHistoryField(label: "Reported reference", value: row.observation.reference)
                    LabHistoryField(label: "Reported flag", value: row.observation.flag)
                    LabHistoryField(label: "Collection day", value: row.observation.collectedOn ?? "")
                    LabHistoryField(label: "Reported collection wording", value: row.observation.reportedTiming ?? "")
                    LabHistoryField(label: "Laboratory", value: row.observation.laboratory)
                    LabHistoryField(label: "Specimen", value: row.observation.specimen)
                    LabHistoryField(label: "Method", value: row.observation.method)
                }.padding(.top, 12)
            }
            LabHistoryToggle(title: "Include result", value: Binding(get: { self.draft?.results[index].included ?? false }, set: { self.draft?.results[index].included = $0; acknowledged = false }), identifier: "includeFHIRResult-\(index)")
            if let issue = row.sourceIssue { Text(issue).font(.footnote).foregroundStyle(Theme.secondary) }
            if let issue = row.observation.firstFieldIssue { Text(issue + " Correct the field or exclude this result.").font(.footnote).foregroundStyle(Theme.secondary) }
            if row.sourceValid && row.original != nil { Button("Edit result", systemImage: "pencil") { editing = row.observation }.frame(minHeight: 44).foregroundStyle(Theme.accent).accessibilityIdentifier("editFHIRResult-\(index)") }
            if !row.proposal.warnings.isEmpty {
                DisclosureGroup("Source context notes") { Text(row.proposal.warnings.joined(separator: "\n\n")).font(.footnote).fixedSize(horizontal: false, vertical: true).padding(.top, 8) }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("fhirResult-\(index)")
    }
    @ViewBuilder private func completion(_ document: HealthDocument) -> some View {
        if let document = companion.documents.first(where: { $0.id == document.id }) {
            LabHistoryHeading(text: "Lab results\nsaved.")
            Text(document.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            let count = document.labReport?.observations.count ?? 0
            Text("\(count) reviewed \(count == 1 ? "result" : "results") · assistant sharing \(document.includeInAssistant ? "on" : "off")").foregroundStyle(Theme.secondary).accessibilityIdentifier("fhirImportSaved")
            NavigationLink { DocumentDetailView(documentID: document.id) } label: { Text("View saved record").multilineTextAlignment(.center).padding(.horizontal, typeSize.isAccessibilitySize ? 24 : 16).padding(.vertical, typeSize.isAccessibilitySize ? 20 : 8) }.buttonStyle(FHIRPrimaryButtonStyle()).accessibilityIdentifier("viewFHIRRecord")
            Text("The saved record keeps selected source fields and its import receipt. Keep the original file separately.").font(.footnote).foregroundStyle(Theme.secondary)
        } else { LabHistoryHeading(text: "Record removed."); Text("The saved record is no longer in Library.") }
    }
    private func read(_ url: URL) {
        execute(title: "Reading FHIR file.", operation: { control in
            let input = try LabFileImportService.read(url, control: control)
            return try FHIRLabPreparation(archive: .init(data: input.data, filename: input.filename, control: control, now: input.readAt), control: control)
        }) { value in
            preparation = value; coverageReviewed = false; subjectKey = nil; personChecked = false; draft = nil; acknowledged = false; page = 0; step = .coverage
        }
    }
    private func personReferenceText(_ subject: FHIRLabPreparation.Subject) -> String {
        guard let preparation else { return subject.label }
        var fields: [FHIRLabPreparation.Field] = [], seen = Set<String>()
        for row in preparation.results where row.subject.key == subject.key {
            for field in row.fields {
                let directSubject = field.path == row.resourcePath + "/subject"
                let patientField = subject.resourcePath.map { path in
                    let prefix = path + "/"
                    return field.path.hasPrefix(prefix) && !field.path.dropFirst(prefix.count).contains("/")
                } ?? false
                if (directSubject || patientField) && seen.insert(field.path).inserted { fields.append(field) }
            }
        }
        return "Person label: " + subject.label + "\nFile: " + preparation.archive.filename + "\nInput SHA-256: " + preparation.archive.sha256 + "\n\n" +
            (fields.isEmpty ? "No original person-reference fields were supplied for this observation." : fields.map { $0.path + ":\n" + $0.token }.joined(separator: "\n\n")) +
            (subject.issues.isEmpty ? "" : "\n\n" + subject.issues.joined(separator: "\n"))
    }
    private func prepareDraft() {
        guard let preparation, let subjectKey else { return }
        let checked = personChecked, coverage = coverageReviewed
        execute(title: "Preparing review.", operation: { control in
            try control.checkCancellation()
            return try FHIRLabDraft(preparation: preparation, subjectKey: subjectKey, personChecked: checked, coverageReviewed: coverage, control: control)
        }) { value in draft = value; acknowledged = false; page = 0; step = .results }
    }
    private func save(allowDuplicate: Bool = false) {
        guard canSave, let draft else { return }
        if !allowDuplicate && draft.hasDuplicate(in: companion.documents) { duplicate = true; return }
        execute(title: "Preparing saved record.", operation: { control in try draft.document(acknowledged: true, control: control) }) { document in
            if !allowDuplicate && draft.hasDuplicate(in: companion.documents) { duplicate = true; return }
            guard !companion.documents.contains(where: { $0.id == document.id }) else { return }
            do { try companion.saveChecked(document) }
            catch { throw SaveFailure.storage }
            saved = document; preparation = nil; self.draft = nil; onSaved()
        }
    }
    private enum SaveFailure: LocalizedError {
        case storage
        var errorDescription: String? { "The results weren't saved. Check available storage and try again." }
    }
    @MainActor private func execute<Value: Sendable>(title: String, operation: @escaping @Sendable (BackupOperationControl) throws -> Value, accept: @escaping @MainActor (Value) throws -> Void) {
        guard control == nil else { return }
        let next = BackupOperationControl(), token = UUID()
        control = next; generation = token; stopping = false; status = nil; workTitle = title
        job = Task { @MainActor in
            do {
                let value = try await Task.detached(priority: .userInitiated) { try operation(next) }.value
                try next.checkCancellation(); guard generation == token && control === next else { return }
                try accept(value)
            } catch {
                guard generation == token && control === next else { return }
                if error is CancellationError || (try? next.checkCancellation()) == nil { status = "Cancelled. No record was saved." }
                else { self.error = error.localizedDescription }
            }
            guard generation == token && control === next else { return }
            control = nil; job = nil; stopping = false
        }
    }
    private func close() { generation = UUID(); control?.cancel(); job?.cancel(); preparation = nil; draft = nil; dismiss() }
}
