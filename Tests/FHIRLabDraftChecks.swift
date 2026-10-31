import Foundation

enum FHIRLabDraftChecks {
    static func run() throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: " + name) }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { print("PASS: " + name) }
        }
        let longText = "Original e\u{0301} \u{00e9} 👨‍👩‍👧‍👦\n" + String(repeating: "\u{0301}", count: 50_000) + String(repeating: "x", count: 12_000)
        let parts = FHIRSourceReading.pages(longText)
        check(parts.joined().utf8.elementsEqual(longText.utf8) && parts.allSatisfy { $0.utf8.count <= 8000 && $0.unicodeScalars.count <= 2000 }, "FHIR source readers preserve every original byte while bounding long tokens, emoji and huge combining sequences per display part")
        check(FHIRSourceReading.pages("") == [""] && FHIRSourceReading.pages("12.00") == ["12.00"], "empty and ordinary FHIR field readers preserve their complete literal text")
        func prepare(_ value: String, identity: String = "o", version: String = "1", extra: String = "") throws -> FHIRLabPreparation {
            let text = #"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"https://synthetic.example/fhir/Observation/"# + identity + #"","resource":{"resourceType":"Observation","id":""# + identity + #"","meta":{"versionId":""# + version + #""},"status":"final","code":{"text":"Synthetic test"},"effectiveDateTime":"2026-10-30T23:40:00-05:00","# + value + extra + "}}]}"
            return try .init(archive: .init(data: Data(text.utf8), filename: "Synthetic FHIR.json"))
        }
        func draft(_ preparation: FHIRLabPreparation) throws -> FHIRLabDraft {
            try .init(preparation: preparation, subjectKey: preparation.results[0].subject.key, personChecked: true, coverageReviewed: true)
        }
        func reviewed(_ preparation: FHIRLabPreparation, day: String) throws -> HealthDocument {
            var value = try draft(preparation)
            for index in value.results.indices {
                value.results[index].observation.collectedOn = day
                value.results[index].observation.unit = "mg/L"
                value.results[index].observation.laboratory = "Synthetic reviewed laboratory"
            }
            return try value.document(acknowledged: true)
        }
        let preparation = try prepare(#""valueQuantity":{"value":12.00,"unit":"mg/L"}"#)
        rejects("FHIR review requires explicit file coverage review") { _ = try FHIRLabDraft(preparation: preparation, subjectKey: preparation.results[0].subject.key, personChecked: true, coverageReviewed: false) }
        rejects("FHIR review requires an explicit intended-person check") { _ = try FHIRLabDraft(preparation: preparation, subjectKey: preparation.results[0].subject.key, personChecked: false, coverageReviewed: true) }
        rejects("FHIR review rejects an unknown person group") { _ = try FHIRLabDraft(preparation: preparation, subjectKey: "absent", personChecked: true, coverageReviewed: true) }
        var value = try draft(preparation)
        rejects("FHIR saving requires result and original-field acknowledgement") { _ = try value.document(acknowledged: false) }
        let original = try value.document(acknowledged: true)
        check(original.id == value.id && !original.includeInAssistant && original.fhirLabImport?.selectedPaths == [preparation.results[0].id], "FHIR save retains stable draft identity, selected paths and sharing off")
        check(original.labReport!.observations[0].source.matches(original.body) && original.labReport!.isCurrent(body: original.body) && original.hasValidFHIRLabImport, "FHIR saved source anchor, typed provenance and full source layout agree")
        check(original.labReport!.observations[0].collectedOn == nil && original.labReport!.observations[0].reportedTiming == nil && original.body.contains("2026-10-30T23:40:00-05:00"), "FHIR effective timestamp stays literal and never fills collection wording or a chart day")
        value.results[0].observation.result = "13.00"
        let corrected = try value.document(acknowledged: true)
        check(corrected.id == original.id && corrected.labReport!.observations[0].result == "13.00" && corrected.labReport!.observations[0].fhirSource?.originalScalarToken == "12.00" && corrected.body == original.body, "FHIR corrections retain original value tokens and the same draft identity")
        var sourceEdit = value; sourceEdit.results[0].observation.source.excerpt = "changed"
        rejects("FHIR draft cannot save a substituted original source anchor") { _ = try sourceEdit.document(acknowledged: true) }
        var metadataEdit = value; metadataEdit.results[0].observation.fhirSource = nil
        rejects("FHIR draft cannot discard the original value form while saving corrected text") { _ = try metadataEdit.document(acknowledged: true) }
        var excluded = value; excluded.results[0].included = false
        rejects("FHIR save cannot create an empty result selection") { _ = try excluded.document(acknowledged: true) }
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("FHIR draft cancellation produces no saved document") { _ = try value.document(acknowledged: true, control: cancelled) }
        rejects("FHIR row preparation respects cancellation before exposing a review") { _ = try FHIRLabDraft(preparation: preparation, subjectKey: preparation.results[0].subject.key, personChecked: true, coverageReviewed: true, control: cancelled) }
        let blockedText = #"{"resourceType":"Bundle","type":"searchset","link":[{"relation":"next","url":"https://synthetic.example/next"}],"entry":[{"fullUrl":"https://synthetic.example/Observation/ok","resource":{"resourceType":"Observation","status":"final","subject":{"reference":"Patient/p"},"code":{"text":"Included synthetic"},"valueInteger":1}},{"fullUrl":"https://synthetic.example/Observation/bad","resource":{"resourceType":"Observation","status":"cancelled","subject":{"reference":"Patient/p"},"code":{"text":"Excluded synthetic"},"valueInteger":2}}]}"#
        let blockedPreparation = try FHIRLabPreparation(archive: .init(data: Data(blockedText.utf8), filename: "Synthetic blocked.json"))
        var blocked = try draft(blockedPreparation)
        check(blocked.results.count == 2 && blocked.includedCount == 2 && blocked.results[1].sourceIssue != nil, "FHIR source issues remain included and visible until the person explicitly excludes them")
        rejects("FHIR save cannot hide a blocked original status through edited review wording") { blocked.results[1].observation.reportedStatus = "final"; _ = try blocked.document(acknowledged: true) }
        blocked.results[1].included = false
        let subset = try blocked.document(acknowledged: true)
        check(subset.fhirLabImport?.hasNextPage == true && subset.fhirLabImport?.proposedResults == 2 && subset.fhirLabImport?.selectedPaths.count == 1 && !subset.body.contains("Excluded synthetic"), "explicit FHIR exclusion preserves input coverage and paging while saving only the chosen original fields")
        var remove = try LabReview.Draft(document: corrected); remove.observations = []
        let sourceOnly = try remove.applying(to: corrected, acknowledged: true)
        check(sourceOnly.labReport == nil && sourceOnly.fhirLabImport == corrected.fhirLabImport && sourceOnly.hasValidFHIRLabImport && value.hasDuplicate(in: [sourceOnly]), "removing every FHIR transcription retains the file receipt and exact-file duplicate identity")
        var wrongKind = sourceOnly; wrongKind.kind = .note
        check(!wrongKind.hasValidFHIRLabImport, "a source-only FHIR receipt remains restricted to a record")
        check(RecordRetrieval.text(sourceOnly)?.contains(preparation.archive.sha256) == true && sourceOnly.markdown.contains(preparation.archive.sha256), "source-only FHIR receipts remain in retrieval and Markdown")
        var missingReceipt = corrected; missingReceipt.fhirLabImport = nil
        check(!missingReceipt.hasValidFHIRLabImport && RecordRetrieval.text(missingReceipt) == nil, "FHIR rows without their record-owned receipt are rejected by retrieval")
        var mixed = corrected
        let table = try LabTable.parse(Data("test,result\nSynthetic,1".utf8), filename: "Synthetic.csv")
        mixed.labImportOrigin = try LabFileDraft(table: table, mapping: table.suggestedMapping, subject: "", personChecked: true).document(acknowledged: true).labImportOrigin
        check(!mixed.hasValidFHIRLabImport, "a retained FHIR receipt cannot be silently mixed with a table import receipt")
        let largePreparation = try prepare(#""valueQuantity":{"value":12.00,"unit":"mg/L"}"#, extra: #", "method":{"text":""# + String(repeating: "m", count: 2500) + #""}"#)
        var largeDraft = try draft(largePreparation)
        check(largeDraft.results[0].sourceText.count > 2000 && largeDraft.results[0].sourceValid, "complete linked FHIR fields can exceed the legacy excerpt limit while the own-result anchor remains valid")
        rejects("an overlong FHIR proposed review field requires correction or exclusion") { _ = try largeDraft.document(acknowledged: true) }
        largeDraft.results[0].observation.method = "Reviewed method"
        let largeDocument = try largeDraft.document(acknowledged: true)
        check(largeDocument.body.contains(String(repeating: "m", count: 2500)) && largeDocument.labReport!.observations[0].fhirSource!.fields.contains { $0.token.contains(String(repeating: "m", count: 2500)) }, "correcting a review field never clips the complete original FHIR method")
        let first = try reviewed(preparation, day: "2026-01-01")
        let second = try reviewed(prepare(#""valueQuantity":{"value":18.50,"unit":"mg/L"}"#, identity: "other"), day: "2026-02-01")
        let selection = try LabHistory.prepare(recordIDs: [first.id, second.id], documents: [first, second])
        let a = selection.points.first { $0.record.id == first.id }!, b = selection.points.first { $0.record.id == second.id }!
        check(LabHistory.compare(a, b, style: .dot, personChecked: true).difference == "6.5", "distinct reviewed FHIR quantity events support explicit exact-number comparison")
        var manualDraft = try LabReview.Draft(document: first)
        manualDraft.observations = [LabObservation(test: "Manually added result", result: "12.00", unit: "mg/L", collectedOn: "2026-01-01", laboratory: "Synthetic reviewed laboratory", source: first.labReport!.observations[0].source)]
        let manualFHIR = try manualDraft.applying(to: first, acknowledged: true)
        let manualSelection = try LabHistory.prepare(recordIDs: [manualFHIR.id], documents: [manualFHIR])
        check(manualFHIR.hasValidFHIRLabImport && manualSelection.points[0].fhirScalarIssue != nil && LabHistory.plot(manualSelection.groups[0], style: .dot, personChecked: true).points.isEmpty, "manually adding a transcription to a retained FHIR record cannot bypass original value-form proof after metadata removal")
        let snapshot = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [first, second])
        check(snapshot.labComparison?.sources.allSatisfy { $0.fhirOrigin != nil && $0.fhirFieldsMatched == true } == true && snapshot.body.contains("Historical FHIR import receipt"), "saved FHIR comparisons retain typed source receipts and exact-layout evidence")
        var missingProof = snapshot.labComparison!.sources[0]; missingProof.fhirFieldsMatched = nil
        check(!missingProof.isValid, "FHIR comparison metadata cannot omit the captured full-layout match state")
        let revision = try reviewed(prepare(#""valueQuantity":{"value":19.00,"unit":"mg/L"}"#, version: "2"), day: "2026-03-01")
        let versions = try LabHistory.prepare(recordIDs: [first.id, revision.id], documents: [first, revision])
        check(LabHistory.compare(versions.points[0], versions.points[1], style: .dot, personChecked: true).difference == nil && LabHistory.plot(versions.groups[0], style: .dot, personChecked: true).points.isEmpty, "known FHIR revisions across files never manufacture independent chart points or differences")
        for literal in [#""valueCodeableConcept":{"text":"12.00"}"#, #""valueString":"12.00""#, #""valueQuantity":{"value":12.00,"comparator":"<","unit":"mg/L"}"#] {
            let nonScalar = try reviewed(prepare(literal, identity: "nonscalar"), day: "2026-03-01")
            let prepared = try LabHistory.prepare(recordIDs: [nonScalar.id], documents: [nonScalar])
            check(prepared.points[0].fhirScalarIssue != nil && LabHistory.plot(prepared.groups[0], style: .dot, personChecked: true).points.isEmpty, "corrected days, units and laboratories cannot turn an original coded, string or qualified value into a scalar: " + literal)
        }
        var changed = first
        changed.body = changed.body.replacingOccurrences(of: "12.00", with: "12.0")
        var rereview = try LabReview.Draft(document: changed)
        rereview.observations[0].source = LabReview.sources(in: changed.body).first { $0.excerpt.contains("12.0") }!
        changed = try rereview.applying(to: changed, acknowledged: true)
        let changedSelection = try LabHistory.prepare(recordIDs: [changed.id], documents: [changed])
        check(!changedSelection.points[0].fhirFieldsMatch && changedSelection.points[0].fhirScalarIssue != nil, "rereviewing changed arranged source text keeps historical FHIR coding and withholds numeric interpretation")
        check(snapshot.labComparison!.sources.first { $0.documentID == first.id }!.state(in: [changed, second]) == .changed && snapshot.labComparison!.sources[0].state(in: []) == .removed && snapshot.labComparison!.isValid, "independent FHIR comparison captures survive changed and removed originals")
        let archive = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [first, second, sourceOnly, snapshot, largeDocument], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        let legacy = try BackupArchive.read(BackupArchive.make(archive)).1
        func preserved(_ documents: [HealthDocument]) -> Bool {
            guard documents.count == archive.documents.count else { return false }
            // Existing backups intentionally serialize dates at ISO whole-second
            // precision. Compare every persisted field at that format's actual
            // precision rather than requiring fractional Date equality.
            return archive.documents.allSatisfy { expected in
                guard let actual = documents.first(where: { $0.id == expected.id }),
                      let left = try? BackupArchive.encoder().encode(expected),
                      let right = try? BackupArchive.encoder().encode(actual) else { return false }
                return left == right
            }
        }
        check(preserved(legacy.documents), "actual version-one backup round trip preserves every FHIR record field at the archive's timestamp precision")
        check(legacy.documents[0].labReport!.observations[0].fhirSource == first.labReport!.observations[0].fhirSource && abs(legacy.documents[0].fhirLabImport!.readAt.timeIntervalSince(first.fhirLabImport!.readAt)) < 1, "FHIR original token bytes round trip exactly while existing archive timestamps retain whole-second precision")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-FHIR-draft-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let encrypted = folder.appendingPathComponent("Synthetic.lumenbackup")
        try BackupPackage.write(archive, photos: [:], password: "Synthetic FHIR passphrase", to: encrypted)
        let restored = try BackupPackage.read(encrypted, password: "Synthetic FHIR passphrase", temporaryRoot: folder)
        defer { restored.removeTemporaryFiles() }
        check(preserved(restored.snapshot.documents), "actual encrypted streamed backup preserves FHIR original fields and retained receipts")
        let readable = folder.appendingPathComponent("Synthetic.json")
        try ReadableExport.write(archive, to: readable)
        let recovered = try ReadableExport.read(Data(contentsOf: readable))
        check(preserved(recovered.snapshot.documents), "actual readable export and reviewed recovery preserve FHIR metadata and saved comparisons")
        var corrupt = archive; corrupt.documents = [missingReceipt]
        rejects("backup validation refuses FHIR provenance without a matching record receipt") { try BackupArchive.validate(corrupt) }
    }
}
