import SwiftUI

/// Full-width review keeps removal scope readable at accessibility sizes.
/// The sheet stays responsible for its checked operation and recovery alert.
struct ConversationRemovalSheet: View {
    let action: String
    let scope: String
    let failureTitle: String
    let failureMessage: String
    let operation: @MainActor () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    FHIRLiteralText(text: scope, identifier: "conversationRemovalScope")
                    FHIRLiteralText(text: "Library copies and confirmed health entries stay.",
                                    identifier: "conversationRemovalRetained")
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("conversationRemovalBody")
            .background(Theme.bg)
            .navigationTitle(action == "Delete" ? "Delete chat?" : "Clear chat?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action, role: .destructive) { perform() }.tint(.red).disabled(saving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if saving {
                    ProgressView(action == "Delete" ? "Deleting conversation" : "Clearing conversation")
                        .padding().frame(maxWidth: .infinity).background(Theme.bg)
                }
            }
            .alert(failureTitle, isPresented: $failed) {
                Button("Retry") { perform() }
                Button("Keep", role: .cancel) { dismiss() }
            } message: { Text(failureMessage) }
        }
        .tint(Theme.accent)
        .presentationDetents([.large])
        .interactiveDismissDisabled(saving)
    }

    private func perform() {
        guard !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            do { try await operation(); dismiss() }
            catch { failed = true }
        }
    }
}
