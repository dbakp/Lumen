import Foundation

public struct HealthConversation: Identifiable, Codable, Sendable {
    public var id = UUID().uuidString
    public var title = "New conversation"
    public var createdAt = Date()
    public var updatedAt = Date()
    public var messages: [ChatMessage] = []
}

enum ConversationSaveError: LocalizedError {
    case notReady, changed
    var errorDescription: String? {
        switch self {
        case .notReady: return "Conversations are still opening or saving. Wait, then try again."
        case .changed: return "This conversation changed. Your draft is still available. Check the current conversation, then try again."
        }
    }
}

struct ConversationReplyOwner: Equatable, Sendable {
    let conversationID: String
    let lifetime: UUID
    let generation: UUID
    let questionID: String
}

struct ConversationSend {
    let owner: ConversationReplyOwner
    let history: [ChatMessage]
}

struct PendingConversationReply: Identifiable {
    var id: String { message.id }
    let message: ChatMessage
    let owner: ConversationReplyOwner
    let savePlan: Bool
}

public enum ConversationArchive {
    public static func migrate(legacy: [ChatMessage], existing: [HealthConversation]) -> [HealthConversation] {
        guard existing.isEmpty, !legacy.isEmpty else { return existing }
        return [HealthConversation(title: suggestedTitle(legacy), createdAt: legacy.first?.date ?? Date(), updatedAt: legacy.last?.date ?? Date(), messages: legacy)]
    }
    public static func appending(_ message: ChatMessage, to id: String, in conversations: [HealthConversation]) -> [HealthConversation] {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return conversations }
        var updated = conversations
        updated[index].messages.append(message); updated[index].updatedAt = Date()
        if updated[index].title == "New conversation" { updated[index].title = suggestedTitle(updated[index].messages) }
        return updated
    }
    public static func suggestedTitle(_ messages: [ChatMessage]) -> String {
        let text = messages.first { $0.role == .user }?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "New conversation" : String(text.prefix(70)).replacingOccurrences(of: "\n", with: " ")
    }
}
