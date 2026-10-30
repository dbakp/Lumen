import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var health: HealthStore
    @ObservedObject private var companion = CompanionStore.shared
    @State private var search = ""
    @State private var kind: HealthDocument.Kind?
    @State private var importing = false
    @State private var recordWorkspace: RecordWorkspace?
    @State private var editing: HealthDocument?
    var filtered: [HealthDocument] {
        companion.documents.filter { (kind == nil || $0.kind == kind) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("A place for\nyour next steps.").font(.system(.largeTitle, weight: .bold)).fontWidth(.expanded).tracking(-1)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        filterButton("All", value: nil)
                        ForEach(HealthDocument.Kind.allCases, id: \.self) { filterButton($0.rawValue.capitalized, value: $0) }
                    }
                }.scrollIndicators(.hidden)
                NavigationLink { InsightsView() } label: {
                    LumenRow("Insights & appointment summaries", subtitle: "Changes over time and a record to share", icon: "chart.xyaxis.line", color: Theme.accent)
                }.buttonStyle(.plain)
                NavigationLink { PlanAgendaView() } label: {
                    LumenRow("Your next steps", subtitle: "Pending actions from your active plans", icon: "list.bullet", color: Theme.accent)
                }.buttonStyle(.plain)
                if filtered.isEmpty {
                    EmptyStateCard(icon: "doc.text", title: search.isEmpty ? "Keep what matters" : "No matching documents", message: "Plans from your assistant, weekly reviews and your own records live here.", actionTitle: "Write a note") { newNote() }
                }
                ForEach(filtered) { doc in
                    NavigationLink { DocumentDetailView(documentID: doc.id) } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: doc.kind == .plan ? "list.bullet.clipboard" : "doc.text").font(.title2).foregroundStyle(Theme.accent).frame(width: 32)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(doc.title).font(.headline).foregroundStyle(Theme.text)
                                Text(doc.body).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(2)
                                Text("\(doc.kind.rawValue.capitalized) · \(doc.updatedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.tertiary)
                                if doc.extraction != nil { Text("Reviewed import").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
                                if doc.kind == .plan { Text(doc.status.label).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
                                if !doc.steps.isEmpty { Text("\(doc.steps.filter(\.isDone).count) of \(doc.steps.count) \(doc.steps.count == 1 ? "step" : "steps") completed").font(.caption).foregroundStyle(Theme.accent) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.tertiary)
                        }.padding(20).surface()
                    }.buttonStyle(.plain)
                        .accessibilityLabel(doc.title)
                        .accessibilityHint("\(doc.kind.rawValue.capitalized). Opens saved document.")
                        .accessibilityIdentifier("library-\(doc.kind.rawValue)-\(doc.id)")
                }
                Button("Create this week's review", systemImage: "calendar") {
                    companion.weeklyReview(health: health); AppRouter.shared.confirm("Weekly review saved")
                }.buttonStyle(LumenTonalButtonStyle())
                NavigationLink { ConnectionsView() } label: { Label("Connections & imports", systemImage: "externaldrive.badge.plus") }.frame(minHeight: 44)
            }.padding(Theme.gutter).padding(.bottom, 24)
        }.lumenScreen().navigationTitle("Library").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search plans and records")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Write a note", systemImage: "square.and.pencil") { newNote() }
                        Button("Import a record", systemImage: "doc.badge.plus") { importing = true }
                    } label: { Image(systemName: "plus") }.accessibilityLabel("Add document")
                }
            }
            .sheet(item: $editing) { DocumentEditor(document: $0) }
            .sheet(isPresented: $importing, onDismiss: { recordWorkspace?.cleanup(); recordWorkspace = nil }) {
                RecordImportView(onWorkspaceReady: { recordWorkspace = $0 }) { kind = .record; search = "" }
            }

    }
    func filterButton(_ title: String, value: HealthDocument.Kind?) -> some View {
        Button(title) { kind = value }
            .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 44)
            .background(kind == value ? Theme.accent : Theme.surfaceRaised, in: Capsule())
            .foregroundStyle(kind == value ? Theme.onAccent : Theme.secondary)
            .accessibilityAddTraits(kind == value ? .isSelected : [])
    }
    func newNote() { editing = HealthDocument(title: "", kind: .note, body: "", source: "Your note") }

}

