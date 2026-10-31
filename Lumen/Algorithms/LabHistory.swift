import Foundation

/// Local history of explicitly selected, currently reviewed source records.
/// Matching strings establish a display group, never clinical comparability.
enum LabHistory {
    static let maxRecords = 10
    static let maxPlotPoints = 256

    enum DecimalStyle: String, CaseIterable, Codable, Sendable {
        case dot, comma, literal
        var label: String {
            switch self { case .dot: return "Dot · 1.25"; case .comma: return "Comma · 1,25"; case .literal: return "Keep wording only" }
        }
        var explanation: String {
            switch self {
            case .dot: return "Dot is the decimal mark. Use wording only for numbers with thousands separators."
            case .comma: return "Comma is the decimal mark. Use wording only for numbers with thousands separators."
            case .literal: return "Wording only. No numbers were interpreted."
            }
        }
        var capturedExplanation: String {
            switch self {
            case .dot: return "Dot was used as the decimal mark. Thousands separators were not interpreted."
            case .comma: return "Comma was used as the decimal mark. Thousands separators were not interpreted."
            case .literal: return "Wording only. No numbers were interpreted."
            }
        }
    }
    enum Failure: LocalizedError {
        case records, missing, source(String), changed, person, review, pair, duplicate, size
        var errorDescription: String? {
            switch self {
            case .records: return "Choose between 1 and 10 distinct lab records."
            case .missing: return "A chosen record is no longer available. Check the record selection."
            case .source(let title): return "Open \(title) and review its current lab results before preparing history."
            case .changed: return "A source record changed. Prepare the history again and check the current results."
            case .person: return "Check that the selected records refer to the intended person."
            case .review: return "Check both results, their sources and number interpretation before saving."
            case .pair: return "Choose two different results from this history."
            case .duplicate: return "These results refer to the same imported cells. Choose independent source results."
            case .size: return "This comparison exceeds the saved-text limit. Keep the original reports separately."
            }
        }
    }
    struct SourceRecord: Identifiable, Sendable {
        let id: String
        let title: String
        let source: String
        let fingerprint: String
        let reviewedAt: Date
        let origin: LabImportOrigin?
        var fhirOrigin: FHIRLabImportOrigin? = nil
        var personLabel: String {
            if let fhirOrigin { return fhirOrigin.subjectLabel }
            guard let origin, let subject = origin.subject else { return "Person label not recorded" }
            return subject.isEmpty ? "Blank source subject cell" : subject
        }
    }
    struct Point: Identifiable, Sendable {
        let record: SourceRecord
        let observation: LabObservation
        let id: String
        let groupID: String
        let importedCellsID: String?
        let collectionDay: String?
        let fhirFieldsMatch: Bool
        init(record: SourceRecord, observation: LabObservation, fhirFieldsMatch: Bool = true) {
            self.record = record; self.observation = observation
            self.fhirFieldsMatch = fhirFieldsMatch
            id = key([record.id, observation.id])
            var context = [observation.test, observation.unit, observation.laboratory, observation.specimen, observation.method, observation.reportedStatus ?? ""]
            if let source = observation.fhirSource { context += ["Original FHIR coding", source.codingContext ?? "Invalid coding"] }
            else if record.fhirOrigin != nil { context += ["Original FHIR coding", "Not retained for this transcription"] }
            groupID = key(context)
            if let origin = record.origin, let row = observation.importRow {
                let mapping = origin.mapping.keys.sorted().flatMap { [$0, origin.mapping[$0] ?? ""] }
                importedCellsID = key([origin.sha256.lowercased(), String(row)] + mapping)
            } else { importedCellsID = observation.fhirSource?.resultIdentity }
            collectionDay = observation.collectedOn.flatMap { PlanDay.date($0, timeZone: TimeZone(secondsFromGMT: 0)!) == nil ? nil : $0 }
        }
        var fhirScalarIssue: String? {
            guard let source = observation.fhirSource else {
                return record.fhirOrigin == nil ? nil : "This transcription has no retained original FHIR value-form proof. Kept as wording; no numeric interpretation was made."
            }
            if !fhirFieldsMatch { return "The captured FHIR fields no longer match this record's source text. Original coding is historical; no numeric interpretation was made." }
            if !source.permitsScalar || !["preliminary", "final", "amended", "corrected"].contains(observation.reportedStatus ?? "") { return "The original FHIR result form or current reported status does not support an unqualified scalar comparison. Kept as wording." }
            return nil
        }
    }
    struct Selection: Sendable {
        let records: [SourceRecord]
        let points: [Point]
        let preparedAt: Date
        let groups: [Group]
        init(records: [SourceRecord], points: [Point], preparedAt: Date) {
            self.records = records; self.points = points; self.preparedAt = preparedAt
            // Preparation runs off the main actor. Cache exact identities,
            // validated dates and group ordering rather than rebuilding them
            // during every native view update.
            groups = Dictionary(grouping: points, by: \.groupID).map { Group(id: $0.key, points: ordered($0.value)) }.sorted {
                let left = $0.points[0].observation.test, right = $1.points[0].observation.test
                return literalEqual(left, right) ? $0.id < $1.id : left.utf8.lexicographicallyPrecedes(right.utf8)
            }
        }
    }
    struct Group: Identifiable, Sendable {
        let id: String
        let points: [Point]
        var exemplar: LabObservation { points[0].observation }
    }

