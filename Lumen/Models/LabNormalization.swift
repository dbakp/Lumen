import Foundation

/// A supplied identifier, not a terminology lookup or proof of authorship.
public struct LabTestCode: Codable, Equatable, Sendable {
    public let system: String
    public let code: String
    public let version: String?
    var id: String { LabHistory.key([system, code, version ?? ""]) }
    var authority: String { LabHistory.key([system]) }
    var unversionedID: String { LabHistory.key([system, code]) }
    var isValid: Bool {
        LabReport.bounded(system, limit: 1000, required: true, multiline: false) && FHIRResourceArchive.isAbsolute(system) &&
        LabReport.bounded(code, limit: 1000, required: true, multiline: false) &&
        (version.map { LabReport.bounded($0, limit: 200, required: true, multiline: false) } ?? true)
    }
    var text: String { system + " · " + code + (version.map { " · version " + $0 } ?? "") }
}

public struct LabUnitAssignment: Codable, Equatable, Sendable {
    public var pointID: String
    public var code: String
    public var checked = false
}

/// Only a separate comparison owns these choices; source records stay literal.
public struct LabNormalizationReview: Codable, Equatable, Sendable {
    public enum TestMatch: String, Codable, Sendable { case reportedName, originalCoding, reviewedNames }
    public var version = 1
    public var units: [LabUnitAssignment]
    public var targetCode: String
    public var testMatch: TestMatch?
    public var testCode: LabTestCode?
    public var testChecked = false
    var isBounded: Bool {
        version == 1 && units.count == 2 && Set(units.map(\.pointID)).count == 2 &&
        units.allSatisfy { $0.pointID.count == 64 && $0.pointID.allSatisfy { $0.isASCII && $0.isHexDigit } && Self.codeBounded($0.code) } &&
        Self.codeBounded(targetCode) && (testCode?.isValid ?? true)
    }
    var isReviewed: Bool { isBounded && units.allSatisfy(\.checked) && testChecked && testMatch != nil && (testMatch == .originalCoding ? testCode != nil : testCode == nil) }
    private static func codeBounded(_ text: String) -> Bool { !text.isEmpty && text.utf8.count <= 128 && text.utf8.allSatisfy { (33...126).contains($0) } }
    private enum CodingKeys: String, CodingKey { case version, units, targetCode, testMatch, testCode, testChecked }
    public init(version: Int = 1, units: [LabUnitAssignment], targetCode: String, testMatch: TestMatch? = nil, testCode: LabTestCode? = nil, testChecked: Bool = false) {
        self.version = version; self.units = units; self.targetCode = targetCode; self.testMatch = testMatch; self.testCode = testCode; self.testChecked = testChecked
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version); targetCode = try c.decode(String.self, forKey: .targetCode)
        testMatch = try c.decodeIfPresent(TestMatch.self, forKey: .testMatch); testCode = try c.decodeIfPresent(LabTestCode.self, forKey: .testCode)
        testChecked = try c.decode(Bool.self, forKey: .testChecked)
        var array = try c.nestedUnkeyedContainer(forKey: .units), decoded: [LabUnitAssignment] = []
        while !array.isAtEnd {
            guard decoded.count < 2 else { throw DecodingError.dataCorruptedError(forKey: .units, in: c, debugDescription: "A unit review must contain exactly two assignments") }
            decoded.append(try array.decode(LabUnitAssignment.self))
        }
        units = decoded
        guard isBounded else { throw DecodingError.dataCorruptedError(forKey: .units, in: c, debugDescription: "Invalid or oversized unit review") }
    }
}

