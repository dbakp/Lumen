import Foundation

/// A separately saved, user-reviewed copy. It never updates its source records.
public struct LabComparisonSnapshot: Codable, Sendable, Equatable {
    public var version = 1
    public var savedAt: Date
    public var decimalStyle: String
    public var sources: [LabComparisonSource]
    public var numberDifference: String?
    public var reasons: [String]
    public var warnings: [String]
    public var bodySHA256: String

    public var isValid: Bool {
        guard version == 1, savedAt.timeIntervalSince1970.isFinite,
              let style = LabHistory.DecimalStyle(rawValue: decimalStyle), sources.count == 2,
              sources.allSatisfy(\.isValid), sources[0].id != sources[1].id,
              bodySHA256.count == 64, bodySHA256.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              reasons.count <= 16, warnings.count <= 16,
              (reasons + warnings).allSatisfy({ LabReport.bounded($0, limit: 2000, required: true) }) else { return false }
        let a = sources[0].point, b = sources[1].point
        guard a.importedCellsID == nil || a.importedCellsID != b.importedCellsID else { return false }
        let expected = LabHistory.compare(a, b, style: style, personChecked: true)
        switch (expected.difference, numberDifference) {
        case (nil, nil): return !reasons.isEmpty
        case let (expected?, stored?):
            guard reasons.isEmpty,
                  let left = try? LabHistory.number(expected, style: .dot).get(),
                  let right = try? LabHistory.number(stored, style: .dot).get() else { return false }
            return left.decimal == right.decimal
        default: return false
        }
    }
    public func isValid(in document: HealthDocument) -> Bool {
        isValid && document.labReport == nil && document.labImportOrigin == nil && document.fhirLabImport == nil && sources.allSatisfy { $0.documentID != document.id } &&
        document.body.count <= RecordReview.maxCharacters && document.body.utf8.count <= RecordRetrieval.maxDocumentBytes
    }
    public func isCurrent(body: String) -> Bool { isValid && LabReport.digest(body) == bodySHA256.lowercased() }

    var capturedComparison: LabHistory.Comparison {
        let comparison = LabHistory.compare(sources[0].point, sources[1].point, style: LabHistory.DecimalStyle(rawValue: decimalStyle), personChecked: true)
        return LabHistory.Comparison(first: comparison.first, second: comparison.second, chronological: comparison.chronological, difference: numberDifference, reasons: reasons, warnings: warnings)
    }
    var capturedText: String {
        guard isValid, let style = LabHistory.DecimalStyle(rawValue: decimalStyle) else { return "" }
        return LabHistory.snapshotText(capturedComparison, style: style, now: savedAt)
    }
    func markdown(body: String) -> String {
        guard isValid else { return "" }
        if isCurrent(body: body) { return "" }
        return "\n\n## Earlier captured lab comparison\nThe document text was edited after this comparison was captured. These earlier values are a separate historical snapshot.\n\n" + capturedText
    }
}

public struct LabComparisonSource: Codable, Sendable, Equatable, Identifiable {
    public var documentID: String
    public var title: String
    public var source: String
    public var fingerprint: String
    public var reviewedAt: Date
    public var origin: LabImportOrigin?
    public var observation: LabObservation
    public var fhirOrigin: FHIRLabImportOrigin? = nil
    public var fhirFieldsMatched: Bool? = nil
    public var id: String { LabHistory.key([documentID, observation.id]) }

    init(_ point: LabHistory.Point) {
        documentID = point.record.id; title = point.record.title; source = point.record.source
        fingerprint = point.record.fingerprint; reviewedAt = point.record.reviewedAt
        origin = point.record.origin; observation = point.observation
        fhirOrigin = point.record.fhirOrigin; fhirFieldsMatched = observation.fhirSource == nil ? nil : point.fhirFieldsMatch
    }
    var point: LabHistory.Point {
        .init(record: .init(id: documentID, title: title, source: source, fingerprint: fingerprint, reviewedAt: reviewedAt, origin: origin, fhirOrigin: fhirOrigin), observation: observation, fhirFieldsMatch: fhirFieldsMatched ?? true)
    }
    public var isValid: Bool {
        LabReport.bounded(documentID, limit: 100, required: true, multiline: false) &&
        LabReport.bounded(title, limit: 4000) && title.utf8.count <= 4000 &&
        LabReport.bounded(source, limit: 4000) && source.utf8.count <= 4000 &&
        fingerprint.count == 64 && fingerprint.allSatisfy { $0.isASCII && $0.isHexDigit } &&
        reviewedAt.timeIntervalSince1970.isFinite && observation.isValid && (origin?.isValid ?? true) &&
        (observation.importRow.map { origin?.selectedRows.contains($0) == true } ?? true) &&
        (fhirOrigin.map { $0.isValid && origin == nil } ?? true) &&
        (observation.fhirSource.map { source in fhirFieldsMatched != nil && (fhirOrigin.map { source.inputSHA256.lowercased() == $0.sha256.lowercased() && $0.selectedPaths.contains(source.resultPath) } ?? false) } ?? (fhirFieldsMatched == nil))
    }
    enum State: String, Sendable { case matching, changed, removed, needsReview }
    func state(in documents: [HealthDocument]) -> State {
        guard let document = documents.first(where: { $0.id == documentID }) else { return .removed }
        guard document.kind == .record, document.hasValidLabImportOrigin, document.hasValidFHIRLabImport,
              let report = document.labReport, report.isValid(in: document), report.isCurrent(body: document.body) else { return .needsReview }
        guard RecordRetrieval.fingerprint(document) == fingerprint.lowercased(),
              report.observations.first(where: { $0.id == observation.id }) == observation else { return .changed }
        return .matching
    }
}
