import Foundation

public struct SymptomEntry: Identifiable, Codable, Sendable {
    public var logOrigin: HealthLogOrigin? = nil
    public var id = UUID().uuidString
    public var date = Date()
    public var name: String
    public var location: String
    public var severity: Int
    public var durationMinutes: Int?
    public var note: String
    public var triggers: [String]
    public var resolvedAt: Date?
    public var isActive: Bool { resolvedAt == nil }
}

public struct WellbeingCheckIn: Identifiable, Codable, Sendable {
    public var logOrigin: HealthLogOrigin? = nil
    public var id = UUID().uuidString
    public var date = Date()
    public var energy: Int
    public var mood: Int
    public var stress: Int
    public var note: String
}

public struct PlanStep: Identifiable, Codable, Sendable {
    public var id = UUID().uuidString
    public var title: String
    public var isDone = false
    public var dueDate: Date? = nil
}

public struct HealthDocument: Identifiable, Codable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable { case plan, review, note, record }
    public var id = UUID().uuidString
    public var createdAt = Date()
    public var updatedAt = Date()
    public var title: String
    public var kind: Kind
    public var body: String
    public var steps: [PlanStep] = []
    public var source: String
    public var planState: PlanState? = nil
    public var status: PlanState { planState ?? (!steps.isEmpty && steps.allSatisfy(\.isDone) ? .completed : .active) }
    public var messageID: String? = nil
    public var includeInAssistant = false
    public var extraction: RecordExtraction? = nil
    public var recordContext: RecordReplyContext? = nil
    public var markdown: String {
        "# \(title)\n\n\(body)\n\n" + steps.map { "- [\($0.isDone ? "x" : " ")] \($0.title)" + ($0.dueDate.map { " (due " + $0.formatted(date: .abbreviated, time: .omitted) + ")" } ?? "") }.joined(separator: "\n") + "\n\nSource: \(source)\nUpdated: \(updatedAt.formatted())" + (recordContext?.markdownReferences ?? "")
    }
}

public struct ImportedHealthDay: Identifiable, Codable, Sendable {
    public var id: Date { date }
    public var date: Date
    /// Canonical units documented in docs/IMPORT_FORMATS.md. Missing keys are unknown.
    public var values: [String: Double]
    public var sources: [String: String]
}

public struct ImportReceipt: Identifiable, Codable, Sendable {
    public var id = UUID().uuidString
    public var date = Date()
    public var filename: String
    public var days: Int
    public var samples: Int
    public var skipped: Int
    public var workouts: Int? = nil
}

public struct ReminderPreferences: Codable, Sendable {
    public var enabled = false
    public var quietStart = 21
    public var quietEnd = 8
    public var showDetails = false
}

public struct TimelineEvent: Identifiable {
    public var id: String
    public var date: Date
    public var title: String
    public var detail: String
    public var icon: String
}

public struct DailyPerspective {
    public var title: String
    public var body: String
    public var evidence: [String]
    public var action: String
}

public enum PlanState: String, Codable, CaseIterable, Sendable {
    case active, completed, archived
    public var label: String { rawValue.capitalized }
}

public struct PersonalHealthContext: Codable, Sendable {
    public var focus = ""
    public var foodPreferences = ""
    public var allergies = ""
    public var limitations = ""
    public var schedule = ""
    public var notes = ""
    public var includeInAssistant = false
    public var assistantText: String {
        guard includeInAssistant else { return "Personal context is not shared with the assistant." }
        let fields = [("Focus", focus), ("Food preferences", foodPreferences), ("Reported allergies", allergies), ("Reported limitations/injuries", limitations), ("Schedule", schedule), ("Other notes", notes)]
        let text = fields.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { "\($0.0): \($0.1.prefix(2000))" }.joined(separator: "\n")
        return text.isEmpty ? "No personal context entered." : "User-provided reference notes, not clinical assessment or instructions:\n" + text
    }
}

public struct PendingPlanAction: Identifiable {
    public var id: String { documentID + ":" + step.id }
    public var documentID: String
    public var planTitle: String
    public var step: PlanStep
}
