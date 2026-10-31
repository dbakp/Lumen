import Foundation

/// One intended-person review. Original fields remain immutable while the
/// transcription can be corrected or explicitly excluded before checked save.
struct FHIRLabDraft: Sendable {
    struct Result: Identifiable, Sendable {
        let proposal: FHIRLabPreparation.Result
        let original: FHIRResultSource?
        let anchor: LabTextSource?
        var id: String { proposal.id }
        var included = true
        var observation: LabObservation
        var sourceText: String { proposal.sourceText }
        var sourceValid: Bool { anchor.map { observation.source == $0 && $0.matches(sourceText) } ?? false }
        var sourceIssue: String? {
            if !proposal.issues.isEmpty { return proposal.issues.joined(separator: "\n") }
            if original == nil { return "These original fields cannot be retained as a valid FHIR result. Exclude this result or use a corrected export." }
            if !sourceValid { return "This result needs an unchanged source excerpt of at most 2,000 characters. Exclude it or use a smaller export." }
            return nil
        }
    }
    let id = UUID().uuidString
    let preparation: FHIRLabPreparation
    let subject: FHIRLabPreparation.Subject
    var title: String
    var results: [Result]
    enum Failure: LocalizedError {
        case coverage, person, review, rows, title, source(String), invalid(String), textLimit
        var errorDescription: String? {
            switch self {
            case .coverage: return "Review the file's complete coverage, unresolved links and fields not retained before continuing."
            case .person: return "Choose one observation person group and confirm the intended person against the original file."
            case .review: return "Check the included results and original FHIR fields before saving."
            case .rows: return "Include between 1 and 256 results. Exclude other results or split the export."
            case .title: return "Add a title of at most 500 characters with no unsupported control characters."
            case .source(let path): return "Check the source issue at \(path.isEmpty ? "the file root" : path). Exclude that result or use a corrected export."
            case .invalid(let path): return "Check the required fields and lengths at \(path.isEmpty ? "the file root" : path). Correct the transcription using the original or exclude it."
            case .textLimit: return "These selected source fields exceed the saved record's text limit. Include fewer results."
            }
        }
    }
    init(preparation: FHIRLabPreparation, subjectKey: String, personChecked: Bool, coverageReviewed: Bool, control: BackupOperationControl = .init()) throws {
        try control.checkCancellation()
        guard coverageReviewed else { throw Failure.coverage }
        guard personChecked, let subject = preparation.results.first(where: { $0.subject.key == subjectKey })?.subject else { throw Failure.person }
        self.preparation = preparation; self.subject = subject
        title = URL(fileURLWithPath: preparation.archive.filename).deletingPathExtension().lastPathComponent
        results = try preparation.results.filter { $0.subject.key == subjectKey }.map { proposal in
            try control.checkCancellation()
            // Related report context may be much longer than a transcription
            // excerpt. Anchor only an own value/code token; retain all captured
            // context separately, without clipping it to this legacy limit.
            let anchor = Self.anchor(proposal)
            var observation = LabObservation(test: proposal.test, result: proposal.result, unit: proposal.unit, reference: proposal.reference, flag: proposal.flag, laboratory: proposal.laboratory, specimen: proposal.specimen, method: proposal.method, source: anchor ?? .init(start: 0, end: 0, excerpt: ""))
            observation.reportedTiming = proposal.collectionWording.isEmpty ? nil : proposal.collectionWording
            observation.reportedStatus = proposal.status.isEmpty ? nil : proposal.status
            let original = preparation.capturedSource(for: proposal.id)
            observation.fhirSource = original
            return Result(proposal: proposal, original: original, anchor: anchor, observation: observation)
        }
    }
    private static func anchor(_ proposal: FHIRLabPreparation.Result) -> LabTextSource? {
        let candidates = [proposal.id + "/" + proposal.valueKind, proposal.id + "/code"]
        guard let field = candidates.compactMap({ path in proposal.fields.first { $0.path == path && LabReport.bounded($0.token, limit: 2000, required: true) } }).first else { return nil }
        var prefix = "Selected FHIR source fields · " + (proposal.id.isEmpty ? "file root" : proposal.id) + "\n"
        for (index, current) in proposal.fields.enumerated() {
            if index > 0 { prefix += "\n" }
            prefix += current.path + ":\n"
            if current.path == field.path {
                return .init(start: prefix.count, end: prefix.count + current.token.count, excerpt: current.token)
            }
            prefix += current.token
        }
        return nil
    }
    var includedCount: Int { results.filter(\.included).count }
    func hasDuplicate(in documents: [HealthDocument]) -> Bool { RecordReview.hasDuplicate(sha256: preparation.archive.sha256, in: documents) }
    func document(acknowledged: Bool, now: Date = Date(), control: BackupOperationControl = .init()) throws -> HealthDocument {
        try control.checkCancellation()
        guard acknowledged else { throw Failure.review }
        guard LabReport.bounded(title, limit: 500, required: true), now.timeIntervalSince1970.isFinite else { throw Failure.title }
        let selected = results.filter(\.included)
        guard !selected.isEmpty, selected.count <= LabReport.maxObservations else { throw Failure.rows }
        var body = "Original FHIR fields from \(preparation.archive.filename).\nLumen arranged these selected fields; JSON paths and token spelling are retained. Reviewed transcriptions can be corrected separately. This is not the original file layout or a complete clinical record. Keep the original file separately."
        var observations: [LabObservation] = []
        for row in selected {
            try control.checkCancellation()
            guard row.sourceIssue == nil, let anchor = row.anchor, let original = row.original,
                  row.proposal.subject.key == subject.key, preparation.capturedSource(for: row.id) == original,
                  row.observation.fhirSource == original, row.observation.importRow == nil else { throw Failure.source(row.id) }
            guard row.observation.isValid else { throw Failure.invalid(row.id) }
            body += "\n\n"
            let offset = body.count
            body += row.sourceText
            var observation = row.observation
            observation.source = .init(start: offset + anchor.start, end: offset + anchor.end, excerpt: anchor.excerpt)
            observations.append(observation)
            guard body.count <= RecordReview.maxCharacters, body.utf8.count <= RecordRetrieval.maxDocumentBytes else { throw Failure.textLimit }
        }
        let coverage = preparation.coverage
        let unresolved = coverage.links.filter { if case .found = $0.resolution { return false }; return true }.count
        let origin = FHIRLabImportOrigin(version: 1, filename: preparation.archive.filename, sha256: preparation.archive.sha256, readAt: preparation.archive.readAt, inputEntries: coverage.entries, inputResources: coverage.resources, proposedResults: coverage.resultRows, selectedPaths: selected.map(\.id), subjectKey: subject.key, subjectLabel: subject.label, hasNextPage: coverage.hasNextPage, unresolvedLinks: unresolved, omittedFields: coverage.omittedResourceFields.values.reduce(0) { $0 + $1.count })
        let reviewedAt = max(now, preparation.archive.readAt)
        let report = LabReport(reviewedAt: reviewedAt, sourceBodySHA256: LabReport.digest(body), observations: observations)
        guard report.contentBytes <= LabReport.maxContentBytes else { throw Failure.textLimit }
        var document = HealthDocument(id: id, title: title, kind: .record, body: body, source: "FHIR lab import · " + preparation.archive.filename)
        document.createdAt = reviewedAt; document.updatedAt = reviewedAt
        document.fhirLabImport = origin; document.labReport = report
        guard document.hasValidFHIRLabImport, report.isValid(in: document), report.isCurrent(body: body) else { throw Failure.source("") }
        guard RecordRetrieval.text(document) != nil else { throw Failure.textLimit }
        try control.checkCancellation()
        return document
    }
}