    static func prepare(recordIDs: [String], documents: [HealthDocument], control: BackupOperationControl = .init(), now: Date = Date()) throws -> Selection {
        try control.checkCancellation()
        guard (1...maxRecords).contains(recordIDs.count), Set(recordIDs).count == recordIDs.count else { throw Failure.records }
        let wanted = Set(recordIDs)
        let chosen = documents.filter { wanted.contains($0.id) }
        guard chosen.count == recordIDs.count, Set(chosen.map(\.id)).count == chosen.count else { throw Failure.missing }
        var records: [SourceRecord] = [], points: [Point] = []
        for id in recordIDs {
            try control.checkCancellation()
            guard let document = chosen.first(where: { $0.id == id }), document.kind == .record,
                  LabReport.bounded(id, limit: 100, required: true, multiline: false),
                  LabReport.bounded(document.title, limit: 4000), LabReport.bounded(document.source, limit: 4000),
                  let report = document.labReport, document.hasValidLabImportOrigin, document.hasValidFHIRLabImport,
                  report.isValid(in: document), report.isCurrent(body: document.body),
                  let fingerprint = RecordRetrieval.fingerprint(document) else {
                let title = chosen.first(where: { $0.id == id }).map { LabTable.displayPreview($0.title, maxCharacters: 100).text } ?? "the record"
                throw Failure.source(title)
            }
            let record = SourceRecord(id: document.id, title: document.title, source: document.source, fingerprint: fingerprint, reviewedAt: report.reviewedAt, origin: document.originalLabImport, fhirOrigin: document.fhirLabImport)
            records.append(record)
            points += report.observations.map { Point(record: record, observation: $0, fhirFieldsMatch: $0.fhirSource?.matchesSource(in: document.body) ?? true) }
        }
        try control.checkCancellation()
        guard now.timeIntervalSince1970.isFinite else { throw Failure.changed }
        return Selection(records: records, points: ordered(points), preparedAt: now)
    }

