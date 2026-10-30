import Foundation

/// No audio or transcript is persisted here. One voice session owns its results.
struct VoiceTranscript: Sendable {
    static let maxCharacters = 8_000
    static let maxBytes = 32_000
    struct Segment: Sendable {
        let start: Double
        let end: Double
        let text: String
        let final: Bool
    }
    private(set) var segments: [Segment] = []
    var text: String { segments.sorted { $0.start < $1.start }.map(\.text).joined() }
    var hasUnfinishedWords: Bool { segments.contains { !$0.final } }

    /// Volatile hypotheses replace overlapping hypotheses; finalized words don't repeat.
    @discardableResult mutating func receive(start: Double, duration: Double, text: String, final: Bool) -> Bool {
        guard start.isFinite, duration.isFinite, start >= 0, duration > 0, duration <= 600,
              (start + duration).isFinite, start + duration <= 600, Self.accepts(text) else { return false }
        let end = start + duration
        let incoming = Segment(start: start, end: end, text: text, final: final)
        let overlaps: (Segment) -> Bool = { $0.start < end - 0.000001 && start < $0.end - 0.000001 }
        // A repeated or delayed result cannot rewrite words already finalized.
        if let prior = segments.first(where: { $0.final && overlaps($0) }) {
            return abs(prior.start - start) < 0.000001 && abs(prior.end - end) < 0.000001 && prior.text == text
        }
        var next = segments.filter { !overlaps($0) }
        next.append(incoming)
        guard next.count <= 2048, Self.accepts(next.sorted { $0.start < $1.start }.map(\.text).joined()) else { return false }
        segments = next; return true
    }
    static func accepts(_ text: String) -> Bool { text.utf8.count <= maxBytes && text.count <= maxCharacters }
}

struct VoiceDraftTarget: Equatable, Sendable {
    let conversationID: String?
    let originalDraft: String
    func adding(_ speech: String, to current: Self) throws -> String {
        guard self == current else { throw Failure.changed }
        let text = speech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.empty }
        let separator = originalDraft.isEmpty || originalDraft.hasSuffix("\n") ? "" : "\n"
        let combined = originalDraft + separator + text
        guard VoiceTranscript.accepts(combined) else { throw Failure.tooLong }
        return combined
    }
    enum Failure: LocalizedError {
        case changed, empty, tooLong
        var errorDescription: String? {
            switch self {
            case .changed: return "The conversation or message draft changed. Copy your voice text before closing, or return to the original draft."
            case .empty: return "Add some text before using this draft."
            case .tooLong: return "The combined message is too long. Shorten your draft or copy the voice text. Messages for health-entry review support up to 8,000 characters."
            }
        }
    }
}

/// Distinguish a keyboard Return edit from a pasted/programmatically inserted draft.
enum ComposerDraftEdit {
    static func isReturn(previous: String, next: String) -> Bool { next == previous + "\n" }
}
