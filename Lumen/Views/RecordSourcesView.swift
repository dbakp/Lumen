import SwiftUI

/// References belong to the reply's saved version, not a new search of today's Library.
struct RecordSourcesView: View {
    let context: RecordReplyContext
    @State private var selected: LibraryPassage?
    @State private var expanded = false
    @ScaledMetric(relativeTo: .subheadline) private var markerSide = 28.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    Text(context.mode == .lookup ? "Library matches" : "Library for this reply")
                        .font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 14, weight: .semibold)).accessibilityHidden(true)
                }.foregroundStyle(Theme.accent).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(expanded ? "Expanded" : "Collapsed").accessibilityIdentifier("libraryReferencesToggle")
            if expanded {
            VStack(alignment: .leading, spacing: 12) {
                Text(context.mode == .lookup ? "Exact excerpts from saved text. No AI interpretation." : "These excerpts accompanied the question. A reference marks text cited by the model; it doesn't verify the claim.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                Text(context.searchedDocuments == context.sharedDocuments
                     ? "\(context.sharedDocuments.formatted()) shared document\(context.sharedDocuments == 1 ? "" : "s") searched"
                     : "\(context.searchedDocuments.formatted()) of \(context.sharedDocuments.formatted()) shared document\(context.sharedDocuments == 1 ? "" : "s") searched")
                    .font(.caption).foregroundStyle(Theme.secondary)
                if context.limited { Text("Search limits reached. Some shared text wasn't searched.").font(.footnote).foregroundStyle(Theme.secondary) }
                Text(method).font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("librarySearchMethod")
                if let audit = context.meaningSearch, audit.status == .used {
                    Text("Related topics may not answer your question. Check the excerpt before relying on it.").font(.footnote).foregroundStyle(Theme.secondary)
                    Text(audit.indexedPassages == 1 && audit.comparedPassages == 1
                         ? "Related-topic search compared the only prepared excerpt."
                         : "Compared \(audit.comparedPassages.formatted()) of \(audit.indexedPassages.formatted()) prepared excerpts for related topics.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                    if audit.limited { Text("Some related-topic comparisons were skipped.").font(.footnote).foregroundStyle(Theme.secondary) }
                } else if context.meaningSearch?.limited == true {
                    Text("Related-topic comparison limits reached. Keyword results are shown.").font(.footnote).foregroundStyle(Theme.secondary)
                }
                if context.passages.isEmpty { Text("No matching excerpts were selected.").font(.footnote).foregroundStyle(Theme.secondary) }
                ForEach(context.passages) { passage in
                    Button { selected = passage } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(passage.number)").font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.accent).frame(width: markerSide, height: markerSide).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: passage.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                                Text(passage.location).font(.caption).foregroundStyle(Theme.secondary)
                                Text(passage.selectionLabel).font(.caption).foregroundStyle(Theme.secondary)
                                if context.mode == .model { Text(passage.referenced ? "Referenced in reply" : "Shared with provider · not cited").font(.caption).foregroundStyle(Theme.secondary) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary).accessibilityHidden(true)
                        }.padding(.vertical, 8).frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("library-reference-\(passage.number)")
                }
                if context.invalidCitations > 0 { Text("The reply included an unrecognized reference. It couldn't be linked to saved text.").font(.footnote).foregroundStyle(Theme.secondary) }
            }.padding(.top, 8)
            }
        }.tint(Theme.accent)
            .sheet(item: $selected) { RecordReferenceView(passage: $0, context: context) }
    }
    private var method: String {
        switch context.meaningSearch?.status {
        case .used: return "Keyword search + English related topics · on this iPhone"
        case .unavailable: return "Keyword search · related-topic model unavailable"
        case .unsupportedLanguage: return "Keyword search · question not identified as English"
        case .queryTooLong: return "Keyword search · question too long for topic matching"
        case .failed: return "Keyword search · related-topic search couldn't finish"
        case .notNeeded: return "Keyword search · no additional topic comparison"
        case .off, .none: return "Keyword search"
        }
    }
}

private extension LibraryPassage {
    var selectionLabel: String {
        switch selection {
        case .relatedTopic: return "Related topic"
        case .keywordAndRelatedTopic: return "Keyword + related topic"
        case .carried: return "Kept from the earlier reply"
        case .keyword: return "Keyword match"
        case .none: return "Selection method not recorded"
        }
    }
}

private struct RecordReferenceView: View {
    let passage: LibraryPassage
    let context: RecordReplyContext
    @ObservedObject private var companion = CompanionStore.shared
    @Environment(\.dismiss) private var dismiss
    var current: HealthDocument? { RecordRetrieval.currentDocument(for: passage, in: companion.documents) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reference \(passage.number)").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                        Text(verbatim: passage.title).font(.largeTitle.bold()).fontWidth(.expanded).tracking(-1)
                        Text(passage.location).font(.subheadline).foregroundStyle(Theme.secondary)
                        Text(passage.selectionLabel).font(.subheadline).foregroundStyle(Theme.secondary)
                        if passage.selection == .relatedTopic || passage.selection == .keywordAndRelatedTopic {
                            Text("This excerpt may not answer your question.").font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                        Text(verbatim: passage.source).font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Text saved with this reply").font(.headline)
                        Text(verbatim: passage.excerpt).font(.body).lineSpacing(4).textSelection(.enabled).accessibilityIdentifier("reference-excerpt")
                        Text("Selected \(context.capturedAt.formatted(date: .abbreviated, time: .shortened)) · document updated \(passage.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        if let current {
                            if !RecordRetrieval.isCurrent(passage, documents: companion.documents, requireSharing: false) {
                                Label("The Library text has changed", systemImage: "pencil").font(.headline)
                                Text("This reply keeps the earlier excerpt. Open Library to read the current version.").font(.subheadline).foregroundStyle(Theme.secondary)
                            } else { Label("Matches the current saved text", systemImage: "checkmark").font(.headline) }
                            if !current.includeInAssistant { Text("Assistant sharing is off for this document. This saved excerpt stays with the earlier reply.").font(.subheadline).foregroundStyle(Theme.secondary) }
                            NavigationLink { DocumentDetailView(documentID: current.id) } label: { Label("Open in Library", systemImage: "doc.text") }.foregroundStyle(Theme.accent).frame(minHeight: 44)
                        } else {
                            Label("Document removed from Library", systemImage: "doc.badge.minus").font(.headline)
                            Text("This reply keeps the earlier excerpt. Delete the conversation and any saved copies to remove their excerpts.").font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                        Text("Saved text may contain errors. Check names, numbers and units against the original.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }.padding(Theme.gutter).padding(.bottom, 24)
            }.lumenScreen().navigationTitle("Saved reference").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(Theme.accent)
    }
}
