import Foundation

enum LabReview {
    enum Failure: LocalizedError {
        case unsupported, sourceChanged, review, invalid, textLimit
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Add lab results to a saved record with text."
            case .sourceChanged: return "This record changed while you were reviewing it. Reopen the lab review and check the current text."
            case .review: return "Check every result, unit, reference and source before saving."
            case .invalid: return "Give each result a test name, reported result and matching source excerpt. Check field lengths and collection dates."
            case .textLimit: return "The record and its lab fields exceed the 200,000-character search limit. Split this record before adding the results."
            }
        }
    }
    struct Draft: Sendable {
        let documentID: String
        let originalFingerprint: String
        let sourceBody: String
        let originalReport: LabReport?
        var observations: [LabObservation]
        init(document: HealthDocument) throws {
            guard document.kind == .record, !document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  document.body.count <= RecordReview.maxCharacters, let fingerprint = RecordRetrieval.fingerprint(document) else { throw Failure.unsupported }
            documentID = document.id; originalFingerprint = fingerprint; sourceBody = document.body; originalReport = document.labReport
            // A stale saved transcription stays available for explicit correction;
            // its old anchors must be selected again before it can be saved.
            observations = document.labReport?.observations ?? []
        }
        func applying(to current: HealthDocument, acknowledged: Bool, now: Date = Date()) throws -> HealthDocument {
            guard current.id == documentID, current.kind == .record,
                  current.body == sourceBody, current.labReport == originalReport, RecordRetrieval.fingerprint(current) == originalFingerprint else { throw Failure.sourceChanged }
            guard acknowledged else { throw Failure.review }
            if observations.isEmpty, originalReport != nil {
                var result = current; result.labImportOrigin = current.originalLabImport; result.labReport = nil; return result
            }
            var report = LabReport(reviewedAt: now, sourceBodySHA256: LabReport.digest(sourceBody), observations: observations)
            report.importedFrom = current.originalLabImport
            guard report.isCurrent(body: sourceBody) else { throw Failure.invalid }
            var result = current; result.labReport = report; result.labImportOrigin = current.originalLabImport
            guard RecordRetrieval.text(result) != nil else { throw Failure.textLimit }
            // Use the latest sharing choice, not the value when the draft opened.
            return result
        }
    }
    /// Offsets are Swift Character offsets, exactly like Library retrieval.
    /// Blank/overlong source lines are not silently truncated into selectable text.
    static func sources(in body: String) -> [LabTextSource] {
        guard body.count <= RecordReview.maxCharacters else { return [] }
        var result: [LabTextSource] = [], start = 0
        let chars = Array(body)
        func append(_ end: Int) {
            let source = LabTextSource(start: start, end: end, excerpt: String(chars[start..<end]))
            if source.isValid { result.append(source) }
        }
        for (index, char) in chars.enumerated() where char == "\n" || char == "\r" || char == "\r\n" {
            append(index); start = index + 1
        }
        append(chars.count)
        return result
    }
    /// Include an adjacent full source line without changing its whitespace,
    /// decimal punctuation or reading order. The excerpt still has a 2,000
    /// character ceiling; do not silently clip an overlong expansion.
    static func extending(_ source: LabTextSource, in body: String, forward: Bool) -> LabTextSource? {
        guard source.matches(body) else { return nil }
        let chars = Array(body)
        func newline(_ value: Character) -> Bool { value == "\n" || value == "\r" || value == "\r\n" }
        var start = source.start, end = source.end
        if forward {
            guard end < chars.count, newline(chars[end]) else { return nil }
            end = chars[(end + 1)...].firstIndex(where: newline) ?? chars.count
        } else {
            guard start > 0, newline(chars[start - 1]) else { return nil }
            start = chars[..<(start - 1)].lastIndex(where: newline).map { $0 + 1 } ?? 0
        }
        let value = LabTextSource(start: start, end: end, excerpt: String(chars[start..<end]))
        return value.isValid ? value : nil
    }
}
