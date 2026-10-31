import Foundation

enum LabNormalizationChecks {
    static func run() throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: " + name) }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { print("PASS: " + name) }
        }
        let now = LabHistoryChecks.now
        let earlier = try LabHistoryChecks.record("unit-earlier", result: "12.00", day: "2026-01-20", test: "Hemoglobin", unit: "g/dL")
        let later = try LabHistoryChecks.record("unit-later", result: "135.00", day: "2026-10-20", test: "Hemoglobin", unit: "g/L")
        let selection = try LabHistory.prepare(recordIDs: [earlier.id, later.id], documents: [earlier, later], now: now)
        let a = selection.points.first { $0.record.id == earlier.id }!, b = selection.points.first { $0.record.id == later.id }!
        func review(_ a: LabHistory.Point, _ b: LabHistory.Point, codes: [String]? = nil, target: String = "g/L", match: LabNormalizationReview.TestMatch = .reportedName) -> LabNormalizationReview {
            .init(units: [.init(pointID: a.id, code: codes?[0] ?? a.observation.unit, checked: true), .init(pointID: b.id, code: codes?[1] ?? b.observation.unit, checked: true)], targetCode: target, testMatch: match, testChecked: true)
        }
        func comparison(_ a: LabHistory.Point, _ b: LabHistory.Point, _ configuration: LabNormalizationReview? = nil) -> LabHistory.Comparison {
            LabHistory.compare(a, b, style: .dot, personChecked: true, normalization: configuration ?? review(a, b))
        }
        let config = review(a, b), normalized = comparison(a, b)
        check(LabHistory.compare(a, b, style: .dot, personChecked: true).difference == nil && normalized.difference == "15", "an explicit reviewed unit conversion enables an exact difference while the original different-unit comparison stays literal")
        check(normalized.normalization?.converted.map(\.value) == ["120", "135"] && normalized.first.observation.result == "12.00" && normalized.first.observation.unit == "g/dL", "converted numbers remain separate from both literal reported results and units")
        check(comparison(b, a, config).difference == "15" && comparison(b, a, config).first.id == a.id, "chronological ordering does not swap the result-owned unit assignments")
        var unchecked = config; unchecked.units[0].checked = false
        check(comparison(a, b, unchecked).difference == nil && comparison(a, b, unchecked).normalization!.converted.isEmpty, "unchecked unit assignments do not expose converted numbers")
        unchecked = config; unchecked.testChecked = false
        check(comparison(a, b, unchecked).difference == nil, "test identity has an independent explicit review gate")
        var invalid = config; invalid.units[1].pointID = String(repeating: "a", count: 64)
        check(comparison(a, b, invalid).difference == nil, "unit review belonging to another result cannot authorize this comparison")
        invalid = config; invalid.units[0].code = "g/L"
        check(comparison(a, b, invalid).difference == nil, "unit assignment cannot relabel a known g/dL source as g/L without scaling")
        invalid = config; invalid.targetCode = "mol/L"
        check(comparison(a, b, invalid).difference == nil, "mass-to-mole conversion is never inferred from a test label")
        check(LabHistory.compare(a, b, style: .dot, personChecked: false, normalization: config).normalization!.converted.isEmpty && comparison(a, a, review(a, a)).difference == nil, "person and independent-result gates survive normalized comparison")
        for field in ["laboratory", "specimen", "method", "status", "day"] {
            var observation = b.observation
            switch field { case "laboratory": observation.laboratory = "Other lab"; case "specimen": observation.specimen = "Whole blood"; case "method": observation.method = "Other assay"; case "status": observation.reportedStatus = "Amended"; default: observation.collectedOn = nil }
            let point = LabHistory.Point(record: b.record, observation: observation)
            check(comparison(a, point).difference == nil && comparison(a, point).normalization!.converted.isEmpty, "normalization does not bypass missing day or differing recorded context: " + field)
        }
        var renamed = b.observation; renamed.test = "Hb"
        let renamedPoint = LabHistory.Point(record: b.record, observation: renamed)
        check(comparison(a, renamedPoint).difference == nil && comparison(a, renamedPoint, review(a, renamedPoint, match: .reviewedNames)).difference == "15", "different un-coded test names require an explicit separately labelled user match")
        var micro = a.observation; micro.unit = "µg/L"
        let microPoint = LabHistory.Point(record: a.record, observation: micro)
        let microBasis = try LabNormalization.assignmentBasis(microPoint, code: "ug/L")
        check(LabNormalization.proposedCode(microPoint) == "ug/L" && microBasis.contains("micro-sign"), "micro-sign mapping is a visible review proposal with a retained user-mapping basis")
        check((try? LabNormalization.assignmentBasis(microPoint, code: "mg/L")) == nil, "a printed micro sign cannot be mapped to milli without changing a known magnitude")
        var unknown = a.observation; unknown.unit = "micrograms per litre"
        let unknownPoint = LabHistory.Point(record: a.record, observation: unknown)
        check((try LabNormalization.assignmentBasis(unknownPoint, code: "ug/L")).contains("unverified"), "an unknown printed-unit assignment is explicitly user provided and unverified")
        for printed in ["", "{cells}/L", "[IU]/L", "IU/L", "mIU/L", "(Cel)", "Cel", "°C"] {
            var row = a.observation; row.unit = printed
            check((try? LabNormalization.assignmentBasis(.init(record: a.record, observation: row), code: "g/L")) == nil, "missing, annotated, arbitrary or special source units stay literal: " + printed)
        }
        var massFraction = a.observation; massFraction.unit = "g/g"; massFraction.result = "0.5"
        var moleFraction = b.observation; moleFraction.unit = "mol/mol"; moleFraction.result = "0.5"
        let massPoint = LabHistory.Point(record: a.record, observation: massFraction), molePoint = LabHistory.Point(record: b.record, observation: moleFraction)
        check(comparison(massPoint, molePoint, review(massPoint, molePoint, target: "%")).normalization!.converted.isEmpty, "a generic percent target cannot bridge conflicting mass-fraction and mole-fraction source units")
        var nonterminating = a.observation; nonterminating.unit = "1/min"; nonterminating.result = "1"
        var finite = b.observation; finite.unit = "1/s"; finite.result = "2"
        let nonterminatingPoint = LabHistory.Point(record: a.record, observation: nonterminating), finitePoint = LabHistory.Point(record: b.record, observation: finite)
        let partial = comparison(nonterminatingPoint, finitePoint, review(nonterminatingPoint, finitePoint, target: "1/s"))
        check(partial.difference == nil && partial.normalization!.converted.count == 1 && partial.normalization!.converted[0].pointID == finitePoint.id, "a partially available conversion retains its actual result identity rather than shifting the later value into the earlier slot")
        let snapshot = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [earlier, later], now: now, normalization: config)
        check(snapshot.labComparison!.isValid && !snapshot.includeInAssistant && snapshot.labComparison!.numberDifference == "15" && snapshot.body.contains("Converted number: 120 g/L") && snapshot.body.contains("Reported result: 12.00") && snapshot.body.contains("Reported unit: g/dL"), "saved normalized comparison retains reviewed mapping, exact converted values, original wording and sharing off")
        check(snapshot.labComparison!.normalization == config && snapshot.labComparison!.capturedText == snapshot.body, "typed captured normalization regenerates the exact independent snapshot text")
        check(snapshot.labComparison!.capturedReaderText.contains("Reviewed unit conversion") && !snapshot.labComparison!.capturedReaderText.contains("## Reviewed unit conversion") && snapshot.body.contains("## Reviewed unit conversion"), "native captured reader omits only generated heading markers while portable Markdown retains them")
        check(snapshot.body.contains("This name match applies only to this snapshot. No terminology equivalence was verified."), "captured reported-name identity records its snapshot-only terminology boundary")
        var markedSource = a.observation
        markedSource.source.excerpt = "## Original report heading\n" + markedSource.source.excerpt
        let markedPoint = LabHistory.Point(record: a.record, observation: markedSource)
        let markedComparison = comparison(markedPoint, b)
        check(LabHistory.snapshotText(markedComparison, style: .dot, now: now, markdownHeadings: false).contains("## Original report heading"), "native reader formatting preserves heading-like literal source text rather than stripping user content")
        rejects("normalized snapshots still require final acknowledgement") { _ = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: true, acknowledged: false, currentDocuments: [earlier, later], now: now, normalization: config) }
        rejects("normalized snapshots cannot save unreviewed unit choices") { _ = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [earlier, later], now: now, normalization: unchecked) }
        var changed = earlier; changed.title = "Changed source"
        rejects("normalized saving revalidates the actual source fingerprint") { _ = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [changed, later], now: now, normalization: config) }
        var forged = snapshot; forged.labComparison!.numberDifference = "150"
        check(!forged.labComparison!.isValid, "saved normalized arithmetic is recomputed rather than trusted from decoded values")
        forged = snapshot; forged.labComparison!.normalization!.units[0].code = "g/L"
        check(!forged.labComparison!.isValid, "changing a captured source-unit assignment invalidates the normalized snapshot")
        forged = snapshot; forged.labComparison!.reasons = ["Invented reason"]
        check(!forged.labComparison!.isValid, "a numeric normalized snapshot cannot also claim a reason for withholding its arithmetic")
        var edited = snapshot; edited.body = "My edited summary"
        check(edited.labComparison!.isValid && !edited.labComparison!.isCurrent(body: edited.body) && edited.markdown.contains("Earlier captured lab comparison") && RecordRetrieval.text(edited)!.contains("withheld"), "editing a normalized snapshot labels earlier converted facts historical and withholds stale arithmetic from new retrieval")
        check(snapshot.labComparison!.sources[0].state(in: []) == .removed && snapshot.labComparison!.sources[0].state(in: [changed, later]) == .changed, "normalized snapshots retain changed/removed original-source states")

        func point(_ document: HealthDocument) throws -> LabHistory.Point { try LabHistory.prepare(recordIDs: [document.id], documents: [document], now: now).points[0] }
        let fa = try point(fhir("a")), fb = try point(fhir("b", name: "Hb", unit: "g/L", unitCode: "g/L", rawValue: "135.00"))
        var coded = review(fa, fb, match: .originalCoding); coded.testCode = LabNormalization.sharedCodes(fa, fb).first
        check(coded.testCode?.code == "718-7" && comparison(fa, fb, coded).difference == "15", "same supplied system/code/version permits differing display names and exact reviewed unit conversion")
        check(!LabHistory.snapshotText(comparison(fa, fb, coded), style: .dot, now: now).contains("This name match applies only"), "supplied-code identity is not mislabelled as a user name match")
        let fhirBasis = try LabNormalization.assignmentBasis(fa, code: "g/dL")
        check(LabNormalization.proposedCode(fa) == "g/dL" && fhirBasis.contains("Original FHIR"), "unchanged reviewed FHIR display retains the original coded unit as an explicit mapping basis")
        let conflict = try point(fhir("c", code: "9999-9", unit: "g/L", unitCode: "g/L", rawValue: "135"))
        check(LabNormalization.conflictingCodes(fa, conflict) && comparison(fa, conflict, review(fa, conflict, match: .reviewedNames)).normalization!.converted.isEmpty, "a user name match cannot override conflicting original codes in the same system/version")
        let crossVersion = try point(fhir("v", code: "9999-9", unit: "g/L", unitCode: "g/L", rawValue: "135", codingVersion: "2.81"))
        check(LabNormalization.conflictingCodes(fa, crossVersion) && comparison(fa, crossVersion, review(fa, crossVersion, match: .reviewedNames)).normalization!.converted.isEmpty, "a version change cannot hide conflicting original codes from the same coding system")
        let sameCodeNewVersion = try point(fhir("v2", unit: "g/L", unitCode: "g/L", rawValue: "135", codingVersion: "2.81"))
        check(LabNormalization.sharedCodes(fa, sameCodeNewVersion).isEmpty && !LabNormalization.conflictingCodes(fa, sameCodeNewVersion), "same code with a different supplied version is not an automatic full-identity match or a fabricated code conflict")
        var changedUnit = fa.observation; changedUnit.unit = "g/L"
        let correctedUnitPoint = LabHistory.Point(record: fa.record, observation: changedUnit)
        check((try LabNormalization.assignmentBasis(correctedUnitPoint, code: "g/L")).contains("original FHIR unit code is historical"), "a reviewed unit correction is distinguished explicitly from the original FHIR coded unit")
        let inconsistent = try point(fhir("u", unit: "g/L", unitCode: "g/dL"))
        check((try? LabNormalization.assignmentBasis(inconsistent, code: "g/L")) == nil && (try? LabNormalization.assignmentBasis(inconsistent, code: "g/dL")) == nil, "contradictory original display/code evidence cannot be normalized by choosing only the convenient field")
        let extended = try point(fhir("e", codingExtra: #", "extension":[{"url":"https://synthetic.example/meaning","valueString":"unknown"}]"#))
        check(extended.observation.fhirSource?.normalizationFacts?.complete == false && comparison(fa, extended).difference == nil, "unsupported original coding extensions block normalized identity instead of being silently discarded")
        let nonscalar = try point(fhir("n", kind: "valueString"))
        var nonscalarObservation = nonscalar.observation; nonscalarObservation.result = "12.00"; nonscalarObservation.unit = "g/L"
        let numericLooking = LabHistory.Point(record: nonscalar.record, observation: nonscalarObservation)
        check(comparison(fa, numericLooking).normalization!.converted.isEmpty, "corrected numeric-looking FHIR text cannot expose a converted scalar")
        let revision = try point(fhir("a", unit: "g/L", unitCode: "g/L", rawValue: "135", version: "2"))
        check(comparison(fa, revision).normalization!.converted.isEmpty, "repeated versions of one FHIR event cannot manufacture normalized measurements")
        let alteredMethod = try point(fhir("m", method: #", "method":{"text":"Other original assay"}"#))
        check(comparison(fa, alteredMethod).normalization!.converted.isEmpty, "matching reviewed method labels cannot erase conflicting original FHIR method context")

        let archive = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [earlier, later, snapshot], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        func preserved(_ documents: [HealthDocument]) -> Bool {
            archive.documents.allSatisfy { expected in
                guard let actual = documents.first(where: { $0.id == expected.id }), let a = try? BackupArchive.encoder().encode(actual), let b = try? BackupArchive.encoder().encode(expected) else { return false }
                return a == b
            }
        }
        check(preserved(try BackupArchive.read(BackupArchive.make(archive)).1.documents), "actual version-one backup round trip preserves all normalized comparison fields at archive precision")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-normalization-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        let encrypted = folder.appendingPathComponent("Synthetic.lumenbackup")
        try BackupPackage.write(archive, photos: [:], password: "Synthetic unit passphrase", to: encrypted)
        let restored = try BackupPackage.read(encrypted, password: "Synthetic unit passphrase", temporaryRoot: folder); defer { restored.removeTemporaryFiles() }
        check(preserved(restored.snapshot.documents), "actual encrypted streamed backup preserves normalized unit choices and exact captured arithmetic")
        let readable = folder.appendingPathComponent("Synthetic.json"); try ReadableExport.write(archive, to: readable)
        check(preserved(try ReadableExport.read(Data(contentsOf: readable)).snapshot.documents), "actual readable export/recovery preserves normalized comparison provenance")
        var excessive = config; excessive.units.append(config.units[0])
        rejects("unit-review decoding rejects more than two assignments before accepting an oversized array") { _ = try JSONDecoder().decode(LabNormalizationReview.self, from: JSONEncoder().encode(excessive)) }
        invalid = config; invalid.targetCode = "g\nL"
        rejects("decoded unit review rejects control/whitespace codes") { _ = try JSONDecoder().decode(LabNormalizationReview.self, from: JSONEncoder().encode(invalid)) }
    }
    private static func json(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self) }
    private static func fhir(_ id: String, code: String = "718-7", name: String = "Hemoglobin", unit: String = "g/dL", unitCode: String = "g/dL", rawValue: String = "12.00", kind: String = "valueQuantity", version: String = "1", codingExtra: String = "", method: String = "", codingVersion: String = "2.80") throws -> HealthDocument {
        let coding = #"{"coding":[{"system":"http://loinc.org","code":""# + code + #"","version":""# + codingVersion + #""}],"text":""# + name + #"""# + codingExtra + "}"
        let unitJSON = try json(unit), unitCodeJSON = try json(unitCode)
        let value = kind == "valueQuantity" ? #""valueQuantity":{"value":"# + rawValue + #", "unit":"# + unitJSON + #", "system":"http://unitsofmeasure.org", "code":"# + unitCodeJSON + "}" : #""valueString":"12.00""#
        let text = #"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"https://synthetic.example/fhir/Observation/"# + id + #"","resource":{"resourceType":"Observation","id":""# + id + #"","meta":{"versionId":""# + version + #""},"status":"final","code":"# + coding + "," + value + method + "}}]}"
        let prepared = try FHIRLabPreparation(archive: .init(data: Data(text.utf8), filename: "Synthetic normalization.json"))
        var draft = try FHIRLabDraft(preparation: prepared, subjectKey: prepared.results[0].subject.key, personChecked: true, coverageReviewed: true)
        draft.results[0].observation.collectedOn = id == "a" ? "2026-01-20" : "2026-10-20"
        draft.results[0].observation.laboratory = "Synthetic laboratory"; draft.results[0].observation.method = "Reviewed assay"
        return try draft.document(acknowledged: true, now: LabHistoryChecks.now)
    }

    static func fixtures(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let earlier = try LabHistoryChecks.record("unit-earlier", result: "12.00", day: "2026-01-20", test: "Hemoglobin", unit: "g/dL")
        let later = try LabHistoryChecks.record("unit-later", result: "135.00", day: "2026-10-20", test: "Hemoglobin", unit: "g/L")
        let renamed = try LabHistoryChecks.record("unit-renamed", result: "135.00", day: "2026-10-20", test: "Hb", unit: "g/L")
        let arbitrary = try LabHistoryChecks.record("unit-arbitrary", result: "2.00", day: "2026-10-20", test: "Hemoglobin", unit: "IU/L")
        var codedEarlier = try fhir("a"), codedLater = try fhir("b", name: "Hb", unit: "g/L", unitCode: "g/L", rawValue: "135.00")
        for (id, title, isEarlier) in [("unit-coded-earlier", "Synthetic coded earlier", true), ("unit-coded-later", "Synthetic coded later", false)] {
            if isEarlier { codedEarlier.id = id; codedEarlier.title = title; codedEarlier.labReport!.observations[0].id = id + "-result" }
            else { codedLater.id = id; codedLater.title = title; codedLater.labReport!.observations[0].id = id + "-result" }
        }
        let documents = [earlier, later, renamed, arbitrary, codedEarlier, codedLater]
        let archive = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: documents, importedDays: [], imports: [], personalContext: .init(), photos: [:])
        try BackupArchive.make(archive).write(to: folder.appendingPathComponent("Lumen-backup-unit-review.json"))
    }

}
