import SwiftUI

struct ConversationHistoryView: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var renaming: HealthConversation?
    @State private var title = ""
    @State private var deleting: HealthConversation?
    var conversations: [HealthConversation] {
        health.conversations.filter { !$0.messages.isEmpty && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(search) }) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        NavigationStack {
            List {
                if conversations.isEmpty {
                    Text(search.isEmpty ? "Your conversations will stay here, ready to pick up again." : "No matching conversations.").foregroundStyle(Theme.secondary)
                }
                ForEach(conversations) { conversation in
                    Button {
                        health.selectConversation(conversation.id); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(conversation.title).font(.headline).foregroundStyle(Theme.text)
                                Spacer()
                                if conversation.id == health.activeConversationID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            Text(conversation.messages.last?.text ?? "").font(.subheadline).lineLimit(2).foregroundStyle(Theme.secondary)
                            Text("\(conversation.messages.count) messages · \(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Theme.secondary)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("conversation-\(conversation.id)")
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { title = conversation.title; renaming = conversation }
                            ShareLink(item: conversation.messages.map { "\($0.role == .user ? "You" : "Lumen"): \($0.text)" + ($0.recordContext?.markdownReferences ?? "") }.joined(separator: "\n\n")) { Label("Share conversation", systemImage: "square.and.arrow.up") }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
                        }
                        .swipeActions { Button("Delete", role: .destructive) { deleting = conversation } }
                }
            }.scrollContentBackground(.hidden).background(Theme.bg)
                .searchable(text: $search, prompt: "Search conversations")
                .navigationTitle("Conversations").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button { health.newConversation(); dismiss() } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New conversation") }
                }
                .alert("Rename conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                    TextField("Title", text: $title)
                    Button("Save") { if let renaming { health.renameConversation(renaming.id, title: title) }; renaming = nil }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel", role: .cancel) { renaming = nil }
                }
                .confirmationDialog("Delete this conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("Delete conversation", role: .destructive) { if let deleting { health.deleteConversation(deleting.id) }; deleting = nil }
                } message: { Text("Saved Library documents and confirmed health entries, including their source messages, stay available. A reply still running for a deleted conversation will be discarded.") }
        }.tint(Theme.accent)
    }
}
