import Foundation

enum FHIRNDJSONChecks {
    static func run() throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: " + name) }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { print("PASS: " + name) }
        }
        func archive(_ text: String) throws -> FHIRResourceArchive { try .init(data: Data(text.utf8), filename: "Synthetic.ndjson") }
        func reference(_ text: String) throws -> LiteralJSON.Node { try LiteralJSON.parse(Data(text.utf8)).root }
        let first = #"{"resourceType":"Observation","id":"one","status":"final","subject":{"reference":"Patient/a"},"code":{"text":"Synthetic \u00b5 test"},"valueQuantity":{"value":1.2300e-9,"unit":"mg/L","system":"http://unitsofmeasure.org","code":"mg/L"}}"#
        let second = #"{"resourceType":"Observation","id":"two","status":"final","subject":{"reference":"Patient/a"},"code":{"text":"Synthetic second"},"valueString":"Not 12\nCheck original"}"#
        let third = #"{"resourceType":"Observation","id":"three","status":"final","subject":{"reference":"Patient/b"},"code":{"text":"Different person"},"valueInteger":3}"#
        let bytes = Data([239,187,191]) + Data((first + "\r\n" + second + "\r\n" + third + "\r\n").utf8)
        let parsed = try FHIRResourceArchive(data: bytes, filename: "Synthetic.NDJSON")
        check(parsed.format == .ndjson && parsed.entries.count == 3 && parsed.resources.map(\.id) == ["/line/1", "/line/2", "/line/3"] && parsed.bundleType == nil && !parsed.hasNextPage, "NDJSON counts every physical resource line without fabricating Bundle or pagination metadata")
        check(parsed.json.source == bytes && parsed.sha256 == BackupArchive.digest(bytes) && parsed.resources[0].node.bytes.lowerBound == 3, "NDJSON preserves the complete original BOM/CRLF input identity and file-relative offsets")
        let literal = parsed.resources[0].node["valueQuantity"]!["value"]!
        check(parsed.json.text(literal) == "1.2300e-9" && String(decoding: bytes[literal.bytes], as: UTF8.self) == "1.2300e-9", "NDJSON decimals keep their original spelling at their original file byte range")
        let escaped = parsed.resources[1].node["valueString"]!
        check(parsed.json.text(escaped) == #""Not 12\nCheck original""# && escaped.string == "Not 12\nCheck original", "escaped newlines belong to one NDJSON source line and remain separately decoded")
        let sliced = try FHIRResourceArchive(data: (Data("prefix".utf8) + bytes).dropFirst(6), filename: "Slice.ndjson")
        check(sliced.json.source.startIndex == 0 && sliced.json.text(sliced.resources[1].node) == second, "sliced NDJSON buffers retain correct full-file source offsets")
        let single = try archive(first)
        check(single.entries.count == 1 && single.resources[0].id == "/line/1", "single-line NDJSON without a final newline remains explicitly line-based")
        let lf = try archive(first + "\n" + second)
        check(lf.json.text(lf.resources[1].node) == second, "LF-delimited exports and final lines without newline preserve exact tokens")
        let spaced = try archive(" \t" + first + " \t\n" + second + " ")
        check(spaced.resources[0].node.bytes.lowerBound == 2 && spaced.json.text(spaced.resources[1].node) == second, "horizontal JSON whitespace does not change physical line identities")
        for (label, text) in [
            ("leading blank line", "\n" + first), ("interior blank line", first + "\n\n" + second),
            ("extra trailing blank line", first + "\n\n"), ("whitespace-only line", first + "\n \t\n"),
            ("multiline resource", first.replacingOccurrences(of: ",\"status\"", with: ",\n\"status\"")),
            ("bare CR inside resource", first.replacingOccurrences(of: ",\"status\"", with: ",\r\"status\"")),
            ("bare CR separator", first + "\r" + second), ("bare CR terminator", first + "\r"),
            ("two resources on one line", first + second), ("truncated final line", first + "\n{\"resourceType\":"),
            ("duplicate decoded member", #"{"resourceType":"Observation","\u0072esourceType":"Observation"}"#),
            ("later BOM", first + "\n\u{feff}" + second), ("mixed types", first + "\n{\"resourceType\":\"Patient\"}"),
            ("Bundle line", #"{"resourceType":"Bundle","type":"collection"}"#), ("array line", "[" + first + "]"),
            ("bulk completion manifest", #"{"transactionTime":"2026-10-31T00:00:00Z","output":[]}"#)
        ] { rejects("NDJSON rejects \(label) without returning a partial archive") { _ = try archive(text) } }
        rejects("NDJSON never treats multiple resources in a .json file as an implicit line format") { _ = try FHIRResourceArchive(data: Data((first + "\n" + second).utf8), filename: "Synthetic.json") }
        rejects("NDJSON rejects invalid UTF-8 instead of replacing source bytes") { _ = try FHIRResourceArchive(data: Data(first.utf8) + Data([10,255]), filename: "Synthetic.ndjson") }
        rejects("NDJSON retains the whole-file 2 MB ceiling") { _ = try FHIRResourceArchive(data: Data(repeating: 32, count: LiteralJSON.maxBytes + 1), filename: "Synthetic.ndjson") }
        let paddingPrefix = #"{"resourceType":"Observation","extra":""#, paddingSuffix = #""}"#
        let fullSize = try archive(paddingPrefix + String(repeating: "x", count: LiteralJSON.maxBytes - paddingPrefix.utf8.count - paddingSuffix.utf8.count) + paddingSuffix)
        check(fullSize.json.source.count == LiteralJSON.maxBytes && fullSize.resources.count == 1, "NDJSON accepts an exact 2 MB original file without clipping a source byte")
        let simple = #"{"resourceType":"Observation"}"#
        let boundary = try archive(Array(repeating: simple, count: 1024).joined(separator: "\n"))
        check(boundary.resources.count == 1024 && boundary.resources.last?.id == "/line/1024", "NDJSON accepts all 1,024 source lines at the inventory boundary")
        rejects("NDJSON rejects a 1,025th resource rather than returning a prefix") { _ = try archive(Array(repeating: simple, count: 1025).joined(separator: "\n")) }
        let contained = ##"{"resourceType":"Observation","id":"contained","contained":[{"resourceType":"Patient","id":"p","name":[{"text":"Synthetic contained person"}]}],"status":"final","subject":{"reference":"#p"},"code":{"text":"Contained test"},"valueInteger":1}"##
        rejects("NDJSON resource limit includes contained resources") { _ = try archive(Array(repeating: simple, count: 1023).joined(separator: "\n") + "\n" + contained) }
        let largeLine = #"{"resourceType":"Observation","extra":["# + Array(repeating: "0", count: 60_000).joined(separator: ",") + "]}"
        rejects("NDJSON shares one 100,000-node budget across lines") { _ = try archive(largeLine + "\n" + largeLine) }
        rejects("NDJSON shares the JSON nesting bound") { _ = try archive(#"{"resourceType":"Observation","extra":"# + String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64) + "}") }
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("cancelled NDJSON parsing exposes no partial resource inventory") { _ = try FHIRResourceArchive(data: bytes, filename: "Synthetic.ndjson", control: cancelled) }

        let twoContained = try archive(contained + "\n" + contained)
        let owner = twoContained.resources[0], otherOwner = twoContained.resources[2]
        check(twoContained.resolve(owner.node["subject"]!, from: owner, expectedTypes: ["Patient"]) == .found("/line/1/contained/0") && twoContained.resolve(otherOwner.node["subject"]!, from: otherOwner) == .found("/line/2/contained/0"), "NDJSON contained references remain scoped to their own source line")
        check(parsed.resolve(try reference(#"{"reference":"Observation/two"}"#), from: parsed.resources[0]) == .found("/line/2"), "relative NDJSON result links can resolve an exact typed ID inside this file")
        check(parsed.resolve(try reference(#"{"reference":"https://outside.example/Observation/two"}"#), from: parsed.resources[0]) == .missing, "NDJSON does not invent a server base or equate an absolute reference by its suffix")
        let versions = try archive(first.replacingOccurrences(of: #""status":"final""#, with: #""meta":{"versionId":"1"},"status":"final""#) + "\n" + first.replacingOccurrences(of: #""status":"final""#, with: #""meta":{"versionId":"2"},"status":"final""#))
        check(versions.resolve(try reference(#"{"reference":"Observation/one"}"#), from: versions.resources[0]) == .ambiguous(["/line/1", "/line/2"]), "duplicate NDJSON IDs and revisions leave unversioned links ambiguous")
        let exactVersion = versions.resolve(try reference(#"{"reference":"Observation/one/_history/2"}"#), from: versions.resources[0])
        let absentVersion = versions.resolve(try reference(#"{"reference":"Observation/one/_history/3"}"#), from: versions.resources[0])
        check(exactVersion == .found("/line/2") && absentVersion == .missing, "versioned NDJSON links require the exact version with no fallback")
        check(versions.identity(of: versions.resources[0]) == versions.identity(of: versions.resources[1]) && versions.identity(of: versions.resources[0])?.contains(versions.sha256) == true, "NDJSON revisions share an explicitly file-scoped event identity without claiming a server URL")
        let versionPreparation = try FHIRLabPreparation(archive: versions)
        var versionDraft = try FHIRLabDraft(preparation: versionPreparation, subjectKey: versionPreparation.results[0].subject.key, personChecked: true, coverageReviewed: true)
        for index in versionDraft.results.indices { versionDraft.results[index].observation.collectedOn = index == 0 ? "2026-10-28" : "2026-10-29" }
        let versionDocument = try versionDraft.document(acknowledged: true)
        let history = try LabHistory.prepare(recordIDs: [versionDocument.id], documents: [versionDocument])
        check(history.points.count == 2 && LabHistory.compare(history.points[0], history.points[1], style: .dot, personChecked: true).difference == nil && LabHistory.plot(history.groups[0], style: .dot, personChecked: true).points.isEmpty, "actual lab-history comparison and charts reject NDJSON revisions as independent measurements")

        let prepared = try FHIRLabPreparation(archive: parsed)
        check(prepared.results.count == 3 && prepared.results[0].subject.key == prepared.results[1].subject.key && prepared.results[0].subject.key != prepared.results[2].subject.key, "same-file relative person references group literally while different people remain separate")
        check(prepared.results.allSatisfy { $0.subject.resourcePath == nil && !$0.warnings.isEmpty }, "missing companion Patient resources remain unresolved and need explicit original/person review")
        for row in prepared.results {
            check(row.fields.allSatisfy { field in String(decoding: bytes[field.byteStart..<field.byteEnd], as: UTF8.self).utf8.elementsEqual(field.token.utf8) }, "every NDJSON proposed field matches its exact original full-file byte range: " + row.id)
        }
        let draft = try FHIRLabDraft(preparation: prepared, subjectKey: prepared.results[0].subject.key, personChecked: true, coverageReviewed: true)
        let document = try draft.document(acknowledged: true)
        check(document.hasValidFHIRLabImport && document.labReport?.observations.count == 2 && !document.includeInAssistant && document.fhirLabImport?.inputFormat == .ndjson, "reviewed NDJSON saves only the chosen person, with a typed receipt and sharing off")
        check(document.labReport!.observations.allSatisfy { $0.fhirSource?.inputFormat == .ndjson && $0.fhirSource?.isValid == true && $0.source.matches(document.body) }, "NDJSON original format, source anchors and retained typed fields agree after saving")
        check(document.labReport!.observations[0].fhirSource?.originalScalarToken == "1.2300e-9" && document.labReport!.observations[1].fhirSource?.permitsScalar == false, "NDJSON original quantity/string forms survive review without converting text to a scalar")
        check(document.markdown.contains("physical line") && document.markdown.contains("NDJSON") && RecordRetrieval.text(document)?.contains("/line/2/valueString") == true, "saved NDJSON references disclose line locations and original format in Markdown and retrieval")
        var removed = try LabReview.Draft(document: document); removed.observations = []
        let sourceOnly = try removed.applying(to: document, acknowledged: true)
        check(sourceOnly.labReport == nil && sourceOnly.fhirLabImport == document.fhirLabImport && draft.hasDuplicate(in: [sourceOnly]) && sourceOnly.hasValidFHIRLabImport, "removing NDJSON transcriptions preserves the file receipt and exact-file duplicate identity")
        var wrongFormat = document; wrongFormat.fhirLabImport?.inputFormat = .json
        check(!wrongFormat.hasValidFHIRLabImport && RecordRetrieval.text(wrongFormat) == nil, "NDJSON line paths cannot be relabelled as JSON provenance")
        let captured = document.labReport!.observations[0].fhirSource!
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(captured)) as! [String: Any]
        encoded.removeValue(forKey: "inputFormat")
        let missingFormat = try JSONDecoder().decode(FHIRResultSource.self, from: JSONSerialization.data(withJSONObject: encoded))
        check(!missingFormat.isValid, "line-based result provenance requires its explicit NDJSON format on decode")
        var shortInventory = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document.fhirLabImport!)) as! [String: Any]
        shortInventory["inputEntries"] = 1
        let impossibleLine = try JSONDecoder().decode(FHIRLabImportOrigin.self, from: JSONSerialization.data(withJSONObject: shortInventory))
        check(!impossibleLine.isValid, "retained NDJSON receipts reject a selected line beyond their complete input-line inventory")
        for path in ["/line/0", "/line/01", "/line/1025", "/line/-1", "/line/1/entry/0/resource", "/line/1/contained/1024"] {
            check(!FHIRResultSource.validResourcePath(path), "retained NDJSON paths reject invalid physical locations: " + path)
        }
        check(FHIRResultSource.validResourcePath("/line/1024/contained/1023") && FHIRResultSource.validResultPath("/line/1/component/1023"), "retained NDJSON locations accept their documented line/resource/component boundaries")

        // The removed-transcription record is a later state of the same ID.
        // Give this synthetic second backup record its own identity rather
        // than asking backup validation to accept duplicate document IDs.
        var independentReceipt = sourceOnly; independentReceipt.id += "-source-only"
        let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [document, independentReceipt], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        func preserved(_ result: BackupSnapshot) -> Bool {
            guard result.documents.count == snapshot.documents.count else { return false }
            return zip(result.documents, snapshot.documents).allSatisfy { actual, expected in
                actual.hasValidFHIRLabImport && (try? BackupArchive.encoder().encode(actual)) == (try? BackupArchive.encoder().encode(expected))
            }
        }
        check(preserved(try BackupArchive.read(BackupArchive.make(snapshot)).1), "actual version-one backup preserves every NDJSON field at its existing timestamp precision")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-NDJSON-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let selectedFile = folder.appendingPathComponent("Synthetic.ndjson")
        try bytes.write(to: selectedFile)
        let selectedInput = try LabFileImportService.read(selectedFile, control: .init(), fhir: true)
        check(selectedInput.data == bytes && selectedInput.filename == "Synthetic.ndjson", "coordinated FHIR file reading accepts NDJSON and returns exactly the selected original bytes")
        rejects("the flat-table file route does not start accepting NDJSON") { _ = try LabFileImportService.read(selectedFile, control: .init()) }
        rejects("the FHIR file route rejects unrelated table extensions before reading") { _ = try LabFileImportService.read(folder.appendingPathComponent("Synthetic.csv"), control: .init(), fhir: true) }
        let encrypted = folder.appendingPathComponent("Synthetic.lumenbackup")
        try BackupPackage.write(snapshot, photos: [:], password: "Synthetic NDJSON passphrase", to: encrypted)
        let restored = try BackupPackage.read(encrypted, password: "Synthetic NDJSON passphrase", temporaryRoot: folder)
        defer { restored.removeTemporaryFiles() }
        check(preserved(restored.snapshot), "actual encrypted streamed backup preserves NDJSON source fields and source-only receipts")
        let readable = folder.appendingPathComponent("Synthetic.json")
        try ReadableExport.write(snapshot, to: readable)
        check(preserved(try ReadableExport.read(Data(contentsOf: readable)).snapshot), "actual readable export and recovery preserve NDJSON format and exact historical field tokens")
    }
}
