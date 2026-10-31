import SwiftUI

struct LabHistoryRecordPicker: View {
    @ObservedObject private var companion = CompanionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var query = ""
    @State private var page = 0
    @State private var reviewing = false
    @State private var personChecked = false
    @State private var control: BackupOperationControl?
    @State private var job: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var error: String?
    @State private var importing = false
    var onCancel: (() -> Void)?
    var notice: String?
    var onPrepared: (LabHistory.Selection) -> Void
    private let pageSize = 20
    init(selected: [String], notice: String? = nil, onCancel: (() -> Void)? = nil, onPrepared: @escaping (LabHistory.Selection) -> Void) {
        _selected = State(initialValue: Set(selected)); self.notice = notice; self.onCancel = onCancel; self.onPrepared = onPrepared
    }
    private var candidates: [HealthDocument] {
        companion.documents.filter { $0.kind == .record && ($0.labReport != nil || $0.labImportOrigin != nil) }.sorted {
            let a = $0.updatedAt.timeIntervalSince1970, b = $1.updatedAt.timeIntervalSince1970
            if a.isFinite && b.isFinite && a != b { return a > b }
            return $0.id < $1.id
        }
    }
    private var filtered: [HealthDocument] { candidates.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) } }
    private var currentPage: Int { min(page, max(0, (filtered.count - 1) / pageSize)) }
    private var pageRecords: [HealthDocument] { Array(filtered.dropFirst(currentPage * pageSize).prefix(pageSize)) }
    private var unavailable: Set<String> { selected.subtracting(Set(candidates.filter { !($0.labReport?.observations.isEmpty ?? true) }.map(\.id))) }
    var body: some View {
        Group {
            if control != nil { progress }
            else if reviewing { review }
            else { choices.searchable(text: $query, prompt: "Search record titles") }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if control != nil { Button("Cancel") { control?.cancel() }.accessibilityIdentifier("cancelLabHistoryPreparation") }
                else if reviewing { Button("Prepare") { prepare() }.disabled(!personChecked || selected.isEmpty || !unavailable.isEmpty).accessibilityIdentifier("prepareLabHistory") }
                else { Button("Review selection") { reviewing = true; personChecked = false }.disabled(selected.isEmpty || !unavailable.isEmpty).accessibilityIdentifier("reviewLabHistoryRecords") }
            }
        }
        .alert("Check the lab records", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .sheet(isPresented: $importing) { LabImportView { query = ""; page = 0; reviewing = false } }
        .onChange(of: query) { _, _ in page = 0 }
        .onReceive(companion.$documents.dropFirst()) { _ in
            personChecked = false
            if control != nil { control?.cancel() }
        }
        .onDisappear { generation = UUID(); control?.cancel(); job?.cancel() }
    }
    private var choices: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                LabHistoryHeading(text: "Choose the\nrecords.")
                if let notice { Text(notice).foregroundStyle(Theme.secondary) }
                Text("Select saved lab reports for one person.").foregroundStyle(Theme.secondary)
                Text("\(selected.count) \(selected.count == 1 ? "record" : "records") selected · up to \(LabHistory.maxRecords)").font(.headline).accessibilityIdentifier("labHistorySelectedRecords")
                unavailableNotice
                if candidates.isEmpty {
                    Text("No saved lab transcriptions. Import a lab file, or add results to a saved record.").foregroundStyle(Theme.secondary)
                    Button("Import lab results", systemImage: "tablecells") { importing = true }.buttonStyle(LumenPrimaryButtonStyle()).accessibilityIdentifier("historyImportLabResults")
                } else {
                    Text("Lumen checks each source for changes since its lab review.").font(.footnote).foregroundStyle(Theme.secondary)
                    if filtered.isEmpty { Text("No matching record titles.") }
                    ForEach(pageRecords) { document in recordChoice(document) }
                    LabHistoryPager(page: currentPage, count: filtered.count, size: pageSize) { page = $0 }
                }
                if let onCancel { Button("Keep current history", action: onCancel).frame(minHeight: 44) }
            }.padding(Theme.gutter).padding(.bottom, 24)
        }.lumenScreen()
    }
    private func recordChoice(_ document: HealthDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if selected.contains(document.id) { selected.remove(document.id) }
                else if selected.count < LabHistory.maxRecords { selected.insert(document.id) }
                personChecked = false
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selected.contains(document.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.accent)
                    Text(document.title.isEmpty ? "Untitled record" : document.title).font(.headline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(((document.labReport?.observations.isEmpty ?? true) && !selected.contains(document.id)) || (selected.count >= LabHistory.maxRecords && !selected.contains(document.id)))
                .accessibilityLabel(document.title.isEmpty ? "Untitled record" : document.title).accessibilityValue(selected.contains(document.id) ? "Selected" : "Not selected").accessibilityIdentifier("history-record-" + document.id)
            Text(personLabel(document)).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            let count = document.labReport?.observations.count ?? 0
            Text(count == 0 ? "No transcriptions" : "\(count.formatted()) saved \(count == 1 ? "transcription" : "transcriptions")").font(.footnote).foregroundStyle(Theme.secondary)
            NavigationLink("Open record") { DocumentDetailView(documentID: document.id) }.frame(minHeight: 44).foregroundStyle(Theme.accent).accessibilityIdentifier("history-open-record-" + document.id)
            Divider()
        }
    }
    private func personLabel(_ document: HealthDocument) -> String {
        guard let subject = document.originalLabImport?.subject else { return "Person label not recorded" }
        return subject.isEmpty ? "Blank source subject cell" : "Source subject: " + subject
    }
    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LabHistoryHeading(text: "Check the\nintended person.")
                Button("Back to records") { reviewing = false; personChecked = false }.frame(minHeight: 44).accessibilityIdentifier("historyBackToRecords")
                Text("Check these selected reports against the originals. A missing person label stays unknown.").foregroundStyle(Theme.secondary)
                unavailableNotice
                ForEach(candidates.filter { selected.contains($0.id) }) { document in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title.isEmpty ? "Untitled record" : document.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text(personLabel(document)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        NavigationLink("Open record") { DocumentDetailView(documentID: document.id) }.frame(minHeight: 44).foregroundStyle(Theme.accent)
                        Divider()
                    }
                }
                LabHistoryToggle(title: "I checked these records belong to the intended person", value: $personChecked, identifier: "labHistoryPersonChecked")
                Text("This history stays on this device. Source sharing settings remain unchanged.").font(.footnote).foregroundStyle(Theme.secondary)
            }.padding(Theme.gutter).padding(.bottom, 24)
        }.lumenScreen()
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: 24) {
            LabHistoryHeading(text: "Checking\nsaved sources.")
            ProgressView("Preparing local lab history")
            Text("No record is changed or saved by preparation.").foregroundStyle(Theme.secondary)
            Spacer()
        }.padding(Theme.gutter).lumenScreen()
    }
    @ViewBuilder private var unavailableNotice: some View {
        if !unavailable.isEmpty {
            Text("\(unavailable.count) selected \(unavailable.count == 1 ? "record has" : "records have") no available lab transcriptions. No results will be silently omitted.").foregroundStyle(Theme.secondary)
            Button("Remove unavailable selections") { selected.subtract(unavailable); personChecked = false }.frame(minHeight: 44).accessibilityIdentifier("historyRemoveUnavailableSelections")
        }
    }
    private func prepare() {
        guard control == nil, personChecked, !selected.isEmpty else { return }
        let next = BackupOperationControl(), token = UUID(), documents = companion.documents
        let ids = selected.sorted()
        control = next; generation = token
        job = Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) { try LabHistory.prepare(recordIDs: ids, documents: documents, control: next) }.value
                try next.checkCancellation(); guard generation == token else { return }
                control = nil; job = nil; onPrepared(result)
            } catch {
                guard generation == token else { return }
                control = nil; job = nil; personChecked = false
                if error is CancellationError { self.error = "Preparation cancelled. No comparison was saved." }
                else { self.error = error.localizedDescription }
            }
        }
    }
}

