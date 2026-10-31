import Foundation
import CryptoKit

/// A reviewed transcription, not an interpretation. All reported strings are
/// retained literally: no numeric conversion, inferred flag or reference range.
public struct LabObservation: Identifiable, Codable, Sendable, Equatable {
    public var id = UUID().uuidString
    public var test: String
    public var result: String
    public var unit = ""
    public var reference = ""
    public var flag = ""
    public var collectedOn: String? = nil
    public var laboratory = ""
    public var specimen = ""
    public var method = ""
    public var source: LabTextSource
    public var reportedTiming: String? = nil
    public var reportedStatus: String? = nil
    public var importRow: Int? = nil

    private var textFields: [(label: String, value: String, limit: Int, required: Bool)] {
        [("Test name", test, 200, true), ("Reported result", result, 500, true),
         ("Unit", unit, 100, false), ("Reference wording", reference, 1000, false),
         ("Reported flag", flag, 200, false), ("Reported collection wording", reportedTiming ?? "", 500, false),
         ("Reported status", reportedStatus ?? "", 200, false), ("Laboratory", laboratory, 500, false),
         ("Specimen", specimen, 500, false), ("Method", method, 500, false)]
    }
    var firstFieldIssue: String? {
        for field in textFields {
            if let issue = LabReport.textIssue(field.value, limit: field.limit, required: field.required) { return issue.message(for: field.label) }
        }
        if let collectedOn, PlanDay.date(collectedOn) == nil { return "Collection day needs a complete ISO calendar date." }
        return nil
    }

    public var isValid: Bool {
        LabReport.bounded(id, limit: 100, required: true, multiline: false) &&
        textFields.allSatisfy { LabReport.bounded($0.value, limit: $0.limit, required: $0.required) } &&
        (collectedOn.map { PlanDay.date($0) != nil } ?? true) && source.isValid &&
        (importRow.map { (1...1024).contains($0) } ?? true)
    }
    public var referenceText: String {
        var fields = ["Test: " + test, "Reported result: " + result, "Reported unit: " + (unit.isEmpty ? "Not recorded" : unit),
         "Reported reference: " + (reference.isEmpty ? "Not recorded" : reference), "Reported flag: " + (flag.isEmpty ? "Not recorded" : flag),
         "Collection day: " + (collectedOn ?? "Not recorded"), "Laboratory: " + (laboratory.isEmpty ? "Not recorded" : laboratory),
         "Specimen: " + (specimen.isEmpty ? "Not recorded" : specimen), "Method: " + (method.isEmpty ? "Not recorded" : method)]
        // Absent new metadata must preserve Batch 20 text and reference hashes.
        if let reportedTiming { fields.append("Reported collection wording: " + reportedTiming) }
        if let reportedStatus { fields.append("Reported status: " + reportedStatus) }
        if let importRow { fields.append("Original import data row: " + String(importRow)) }
        fields.append("Transcribed from saved text characters \(source.start + 1)–\(source.end)")
        return fields.joined(separator: "\n")
    }
}

public struct LabTextSource: Codable, Sendable, Equatable {
    public var start: Int
    public var end: Int
    public var excerpt: String
    public var isValid: Bool {
        start >= 0 && end > start && end <= RecordReview.maxCharacters && end - start == excerpt.count &&
        LabReport.bounded(excerpt, limit: 2000, required: true, multiline: true)
    }
    public func matches(_ body: String) -> Bool {
        isValid && body.count >= end && String(body.dropFirst(start).prefix(end - start)) == excerpt
    }
}

