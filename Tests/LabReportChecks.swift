import Foundation

enum LabReportChecks {
    static func fixtures(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let body = "## Page 1\n\nSYNTHETIC LABORATORY FIXTURE. NOT PATIENT DATA.\nFerritin: <5,0 µg/L; reported reference 15–150; flag L.\nSpecimen: Serum. Method: synthetic assay.\nPCR: Not detected; reported reference Not detected.\n"
        let raw = HealthDocument(id: "lab-fixture-raw", title: "Synthetic laboratory report", kind: .record, body: body, source: "Synthetic fixture · no patient data")
        let sources = LabReview.sources(in: body)
        var draft = try LabReview.Draft(document: raw)
        draft.observations = [LabObservation(test: "Ferritin", result: "<5,0", unit: "µg/L", reference: "15–150", flag: "L", collectedOn: "2026-10-20", laboratory: "Synthetic laboratory", specimen: "Serum", method: "Synthetic reported method", source: sources.first { $0.excerpt.hasPrefix("Ferritin:") }!), LabObservation(test: "PCR", result: "Not detected", reference: "Not detected", source: sources.first { $0.excerpt.hasPrefix("PCR:") }!)]
        var reviewed = try draft.applying(to: raw, acknowledged: true)
        reviewed.id = "lab-fixture-reviewed"; reviewed.title = "Saved synthetic lab results"
        let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [raw, reviewed], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        try BackupArchive.make(snapshot).write(to: folder.appendingPathComponent("Lumen-backup-labs.json"))
    }
    static func run() async throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); print("PASS: " + name) }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { print("PASS: " + name) }
        }
        let body = "## Page 1\n\nSynthetic report · not patient data\nCafé sample 🧪\nFerritin: <5,0 µg/L; reference 15–150; flag L\nPCR: Not detected; reference Not detected\n"
        let original = HealthDocument(title: "Synthetic lab report", kind: .record, body: body, source: "Synthetic fixture")
        let sources = LabReview.sources(in: body)
        let ferritin = sources.first { $0.excerpt.hasPrefix("Ferritin:") }!
        let pcr = sources.first { $0.excerpt.hasPrefix("PCR:") }!
        check(sources.allSatisfy { $0.matches(body) } && ferritin.start == Array(body).firstIndex(of: "F"), "lab source offsets preserve Unicode and exact selected lines")
        check(LabReview.sources(in: "A\r\nB\rC\n").map(\.excerpt) == ["A", "B", "C"], "lab source selection retains exact CRLF, CR and LF character offsets")
        check(LabReview.sources(in: "\n \n" + String(repeating: "x", count: 2001)).isEmpty, "blank and overlong lab source lines are not silently truncated")
        let wrapped = "A\r\nβ\n\nC"
        let first = LabReview.sources(in: wrapped)[0]
        let extended = LabReview.extending(first, in: wrapped, forward: true)!
        check(extended.excerpt == "A\r\nβ" && extended.matches(wrapped), "wrapped lab sources can include the next complete line with exact Unicode/CRLF offsets")
        let backwards = LabReview.extending(LabReview.sources(in: wrapped)[1], in: wrapped, forward: false)!
        check(backwards == extended, "lab source expansion can include the previous complete line without changing its wording")
        let blank = LabReview.extending(extended, in: wrapped, forward: true)!
        let whole = LabReview.extending(blank, in: wrapped, forward: true)!
        check(whole.excerpt == wrapped && whole.matches(wrapped), "adjacent blank source lines remain literal while expanding an excerpt")
        let tooLong = "A\n" + String(repeating: "x", count: 1999)
        check(LabReview.extending(LabReview.sources(in: tooLong)[0], in: tooLong, forward: true) == nil && LabReview.extending(first, in: "Changed source", forward: true) == nil, "source expansion refuses overlong or changed text without silently clipping it")
        var draft = try LabReview.Draft(document: original)
        let result = LabObservation(test: "Ferritin", result: "<5,0", unit: "µg/L", reference: "15–150", flag: "L", collectedOn: "2026-10-20", laboratory: "Synthetic laboratory", specimen: "Serum", method: "Reported method", source: ferritin)
        draft.observations = [result, LabObservation(test: "PCR", result: "Not detected", reference: "Not detected", source: pcr)]
        rejects("lab transcription cannot save without explicit review") { _ = try draft.applying(to: original, acknowledged: false) }
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        var saved = try draft.applying(to: original, acknowledged: true, now: now)
        check(saved.labReport?.isCurrent(body: body) == true && saved.labReport?.observations == draft.observations && saved.body == body, "lab review retains exact comparators, comma decimals, units, wording and source without altering the record")
        check(saved.id == original.id && !saved.includeInAssistant && saved.labReport?.reviewedAt == now, "lab review updates the same record, preserves sharing off and records actual review time")
        check(saved.labReport?.observations[1].unit.isEmpty == true && saved.labReport?.observations[1].collectedOn == nil, "qualitative results and missing unit/date remain literal or unknown")
        var changedConsent = original; changedConsent.includeInAssistant = true
        let shared = try draft.applying(to: changedConsent, acknowledged: true)
        check(shared.includeInAssistant, "lab review preserves a newer sharing choice rather than overwriting it from the draft")
        for field in ["body", "title", "source", "identity", "kind"] {
            var changed = original
            switch field {
            case "body": changed.body += "Updated report"
            case "title": changed.title += " corrected"
            case "source": changed.source += " corrected"
            case "identity": changed.id = "different-copy"
            default: changed.kind = .note
            }
            rejects("concurrent lab record \(field) changes cannot be overwritten by an old draft") { _ = try draft.applying(to: changed, acknowledged: true) }
        }
        let editing = try LabReview.Draft(document: saved)
        var cleared = editing; cleared.observations = []
        let removed = try cleared.applying(to: saved, acknowledged: true)
        check(removed.labReport == nil && removed.body == saved.body, "explicitly reviewed removal of all transcriptions preserves the source record")
        var rereviewed = saved; rereviewed.labReport?.reviewedAt = now.addingTimeInterval(1)
        rejects("a concurrent lab re-review cannot be overwritten even when its values match") { _ = try editing.applying(to: rereviewed, acknowledged: true) }
        for broken in ["empty", "identity", "date", "source", "name", "result", "control", "whitespace", "limit"] {
            var invalid = draft
            switch broken {
            case "empty": invalid.observations = []
            case "identity": invalid.observations.append(invalid.observations[0])
            case "date": invalid.observations[0].collectedOn = "2026-02-30"
            case "source": invalid.observations[0].source.excerpt = "Invented"; invalid.observations[0].source.end = invalid.observations[0].source.start + 8
            case "name": invalid.observations[0].test = ""
            case "result": invalid.observations[0].result = ""
            case "control": invalid.observations[0].unit = "mg\u{0}/L"
            case "whitespace": invalid.observations[0].unit = " "
            default: invalid.observations = (0...LabReport.maxObservations).map { _ in var value = result; value.id = UUID().uuidString; return value }
            }
            rejects("invalid lab \(broken) is rejected before storage, without silent data loss") { _ = try invalid.applying(to: original, acknowledged: true) }
        }
        let encoded = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(HealthDocument.self, from: encoded)
        check(decoded.labReport == saved.labReport && decoded.labReport?.isValid(in: decoded) == true, "lab fields and original source anchors round-trip with the Library document")
        var oldObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]; oldObject.removeValue(forKey: "labReport")
        let legacy = try JSONDecoder().decode(HealthDocument.self, from: JSONSerialization.data(withJSONObject: oldObject))
        check(legacy.labReport == nil && legacy.body == body, "existing records decode without invented lab transcriptions")
        let privateContext = try RecordRetrieval.search(query: "Ferritin", documents: [saved])
        check(privateContext.passages.isEmpty && privateContext.sharedDocuments == 0, "private lab records do not enter question retrieval")
        saved.includeInAssistant = true
        let context = try RecordRetrieval.search(query: "Reported method", documents: [saved])
        check(context.passages.contains { $0.excerpt.contains("Reported method") }, "reviewed lab metadata participates in consented question retrieval")
        check(RecordRetrieval.text(saved)?.contains("not clinical interpretation") == true && saved.markdown.contains("<5,0") && saved.markdown.contains(ferritin.excerpt), "assistant and readable sharing retain lab uncertainty, literal result and exact source excerpt")
        var corrected = saved; corrected.labReport?.observations[0].result = "<4,0"
        check(RecordRetrieval.fingerprint(corrected) != RecordRetrieval.fingerprint(saved), "a structured result correction changes the canonical source fingerprint")
        var multiline = saved
        multiline.labReport?.observations[0].result = "<5,0\nRepeat sample requested"
        multiline.labReport?.observations[0].method = "First method line\n\n## Page 2\n\nMETADATAONLYCANARY"
        multiline.extraction = RecordExtraction(filename: "Synthetic source", sha256: String(repeating: "a", count: 64), readAt: now, reviewedAt: now, pages: [.init(number: 1, method: .plainText, edited: false, lowConfidenceLines: 0), .init(number: 2, method: .plainText, edited: false, lowConfidenceLines: 0)])
        check(multiline.labReport?.isValid(in: multiline) == true && RecordRetrieval.text(multiline)?.contains("<5,0\nRepeat sample requested") == true, "multiline qualitative/result wording stays literal without stripping line breaks")
        let metadata = try RecordRetrieval.search(query: "METADATAONLYCANARY", documents: [multiline])
        check(!metadata.passages.isEmpty && metadata.passages.allSatisfy { $0.page == nil }, "structured lab metadata cannot inherit or forge an original source-page number")
        let largeBody = String(repeating: "x\n", count: 99_950) + "Ferritin: <5,0 µg/L"
        let largeDocument = HealthDocument(title: "Synthetic near-limit record", kind: .record, body: largeBody, source: "Synthetic")
        var largeDraft = try LabReview.Draft(document: largeDocument)
        var largeResult = result; largeResult.source = LabReview.sources(in: largeBody).last!
        largeDraft.observations = [largeResult]
        do { _ = try largeDraft.applying(to: largeDocument, acknowledged: true); preconditionFailure("over-limit combined lab text accepted") }
        catch LabReview.Failure.textLimit { print("PASS: combined record/lab search limits fail explicitly rather than truncating source or transcription") }
        var stale = saved; stale.body = "Corrected current record. The original values have been replaced."
        check(stale.labReport?.isValid(in: stale) == true && stale.labReport?.isCurrent(body: stale.body) == false, "editing source text preserves an explicitly stale historical lab transcription")
        check(RecordRetrieval.text(stale)?.contains("<5,0") == false && RecordRetrieval.text(stale)?.contains("withheld") == true && stale.markdown.contains("SOURCE TEXT CHANGED"), "changed-source lab values are withheld from future assistant retrieval and marked in readable sharing")
        rejects("stale lab anchors require correction before a fresh review can save") { _ = try LabReview.Draft(document: stale).applying(to: stale, acknowledged: true) }
        var snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [saved, stale], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        snapshot.documents[1].id = "stale-copy"
        let backup = try BackupArchive.read(BackupArchive.make(snapshot)).1
        check(backup.documents.map(\.labReport) == snapshot.documents.map(\.labReport), "version-one backups preserve current and stale lab transcriptions without a forced migration")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumenBatch20LabChecks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let encrypted = folder.appendingPathComponent("synthetic.lumenbackup")
        try BackupPackage.write(snapshot, photos: [:], password: "Synthetic lab test passphrase", to: encrypted)
        let restored = try BackupPackage.read(encrypted, password: "Synthetic lab test passphrase", temporaryRoot: folder)
        defer { restored.removeTemporaryFiles() }
        check(restored.snapshot.documents.map(\.labReport) == snapshot.documents.map(\.labReport), "actual encrypted streamed backup retains every lab field and source state")
        let readable = folder.appendingPathComponent("synthetic.json")
        try ReadableExport.write(snapshot, to: readable)
        let recovery = try ReadableExport.read(Data(contentsOf: readable))
        check(recovery.snapshot.documents.map(\.labReport) == snapshot.documents.map(\.labReport), "actual readable export and reviewed recovery retain lab fields and source state")
        let local = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        check(snapshot.merging(into: local, restorePreferences: false).documents.allSatisfy { !$0.includeInAssistant }, "restored lab records require fresh assistant consent")
        for corruption in ["version", "anchor", "kind", "count"] {
            var invalid = snapshot
            switch corruption {
            case "version": invalid.documents[0].labReport?.version = 2
            case "anchor": invalid.documents[0].labReport?.observations[0].source.start += 1; invalid.documents[0].labReport?.observations[0].source.end += 1
            case "kind": invalid.documents[0].kind = .plan
            default: invalid.documents[0].labReport?.observations = []
            }
            rejects("backup recovery rejects lab \(corruption) corruption before restore") { try BackupArchive.validate(invalid) }
        }
    }
}
