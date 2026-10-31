import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct RecordImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private enum Field: Hashable { case title, page(Int) }
    @FocusState private var focused: Field?
    @ObservedObject private var companion = CompanionStore.shared
    var onWorkspaceReady: (RecordWorkspace) -> Void
    var onSaved: () -> Void
    @State private var choosing = false
    @State private var preview: RecordImportService.Preview?
    @State private var pages: [RecordPageDraft] = []
    @State private var title = ""
    @State private var initialTitle = ""
    @State private var pageIndex = 0
    @State private var acknowledged = false
    @State private var share = false
    @State private var control: RecordImportControl?
    @State private var job: Task<Void, Never>?
    @State private var stopping = false
    @State private var error: String?
    @State private var errorTitle = "Couldn't read record"
    @State private var status: String?
    @State private var original: URL?
    @State private var discard = false
    @State private var duplicate = false
    @State private var sourceChange: RecordExtraction.Method?

    private var hasEdits: Bool { pages.contains { $0.edited || $0.excluded } || share || (preview != nil && title != initialTitle) }
    private var canSave: Bool { acknowledged && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (try? RecordReview.body(pages)) != nil && control == nil }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(preview == nil ? "Read a record." : "Review your record.")
                        .font(.system(.largeTitle, weight: .bold)).fontWidth(.expanded).tracking(-1)
                    if let control {
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            let progress = control.progress
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { ProgressView(); Text(stopping ? "Stopping" : progress.title).font(.headline) }
                                if progress.total > 0 { Text("Page \(progress.page.formatted()) of \(progress.total.formatted())").foregroundStyle(Theme.secondary) }
                                Text(stopping ? "Finishing local cleanup. No record was saved." : "Reading on this device. You can cancel at any time.").font(.footnote).foregroundStyle(Theme.secondary)
                            }.padding(20).surface().accessibilityElement(children: .contain).accessibilityIdentifier("recordReadingProgress")
                        }
                    } else if let preview {
                        review(preview)
                    } else {
                        Text("Choose a PDF, a still image or a text file. Lumen reads it on this device, then lets you check and edit the text before saving.").foregroundStyle(Theme.secondary)
                        Button("Choose a file", systemImage: "doc.badge.plus") { choosing = true }.buttonStyle(LumenPrimaryButtonStyle()).accessibilityIdentifier("chooseRecordFile")
                        Text("PDF, JPEG, PNG, HEIC, text or Markdown. Up to 20 MB, 100 pages and 200,000 characters.").font(.footnote).foregroundStyle(Theme.secondary)
                        Text("Text recognition can misread names, numbers and units. It does not interpret results or add measurements to your health logs.").font(.footnote).foregroundStyle(Theme.secondary)
                        if let status { Text(status).font(.subheadline).foregroundStyle(Theme.secondary) }
                    }
                }.padding(Theme.gutter).padding(.bottom, 24)
            }.lumenScreen().scrollDismissesKeyboard(focused == nil ? .interactively : .never)
                .safeAreaPadding(.bottom, focused == nil ? 0 : 112)
                .onChange(of: focused) { _, value in
                    if case .page(let index) = value { withAnimation { proxy.scrollTo("recordPageText-\(index)", anchor: .center) } }
                }
            }
                .onChange(of: pageIndex) { _, _ in focused = nil }
                .onChange(of: acknowledged) { _, value in if value { focused = nil } }
                .navigationTitle(preview == nil ? "Import a record" : "Review record").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil }.accessibilityIdentifier("finishRecordEditing") }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(stopping ? "Stopping…" : "Cancel") {
                            if let control { stopping = true; control.cancel() }
                            else if hasEdits { discard = true } else { close() }
                        }.disabled(stopping).accessibilityIdentifier("cancelRecordImport")
                    }
                    if preview != nil {
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold).disabled(!canSave).accessibilityIdentifier("saveReviewedRecord") }
                    }
                }
                .fileImporter(isPresented: $choosing, allowedContentTypes: [.pdf, .jpeg, .png, .heic, .heif, .plainText, UTType(filenameExtension: "md") ?? .plainText]) { result in
                    switch result { case .success(let url): read(url); case .failure(let failure): error = failure.localizedDescription }
                }
                .fullScreenCover(isPresented: Binding(get: { original != nil }, set: { if !$0 { original = nil } })) {
                    if let original { RecordOriginalView(url: original) }
                }
                .alert(errorTitle, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
                .alert("Discard your changes?", isPresented: $discard) {
                    Button("Discard changes", role: .destructive) { close() }; Button("Keep reviewing", role: .cancel) {}
                }
                .alert("Save another copy?", isPresented: $duplicate) {
                    Button("Save another copy") { save(allowDuplicate: true) }; Button("Keep reviewing", role: .cancel) {}
                } message: { Text("A record from this same file is already in Library. Saving adds a separate copy.") }
                .alert("Replace your edits with the other text version?", isPresented: Binding(get: { sourceChange != nil }, set: { if !$0 { sourceChange = nil } })) {
                    Button("Replace page text", role: .destructive) { if let sourceChange, pages.indices.contains(pageIndex) { pages[pageIndex].select(sourceChange); acknowledged = false }; sourceChange = nil }
                    Button("Keep edits", role: .cancel) { sourceChange = nil }
                }
                .background(SheetDismissGuard(hasEdits: hasEdits) { discard = true })
                .onDisappear { control?.cancel(); job?.cancel() }
        }.tint(Theme.accent)
    }
    @ViewBuilder private func review(_ preview: RecordImportService.Preview) -> some View {
        Text(preview.filename).font(.subheadline).foregroundStyle(Theme.secondary).accessibilityIdentifier("recordPreviewReady")
        VStack(alignment: .leading, spacing: 8) {
            Text("Title").font(.headline)
            TextField("Record title", text: $title).textFieldStyle(.roundedBorder).focused($focused, equals: .title).accessibilityIdentifier("recordTitle")
        }
        HStack(spacing: 16) {
            Button { pageIndex -= 1 } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }.disabled(pageIndex == 0).foregroundStyle(pageIndex == 0 ? Theme.tertiary : Theme.accent).accessibilityLabel("Previous page")
            Spacer(minLength: 0)
            Text("Page \((pageIndex + 1).formatted()) of \(pages.count.formatted())").font(.headline).accessibilityIdentifier("recordPageNumber")
            Spacer(minLength: 0)
            Button { pageIndex += 1 } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }.disabled(pageIndex + 1 == pages.count).foregroundStyle(pageIndex + 1 == pages.count ? Theme.tertiary : Theme.accent).accessibilityLabel("Next page")
        }
        if pages.indices.contains(pageIndex) {
            let index = pageIndex
            let page = pages[index]
            if !page.selectable.isEmpty && !page.recognized.isEmpty {
                Menu {
                    Picker("Text source", selection: Binding(get: { pages.indices.contains(index) ? pages[index].method : page.method }, set: { method in
                        guard pages.indices.contains(index) else { return }
                        if pages[index].edited { sourceChange = method }
                        else { pages[index].select(method); acknowledged = false }
                    })) {
                        Text("Selectable text").tag(RecordExtraction.Method.selectableText)
                        Text("Text recognition").tag(RecordExtraction.Method.textRecognition)
                    }.pickerStyle(.inline)
                } label: {
                    HStack(spacing: 12) {
                        Text(page.method == .selectableText ? "Selectable text" : "Text recognition").lineLimit(nil).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                    }.padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityLabel("Text source")
                    .accessibilityValue(page.method == .selectableText ? "Selectable text" : "Text recognition").accessibilityIdentifier("recordTextSource")
            } else { Text(page.method == .plainText ? "Text file" : page.method == .selectableText ? "Selectable text" : "Text recognition").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent) }
            if page.recognitionUnavailable { Text("Text recognition wasn't available for this page. Check the selectable text against the original.").font(.footnote).foregroundStyle(Theme.secondary) }
            if page.method == .textRecognition {
                Text("Check names, numbers and units against the original. Recognition may change wording or reading order.").font(.footnote).foregroundStyle(Theme.secondary)
                if page.lowConfidenceLines > 0 { Text("\(page.lowConfidenceLines.formatted()) uncertain line\(page.lowConfidenceLines == 1 ? "" : "s"). Review the whole page; other errors may be unmarked.").font(.footnote).foregroundStyle(Theme.secondary) }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Page text").font(.headline)
            if let url = page.imageURL, let image = UIImage(contentsOfFile: url.path) {
                DisclosureGroup { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Original page \(page.number)") } label: { Text("Page image").foregroundStyle(Theme.accent) }
            }
            Button("Open original", systemImage: "doc.viewfinder") { original = preview.originalURL }.foregroundStyle(Theme.accent).frame(minHeight: 44)

                TextEditor(text: pageBinding(index, \.text, fallback: page.text))
                    .autocorrectionDisabled(true).textInputAutocapitalization(.never).scrollContentBackground(.hidden)
                    .frame(minHeight: 240).padding(8).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16)).focused($focused, equals: .page(index)).accessibilityIdentifier("recordPageText").id("recordPageText-\(index)")
            }
            reviewToggle("Exclude this page", isOn: pageBinding(index, \.excluded, fallback: page.excluded), identifier: "excludeRecordPage")
            if !page.excluded && page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("No text was found. Add the missing text or exclude this page before saving.").font(.footnote).foregroundStyle(Theme.secondary) }
        }
        if pages.allSatisfy(\.excluded) { Text("Include at least one page with text before saving.").font(.footnote).foregroundStyle(Theme.secondary) }
        Divider()
        reviewToggle("I checked all included pages against the original", isOn: $acknowledged, identifier: "acknowledgeRecordText")
        reviewToggle("Use in assistant", isOn: $share, identifier: "shareImportedRecord")
        Text("Leave off to exclude this record from assistant context. If enabled, excerpts may be sent with your questions to your selected AI provider.").font(.footnote).foregroundStyle(Theme.secondary)
        Text("Save keeps your reviewed text and page details. The original file isn't stored in Library; keep your own copy.").font(.footnote).foregroundStyle(Theme.secondary)
    }
    @ViewBuilder private func reviewToggle(_ title: String, isOn: Binding<Bool>, identifier: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Toggle(title, isOn: isOn).labelsHidden().accessibilityLabel(title).accessibilityIdentifier(identifier)
            }
        } else { Toggle(title, isOn: isOn).accessibilityIdentifier(identifier) }
    }
    private func pageBinding<Value: Equatable>(_ index: Int, _ keyPath: WritableKeyPath<RecordPageDraft, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { pages.indices.contains(index) ? pages[index][keyPath: keyPath] : fallback }, set: { value in
            guard pages.indices.contains(index), pages[index][keyPath: keyPath] != value else { return }
            pages[index][keyPath: keyPath] = value; acknowledged = false
        })
    }
    private func read(_ url: URL) {
        guard control == nil else { return }
        let next = RecordImportControl(); control = next; stopping = false; status = nil
        job = Task { @MainActor in
            do {
                let value = try await Task.detached(priority: .userInitiated) { try RecordImportService.read(url, control: next) }.value
                try next.check()
                guard control === next else { return }
                preview = value; onWorkspaceReady(value.workspace); pages = value.pages; title = String(URL(fileURLWithPath: value.filename).deletingPathExtension().lastPathComponent.prefix(500)); initialTitle = title; pageIndex = 0; acknowledged = false; share = false
            } catch is CancellationError { status = "Reading cancelled. No record was saved." }
            catch {
                if (try? next.check()) == nil { status = "Reading cancelled. No record was saved." }
                else { errorTitle = "Couldn't read record"; self.error = error.localizedDescription }
            }
            guard control === next else { return }
            control = nil; job = nil; stopping = false
        }
    }
    private func close() {
        focused = nil; sourceChange = nil
        preview = nil; pages = []; original = nil
        dismiss()
    }
    private func save(allowDuplicate: Bool = false) {
        guard let preview else { return }
        do {
            if !allowDuplicate && RecordReview.hasDuplicate(sha256: preview.sha256, in: companion.documents) { duplicate = true; return }
            var document = try RecordReview.document(title: title, pages: pages, filename: preview.filename, sha256: preview.sha256, readAt: preview.readAt, acknowledged: acknowledged)
            document.includeInAssistant = share
            try companion.saveChecked(document)
            onSaved(); close(); AppRouter.shared.confirm("Reviewed record saved")
        } catch { errorTitle = "Couldn't save record"; self.error = error is RecordImportError ? error.localizedDescription : "The reviewed text wasn't saved. Check available storage and try again." }
    }
}
