import Foundation

public struct SymptomEntry: Identifiable, Codable, Sendable {
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
    public var messageID: String? = nil
    public var includeInAssistant = false
    public var markdown: String {
        "# \(title)\n\n\(body)\n\n" + steps.map { "- [\($0.isDone ? "x" : " ")] \($0.title)" }.joined(separator: "\n") + "\n\nSource: \(source)\nUpdated: \(updatedAt.formatted())"
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