struct LabHistoryHeading: View {
    let text: String
    var body: some View { Text(text).font(.system(.largeTitle, weight: .bold)).fontWidth(.expanded).tracking(-1).fixedSize(horizontal: false, vertical: true) }
}
struct LabHistoryToggle: View {
    let title: String
    @Binding var value: Bool
    let identifier: String
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) { Text(title).fixedSize(horizontal: false, vertical: true); Toggle(title, isOn: $value).labelsHidden().accessibilityLabel(title).accessibilityIdentifier(identifier) }
        } else { Toggle(title, isOn: $value).accessibilityIdentifier(identifier) }
    }
}
struct LabHistoryPager: View {
    let page: Int
    let count: Int
    let size: Int
    var onPage: (Int) -> Void
    private var last: Int { max(0, (count - 1) / size) }
    var body: some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("\((page * size + 1).formatted())–\(min(count, (page + 1) * size).formatted()) of \(count.formatted())").font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("labHistoryPageCount")
                if last > 0 {
                    HStack { Button("Previous") { onPage(max(0, page - 1)) }.disabled(page == 0).accessibilityIdentifier("historyPreviousPage"); Spacer(); Button("Next") { onPage(min(last, page + 1)) }.disabled(page == last).accessibilityIdentifier("historyNextPage") }.buttonStyle(.bordered)
                }
            }
        }
    }
}
