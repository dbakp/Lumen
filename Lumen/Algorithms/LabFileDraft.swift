import Foundation

struct LabFileDraft: Sendable {
    struct Result: Identifiable, Sendable {
        var id: Int
        var included = true
        var observation: LabObservation
        let sourceText: String
        var sourceValid: Bool { observation.source.matches(sourceText) }
    }
    let id = UUID().uuidString
    let table: LabTable
    let mapping: [String: String]
    let subject: String
    var title: String
    var results: [Result]
    enum Failure: LocalizedError {
        case mapping, subject, subjectLength, identity, review, rows, source, invalid(Int), textLimit
        var errorDescription: String? {
            switch self {
            case .mapping: return "Choose separate columns for test name and reported result. Each mapped column can be used once."
            case .subject: return "Choose one subject group and check the intended person against the original file."
            case .subjectLength: return "The selected subject label must fit within 500 characters and contain no unsupported control characters. Check the mapped subject column."
            case .identity: return "Confirm that these are the intended person's results before continuing."
            case .review: return "Check the included results and their mapped source cells before saving."
            case .rows: return "Include between 1 and 256 results. Select fewer rows or split the file."
            case .source: return "Mapped source cells must fit within 2,000 characters per row. Exclude the row or map fewer optional columns."
            case .invalid(let row): return "Check the required fields and field lengths for included row \(row). Correct it using the original, or exclude that row."
            case .textLimit: return "The selected source cells and lab fields exceed this record's text-size limit. Select fewer rows."
            }
        }
    }
    init(table: LabTable, mapping: [String: String], subject: String, personChecked: Bool) throws {
        guard table.validates(mapping) else { throw Failure.mapping }
        guard table.subjects(mapping: mapping).contains(subject) else { throw Failure.subject }
        guard LabImportOrigin.validSubject(subject) else { throw Failure.subjectLength }
        guard personChecked else { throw Failure.identity }
        self.table = table; self.mapping = mapping; self.subject = subject
        title = String(URL(fileURLWithPath: table.filename).deletingPathExtension().lastPathComponent)
        results = table.rows.filter { row in (mapping["subject"].map { row.cells[$0]?.value ?? "" } ?? "") == subject }.map { row in
            func value(_ key: String) -> String { mapping[key].flatMap { row.cells[$0]?.value } ?? "" }
            let source = Self.source(row: row, mapping: mapping)
            var observation = LabObservation(test: value("test"), result: value("result"), unit: value("unit"), reference: value("reference"), flag: value("flag"), collectedOn: PlanDay.date(value("timing")) != nil ? value("timing") : nil, laboratory: value("laboratory"), specimen: value("specimen"), method: value("method"), source: .init(start: 0, end: source.count, excerpt: source))
            observation.reportedTiming = value("timing").isEmpty ? nil : value("timing")
            observation.reportedStatus = value("status").isEmpty ? nil : value("status")
            observation.importRow = row.id
            return Result(id: row.id, observation: observation, sourceText: source)
        }
    }
    private static func source(row: LabTable.Row, mapping: [String: String]) -> String {
        "Imported data row \(row.id) · mapped source cells\n" + LabColumn.allCases.compactMap { field -> String? in
            guard let column = mapping[field.rawValue] else { return nil }
            // A missing JSON member differs from an explicit null token. The
            // labels/layout are generated; only the source token is literal.
            let token = row.cells[column]?.token ?? "[Not present in this source row]"
            return field.label + " [" + column + "]:\n" + token
        }.joined(separator: "\n")
    }
    var includedCount: Int { results.filter(\.included).count }
    func hasDuplicate(in documents: [HealthDocument]) -> Bool {
        RecordReview.hasDuplicate(sha256: table.sha256, in: documents)
    }
    func document(acknowledged: Bool, now: Date = Date()) throws -> HealthDocument {
        guard acknowledged else { throw Failure.review }
        let selected = results.filter(\.included)
        guard !selected.isEmpty, selected.count <= LabReport.maxObservations else { throw Failure.rows }
        guard LabReport.bounded(title, limit: 500, required: true), now.timeIntervalSince1970.isFinite else { throw Failure.mapping }
        var body = "Original lab cell values from \(table.filename).\nLumen arranged these selected cells here; their spelling is unchanged. Your reviewed fields can be corrected separately. Keep the original file."
        var observations: [LabObservation] = []
        for row in selected {
            guard row.sourceValid else { throw Failure.source }
            guard row.observation.isValid else { throw Failure.invalid(row.id) }
            body += "\n\n"
            let start = body.count
            body += row.sourceText
            var observation = row.observation
            observation.source = .init(start: start, end: body.count, excerpt: row.sourceText)
            observation.importRow = row.id
            observations.append(observation)
            guard body.count <= RecordReview.maxCharacters else { throw Failure.textLimit }
        }
        var origin = LabImportOrigin(filename: table.filename, sha256: table.sha256, format: table.format, readAt: table.readAt, inputRows: table.rows.count, blankRows: table.blankRows, mapping: mapping, selectedRows: selected.map(\.id), subject: mapping["subject"] == nil ? nil : subject, separator: table.separator)
        origin.layoutSHA256 = LabReport.digest(body)
        var report = LabReport(reviewedAt: now, sourceBodySHA256: LabReport.digest(body), observations: observations)
        report.importedFrom = origin
        guard report.contentBytes <= LabReport.maxContentBytes else { throw Failure.textLimit }
        var document = HealthDocument(id: id, title: title, kind: .record, body: body, source: "Lab import · " + table.filename)
        document.labReport = report
        document.labImportOrigin = origin
        guard report.isValid(in: document), report.isCurrent(body: body) else { throw Failure.source }
        guard RecordRetrieval.text(document) != nil else { throw Failure.textLimit }
        return document
    }
}
