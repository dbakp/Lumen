import SwiftUI
import UniformTypeIdentifiers

struct LabImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var companion = CompanionStore.shared
    var onSaved: () -> Void
    private enum Step { case mapping, subject, review }
    @State private var step = Step.mapping
    @State private var choosing = false
    @State private var input: LabFileImportService.Input?
    @State private var table: LabTable?
    @State private var separator = ""
    @State private var mapping: [String: String] = [:]
    @State private var subject: String?
    @State private var personChecked = false
    @State private var draft: LabFileDraft?
    @State private var page = 0
    @State private var acknowledged = false
    @State private var editing: LabObservation?
    @State private var saved: HealthDocument?
    @State private var control: BackupOperationControl?
    @State private var job: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var stopping = false
    @State private var workTitle = "Reading lab results."
    @State private var status: String?
    @State private var error: String?
    @State private var errorTitle = "Couldn't read lab file"
    @State private var discard = false
    @State private var backToMapping = false
    @State private var duplicate = false
    @State private var editingTitle = false
    private let pageSize = 10
    private let acknowledgement = "I checked the included results and their sources"
    private func separatorMatches(_ table: LabTable) -> Bool {
        table.format == "json" || table.separator == (separator.isEmpty ? (table.filename.lowercased().hasSuffix(".tsv") ? "\t" : ",") : separator)
    }
    private var hasDraft: Bool { saved == nil && (input != nil || draft != nil || control != nil) }
    private var canSave: Bool {
        guard control == nil, saved == nil, let draft else { return false }
        return acknowledged && LabReport.bounded(draft.title, limit: 500, required: true) &&
        (1...LabReport.maxObservations).contains(draft.includedCount) && draft.results.filter(\.included).allSatisfy { $0.sourceValid && $0.observation.isValid }
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 1).id("labImportTop")
                        if let saved { completion(saved) }
                        else if control != nil {
                            heading(stopping ? "Stopping." : workTitle)
                            ProgressView(stopping ? "Stopping local work" : "Reading on this device")
                            Text("No record is saved until you review and confirm.").foregroundStyle(Theme.secondary)
                        } else if let table {
                            switch step {
                            case .mapping: columnMapping(table)
                            case .subject: subjectSelection(table)
                            case .review: resultReview
                            }
                        } else { landing }
                    }.padding(Theme.gutter).padding(.bottom, 24)
                }.lumenScreen().scrollDismissesKeyboard(.interactively)
                    .onChange(of: step) { _, _ in proxy.scrollTo("labImportTop", anchor: .top) }
                    .onChange(of: page) { _, _ in proxy.scrollTo("labImportTop", anchor: .top) }
                    .onChange(of: saved?.id) { _, _ in proxy.scrollTo("labImportTop", anchor: .top) }
                    .onChange(of: control != nil) { _, active in if !active { proxy.scrollTo("labImportTop", anchor: .top) } }
            }
            .navigationTitle(saved == nil ? "Import lab results" : "Saved lab results").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved != nil ? "Done" : (stopping ? "Stopping…" : "Cancel")) {
                        if let control { stopping = true; control.cancel() }
                        else if hasDraft { discard = true } else { close() }
                    }.disabled(stopping).accessibilityIdentifier("cancelLabImport")
                }
                if step == .review && draft != nil && saved == nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold).disabled(!canSave).accessibilityIdentifier("saveLabImport") }
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [UTType(filenameExtension: "csv") ?? .plainText, UTType(filenameExtension: "tsv") ?? .plainText, .json]) { result in
                switch result {
                case .success(let url): read(url)
                case .failure(let failure): errorTitle = "Couldn't open lab file"; error = failure.localizedDescription
                }
            }
            .sheet(item: $editing) { value in
                if let row = draft?.results.first(where: { $0.observation.id == value.id }) {
                    LabObservationEditor(observation: value, sourceBody: row.sourceText, allowSourceChange: false) { corrected in
                        guard let index = draft?.results.firstIndex(where: { $0.observation.id == corrected.id }) else { return }
                        draft?.results[index].observation = corrected; acknowledged = false
                    }
                }
            }
            .sheet(isPresented: $editingTitle) {
                LabTextEditor(text: draft?.title ?? "", title: "Record title", limit: 500, required: true, identifier: "labImportTitle", doneIdentifier: "finishLabImportTitle") { value in draft?.title = value; acknowledged = false }
            }
            .alert(errorTitle, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .alert("Discard this lab import?", isPresented: $discard) { Button("Discard draft", role: .destructive) { close() }; Button("Keep reviewing", role: .cancel) {} } message: { Text("The original file stays unchanged. No record has been saved.") }
            .alert("Return to column mapping?", isPresented: $backToMapping) { Button("Discard row review", role: .destructive) { draft = nil; acknowledged = false; personChecked = false; step = .mapping }; Button("Keep reviewing", role: .cancel) {} } message: { Text("This discards row corrections, exclusions and the record title. Check the person and results again after changing the mapping.") }
            .alert("Save another copy?", isPresented: $duplicate) { Button("Save another copy") { save(allowDuplicate: true) }; Button("Keep reviewing", role: .cancel) {} } message: { Text("A record from this exact file is already in Library. Saving adds a separate record.") }
            .background(SheetDismissGuard(hasEdits: hasDraft) { if let control { stopping = true; control.cancel() } else { discard = true } })
            .onDisappear { generation = UUID(); control?.cancel(); job?.cancel(); input = nil; table = nil; draft = nil }
        }.tint(Theme.accent)
    }
    private func heading(_ value: String) -> some View { Text(value).font(.system(.largeTitle, weight: .bold)).fontWidth(.expanded).tracking(-1) }
    private var landing: some View {
        Group {
            heading("Bring in\nlab results.")
            Text("Choose a table export, then check its columns, person and results before saving.").foregroundStyle(Theme.secondary)
            Button("Choose a file", systemImage: "doc.badge.plus") { choosing = true }.buttonStyle(LumenPrimaryButtonStyle()).accessibilityIdentifier("chooseLabFile")
            Text("UTF-8 CSV, TSV or flat JSON. Up to 2 MB, 1,024 data rows and 64 columns.").font(.footnote).foregroundStyle(Theme.secondary)
            separatorPicker
            if let input {
                Text(input.filename).font(.subheadline).foregroundStyle(Theme.secondary)
                Button("Read with this separator") { parse(input) }.buttonStyle(LumenTonalButtonStyle()).accessibilityIdentifier("retryLabSeparator")
            }
            Text("The original file stays separate. Lumen doesn't interpret these results or add them to Apple Health.").font(.footnote).foregroundStyle(Theme.secondary)
            if let status { Text(status).foregroundStyle(Theme.secondary).accessibilityIdentifier("labImportStatus") }
        }
    }
    private var separatorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Separator").font(.headline)
            choiceMenu("Separator", selection: $separator, choices: [.init(id: "", label: "File default"), .init(id: ",", label: "Comma"), .init(id: ";", label: "Semicolon"), .init(id: "\t", label: "Tab")], identifier: "labSeparator")
            Text("CSV defaults to comma; TSV to tab. JSON ignores this choice.").font(.footnote).foregroundStyle(Theme.secondary)
        }
    }
    private func columnMapping(_ table: LabTable) -> some View {
        Group {
            heading("Match the\ncolumns.")
            Text(table.filename).font(.headline).accessibilityIdentifier("labTableReady")
            Text("\(table.rows.count) data \(table.rows.count == 1 ? "row" : "rows") · \(table.headers.count) \(table.headers.count == 1 ? "column" : "columns") · \(table.blankRows) blank \(table.blankRows == 1 ? "row" : "rows") skipped").font(.subheadline).foregroundStyle(Theme.secondary)
            Text("Check every suggested match. Use each column once; unmapped columns won't be saved.").font(.subheadline).foregroundStyle(Theme.secondary)
            ForEach(LabColumn.allCases, id: \.rawValue) { field in
                VStack(alignment: .leading, spacing: 8) {
                    Text(field.label + ([LabColumn.test, .result].contains(field) ? " · required" : "")).font(.headline)
                    choiceMenu(field.label, selection: Binding(get: { mapping[field.rawValue] ?? "" }, set: { mapping[field.rawValue] = $0.isEmpty ? nil : $0; subject = nil; personChecked = false }), choices: [.init(id: "", label: "Not mapped")] + table.headers.map { .init(id: $0, label: $0) }, identifier: "labColumn-\(field.rawValue)")
                    if let column = mapping[field.rawValue], let sample = table.rows.first?.cells[column]?.value, !sample.isEmpty {
                        Text("First row: " + displayText(sample, limit: 160) + (LabTable.displayPreview(sample, maxCharacters: 160).truncated ? " … (preview)" : "")).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !table.validates(mapping) { Text("Choose separate columns for test name and result. Each source column can be used once.").font(.footnote).foregroundStyle(Theme.secondary) }
            if !separatorMatches(table) { Text("Separator changed. Read the columns again before continuing.").font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("labSeparatorNeedsRead") }
            Button("Continue") { guard table.validates(mapping), separatorMatches(table) else { return }; subject = mapping["subject"] == nil ? "" : nil; personChecked = false; step = .subject }.buttonStyle(LumenPrimaryButtonStyle()).disabled(!table.validates(mapping) || !separatorMatches(table)).opacity(table.validates(mapping) && separatorMatches(table) ? 1 : 0.45).accessibilityIdentifier("continueLabMapping")
            if table.format != "json" {
                DisclosureGroup("Change separator") { separatorPicker; Button("Read columns again") { if let input { parse(input) } }.frame(minHeight: 44) }
            }
        }
    }
    private func subjectSelection(_ table: LabTable) -> some View {
        Group {
            heading("Check the\nintended person.")
            if let column = mapping["subject"] {
                Text("Subject column: " + column).font(.headline)
                Text("Choose one person or identifier from the file. Blank entries stay separate.").font(.subheadline).foregroundStyle(Theme.secondary)
                ForEach(Array(table.subjects(mapping: mapping).enumerated()), id: \.offset) { pair in
                    let value = pair.element
                    let count = table.rows.filter { ($0.cells[column]?.value ?? "") == value }.count
                    Button { subject = value; personChecked = false } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: subject == value ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(subjectLabel(value)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                                Text("\(count) data \(count == 1 ? "row" : "rows")").font(.footnote).foregroundStyle(Theme.secondary)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("labSubject-\(pair.offset)").accessibilityAddTraits(subject == value ? .isSelected : [])
                }
            } else {
                Text("No subject column mapped").font(.headline)
                Text("\(table.rows.count) \(table.rows.count == 1 ? "row is" : "rows are") in one group. Check that these are the intended person's results. Go back and map a subject column if needed.").foregroundStyle(Theme.secondary)
            }
            reviewToggle("I checked the intended person against the original file", value: $personChecked, identifier: "labPersonChecked")
            Button("Review results") { prepareReview(table) }.buttonStyle(LumenPrimaryButtonStyle()).disabled(subject == nil || !personChecked).opacity(subject != nil && personChecked ? 1 : 0.45).accessibilityIdentifier("reviewLabImport")
            Button("Back to mapping") { personChecked = false; step = .mapping }.buttonStyle(LumenTonalButtonStyle())
        }
    }
    @ViewBuilder private var resultReview: some View {
        if let draft {
            heading("Check the\nimported results.")
            Text(mapping["subject"] == nil ? "No subject column mapped · person checked" : subjectLabel(draft.subject)).font(.subheadline).foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Record title").font(.headline)
                LabTextEditButton(text: draft.title, title: "Record title", identifier: "labImportTitle") { editingTitle = true }
                if let issue = LabReport.textIssue(draft.title, limit: 500, required: true) { Text(issue.message(for: "Record title")).font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("labImportTitleIssue") }
            }
            Text("\(draft.includedCount) of \(draft.results.count) \(draft.results.count == 1 ? "result" : "results") included").font(.headline).accessibilityIdentifier("labImportIncludedCount")
            Menu("Result selection") {
                Button("Include all results") { for index in self.draft?.results.indices ?? 0..<0 { self.draft?.results[index].included = true }; acknowledged = false }
                Button("Exclude all results") { for index in self.draft?.results.indices ?? 0..<0 { self.draft?.results[index].included = false }; acknowledged = false }
            }.frame(minHeight: 44).accessibilityIdentifier("labImportSelection")
            if draft.includedCount > LabReport.maxObservations { Text("Keep up to 256 results in one record. Exclude rows or split the original file.").foregroundStyle(Theme.secondary) }
            ForEach(Array(draft.results.enumerated().dropFirst(page * pageSize).prefix(pageSize)), id: \.element.id) { pair in
                importedRow(pair.element, index: pair.offset)
                Divider()
            }
            if draft.results.count > pageSize {
                VStack(alignment: .leading, spacing: 12) {
                    choiceMenu("Result page", selection: Binding(get: { String(page) }, set: { if let index = Int($0), index >= 0, index * pageSize < draft.results.count { page = index } }), choices: (0..<((draft.results.count + pageSize - 1) / pageSize)).map { index in
                        .init(id: String(index), label: "Results \(index * pageSize + 1)–\(min((index + 1) * pageSize, draft.results.count))")
                    }, identifier: "labImportPagePicker")
                    HStack {
                    Button("Previous") { page -= 1 }.disabled(page == 0)
                    Spacer(minLength: 8)
                    Button("Next") { page += 1 }.disabled((page + 1) * pageSize >= draft.results.count)
                    }.frame(minHeight: 44)
                }
            }
            reviewToggle(acknowledgement, value: Binding(get: { acknowledged }, set: { acknowledged = $0 }), identifier: "acknowledgeLabImport")
            Text("Saving keeps only included mapped cells and reviewed fields. Assistant sharing starts off. Keep the original file separately.").font(.footnote).foregroundStyle(Theme.secondary)
            Button("Back to mapping") { backToMapping = true }.buttonStyle(LumenTonalButtonStyle()).accessibilityIdentifier("labImportBackToMapping")
        }
    }
    private func importedRow(_ row: LabFileDraft.Result, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data row \(row.id)").font(.footnote).foregroundStyle(Theme.secondary)
            Text(row.observation.test.isEmpty ? "Test name needed" : displayText(row.observation.test, limit: 200)).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(displayText(row.observation.result + (row.observation.unit.isEmpty ? "" : " " + row.observation.unit), limit: 600)).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if !row.observation.flag.isEmpty { Text("Reported flag: " + displayText(row.observation.flag, limit: 200)).font(.subheadline).foregroundStyle(Theme.secondary) }
            Text("Reported status: " + (row.observation.reportedStatus.map { displayText($0, limit: 200) } ?? "Not recorded")).font(.subheadline).foregroundStyle(Theme.secondary)
            Text("Reported collection wording: " + (row.observation.reportedTiming.map { displayText($0, limit: 500) } ?? "Not recorded")).font(.subheadline).foregroundStyle(Theme.secondary)
            Text("Collection day: " + (row.observation.collectedOn ?? "Not recorded")).font(.footnote).foregroundStyle(Theme.secondary)
            reviewToggle("Include result", value: Binding(get: { self.draft?.results[index].included ?? false }, set: { self.draft?.results[index].included = $0; acknowledged = false }), identifier: "includeLabImport-\(row.id)")
            if [(row.observation.test, 200), (row.observation.result, 500), (row.observation.unit, 100), (row.observation.reportedStatus ?? "", 200), (row.observation.reportedTiming ?? "", 500), (row.observation.flag, 200)].contains(where: { LabTable.displayPreview($0.0, maxCharacters: $0.1).truncated }) { Text("Field preview only. Correct the overlong field or exclude this result.").font(.footnote).foregroundStyle(Theme.secondary) }
            if !row.sourceValid { Text(sourceIssue(row)).font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("labImportSourceIssue-\(row.id)") }
            else {
                Button("Edit result", systemImage: "pencil") { editing = row.observation }.frame(minHeight: 44).accessibilityIdentifier("editLabImport-\(row.id)")
                if let issue = row.observation.firstFieldIssue { Text(issue + " Correct it using the original, or exclude this row.").font(.footnote).foregroundStyle(Theme.secondary) }
            }
            DisclosureGroup("Mapped source cells") {
                let source = LabTable.displayPreview(row.sourceText, maxCharacters: 2000)
                Text(source.text.isEmpty ? "Source text is too large to preview." : source.text).font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.top, 8)
                if source.truncated { Text("Preview only. This row can't be saved while included. Check the original file.").font(.footnote).foregroundStyle(Theme.secondary) }
                Text("Original cell values arranged by Lumen, not the original file layout.").font(.footnote).foregroundStyle(Theme.secondary)
            }.accessibilityIdentifier("labImportSource-\(row.id)")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("labImportRow-\(row.id)")
    }
    private func reviewToggle(_ label: String, value: Binding<Bool>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize { Text(label).fixedSize(horizontal: false, vertical: true); Toggle(label, isOn: value).labelsHidden().accessibilityLabel(label).accessibilityIdentifier(identifier) }
            else { Toggle(label, isOn: value).accessibilityIdentifier(identifier) }
        }
    }
    private func sourceIssue(_ row: LabFileDraft.Result) -> String {
        let action = " Exclude this row or map fewer optional columns."
        switch LabReport.textIssue(row.sourceText, limit: 2000, required: true) {
        case .characters(let limit): return "These source cells exceed the \(limit.formatted())-character limit." + action
        case .bytes(let limit): return "These source cells exceed the \(limit.formatted())-byte limit." + action
        case .controls: return "These source cells contain unsupported control characters." + action
        case .required, .blank: return "These source cells have no visible text. Exclude this row or check the column mapping."
        case nil: return "These source cells no longer match this draft. Go back to mapping and prepare the review again."
        }
    }
    private func completion(_ document: HealthDocument) -> some View {
        Group {
            if let document = companion.documents.first(where: { $0.id == document.id }) {
            heading("Lab results\nsaved.")
            Text(document.title).font(.title2.weight(.semibold))
            let count = document.labReport?.observations.count ?? 0
            Text("\(count) reviewed \(count == 1 ? "result" : "results") · assistant sharing \(document.includeInAssistant ? "on" : "off")").foregroundStyle(Theme.secondary).accessibilityIdentifier("labImportSaved")
            NavigationLink { DocumentDetailView(documentID: document.id) } label: { Text("View saved record").multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 8) }.buttonStyle(LumenPrimaryButtonStyle()).accessibilityIdentifier("viewImportedLabRecord")
            Text("Keep the original file separately. The saved record contains your included fields and mapped source cells.").font(.footnote).foregroundStyle(Theme.secondary)
            } else { heading("Record removed."); Text("The imported record is no longer in Library.").foregroundStyle(Theme.secondary) }
        }
    }
    private func subjectLabel(_ value: String) -> String {
        if value.isEmpty { return "Blank subject cell" }
        let preview = LabTable.displayPreview(value, maxCharacters: 500)
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Spaces or line breaks only: " + preview.text.debugDescription + (preview.truncated ? " (preview; label is too long)" : "") }
        return displayText(value, limit: 500) + (preview.truncated ? " … (preview; label is too long)" : "")
    }
    private func displayText(_ value: String, limit: Int) -> String {
        let preview = LabTable.displayPreview(value, maxCharacters: limit)
        return preview.text.isEmpty && !value.isEmpty ? "Value too large to preview" : preview.text
    }
    private struct MenuChoice: Identifiable { let id: String; let label: String }
    /// Native choices, with a label that grows to show every line. The built-in
    /// menu Picker label crops multiline values at actual XXXL.
    private func choiceMenu(_ title: String, selection: Binding<String>, choices: [MenuChoice], identifier: String) -> some View {
        let selected = choices.first { $0.id == selection.wrappedValue }?.label ?? selection.wrappedValue
        return Menu {
            Picker(title, selection: selection) { ForEach(choices) { Text($0.label).tag($0.id) } }.pickerStyle(.inline)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(selected).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).imageScale(.small).fixedSize().padding(.top, 4)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityLabel(title).accessibilityValue(selected).accessibilityIdentifier(identifier)
    }
    private func read(_ url: URL) {
        begin { next in try LabFileImportService.read(url, control: next) }
    }
    private func parse(_ input: LabFileImportService.Input) { begin { _ in input } }
    private func begin(_ load: @escaping @Sendable (BackupOperationControl) throws -> LabFileImportService.Input) {
        guard control == nil else { return }
        let next = BackupOperationControl(), token = UUID(); control = next; generation = token; stopping = false; status = nil
        workTitle = "Reading lab results."
        input = nil; table = nil; draft = nil
        let delimiter = separator
        job = Task { @MainActor in
            do {
                let value = try await Task.detached(priority: .userInitiated) { try load(next) }.value
                try next.checkCancellation(); guard generation == token && control === next else { return }
                input = value; table = nil; draft = nil
                let parsed = try await Task.detached(priority: .userInitiated) { try value.parse(separator: value.filename.lowercased().hasSuffix(".json") || delimiter.isEmpty ? nil : delimiter, control: next) }.value
                try next.checkCancellation(); guard generation == token && control === next else { return }
                table = parsed; mapping = parsed.suggestedMapping; subject = nil; personChecked = false; acknowledged = false; page = 0; step = .mapping
            } catch {
                guard generation == token && control === next else { return }
                if error is CancellationError || (try? next.checkCancellation()) == nil { input = nil; table = nil; draft = nil; status = "Reading cancelled. No record was saved." }
                else { errorTitle = "Couldn't read lab file"; self.error = error.localizedDescription }
            }
            guard generation == token && control === next else { return }
            control = nil; job = nil; stopping = false
        }
    }
    private func prepareReview(_ table: LabTable) {
        guard let subject, control == nil else { return }
        let next = BackupOperationControl(), token = UUID(), columns = mapping, checked = personChecked
        control = next; generation = token; stopping = false; workTitle = "Preparing review."
        job = Task { @MainActor in
            do {
                let value = try await Task.detached(priority: .userInitiated) { try next.checkCancellation(); return try LabFileDraft(table: table, mapping: columns, subject: subject, personChecked: checked) }.value
                try next.checkCancellation(); guard generation == token && control === next else { return }
                draft = value; acknowledged = false; page = 0; step = .review
            } catch {
                guard generation == token && control === next else { return }
                if error is CancellationError || (try? next.checkCancellation()) == nil { personChecked = false }
                else { errorTitle = "Check the lab mapping"; self.error = error.localizedDescription }
            }
            guard generation == token && control === next else { return }
            control = nil; job = nil; stopping = false
        }
    }
    private func save(allowDuplicate: Bool = false) {
        guard canSave, let draft else { return }
        do {
            if !allowDuplicate && draft.hasDuplicate(in: companion.documents) { duplicate = true; return }
            let document = try draft.document(acknowledged: acknowledged)
            guard !companion.documents.contains(where: { $0.id == document.id }) else { return }
            try companion.saveChecked(document)
            saved = document; input = nil; table = nil; self.draft = nil; onSaved()
        } catch { errorTitle = "Couldn't save lab results"; self.error = error is LabFileDraft.Failure ? error.localizedDescription : "The lab results weren't saved. Check available storage and try again." }
    }
    private func close() { generation = UUID(); control?.cancel(); job?.cancel(); input = nil; table = nil; draft = nil; dismiss() }
}
