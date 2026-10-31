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

    public var isValid: Bool {
        LabReport.bounded(id, limit: 100, required: true, multiline: false) &&
        LabReport.bounded(test, limit: 200, required: true) && LabReport.bounded(result, limit: 500, required: true) &&
        LabReport.bounded(unit, limit: 100) && LabReport.bounded(reference, limit: 1000) &&
        LabReport.bounded(flag, limit: 200) && LabReport.bounded(laboratory, limit: 500) &&
        LabReport.bounded(specimen, limit: 500) && LabReport.bounded(method, limit: 500) &&
        (collectedOn.map { PlanDay.date($0) != nil } ?? true) && source.isValid
    }
    public var referenceText: String {
        ["Test: " + test, "Reported result: " + result, "Reported unit: " + (unit.isEmpty ? "Not recorded" : unit),
         "Reported reference: " + (reference.isEmpty ? "Not recorded" : reference), "Reported flag: " + (flag.isEmpty ? "Not recorded" : flag),
         "Collection day: " + (collectedOn ?? "Not recorded"), "Laboratory: " + (laboratory.isEmpty ? "Not recorded" : laboratory),
         "Specimen: " + (specimen.isEmpty ? "Not recorded" : specimen), "Method: " + (method.isEmpty ? "Not recorded" : method),
         "Transcribed from saved text characters \(source.start + 1)–\(source.end)"].joined(separator: "\n")
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
    public static let maxObservations = 256
    public static let heading = "## Reviewed lab transcriptions"
    public var isValid: Bool {
        version == 1 && reviewedAt.timeIntervalSince1970.isFinite &&
        sourceBodySHA256.count == 64 && sourceBodySHA256.allSatisfy { $0.isASCII && $0.isHexDigit } &&
        !observations.isEmpty && observations.count <= Self.maxObservations &&
        Set(observations.map(\.id)).count == observations.count && observations.allSatisfy(\.isValid) &&
        observations.reduce(0, { $0 + $1.referenceText.utf8.count + $1.source.excerpt.utf8.count }) <= 1_000_000
    }
    public func isCurrent(body: String) -> Bool {
        isValid && sourceBodySHA256 == Self.digest(body) && sourcesMatch(body)
    }
    /// A changed source is a valid historical transcription, visibly stale. A
    /// matching body hash with invalid anchors is corrupt and cannot be restored.
    public func isValid(in document: HealthDocument) -> Bool {
        isValid && document.kind == .record && document.body.count <= RecordReview.maxCharacters && document.body.utf8.count <= RecordRetrieval.maxDocumentBytes &&
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
        Self.heading + "\n\nReviewed transcription, not clinical interpretation. Values, units, flags and reference wording were entered during review; the saved source excerpt can differ. Missing fields are unknown. No unit conversions or clinical comparisons were made.\n\n" +
        observations.enumerated().map { "Lab result \($0.offset + 1)\n" + $0.element.referenceText }.joined(separator: "\n\n")
    }
    public func markdown(body: String) -> String {
        let state = isCurrent(body: body) ? "Source text matches the reviewed version." : "SOURCE TEXT CHANGED: these earlier transcriptions have not been checked against the current text."
        return "\n\n" + state + "\nReview: " + reviewedAt.formatted() + "\n\n" + referenceText + "\n\nSaved transcription source excerpts\n\n" +
        observations.enumerated().map { "\($0.offset + 1). " + $0.element.source.excerpt }.joined(separator: "\n\n")
    }
    static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func bounded(_ value: String, limit: Int, required: Bool = false, multiline: Bool = true) -> Bool {
        value.count <= limit && value.utf8.count <= limit * 4 && (value.isEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) || (multiline && [9, 10, 13].contains($0.value)) }
    }
}