public struct LabReport: Codable, Sendable, Equatable {
    public var version = 1
    public var reviewedAt: Date
    public var sourceBodySHA256: String
    public var observations: [LabObservation]
    public var importedFrom: LabImportOrigin? = nil
    public static let maxObservations = 256
    static let maxContentBytes = 1_000_000
    var contentBytes: Int { observations.reduce(0, { $0 + $1.referenceText.utf8.count + $1.source.excerpt.utf8.count }) }
    public static let heading = "## Reviewed lab transcriptions"
    public var isValid: Bool {
        version == 1 && reviewedAt.timeIntervalSince1970.isFinite &&
        sourceBodySHA256.count == 64 && sourceBodySHA256.allSatisfy { $0.isASCII && $0.isHexDigit } &&
        !observations.isEmpty && observations.count <= Self.maxObservations &&
        Set(observations.map(\.id)).count == observations.count && observations.allSatisfy(\.isValid) &&
        contentBytes <= Self.maxContentBytes &&
        (importedFrom?.isValid ?? true) && observations.allSatisfy { row in row.importRow.map { importedFrom?.selectedRows.contains($0) == true } ?? true }
    }
    public func isCurrent(body: String) -> Bool {
        isValid && sourceBodySHA256 == Self.digest(body) && sourcesMatch(body)
    }
    public func matchesOriginalImportLayout(body: String) -> Bool {
        guard let original = importedFrom?.layoutSHA256 else { return false }
        return original == Self.digest(body)
    }
    /// A changed source is a valid historical transcription, visibly stale. A
    /// matching body hash with invalid anchors is corrupt and cannot be restored.
    public func isValid(in document: HealthDocument) -> Bool {
        isValid && (document.labImportOrigin.map { $0.isValid && importedFrom == $0 } ?? true) && document.kind == .record && document.body.count <= RecordReview.maxCharacters && document.body.utf8.count <= RecordRetrieval.maxDocumentBytes &&
        (sourceBodySHA256 != Self.digest(document.body) || sourcesMatch(document.body))
    }
    private func sourcesMatch(_ body: String) -> Bool {
        let characters = Array(body)
        return observations.allSatisfy { observation in
            let source = observation.source
            return source.isValid && source.end <= characters.count && String(characters[source.start..<source.end]) == source.excerpt
        }
    }
    public var referenceText: String {
        Self.heading + "\n\nReviewed transcription, not clinical interpretation. Values, units, flags and reference wording were entered during review; the saved source excerpt can differ. Missing fields are unknown. No unit conversions or clinical comparisons were made.\n\n" + (importedFrom.map { $0.referenceText + "\n\n" } ?? "") +
        observations.enumerated().map { "Lab result \($0.offset + 1)\n" + $0.element.referenceText }.joined(separator: "\n\n")
    }
    public func markdown(body: String) -> String {
        let state = isCurrent(body: body) ? "Source text matches the reviewed version." : "SOURCE TEXT CHANGED: these earlier transcriptions have not been checked against the current text."
        return "\n\n" + state + "\nReview: " + reviewedAt.formatted() + "\n\n" + referenceText + "\n\nSaved transcription source excerpts\n\n" +
        observations.enumerated().map { "\($0.offset + 1). " + $0.element.source.excerpt }.joined(separator: "\n\n")
    }
    static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    enum TextIssue: Equatable {
        case required, blank, characters(Int), bytes(Int), controls
        func message(for field: String) -> String {
            switch self {
            case .required: return field + " is required."
            case .blank: return "Use visible text for " + field.lowercased() + ", or leave it blank."
            case .characters(let limit): return field + " exceeds \(limit.formatted()) characters."
            case .bytes(let limit): return field + " exceeds \(limit.formatted()) bytes. Shorten this field."
            case .controls: return field + " contains unsupported control characters. Remove them."
            }
        }
    }
    static func textIssue(_ value: String, limit: Int, required: Bool = false, multiline: Bool = true) -> TextIssue? {
        if value.count > limit { return .characters(limit) }
        if value.utf8.count > limit * 4 { return .bytes(limit * 4) }
        let invisible = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if required && invisible { return .required }
        if !value.isEmpty && invisible { return .blank }
        if !value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || (multiline && [9, 10, 13].contains($0.value)) }) { return .controls }
        return nil
    }
    static func bounded(_ value: String, limit: Int, required: Bool = false, multiline: Bool = true) -> Bool {
        textIssue(value, limit: limit, required: required, multiline: multiline) == nil
    }
}