enum LabNormalization {
    struct Converted: Sendable {
        let pointID: String
        let sourceCode: String
        let value: String
        let factor: String
        let basis: String
    }
    struct Values: Sendable {
        let review: LabNormalizationReview
        let converted: [Converted]
        let identity: String
        var unit: String { review.targetCode }
    }
    struct SourceFacts: Sendable, Equatable {
        let codes: [LabTestCode]
        let complete: Bool
        let unitSystem: String?
        let unitCode: String?
        let unitDisplay: String?
        let clinicalContext: String
    }
    /// This is a displayed proposal, never an automatically applied alias.
    static func printedCandidate(_ text: String) -> String {
        text.replacingOccurrences(of: "µ", with: "u").replacingOccurrences(of: "μ", with: "u")
    }
    static func sharedCodes(_ a: LabHistory.Point, _ b: LabHistory.Point) -> [LabTestCode] {
        let left = a.observation.fhirSource?.normalizationFacts?.codes ?? []
        let right = Set((b.observation.fhirSource?.normalizationFacts?.codes ?? []).map(\.id))
        return left.filter { right.contains($0.id) }
    }
    static func conflictingCodes(_ a: LabHistory.Point, _ b: LabHistory.Point) -> Bool {
        let left = Dictionary(grouping: a.observation.fhirSource?.normalizationFacts?.codes ?? [], by: \.authority)
        let right = Dictionary(grouping: b.observation.fhirSource?.normalizationFacts?.codes ?? [], by: \.authority)
        return left.contains { authority, codes in
            right[authority].map { Set(codes.map(\.unversionedID)) != Set($0.map(\.unversionedID)) } ?? false
        }
    }
    static func proposedCode(_ point: LabHistory.Point) -> String {
        let observation = point.observation, facts = observation.fhirSource?.normalizationFacts
        if let facts, facts.unitSystem == "http://unitsofmeasure.org", let code = facts.unitCode,
           LabHistory.literalEqual(observation.unit, facts.unitDisplay ?? "") { return code }
        return printedCandidate(observation.unit)
    }
    static func assignmentBasis(_ point: LabHistory.Point, code: String) throws -> String {
        let assigned = try LabUnit.parse(code), printed = point.observation.unit
        let candidate = printedCandidate(printed)
        var bases: [String] = []
        if let known = try? LabUnit.parse(candidate) {
            guard known.sameMagnitude(as: assigned) else { throw ReviewFailure.unitConflict }
            bases.append(LabHistory.literalEqual(candidate, printed) ? "Reviewed reported unit code" : "Your reviewed micro-sign mapping")
        }
        if let facts = point.observation.fhirSource?.normalizationFacts,
           facts.unitSystem == "http://unitsofmeasure.org", let original = facts.unitCode,
           LabHistory.literalEqual(printed, facts.unitDisplay ?? "") {
            let known = try LabUnit.parse(original)
            guard known.sameMagnitude(as: assigned) else { throw ReviewFailure.unitConflict }
            bases.append("Original FHIR UCUM code; reviewed unit unchanged")
        }
        if bases.isEmpty {
            guard !printed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReviewFailure.unitMissing }
            // Known unsupported/arbitrary/annotated printed forms cannot escape
            // their boundary through the manual-assignment path.
            let forbiddenAtom = #"(?:^|[^A-Za-z])(?:da|[YZEPTGMkhdcmunpfazy])?(?:IU|iU|AU|Cel)(?:[^A-Za-z]|$)"#
            if printed.contains("{") || printed.contains("}") || printed.contains("[") || printed.contains("]") || printed.contains("°") ||
                printed.range(of: forbiddenAtom, options: .regularExpression) != nil || printed == "a.u." { throw ReviewFailure.unitUnsupported }
            bases.append("Your unit-code assignment; original wording unverified")
        }
        if let facts = point.observation.fhirSource?.normalizationFacts, facts.unitCode != nil,
           !LabHistory.literalEqual(printed, facts.unitDisplay ?? "") {
            bases.append("Reviewed unit changed; original FHIR unit code is historical")
        }
        return bases.joined(separator: "; ")
    }
    enum ReviewFailure: Error {
        case unitConflict, unitMissing, unitUnsupported
        var message: String {
            switch self {
            case .unitConflict: return "The assigned code changes a known reported unit's magnitude or quantity. Check the source; no conversion was made."
            case .unitMissing: return "No reported or original coded unit is available. An unknown unit was not filled in."
            case .unitUnsupported: return "The reported unit is annotated, arbitrary or unsupported. Keep the literal comparison."
            }
        }
    }
    static func compare(_ a: LabHistory.Point, _ b: LabHistory.Point, style: LabHistory.DecimalStyle?, personChecked: Bool, review: LabNormalizationReview) -> LabHistory.Comparison {
        let chronological = a.collectionDay != nil && b.collectionDay != nil && a.collectionDay != b.collectionDay
        let first = chronological && a.collectionDay! > b.collectionDay! ? b : a
        let second = chronological && a.collectionDay! > b.collectionDay! ? a : b
        var reasons = LabHistory.comparisonReasons(first, second, personChecked: personChecked, chronological: chronological, exactContext: false, printedUnits: false)
        if !review.isReviewed { reasons.append("Check both unit assignments, the target unit and the test identity before converting.") }
        if Set(review.units.map(\.pointID)) != Set([first.id, second.id]) { reasons.append("The unit assignments no longer belong to these selected results.") }
        let left = first.observation, right = second.observation
        let contexts = [(left.laboratory, right.laboratory), (left.specimen, right.specimen), (left.method, right.method), (left.reportedStatus ?? "", right.reportedStatus ?? "")]
        if !contexts.allSatisfy({ LabHistory.literalEqual($0.0, $0.1) }) { reasons.append("The recorded laboratory, specimen, method or status differs. Unit conversion does not resolve that context.") }
        let sourceA = left.fhirSource?.normalizationFacts, sourceB = right.fhirSource?.normalizationFacts
        if sourceA?.complete == false || sourceB?.complete == false { reasons.append("Original test coding is incomplete or has unsupported structure. No identity was inferred.") }
        if let sourceA, let sourceB, sourceA.clinicalContext != sourceB.clinicalContext { reasons.append("Original FHIR method, body-site or specimen-type context differs. It remains separate.") }
        if conflictingCodes(first, second) { reasons.append("The original reports supply conflicting test codes. A name match cannot override them.") }
        var identity = "Test identity not reviewed"
        switch review.testMatch {
        case .reportedName:
            identity = "Exact reviewed reported test names"
            if !LabHistory.literalEqual(left.test, right.test) { reasons.append("The reported test names differ. Review their identity explicitly.") }
        case .originalCoding:
            if let code = review.testCode, sharedCodes(first, second).contains(where: { $0.id == code.id }) { identity = "Matching supplied test code: " + code.text }
            else { reasons.append("The chosen test code is not shared by both original source captures.") }
        case .reviewedNames: identity = "Your reviewed test-name match; no terminology equivalence was verified"
        case nil: reasons.append("Choose how the two test identities were checked.")
        }
        var converted: [Converted] = [], numbers: [LabHistory.Number] = []
        if review.isBounded,
           let codeA = review.units.first(where: { $0.pointID == first.id })?.code,
           let codeB = review.units.first(where: { $0.pointID == second.id })?.code,
           let unitA = try? LabUnit.parse(codeA), let unitB = try? LabUnit.parse(codeB), !unitA.compatibleQuantity(with: unitB) {
            reasons.append("The assigned source units describe different quantities or fraction bases. A common target does not make them comparable.")
        }
        if reasons.isEmpty && review.isReviewed && review.isBounded {
            for (label, point) in [(chronological ? "Earlier result" : "First result", first), (chronological ? "Later result" : "Second result", second)] {
                guard let assignment = review.units.first(where: { $0.pointID == point.id }) else { continue }
                do {
                    let basis = try assignmentBasis(point, code: assignment.code)
                    let value = try LabUnit.convert(point.observation.result, style: style, from: LabUnit.parse(assignment.code), to: LabUnit.parse(review.targetCode))
                    numbers.append(value.number)
                    converted.append(.init(pointID: point.id, sourceCode: assignment.code, value: value.number.canonical, factor: value.factor, basis: basis))
                } catch let error as LabUnit.Failure { reasons.append(label + ": " + error.message) }
                catch let error as ReviewFailure { reasons.append(label + ": " + error.message) }
                catch { reasons.append(label + ": The unit assignment could not be checked. Keep the literal result.") }
            }
        }
        var difference: String?
        if reasons.isEmpty && numbers.count == 2 {
            difference = LabHistory.checkedDifference(later: numbers[1], earlier: numbers[0])
            if difference == nil { reasons.append("The exact converted difference cannot be represented. Both reported values are retained.") }
        }
        let values = Values(review: review, converted: converted, identity: identity)
        return .init(first: first, second: second, chronological: chronological, difference: difference, reasons: reasons, warnings: LabHistory.contextWarnings([first, second]), normalization: values)
    }
}