    static func ordered(_ points: [Point]) -> [Point] {
        points.sorted {
            switch ($0.collectionDay, $1.collectionDay) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.id < $1.id
            }
        }
    }
    static func key(_ fields: [String]) -> String { LabReport.digest(fields.map { "\($0.utf8.count):" + $0 }.joined()) }
    static func literalEqual(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }

    enum NumberIssue: Error, Equatable, Sendable {
        case decimalChoice, wording, separator, precision, range, literalOnly
        var message: String {
            switch self {
            case .decimalChoice: return "Choose the reports' decimal mark, or keep wording only."
            case .wording: return "Qualified or nonnumeric result. Kept exactly as reported."
            case .separator: return "The value could not be read with the chosen decimal mark. Kept as reported."
            case .precision: return "The number exceeds exact decimal precision. Kept exactly as reported."
            case .range: return "The number is outside the supported decimal range. Kept exactly as reported."
            case .literalOnly: return "Kept as reported. Numeric interpretation was not selected."
            }
        }
    }
    struct Number: Sendable {
        let decimal: Decimal
        let canonical: String
        var plotValue: Double { NSDecimalNumber(decimal: decimal).doubleValue }
    }
    private struct DecimalToken: Equatable {
        let negative: Bool
        let digits: String
        let exponent: Int
    }
    private static let numberPattern = #"^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
    /// Normalize syntax only, with no numeric conversion or guessed grouping.
    private static func token(_ text: String) -> DecimalToken? {
        guard text.utf8.count <= 2000, text.range(of: numberPattern, options: .regularExpression) != nil else { return nil }
        var raw = text
        let negative = raw.first == "-"
        if raw.first == "+" || raw.first == "-" { raw.removeFirst() }
        let exponentParts = raw.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let explicitExponent: Int
        if exponentParts.count == 2 {
            guard let value = Int(exponentParts[1]), (-10000...10000).contains(value) else { return nil }
            explicitExponent = value
        } else { explicitExponent = 0 }
        let mantissa = exponentParts[0].split(separator: ".", omittingEmptySubsequences: false)
        let fraction = mantissa.count == 2 ? mantissa[1].count : 0
        var digits = mantissa.joined()
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty { return DecimalToken(negative: false, digits: "0", exponent: 0) }
        var exponent = explicitExponent - fraction
        while digits.last == "0" { digits.removeLast(); exponent += 1 }
        return DecimalToken(negative: negative, digits: digits, exponent: exponent)
    }
    /// Verify subtraction as signed decimal digits. Foundation can report
    /// noError after discarding a much smaller operand during scale alignment.
    private static func exactDifference(_ later: String, _ earlier: String) -> DecimalToken? {
        guard let a = token(later), let b = token(earlier) else { return nil }
        let exponent = min(a.exponent, b.exponent)
        let aZeros = a.exponent - exponent, bZeros = b.exponent - exponent
        guard aZeros <= 2048, bZeros <= 2048 else { return nil }
        var left = a.digits.map { Int($0.asciiValue! - 48) } + Array(repeating: 0, count: aZeros)
        var right = b.digits.map { Int($0.asciiValue! - 48) } + Array(repeating: 0, count: bZeros)
        while left.count > 1 && left.first == 0 { left.removeFirst() }
        while right.count > 1 && right.first == 0 { right.removeFirst() }
        let width = max(left.count, right.count)
        left = Array(repeating: 0, count: width - left.count) + left
        right = Array(repeating: 0, count: width - right.count) + right
        var digits = Array(repeating: 0, count: width), negative: Bool
        if a.negative != b.negative {
            negative = a.negative
            var carry = 0
            for i in (0..<width).reversed() { let n = left[i] + right[i] + carry; digits[i] = n % 10; carry = n / 10 }
            if carry != 0 { digits.insert(carry, at: 0) }
        } else {
            let leftSmaller = left.lexicographicallyPrecedes(right)
            let larger = leftSmaller ? right : left, smaller = leftSmaller ? left : right
            negative = leftSmaller ? !a.negative : a.negative
            var borrow = 0
            for i in (0..<width).reversed() {
                var n = larger[i] - smaller[i] - borrow
                borrow = n < 0 ? 1 : 0; if n < 0 { n += 10 }; digits[i] = n
            }
        }
        return token((negative ? "-" : "") + digits.map(String.init).joined() + "e" + String(exponent))
    }
    static func number(_ raw: String, style: DecimalStyle?) -> Result<Number, NumberIssue> {
        guard let style else { return .failure(.decimalChoice) }
        guard style != .literal else { return .failure(.literalOnly) }
        guard raw.count <= 500, raw.utf8.count <= 2000 else { return .failure(.range) }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Set("0123456789+-.eE,".utf8)
        guard text.utf8.allSatisfy(characters.contains) else { return .failure(.wording) }
        if text.contains(style == .dot ? "," : ".") { return .failure(.separator) }
        let normalized = style == .comma ? text.replacingOccurrences(of: ",", with: ".") : text
        if normalized.filter({ $0 == "." }).count > 1 { return .failure(.separator) }
        guard normalized.range(of: numberPattern, options: .regularExpression) != nil else { return .failure(.wording) }
        guard let original = token(normalized) else { return .failure(.range) }
        guard original.digits.count <= 38 else { return .failure(.precision) }
        guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), !decimal.isNaN else { return .failure(.range) }
        let canonical = NSDecimalNumber(decimal: decimal).stringValue
        // Foundation must not round a long coefficient or silently underflow to
        // zero. Verify its complete normalized decimal representation exactly.
        guard token(canonical) == original else { return .failure(.precision) }
        let value = Number(decimal: decimal, canonical: canonical)
        guard value.plotValue.isFinite, value.plotValue != 0 || original.digits == "0" else { return .failure(.range) }
        return .success(value)
    }

    enum PlotIssue: Equatable, Sendable {
        case person, decimalChoice, unit, laboratory, duplicates, tooMany(Int), context, range, wordingOnly, fhir(String)
        var message: String {
            switch self {
            case .person: return "Check the intended person before showing numeric results."
            case .decimalChoice: return "Choose the reports' decimal mark, or keep wording only."
            case .unit: return "A single-line reported unit is needed for the numeric view."
            case .laboratory: return "The laboratory is not recorded. Check the original reports."
            case .duplicates: return "Selected records repeat the same imported cells. Choose one copy in the record selection."
            case .tooMany(let count): return "This window has \(count.formatted()) numeric results. Narrow the dates to show up to \(maxPlotPoints.formatted()) points. All results remain in the list."
            case .context: return "These results have different recorded test or laboratory context."
            case .range: return "Choose a valid collection-day range."
            case .wordingOnly: return "Numeric view is off. Every reported value remains in the history below."
            case .fhir(let message): return message
            }
        }
    }
    struct PlotPoint: Identifiable, Sendable {
        let point: Point
        let day: Date
        let number: Number
        var id: String { point.id }
    }
    struct Omission: Sendable {
        let pointID: String
        let message: String
    }
    struct Plot: Sendable {
        let points: [PlotPoint]
        let numericDatedCount: Int
        let omitted: [Omission]
        let blockers: [PlotIssue]
        let warnings: [String]
    }
    static func plot(_ group: Group, style: DecimalStyle?, personChecked: Bool, days: ClosedRange<String>? = nil) -> Plot {
        guard !group.points.isEmpty, group.points.allSatisfy({ $0.groupID == group.id }) else { return Plot(points: [], numericDatedCount: 0, omitted: [], blockers: [.context], warnings: []) }
        if let days, PlanDay.date(days.lowerBound) == nil || PlanDay.date(days.upperBound) == nil {
            return Plot(points: [], numericDatedCount: 0, omitted: [], blockers: [.range], warnings: [])
        }
        let selected = group.points.filter { point in point.collectionDay.map { days?.contains($0) ?? true } ?? true }
        if style == .literal {
            return Plot(points: [], numericDatedCount: 0, omitted: selected.map { Omission(pointID: $0.id, message: $0.collectionDay == nil ? "Collection day not recorded. No date was inferred." : NumberIssue.literalOnly.message) }, blockers: personChecked ? [.wordingOnly] : [.person, .wordingOnly], warnings: contextWarnings(selected))
        }
        var blockers: [PlotIssue] = [], plotted: [PlotPoint] = [], omitted: [Omission] = []
        if !personChecked { blockers.append(.person) }
        if style == nil { blockers.append(.decimalChoice) }
        let example = group.exemplar
        if !LabReport.bounded(example.unit, limit: 100, required: true, multiline: false) { blockers.append(.unit) }
        if example.laboratory.isEmpty { blockers.append(.laboratory) }
        let origins = selected.compactMap(\.importedCellsID)
        if Set(origins).count != origins.count { blockers.append(.duplicates) }
        let events = selected.compactMap { $0.observation.fhirSource?.eventIdentity }
        if Set(events).count != events.count && !blockers.contains(.duplicates) { blockers.append(.duplicates) }
        for issue in Set(selected.compactMap(\.fhirScalarIssue)).sorted() { blockers.append(.fhir(issue)) }
        let utc = TimeZone(secondsFromGMT: 0)!
        for point in selected {
            guard let day = point.collectionDay, let date = PlanDay.date(day, timeZone: utc) else { omitted.append(Omission(pointID: point.id, message: "Collection day not recorded. No date was inferred.")); continue }
            switch number(point.observation.result, style: style) {
            case .success(let value): plotted.append(PlotPoint(point: point, day: date, number: value))
            case .failure(let issue): omitted.append(Omission(pointID: point.id, message: issue.message))
            }
        }
        if plotted.count > maxPlotPoints { blockers.append(.tooMany(plotted.count)) }
        return Plot(points: blockers.isEmpty ? plotted : [], numericDatedCount: plotted.count, omitted: omitted, blockers: blockers, warnings: contextWarnings(selected))
    }
    static func contextWarnings(_ points: [Point]) -> [String] {
        var warnings: [String] = []
        if points.contains(where: { $0.observation.specimen.isEmpty }) { warnings.append("Specimen is not recorded for every result.") }
        if points.contains(where: { $0.observation.method.isEmpty }) { warnings.append("Method is not recorded for every result.") }
        if points.contains(where: { ($0.observation.reportedStatus ?? "").isEmpty }) { warnings.append("Reported status is not recorded for every result.") }
        if Set(points.map { key([$0.observation.reference]) }).count > 1 { warnings.append("Reference wording differs. Use each report's own reference.") }
        return warnings
    }

    struct Comparison: Sendable {
        let first: Point
        let second: Point
        let chronological: Bool
        let difference: String?
        let reasons: [String]
        let warnings: [String]
    }
    static func compare(_ a: Point, _ b: Point, style: DecimalStyle?, personChecked: Bool) -> Comparison {
        let chronological = a.collectionDay != nil && b.collectionDay != nil && a.collectionDay != b.collectionDay
        let first = chronological && a.collectionDay! > b.collectionDay! ? b : a
        let second = chronological && a.collectionDay! > b.collectionDay! ? a : b
        var reasons: [String] = []
        if !personChecked { reasons.append(PlotIssue.person.message) }
        if first.id == second.id { reasons.append(Failure.pair.localizedDescription) }
        if first.importedCellsID != nil && first.importedCellsID == second.importedCellsID { reasons.append(Failure.duplicate.localizedDescription) }
        if let event = first.observation.fhirSource?.eventIdentity, event == second.observation.fhirSource?.eventIdentity { reasons.append("These FHIR results belong to the same original observation event. They are not independent measurements.") }
        for point in [first, second] { if let issue = point.fhirScalarIssue, !reasons.contains(issue) { reasons.append(issue) } }
        if first.groupID != second.groupID { reasons.append(PlotIssue.context.message) }
        if !LabReport.bounded(first.observation.unit, limit: 100, required: true, multiline: false) || !LabReport.bounded(second.observation.unit, limit: 100, required: true, multiline: false) { reasons.append(PlotIssue.unit.message) }
        if first.observation.laboratory.isEmpty || second.observation.laboratory.isEmpty { reasons.append(PlotIssue.laboratory.message) }
        if !chronological { reasons.append(a.collectionDay == nil || b.collectionDay == nil ? "A collection day is missing. Record timestamps were not used." : "The collection day is the same. Order within that day is unknown.") }
        var numbers: [Number] = []
        for (label, point) in [(chronological ? "Earlier result" : "First result", first), (chronological ? "Later result" : "Second result", second)] {
            switch number(point.observation.result, style: style) {
            case .success(let value): numbers.append(value)
            case .failure(let issue): reasons.append(label + ": " + issue.message)
            }
        }
        var difference: String?
        if reasons.isEmpty && numbers.count == 2 {
            var earlier = numbers[0].decimal, later = numbers[1].decimal, value = Decimal()
            let status = NSDecimalSubtract(&value, &later, &earlier, .plain)
            let canonical = NSDecimalNumber(decimal: value).stringValue
            if status == .noError, !value.isNaN,
               let expected = exactDifference(numbers[1].canonical, numbers[0].canonical), token(canonical) == expected,
               case .success = number(canonical, style: .dot) { difference = canonical }
            else { reasons.append("The exact decimal difference cannot be represented. Both reported values are retained.") }
        }
        return Comparison(first: first, second: second, chronological: chronological, difference: difference, reasons: reasons, warnings: contextWarnings([first, second]))
    }

    static func snapshot(_ selection: Selection, firstID: String, secondID: String, style: DecimalStyle?, personChecked: Bool, acknowledged: Bool, currentDocuments: [HealthDocument], now: Date = Date()) throws -> HealthDocument {
        guard personChecked else { throw Failure.person }
        guard acknowledged, style != nil else { throw Failure.review }
        let current = try prepare(recordIDs: selection.records.map(\.id), documents: currentDocuments, now: now)
        guard zip(selection.records, current.records).allSatisfy({ $0.id == $1.id && $0.fingerprint == $1.fingerprint && $0.reviewedAt == $1.reviewedAt }) else { throw Failure.changed }
        guard firstID != secondID, let first = current.points.first(where: { $0.id == firstID }), let second = current.points.first(where: { $0.id == secondID }) else { throw Failure.pair }
        guard first.importedCellsID == nil || first.importedCellsID != second.importedCellsID else { throw Failure.duplicate }
        let result = compare(first, second, style: style, personChecked: true)
        let body = snapshotText(result, style: style!, now: now)
        guard body.count <= RecordReview.maxCharacters, body.utf8.count <= RecordRetrieval.maxDocumentBytes else { throw Failure.size }
        var document = HealthDocument(title: "Lab comparison · " + (result.chronological ? result.first.collectionDay! + " to " + result.second.collectionDay! : "reported results"), kind: .review, body: body, source: "Lumen · checked lab comparison snapshot")
        document.createdAt = now; document.updatedAt = now; document.includeInAssistant = false
        document.labComparison = LabComparisonSnapshot(savedAt: now, decimalStyle: style!.rawValue, sources: [.init(result.first), .init(result.second)], numberDifference: result.difference, reasons: result.reasons, warnings: result.warnings, bodySHA256: LabReport.digest(body))
        guard document.labComparison!.isValid(in: document) else { throw Failure.changed }
        return document
    }
    static func snapshotText(_ result: Comparison, style: DecimalStyle, now: Date) -> String {
        let iso = ISO8601DateFormatter()
        var body = "Independent lab comparison snapshot. Checked and saved \(iso.string(from: now)). Later edits or deletion of source records do not update this separate copy. Check the current original reports before relying on it.\n\nNumber interpretation: \(style.capturedExplanation)\nThe selected records were checked by you as belonging to the intended person. This snapshot does not establish clinical comparability or interpret results."
        if let difference = result.difference {
            body += "\n\n## Number difference\nLater minus earlier: \(difference)\nReported unit: \(result.first.observation.unit)\nArithmetic in the reported units, not a relative percentage or clinical assessment."
        } else { body += "\n\n## Literal comparison\nNo numeric difference was calculated.\n" + result.reasons.joined(separator: "\n") }
        if !result.warnings.isEmpty { body += "\n\nContext to check\n" + result.warnings.joined(separator: "\n") }
        for (label, point) in [(result.chronological ? "Earlier result" : "First result", result.first), (result.chronological ? "Later result" : "Second result", result.second)] {
            body += "\n\n## \(label)\nRecord: \(point.record.title)\nRecord source: \(point.record.source)\nRecord ID: \(point.record.id)\nResult ID: \(point.observation.id)\nSource content SHA-256: \(point.record.fingerprint)\nSource review: \(iso.string(from: point.record.reviewedAt))\nOriginal person label: \(point.record.personLabel)\n\n\(point.observation.referenceText)\n\nExact saved source excerpt\n\(point.observation.source.excerpt)"
            if let origin = point.record.origin { body += "\n\nHistorical original-file receipt\n" + origin.referenceText }
            if let origin = point.record.fhirOrigin { body += "\n\nHistorical FHIR import receipt\n" + origin.referenceText }
        }
        return body
    }
}
