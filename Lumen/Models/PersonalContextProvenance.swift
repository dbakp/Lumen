import Foundation
import CryptoKit

/// Local provenance of the notes used for a reply, not authentication of its text.
/// A missing record on ChatMessage means unknown legacy provenance.
public struct PersonalContextProvenance: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var notesSHA256: String?

    public static let withoutNotes = PersonalContextProvenance(notesSHA256: nil)

    public static func included(_ context: PersonalHealthContext) -> Self {
        guard context.includeInAssistant, !context.includedFieldsText.isEmpty else { return .withoutNotes }
        let bytes = Data(("Lumen personal-context v1\n" + context.assistantText).utf8)
        return .init(notesSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }

    public var isValid: Bool {
        version == 1 && (notesSHA256.map { $0.count == 64 && $0.allSatisfy { $0.isASCII && ("0123456789abcdef".contains($0)) } } ?? true)
    }

    public func allowsHistory(current: Self) -> Bool {
        isValid && current.isValid && (notesSHA256 == nil || self == current)
    }

    public static func history(_ messages: [ChatMessage], current: Self) -> [ChatMessage] {
        messages.filter { $0.role == .user || $0.personalContext?.allowsHistory(current: current) == true }
    }
}
