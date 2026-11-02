import SwiftUI

struct ConversationHistoryView: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = ""
    @State private var renaming: HealthConversation?
    @State private var deleting: HealthConversation?
    @State private var failure: String?
    @State private var failureTitle = "Couldn’t change conversation"
    @State private var retry: (() -> Void)?
    var conversations: [HealthConversation] {
        health.conversations.filter { !$0.messages.isEmpty && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(search) }) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        NavigationStack {
            List {
                ConversationStorageStatus().environmentObject(health)
                if health.conversationReady, conversations.isEmpty {
                    Text(search.isEmpty ? "Your conversations will stay here, ready to pick up again." : "No matching conversations.").foregroundStyle(Theme.secondary)
                }
                ForEach(health.conversationReady ? conversations : []) { conversation in
                    Button {
                        save("Couldn’t open conversation") { try await health.selectConversation(conversation.id); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            FHIRLiteralText(text: conversation.title, identifier: "conversationTitle-" + conversation.id,
                                            style: .headline, selectable: false)
                            Text(conversation.messages.last?.text ?? "").font(.subheadline).lineLimit(2).foregroundStyle(Theme.secondary)
                            HStack(alignment: .top) {
                                Text("\(conversation.messages.count) \(conversation.messages.count == 1 ? "message" : "messages") · \(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Theme.secondary)
                                Spacer(minLength: 8)
                                if conversation.id == health.activeConversationID {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent).accessibilityLabel("Current conversation")
                                }
                            }
                            if health.pendingConversationReplies.contains(where: { $0.owner.conversationID == conversation.id }) {
                                Label("Reply not saved", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.secondary)
                            }
                        }.padding(.vertical, 8)
                    }.disabled(health.isConversationSaving).accessibilityIdentifier("conversation-\(conversation.id)")
                        .listRowInsets(typeSize.isAccessibilitySize ? EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8) : nil)
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { renaming = conversation }.disabled(health.isConversationSaving)
                            ShareLink(item: conversation.messages.map { "\($0.role == .user ? "You" : "Lumen"): \($0.text)" + ($0.recordContext?.markdownReferences ?? "") }.joined(separator: "\n\n")) { Label("Share conversation", systemImage: "square.and.arrow.up") }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }.disabled(health.isConversationSaving)
                        }
                        .swipeActions { Button("Delete", role: .destructive) { deleting = conversation }.disabled(health.isConversationSaving) }
                }
            }.scrollContentBackground(.hidden).background(Theme.bg)
                .contentMargins(.horizontal, typeSize.isAccessibilitySize ? 0 : nil, for: .scrollContent)
                .searchable(text: $search, prompt: "Search conversations")
                .navigationTitle("Conversations").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(health.isConversationSaving) }
                    ToolbarItem(placement: .primaryAction) { Button { save("Couldn’t start conversation") { try await health.newConversation(); dismiss() } } label: { Image(systemName: "square.and.pencil") }.disabled(health.isConversationSaving || !health.conversationReady).accessibilityLabel("New conversation") }
                }
                .sheet(item: $renaming) { conversation in
                    ConversationRenameSheet(conversation: conversation).environmentObject(health)
                }
                .alert(failureTitle, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                    Button("Retry") { failure = nil; retry?() }
                    Button("Keep", role: .cancel) { failure = nil; retry = nil }
                } message: { Text(failure ?? "") }
                .sheet(item: $deleting) { conversation in
                    ConversationRemovalSheet(action: "Delete", scope: "This conversation and any unsaved reply will be removed.",
                                             failureTitle: "Couldn’t delete chat",
                                             failureMessage: "Your saved conversation is unchanged. Try again when storage is available.") {
                        try await health.deleteConversation(conversation.id)
                    }
                }
        }.tint(Theme.accent).interactiveDismissDisabled(health.isConversationSaving)
    }

    func save(_ title: String, operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await operation(); retry = nil }
            catch {
                failureTitle = title
                failure = "Your saved conversation is unchanged. Try again when storage is available."
                retry = { save(title, operation: operation) }
            }
        }
    }
}

struct ConversationStorageStatus: View {
    @EnvironmentObject var health: HealthStore
    var body: some View {
        if !health.conversationReady {
            if let issue = health.conversationStorageIssue {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conversations unavailable").font(.headline).accessibilityIdentifier("conversationStorageIssue")
                    Text(issue).font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("conversationStorageExplanation")
                    Button("Retry opening") { Task { await health.openConversationsChecked() } }
                        .frame(minHeight: 44).disabled(health.isConversationSaving).accessibilityIdentifier("retryOpeningConversations")
                }
            } else { ProgressView("Opening conversations").font(.footnote) }
        } else if health.isConversationSaving { ProgressView("Saving conversation").font(.footnote) }
    }
}

private struct ConversationRenameSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    let conversation: HealthConversation
    @State private var title: String
    @State private var failure: String?
    @State private var saving = false
    @FocusState private var titleFocused: Bool
    init(conversation: HealthConversation) { self.conversation = conversation; _title = State(initialValue: conversation.title) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical).lineLimit(1...5).focused($titleFocused).accessibilityIdentifier("conversationTitleDraft")
                } footer: { Text("Up to 100 characters.") }
                if let failure { Section { Text(failure).foregroundStyle(Theme.secondary).accessibilityIdentifier("conversationRenameFailure") } }
                if saving { ProgressView("Saving title") }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Rename").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        titleFocused = false
                        saving = true
                        Task {
                            defer { saving = false }
                            do {
                                #if DEBUG && targetEnvironment(simulator)
                                try await ConversationNativeFixtures.changeTitleIfRequested(health: health, id: conversation.id)
                                #endif
                                try await health.renameConversation(conversation.id, title: title, expectedTitle: conversation.title); dismiss()
                            }
                            catch ConversationSaveError.changed { failure = "The saved title changed. Your draft is still here. Copy it before cancelling, then reopen this conversation." }
                            catch { failure = "The title wasn't saved. Your draft is still here. Try saving again." }
                        }
                    }.disabled(saving || health.isConversationSaving || !health.conversationReady || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 100)
                }
            }
            .disabled(saving)
        }.tint(Theme.accent).interactiveDismissDisabled(saving || title != conversation.title)
    }
}
