import Foundation

public struct HealthConversation: Identifiable, Codable, Sendable {
    public var id = UUID().uuidString
    public var title = "New conversation"
    public var createdAt = Date()
    public var updatedAt = Date()
    public var messages: [ChatMessage] = []
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
