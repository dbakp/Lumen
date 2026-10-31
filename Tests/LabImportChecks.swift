import Foundation

enum LabImportChecks {
    static func fixtures(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let csv = "Subject,Component,Your value,Units,Standard range,Flag,Collection date,Status,Private column\r\nSynthetic A,Ferritin,\"<5,0\",µg/L,15–150,L,20/10/2026,Preliminary,UNMAPPED-PRIVATE-CANARY\r\nSynthetic B,Albumin,42,g/L,35–50,,2026-10-21,Final,OTHER-SUBJECT-CANARY\r\nSynthetic A,PCR,Not detected,,Not detected,,2026-10-20,Final,Unused\r\n"
        try Data(csv.utf8).write(to: folder.appendingPathComponent("Lumen-lab-table.csv"))
        try Data(#"[{"test":"Synthetic quantity","result":1.2300e-9,"unit":"mg/L","timing":null,"status":"Final"},{"test":"Synthetic qualitative","result":false,"reference":"Not detected"}]"#.utf8).write(to: folder.appendingPathComponent("Lumen-lab-literal.json"))
        try Data("test;result;unit\nFerritin;<5,0;µg/L".utf8).write(to: folder.appendingPathComponent("Lumen-lab-regional.csv"))
        try Data("test\tresult\tunit\nSynthetic TSV\t12.00\tmg/L".utf8).write(to: folder.appendingPathComponent("Lumen-lab-tab.tsv"))
        try Data("test,result\n\"Unclosed,1".utf8).write(to: folder.appendingPathComponent("Lumen-lab-invalid.csv"))
        let pages = "test,result\n" + (1...21).map { "Synthetic row \($0),\($0).00" }.joined(separator: "\n")
        try Data(pages.utf8).write(to: folder.appendingPathComponent("Lumen-lab-paged.csv"))
        try Data("Test name recorded by the laboratory,Reported result,Laboratory facility name provided by the laboratory\nSynthetic long heading,12.00,Example facility".utf8).write(to: folder.appendingPathComponent("Lumen-lab-long-header.csv"))
        try Data(("test,result,method\nOversized source,1," + String(repeating: "x", count: 2001) + "\nMissing result,,Brief").utf8).write(to: folder.appendingPathComponent("Lumen-lab-limits.csv"))
    }
    static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); print("PASS: " + name) }
        func rejects(_ name: String, _ action: () throws -> Void) { do { try action(); preconditionFailure(name) } catch { print("PASS: " + name) } }
        // Version-one archives retain timestamps at ISO-8601 second precision.
        // Use a known whole second when asserting complete report equality.
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let legacyBody = "Ferritin: <5,0 µg/L"
        let legacyObservation = LabObservation(test: "Ferritin", result: "<5,0", unit: "µg/L", source: .init(start: 0, end: legacyBody.count, excerpt: legacyBody))
        check(LabReport.textIssue(String(repeating: "9", count: 501), limit: 500, required: true) == .characters(500), "lab field guidance identifies the exact character limit without blaming unrelated fields")
        check(LabReport.textIssue("12\u{0000}", limit: 500) == .controls && LabReport.textIssue("", limit: 500, required: true) == .required && LabReport.textIssue(" ", limit: 500) == .blank, "missing required text, invisible optional text and unsupported controls have distinct recovery reasons")
        var invalidMethod = legacyObservation; invalidMethod.method = String(repeating: "x", count: 501)
        check(!invalidMethod.isValid && invalidMethod.firstFieldIssue == "Method exceeds 500 characters.", "an invalid optional method is named without claiming that the valid test and result are missing")
        let legacyText = "Test: Ferritin\nReported result: <5,0\nReported unit: µg/L\nReported reference: Not recorded\nReported flag: Not recorded\nCollection day: Not recorded\nLaboratory: Not recorded\nSpecimen: Not recorded\nMethod: Not recorded\nTranscribed from saved text characters 1–19"
        check(legacyObservation.referenceText == legacyText, "absent new lab fields preserve the exact published Batch 20 reference text instead of inventing unknown-field lines")
        let hugeGrapheme = "e" + String(repeating: "\u{0301}", count: 5000)
        check(LabReport.textIssue(hugeGrapheme, limit: 500) == .bytes(2000), "a single oversized grapheme gets the byte-size recovery reason rather than an incorrect character count")
        let hugePreview = LabTable.displayPreview(hugeGrapheme, maxCharacters: 160)
        check(hugeGrapheme.count == 1 && hugePreview.text.isEmpty && hugePreview.truncated, "a single oversized Unicode grapheme cannot bypass the native preview byte bound")
        let prefixPreview = LabTable.displayPreview("Literal " + hugeGrapheme + " suffix", maxCharacters: 160)
        check(prefixPreview.text == "Literal " && prefixPreview.truncated, "bounded previews retain a complete literal prefix without splitting or repairing source graphemes")
        check(LabTable.displayPreview("<5,0 µg/L", maxCharacters: 160).text == "<5,0 µg/L" && !LabTable.displayPreview("<5,0 µg/L", maxCharacters: 160).truncated, "ordinary lab preview wording and decimal signs remain exact")
        // Golden uses the published 4e455c6 text and JSON-encoded fingerprint
        // fields, including Foundation's escaped slash spelling.
        var legacyDocument = HealthDocument(title: "Legacy lab record", kind: .record, body: legacyBody, source: "Batch 20 fixture")
        legacyDocument.labReport = LabReport(reviewedAt: now, sourceBodySHA256: LabReport.digest(legacyBody), observations: [legacyObservation])
        let legacyFingerprint = "68882639acb7fd569ca79892c34f0f4c2edb1e40f6560db5be408fc763be942e"
        check(RecordRetrieval.fingerprint(legacyDocument) == legacyFingerprint, "published Batch 20 lab references keep their exact content fingerprint when new optional fields are absent")
        legacyDocument.labReport?.observations[0].reportedStatus = "Final"
        check(RecordRetrieval.fingerprint(legacyDocument) != legacyFingerprint, "new explicitly recorded status changes the lab content fingerprint while absent metadata does not")
        let csv = "Subject,Component,Your value,Units,Standard range,Flag,Collection date,Status,Private column\r\nSynthetic A,Ferritin,\"<5,0\",µg/L,15–150,L,20/10/2026,Preliminary,UNMAPPED-PRIVATE-CANARY\r\nSynthetic B,Albumin,42,g/L,35–50,,2026-10-21,Final,OTHER-SUBJECT-CANARY\r\nSynthetic A,PCR,Not detected,,Not detected,,2026-10-20,Final,Unused\r\n"
        let table = try LabTable.parse(Data(csv.utf8), filename: "Synthetic portal.csv", now: now)
        let map = table.suggestedMapping
        check(table.rows.count == 3 && table.headers.count == 9 && table.validates(map), "real export headings produce a separately reviewable, complete lab column suggestion")
        check(table.rows[0].cells["Your value"]?.value == "<5,0" && table.rows[0].cells["Your value"]?.token == "\"<5,0\"", "CSV lab import preserves decoded comma decimals and their exact quoted source token")
        check(table.subjects(mapping: map) == ["Synthetic A", "Synthetic B"], "different literal lab subjects remain separate groups in source order")
        rejects("lab import cannot continue without checking the intended person") { _ = try LabFileDraft(table: table, mapping: map, subject: "Synthetic A", personChecked: false) }
        rejects("lab import cannot invent a subject group") { _ = try LabFileDraft(table: table, mapping: map, subject: "Absent", personChecked: true) }
        var draft = try LabFileDraft(table: table, mapping: map, subject: "Synthetic A", personChecked: true)
        check(draft.results.map(\.id) == [1, 3] && draft.results[0].observation.reportedTiming == "20/10/2026" && draft.results[0].observation.collectedOn == nil, "subject selection keeps original row identities and retains ambiguous date wording without guessing its day")
        check(draft.results[1].observation.collectedOn == "2026-10-20" && draft.results[0].observation.reportedStatus == "Preliminary", "literal complete calendar days can seed review while reported status stays unmodified")
        rejects("imported lab rows cannot save before fresh acknowledgement") { _ = try draft.document(acknowledged: false) }
        let document = try draft.document(acknowledged: true)
        let previousPlain = try RecordReview.document(title: "Prior plain record", pages: [.init(number: 1, selectable: csv, recognized: "", method: .plainText, text: csv)], filename: table.filename, sha256: table.sha256, readAt: now, acknowledged: true)
        check(draft.hasDuplicate(in: [document]) && draft.hasDuplicate(in: [previousPlain]), "same-file decisions cover both prior lab imports and the existing general record-import route")
        check(!draft.hasDuplicate(in: [HealthDocument(title: document.title, kind: .record, body: csv, source: "Your note")]), "matching lab titles or visible text do not invent a duplicate-file fingerprint")
        check(!document.includeInAssistant && document.id == draft.id && document.labReport?.isCurrent(body: document.body) == true, "reviewed lab file save has stable identity, current source anchors and sharing off")
        check(!document.body.contains("OTHER-SUBJECT-CANARY") && !document.body.contains("UNMAPPED-PRIVATE-CANARY") && !document.markdown.contains("OTHER-SUBJECT-CANARY"), "other subjects and unmapped columns do not enter saved lab source text or readable sharing")
        check(document.labReport?.importedFrom?.selectedRows == [1, 3] && document.labReport?.observations.map(\.importRow) == [1, 3] && document.labReport?.importedFrom?.sha256 == BackupArchive.digest(Data(csv.utf8)), "lab import receipt binds original bytes, mapping and selected data rows without retaining the whole file")
        draft.results[0].observation.result = "<4,0"; draft.results[1].included = false
        let corrected = try draft.document(acknowledged: true, now: now)
        check(corrected.labReport?.observations[0].result == "<4,0" && corrected.labReport?.observations[0].source.excerpt.contains("\"<5,0\"") == true && !corrected.body.contains("Not detected"), "review corrections stay separate from mapped source cells and excluded rows are absent from the saved source")
        var reviewed = try LabReview.Draft(document: corrected)
        reviewed.observations[0].result = "<3,0"
        let rereviewed = try reviewed.applying(to: corrected, acknowledged: true)
        check(rereviewed.labReport?.importedFrom == corrected.labReport?.importedFrom, "later lab review preserves historical import origin rather than inventing a new source file")
        var removing = try LabReview.Draft(document: corrected); removing.observations = []
        let withoutTranscriptions = try removing.applying(to: corrected, acknowledged: true, now: now)
        check(withoutTranscriptions.labReport == nil && withoutTranscriptions.body == corrected.body && RecordReview.hasDuplicate(sha256: table.sha256, in: [withoutTranscriptions]), "removing lab transcriptions preserves the record's original file identity for later duplicate decisions")
        check(withoutTranscriptions.labImportOrigin == corrected.labReport?.importedFrom && withoutTranscriptions.markdown.contains("Input SHA-256: " + table.sha256) && RecordRetrieval.text(withoutTranscriptions)?.contains(table.sha256) == true, "source-only records retain the historical file receipt in readable sharing and consented reference text")
        var olderImport = corrected; olderImport.labImportOrigin = nil
        check(RecordRetrieval.fingerprint(olderImport) == RecordRetrieval.fingerprint(corrected), "moving file identity to record ownership does not change an unchanged earlier imported lab reference fingerprint")
        var removingOlder = try LabReview.Draft(document: olderImport); removingOlder.observations = []
        let upgradedSourceOnly = try removingOlder.applying(to: olderImport, acknowledged: true, now: now)
        check(upgradedSourceOnly.labReport == nil && upgradedSourceOnly.labImportOrigin == olderImport.labReport?.importedFrom, "an earlier report-only import moves its historical file receipt to the retained record before clearing the last transcription")
        var addingAgain = try LabReview.Draft(document: withoutTranscriptions)
        var manual = corrected.labReport!.observations[0]; manual.importRow = nil; addingAgain.observations = [manual]
        let reviewedAgain = try addingAgain.applying(to: withoutTranscriptions, acknowledged: true, now: now)
        check(reviewedAgain.labReport?.importedFrom == withoutTranscriptions.labImportOrigin && reviewedAgain.labReport?.observations[0].importRow == nil, "adding a later manual transcription keeps historical file origin without inventing an original import-row identity")
        check(rereviewed.labReport?.matchesOriginalImportLayout(body: rereviewed.body) == true && rereviewed.labReport?.matchesOriginalImportLayout(body: rereviewed.body + "Edited source") == false, "original source-cell labels require the retained initial cell-layout fingerprint rather than a later review hash")
        var changedSource = corrected
        changedSource.body += "\nAdditional source wording"
        let checkedAgain = try LabReview.Draft(document: changedSource).applying(to: changedSource, acknowledged: true, now: now)
        check(checkedAgain.labReport?.isCurrent(body: checkedAgain.body) == true && checkedAgain.labReport?.matchesOriginalImportLayout(body: checkedAgain.body) == false && checkedAgain.labReport?.importedFrom == corrected.labReport?.importedFrom, "a later source review preserves historical import origin but does not relabel changed text as original file cells")
        let json = #"[{"test":"Synthetic quantity","result":1.2300e-9,"unit":"mg/L","timing":null,"status":"Final"},{"test":"Synthetic qualitative","result":false,"reference":"Not detected"}]"#
        let jsonTable = try LabTable.parse(Data(json.utf8), filename: "Literal.json", now: now)
        check(jsonTable.rows[0].cells["result"]?.value == "1.2300e-9" && jsonTable.rows[0].cells["result"]?.token == "1.2300e-9" && jsonTable.rows[1].cells["result"]?.value == "false", "JSON lab scalars preserve exponent/trailing-zero spelling and never coerce booleans to numbers")
        check(jsonTable.rows[0].cells["timing"]?.value == "" && jsonTable.rows[0].cells["timing"]?.token == "null" && jsonTable.rows[1].cells["timing"] == nil, "explicit JSON null and missing members remain distinguishable in mapped source provenance")
        let jsonDraft = try LabFileDraft(table: jsonTable, mapping: jsonTable.suggestedMapping, subject: "", personChecked: true)
        let jsonDocument = try jsonDraft.document(acknowledged: true, now: now)
        check(jsonDocument.labReport?.observations[0].collectedOn == nil && jsonDocument.labReport?.observations[0].reportedTiming == nil && jsonDocument.body.contains("[Not present in this source row]"), "missing JSON collection data does not become today or a fabricated result")
        let ambiguous = try LabTable.parse(Data("test,component,result\nA,B,1".utf8), filename: "Ambiguous.csv")
        check(ambiguous.suggestedMapping["test"] == nil && !ambiguous.validates(ambiguous.suggestedMapping), "two plausible test-name columns require an explicit mapping instead of choosing the first")
        let longSource = try LabTable.parse(Data(("test,result,method\nLong,1," + String(repeating: "x", count: 2001) + "\nShort,2,Brief").utf8), filename: "Long cell.csv")
        var longDraft = try LabFileDraft(table: longSource, mapping: longSource.suggestedMapping, subject: "", personChecked: true)
        check(longDraft.results.count == 2 && !longDraft.results[0].sourceValid && longDraft.results[0].sourceText.contains(String(repeating: "x", count: 2001)), "an overlong mapped cell stays in the review draft without silent clipping")
        rejects("an included overlong source row blocks saving") { _ = try longDraft.document(acknowledged: true) }
        longDraft.results[0].included = false
        let shortOnly = try longDraft.document(acknowledged: true)
        check(shortOnly.labReport?.observations.count == 1 && shortOnly.labReport?.importedFrom?.selectedRows == [2] && !shortOnly.body.contains(String(repeating: "x", count: 2001)), "explicit exclusion saves the valid row while leaving the oversized row out of saved source and provenance selection")
        let unicodeRow = String(repeating: "🧪", count: 200) + "," + String(repeating: "🧪", count: 500) + "," + String(repeating: "🧪", count: 1000)
        let combined = try LabTable.parse(Data(("test,result,reference\n" + Array(repeating: unicodeRow, count: 100).joined(separator: "\n")).utf8), filename: "Combined limits.csv")
        let combinedDraft = try LabFileDraft(table: combined, mapping: combined.suggestedMapping, subject: "", personChecked: true)
        do { _ = try combinedDraft.document(acknowledged: true); preconditionFailure("oversized combined lab text accepted") }
        catch LabFileDraft.Failure.textLimit { print("PASS: combined Unicode lab payload limit gives the record-size recovery action rather than a misleading per-row source error") }
        var forged = draft; forged.results[0].observation.source.excerpt = "Forged source"
        rejects("changing an imported source anchor cannot forge mapped cells during saving") { _ = try forged.document(acknowledged: true) }
        let escaped = try LabTable.parse(Data(#"[{"test":"Caf\u00e9","result":-0.00,"status":"Pre\nliminary"}]"#.utf8), filename: "Escaped.json")
        let escapedDraft = try LabFileDraft(table: escaped, mapping: escaped.suggestedMapping, subject: "", personChecked: true)
        let escapedDocument = try escapedDraft.document(acknowledged: true)
        check(escapedDocument.labReport?.observations[0].test == "Café" && escapedDocument.body.contains(#""Caf\u00e9""#) && escapedDocument.labReport?.observations[0].result == "-0.00", "JSON string escapes and negative decimal zero retain raw source spelling beside decoded reviewed fields")
        let multiline = try LabTable.parse(Data("test,result,reference\r\n\"Café \"\"panel\"\"\",\"Line one\r\nLine two\",\" a, b \"\r\n".utf8), filename: "Quotes.csv")
        check(multiline.rows[0].cells["test"]?.value == "Café \"panel\"" && multiline.rows[0].cells["result"]?.value == "Line one\r\nLine two" && multiline.rows[0].cells["reference"]?.value == " a, b ", "CSV quoted escapes, embedded CRLF and meaningful whitespace remain literal")
        let combining = "\u{0301}<5,0"
        let combiningPlain = try? LabTable.parse(Data(("test;result\r\nMarker;" + combining + "\r\n").utf8), filename: "Combining.csv", separator: ";")
        check(combiningPlain?.rows.first?.cells["result"]?.value == combining && combiningPlain?.rows.count == 1, "a combining mark immediately after a CSV separator cannot absorb the delimiter")
        let combiningQuoted = try? LabTable.parse(Data(("test,result\r\nMarker,\"" + combining + "\"\r\n").utf8), filename: "Combining quoted.csv")
        check(combiningQuoted?.rows.first?.cells["result"]?.value == combining && combiningQuoted?.rows.first?.cells["result"]?.token == "\"" + combining + "\"", "CSV quotation is parsed independently of adjacent Unicode grapheme boundaries while retaining the exact token")
        let bom = try LabTable.parse(Data([239,187,191]) + Data("test\tresult\nPCR\tNot detected".utf8), filename: "BOM.tsv")
        check(bom.format == "tsv" && bom.separator == "\t" && bom.rows[0].cells["result"]?.value == "Not detected", "UTF-8 BOM and TSV parsing retain the original fingerprint and explicit separator")
        let semicolon = try LabTable.parse(Data("test;result;unit\nFerritin;<5,0;µg/L".utf8), filename: "Regional.csv", separator: ";")
        check(semicolon.rows[0].cells["result"]?.value == "<5,0" && semicolon.separator == ";", "explicit semicolon selection supports regional CSV decimals without splitting the result")
        let blank = try LabTable.parse(Data("\ntest,result\n\nPCR,Not detected\n,\n".utf8), filename: "Blank.csv")
        check(blank.blankRows == 2 && blank.rows.count == 2 && blank.rows[1].cells["test"]?.value == "", "only physically blank CSV records are counted separately; explicit empty rows remain reviewable")
        let emptySubjects = try LabTable.parse(Data("test,result,subject\nA,1,\nB,2,Synthetic A".utf8), filename: "Subjects.csv")
        check(emptySubjects.subjects(mapping: emptySubjects.suggestedMapping) == ["", "Synthetic A"], "blank subject cells are not silently combined with a named person")
        for malformed in ["test,result\nA,\"unclosed", "test,result\nA,un\"quoted", "test,result\nA,\"closed\"x", "test,result\nA,1,extra", "test,test\nA,1", "test,\nA,1", "test,result\n", "test,result\n\"A\" ,1"] {
            rejects("malformed or ambiguous CSV creates no lab proposal") { _ = try LabTable.parse(Data(malformed.utf8), filename: "Invalid.csv") }
        }
        for malformed in [#"[{"test":"A","test":"B","result":1}]"#, #"[{"test":"A","result":01}]"#, #"[{"test":"A","result":NaN}]"#, #"[{"test":"A","result":{"value":1}}]"#, #"[{"test":"A","result":"bad\q"}]"#, #"[{"test":"A","result":true,}]"#, #"{"resourceType":"Bundle"}"#, "[]", #"[{"test":"A","result":1}] trailing"#] {
            rejects("unsupported, malformed or ambiguous JSON creates no lab proposal") { _ = try LabTable.parse(Data(malformed.utf8), filename: "Invalid.json") }
        }
        rejects("invalid UTF-8 is not repaired into a different lab file") { _ = try LabTable.parse(Data([255,254,0]), filename: "Invalid.csv") }
        rejects("oversized lab input is refused before row construction") { _ = try LabTable.parse(Data(repeating: 65, count: LabTable.maxBytes + 1), filename: "Large.csv") }
        let tooMany = "test,result\n" + (0...LabTable.maxRows).map { "Test\($0),1" }.joined(separator: "\n")
        rejects("overlarge lab files are refused as a whole rather than importing a first subset") { _ = try LabTable.parse(Data(tooMany.utf8), filename: "Rows.csv") }
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("cancelled parsing produces no lab draft") { _ = try LabTable.parse(Data(csv.utf8), filename: "Cancel.csv", control: cancelled) }
        var invalidMap = map; invalidMap["result"] = invalidMap["test"]
        check(!table.validates(invalidMap), "one source column cannot silently fill multiple lab fields")
        var excluded = draft; for i in excluded.results.indices { excluded.results[i].included = false }
        rejects("lab file save cannot create an empty report after exclusion") { _ = try excluded.document(acknowledged: true) }
        var invalid = draft; invalid.results[0].observation.result = ""
        rejects("included missing results require correction or explicit exclusion") { _ = try invalid.document(acknowledged: true) }
        var sourceOnlyCopy = withoutTranscriptions; sourceOnlyCopy.id = "Synthetic source-only record"
        let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [corrected, jsonDocument, sourceOnlyCopy], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        let legacy = try BackupArchive.read(BackupArchive.make(snapshot)).1
        check(legacy.documents.map(\.labReport) == snapshot.documents.map(\.labReport), "version-one backups preserve literal imported lab fields and file/row provenance")
        check(legacy.documents.map(\.originalLabImport) == snapshot.documents.map(\.originalLabImport), "version-one backup retains document-owned file receipts even when no lab transcriptions remain")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumenBatch21LabChecks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false); defer { try? FileManager.default.removeItem(at: folder) }
        let inputURL = folder.appendingPathComponent("Synthetic.csv")
        try Data(csv.utf8).write(to: inputURL)
        let input = try LabFileImportService.read(inputURL, control: .init())
        let reread = try input.parse(control: .init())
        check(input.data == Data(csv.utf8) && input.filename == "Synthetic.csv" && reread.sha256 == table.sha256 && reread.readAt == input.readAt, "actual coordinated bounded file reading retains exact bytes and one read timestamp without a private file mirror")
        let denied = BackupOperationControl(); denied.cancel()
        rejects("cancelled file read returns no input") { _ = try LabFileImportService.read(inputURL, control: denied) }
        rejects("cancelled input reparse returns no table") { _ = try input.parse(control: denied) }
        let largeURL = folder.appendingPathComponent("Large.csv")
        try Data(repeating: 65, count: LabTable.maxBytes + 1).write(to: largeURL)
        rejects("actual file reader refuses oversized input before loading the whole file") { _ = try LabFileImportService.read(largeURL, control: .init()) }
        try FileManager.default.removeItem(at: largeURL)
        let link = folder.appendingPathComponent("Link.csv")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: inputURL)
        rejects("symbolic lab input is refused rather than following a source link") { _ = try LabFileImportService.read(link, control: .init()) }
        let whitespace = try LabTable.parse(Data("subject,test,result\n ,Synthetic,1\n,Synthetic blank,2".utf8), filename: "Whitespace.csv")
        let whiteDraft = try LabFileDraft(table: whitespace, mapping: whitespace.suggestedMapping, subject: " ", personChecked: true)
        let whiteDocument = try whiteDraft.document(acknowledged: true)
        check(whiteDocument.labReport?.importedFrom?.subject == " ", "whitespace-only literal subject groups remain distinct and retain their exact label")
        check(corrected.markdown.contains("result: Your value") && corrected.markdown.contains("data rows: 1."), "readable lab sharing includes the original mapped columns and selected row identities")
        let encrypted = folder.appendingPathComponent("Synthetic.lumenbackup")
        try BackupPackage.write(snapshot, photos: [:], password: "Synthetic lab import passphrase", to: encrypted)
        let restored = try BackupPackage.read(encrypted, password: "Synthetic lab import passphrase", temporaryRoot: folder); defer { restored.removeTemporaryFiles() }
        check(restored.snapshot.documents.map(\.labReport) == snapshot.documents.map(\.labReport), "actual encrypted backup retains lab import receipt, statuses and raw collection wording")
        check(restored.snapshot.documents.map(\.originalLabImport) == snapshot.documents.map(\.originalLabImport), "actual encrypted backup retains source-only file identity after transcription removal")
        let readable = folder.appendingPathComponent("Synthetic.json"); try ReadableExport.write(snapshot, to: readable)
        let recovered = try ReadableExport.read(Data(contentsOf: readable))
        check(recovered.snapshot.documents.map(\.labReport) == snapshot.documents.map(\.labReport), "actual readable export/recovery retains lab import receipt and literal scalar spelling")
        check(recovered.snapshot.documents.map(\.originalLabImport) == snapshot.documents.map(\.originalLabImport), "actual readable recovery preserves file receipts independently of the lab transcription list")
        var corrupted = snapshot; corrupted.documents[0].labReport?.observations[0].importRow = 999
        rejects("restoration rejects a row origin outside the original selected import") { try BackupArchive.validate(corrupted) }
        var contradictory = snapshot; contradictory.documents[0].labImportOrigin?.sha256 = String(repeating: "f", count: 64)
        rejects("restoration rejects contradictory document and transcription file receipts") { try BackupArchive.validate(contradictory) }
        check(contradictory.documents[0].labReport?.isValid(in: contradictory.documents[0]) == false, "report validation also rejects contradictory record-owned file identity")
        var mismatchedReport = corrected.labReport!; mismatchedReport.importedFrom?.sha256 = String(repeating: "f", count: 64)
        check(!mismatchedReport.isValid(in: withoutTranscriptions), "a proposed report must match a source-only record's file identity before it is attached")
        var invalidOrigin = snapshot; invalidOrigin.documents[2].labImportOrigin?.selectedRows = [999]
        rejects("restoration validates source-only receipts even with no lab report") { try BackupArchive.validate(invalidOrigin) }
        check(RecordRetrieval.text(invalidOrigin.documents[2]) == nil, "invalid source-only provenance is withheld from assistant reference text")
    }
}
