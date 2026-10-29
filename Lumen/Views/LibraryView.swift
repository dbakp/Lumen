import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct LibraryView: View {
    @EnvironmentObject var health: HealthStore
    @ObservedObject private var companion = CompanionStore.shared
    @State private var search = ""
    @State private var kind: HealthDocument.Kind?
    @State private var importing = false
    @State private var editing: HealthDocument?
    @State private var error: String?
    @State private var extracting = false
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
                if extracting { ProgressView("Reading your record locally…") }
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
                                if !doc.steps.isEmpty { Text("\(doc.steps.filter(\.isDone).count) of \(doc.steps.count) steps completed").font(.caption).foregroundStyle(Theme.accent) }
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
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText]) { result in importRecord(result) }
            .alert("Couldn't import record", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    func filterButton(_ title: String, value: HealthDocument.Kind?) -> some View {
        Button(title) { kind = value }
            .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 44)
            .background(kind == value ? Theme.accent : Theme.surfaceRaised, in: Capsule())
            .foregroundStyle(kind == value ? Theme.onAccent : Theme.secondary)
            .accessibilityAddTraits(kind == value ? .isSelected : [])
    }
    func newNote() { editing = HealthDocument(title: "", kind: .note, body: "", source: "Your note") }
    func importRecord(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { if case .failure(let e) = result { error = e.localizedDescription }; return }
        extracting = true
        Task {
            do {
                let draft = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                    guard size < 20_000_000 else { throw HealthImportError.tooLarge }
                    let text: String
                    if url.pathExtension.lowercased() == "pdf" { text = PDFDocument(url: url)?.string ?? "" }
                    else { text = try String(contentsOf: url, encoding: .utf8) }
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HealthImportError.malformed("No readable text. Scanned PDFs need text recognition before importing.") }
                    guard text.count <= 200_000 else { throw HealthImportError.malformed("The record exceeds 200,000 characters. Split it into smaller records.") }
                    return HealthDocument(title: url.deletingPathExtension().lastPathComponent, kind: .record, body: text, source: "Imported · \(url.lastPathComponent)")
                }.value
                editing = draft
            } catch { self.error = error.localizedDescription }
            extracting = false
        }
    }
}

struct DocumentDetailView: View {
    let documentID: String
    @ObservedObject private var companion = CompanionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HealthDocument?
    @State private var confirmDelete = false
    var document: HealthDocument? { companion.documents.first { $0.id == documentID } }
    var body: some View {
        ScrollView {
            if let doc = document {
                VStack(alignment: .leading, spacing: 24) {
                    Text(doc.title).font(.largeTitle.bold()).tracking(-1)
                    Text("\(doc.source)\nUpdated \(doc.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(Theme.secondary)
                    Text(.init(doc.body)).font(.body).lineSpacing(5).textSelection(.enabled)
                    ForEach(doc.steps) { step in
                        Button {
                            var updated = doc
                            if let i = updated.steps.firstIndex(where: { $0.id == step.id }) { updated.steps[i].isDone.toggle(); companion.save(updated) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                Text(step.title).strikethrough(step.isDone)
                                Spacer()
                            }.frame(minHeight: 44).foregroundStyle(step.isDone ? Theme.secondary : Theme.text)
                        }.buttonStyle(.plain).accessibilityLabel("\(step.isDone ? "Completed" : "Incomplete"): \(step.title)")
                    }
                    Text(doc.kind == .plan ? "An editable wellness draft. Adjust it to how you feel; discuss medical decisions with a clinician." : "Saved on this device. You control whether the assistant can use this text.").font(.footnote).foregroundStyle(Theme.secondary)
                    Toggle("Use in assistant", isOn: Binding(get: { doc.includeInAssistant }, set: { var d = doc; d.includeInAssistant = $0; companion.save(d) }))
                    Text("When enabled, excerpts are sent with your questions to the AI provider selected in Settings. Imported text is treated as reference material.").font(.footnote).foregroundStyle(Theme.secondary)
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
            .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { companion.deleteDocument(documentID); dismiss() }
            }
    }
}

struct DocumentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var document: HealthDocument
    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Document title", text: $document.title) }
                Section("Content") { TextEditor(text: $document.body).frame(minHeight: 280) }
                Section {
                    Toggle("Use in assistant", isOn: $document.includeInAssistant)
                } footer: { Text("Excerpts may be sent to your selected AI provider when you chat. Leave off to keep this record out of assistant context.") }
            }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Edit document").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { CompanionStore.shared.save(document); dismiss() }.fontWeight(.bold).disabled(document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.tint(Theme.accent)
    }
}