struct DocumentDetailView: View {
    let documentID: String
    @ObservedObject private var companion = CompanionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HealthDocument?
    @State private var confirmDelete = false
    @State private var mutationError: String?
    var document: HealthDocument? { companion.documents.first { $0.id == documentID } }
    var body: some View {
        ScrollView {
            if let doc = document {
                VStack(alignment: .leading, spacing: 24) {
                    Text(doc.title).font(.largeTitle.bold()).tracking(-1)
                    Text("\(doc.source)\nUpdated \(doc.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary)
                    if let extraction = doc.extraction {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reviewed imported text").font(.headline)
                            Text("\(extraction.pages.count.formatted()) source page\(extraction.pages.count == 1 ? "" : "s") · \(extraction.recognizedPages.formatted()) from text recognition").font(.subheadline).foregroundStyle(Theme.secondary)
                            Text("Import review: \(extraction.reviewedAt.formatted(date: .abbreviated, time: .shortened)). Keep the original file separately. This text can still contain errors.").font(.footnote).foregroundStyle(Theme.secondary)
                            let excluded = extraction.pages.filter { $0.method == .excluded }.count
                            if excluded > 0 { Text("\(excluded.formatted()) source page\(excluded == 1 ? "" : "s") excluded from the saved text.").font(.footnote).foregroundStyle(Theme.secondary) }
                            if extraction.laterEditedAt != nil { Text("Text was edited after the import review.").font(.footnote).foregroundStyle(Theme.secondary) }
                        }
                    }
                    if doc.kind == .plan { Text(doc.status.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent) }
                    if doc.kind != .plan || doc.steps.isEmpty { DocumentBodyView(text: doc.body) }
                    if doc.kind == .plan && !doc.steps.isEmpty { GroupLabel("Your plan steps") }
                    ForEach(doc.steps) { step in
                        Button {
                            var updated = doc
                            if let i = updated.steps.firstIndex(where: { $0.id == step.id }) { updated.steps[i].isDone.toggle(); do { try companion.saveChecked(updated) } catch { mutationError = "Your change wasn't saved. Try again." } }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.title).strikethrough(step.isDone)
                                    if let due = step.dueDate { Text("Due " + due.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Theme.secondary) }
                                }
                                Spacer()
                            }.frame(minHeight: 44).foregroundStyle(step.isDone ? Theme.secondary : Theme.text)
                        }.buttonStyle(.plain).accessibilityLabel("\(step.isDone ? "Completed" : "Incomplete"): \(step.title)")
                    }
                    if doc.kind == .plan && !doc.steps.isEmpty {
                        DisclosureGroup("Original guidance") { DocumentBodyView(text: doc.body).padding(.top, 12) }
                    }
                    if let context = doc.recordContext, context.mode != .guide { RecordSourcesView(context: context) }
                    Text(doc.kind == .plan ? "An editable wellness draft. Adjust it to how you feel; discuss medical decisions with a clinician." : "Saved on this device. You control whether the assistant can use this text.").font(.footnote).foregroundStyle(Theme.secondary)
                    Toggle("Use in assistant", isOn: Binding(get: { doc.includeInAssistant }, set: { var d = doc; d.includeInAssistant = $0; do { try companion.saveChecked(d) } catch { mutationError = "The sharing setting wasn't saved. It is still set as shown. Try again." } }))
                    Text("When enabled, matching text can be sent with your questions to the AI provider selected in Settings. Turning this off stops future retrieval. Earlier replies and saved copies keep their excerpts.").font(.footnote).foregroundStyle(Theme.secondary)
                }.padding(Theme.gutter)
            }
        }.lumenScreen().navigationTitle("Document").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let doc = document {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit", systemImage: "pencil") { editing = doc }
                            ShareLink(item: doc.markdown) { Label("Share document", systemImage: "square.and.arrow.up") }
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Document actions")
                    }
                }
            }
            .sheet(item: $editing) { DocumentEditor(document: $0) }
            .alert("Couldn't update document", isPresented: Binding(get: { mutationError != nil }, set: { if !$0 { mutationError = nil } })) { Button("OK") { mutationError = nil } } message: { Text(mutationError ?? "") }
            .alert("Delete this document?", isPresented: $confirmDelete) {
                Button("Keep document", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    do { try companion.deleteDocumentChecked(documentID); dismiss() }
                    catch { mutationError = "The document wasn't deleted. Try again." }
                }
            } message: { Text("Earlier replies and saved copies keep their excerpts. Delete those separately if you want to remove them too.") }
    }
}

struct DocumentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var document: HealthDocument
    @State private var saveError: String?
    @State private var discardEdits = false
    private let original: Data
    init(document: HealthDocument) {
        _document = State(initialValue: document)
        original = Self.encoded(document)
    }
    private static func encoded(_ value: HealthDocument) -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)) ?? Data()
    }
    private var hasEdits: Bool { Self.encoded(document) != original }
    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Document title", text: $document.title) }
                if document.kind == .plan {
                    Section("Plan status") {
                        Picker("Status", selection: Binding(get: { document.status }, set: { document.planState = $0 })) {
                            ForEach(PlanState.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                }
                Section("Content") { TextEditor(text: $document.body).frame(minHeight: 280) }
                Section("Checklist") {
                    ForEach($document.steps) { $step in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Step", text: $step.title, axis: .vertical)
                            Toggle("Completed", isOn: $step.isDone)
                            Toggle("Set a date", isOn: Binding(get: { step.dueDate != nil }, set: { step.dueDate = $0 ? (step.dueDate ?? Date()) : nil })).accessibilityIdentifier("plan-date-\(step.id)")
                            if step.dueDate != nil {
                                DatePicker("Date", selection: Binding(get: { step.dueDate ?? Date() }, set: { step.dueDate = $0 }), displayedComponents: .date)
                            }
                        }.padding(.vertical, 6)
                    }.onDelete { document.steps.remove(atOffsets: $0) }
                    Button("Add a step", systemImage: "plus") { document.steps.append(PlanStep(title: "")) }
                }
                Section {
                    Toggle("Use in assistant", isOn: $document.includeInAssistant)
                } footer: { Text("Excerpts may be sent to your selected AI provider when you chat. Leave off to keep this record out of assistant context.") }
            }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Edit document").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasEdits { discardEdits = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        do {
                            document.steps = document.steps.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            try CompanionStore.shared.saveChecked(document); dismiss()
                        } catch { saveError = "Your changes were not saved. Try again." }
                    }.fontWeight(.bold).disabled(document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.tint(Theme.accent)
            .background(SheetDismissGuard(hasEdits: hasEdits) { discardEdits = true })
            .alert("Discard your document changes?", isPresented: $discardEdits) {
                Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {}
            }
            .alert("Couldn't save document", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
    }
}
