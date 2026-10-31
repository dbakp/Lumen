import Foundation

enum LabHistoryChecks {
    static func capturedFixture(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let earlier = try record("history-earlier", result: "12.00", day: "2026-01-20")
        let later = try record("history-later", result: "18.50", day: "2026-10-20", reference: "20–160")
        let selected = try LabHistory.prepare(recordIDs: [earlier.id, later.id], documents: [earlier, later], now: now)
        var captured = try LabHistory.snapshot(selected, firstID: selected.points[0].id, secondID: selected.points[1].id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [earlier, later], now: now)
        captured.id = "history-captured-comparison"; captured.title = "Restored synthetic comparison"
        let archive = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [earlier, later, captured], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        try BackupArchive.make(archive).write(to: folder.appendingPathComponent("Lumen-backup-captured-comparison.json"))
    }
    static func fixtures(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var documents = [
            try record("history-earlier", result: "12.00", day: "2026-01-20"),
            try record("history-later", result: "18.50", day: "2026-10-20", reference: "20–160"),
            try record("history-undated", result: "7.00", day: nil),
            try record("history-qualified", result: "<5,0", day: "2026-05-10"),
            try record("history-zero", result: "0.00", day: "2026-03-05"),
            try record("history-other-lab", result: "22.00", day: "2026-10-25", lab: "Other synthetic laboratory"),
            try record("history-qualitative", result: "Not detected", day: nil, test: "PCR", unit: "", lab: "", specimen: "", method: "", reference: "Not detected", status: nil)
        ]
        let pagedBody = (1...21).map { "Synthetic paged result \($0): \($0).00 mg/L" }.joined(separator: "\n")
        let paged = HealthDocument(id: "history-paged", title: "Synthetic report · 21 results", kind: .record, body: pagedBody, source: "Synthetic history pagination fixture")
        var draft = try LabReview.Draft(document: paged)
        draft.observations = LabReview.sources(in: pagedBody).enumerated().map { index, source in
            var value = LabObservation(test: "Paged synthetic test", result: "\(index + 1).00", unit: "mg/L", collectedOn: "2026-10-20", laboratory: "Synthetic laboratory", specimen: "Serum", method: "Synthetic assay", source: source)
            value.id = "history-paged-\(index + 1)"; value.reportedStatus = "Final"; return value
        }
        documents.append(try draft.applying(to: paged, acknowledged: true, now: now))
        let table = try LabTable.parse(Data("test,result,unit,date,laboratory\nSynthetic copied cells,12.0,µg/L,2026-01-20,Synthetic laboratory".utf8), filename: "Synthetic duplicate history.csv", now: now)
        var imported = try LabFileDraft(table: table, mapping: table.suggestedMapping, subject: "", personChecked: true).document(acknowledged: true, now: now)
        imported.id = "history-imported"; imported.title = "Synthetic imported original"
        var copy = imported; copy.id = "history-imported-copy"; copy.title = "Synthetic imported copy"
        documents += [imported, copy]
        let archive = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: documents, importedDays: [], imports: [], personalContext: .init(), photos: [:])
        try BackupArchive.make(archive).write(to: folder.appendingPathComponent("Lumen-backup-history.json"))
        let selection = try LabHistory.prepare(recordIDs: documents.map(\.id), documents: documents, now: now)
        let manifest = selection.points.map { ["record": $0.record.id, "result": $0.observation.id, "point": $0.id, "group": $0.groupID] }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("history-identities.json"))
    }
    static let now = Date(timeIntervalSince1970: 1_793_000_000)
    static func record(_ id: String, result: String, day: String?, test: String = "Ferritin", unit: String = "µg/L", lab: String = "Synthetic laboratory", specimen: String = "Serum", method: String = "Synthetic assay", reference: String = "15–150", status: String? = "Final") throws -> HealthDocument {
        let body = "SYNTHETIC LAB HISTORY. NOT PATIENT DATA.\n\(test): \(result) \(unit); collection \(day ?? "not reported"); \(lab); \(specimen); \(method)."
        let raw = HealthDocument(id: id, title: "Synthetic report · " + id, kind: .record, body: body, source: "Synthetic lab history fixture")
        let source = LabReview.sources(in: body).last!
        var observation = LabObservation(test: test, result: result, unit: unit, reference: reference, collectedOn: day, laboratory: lab, specimen: specimen, method: method, source: source)
        observation.id = id + "-result"; observation.reportedStatus = status
        var draft = try LabReview.Draft(document: raw); draft.observations = [observation]
        var value = try draft.applying(to: raw, acknowledged: true, now: now)
        value.createdAt = now; value.updatedAt = now
        return value
    }
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        func rejects(_ label: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(label) } catch { print("PASS: " + label) }
        }
        func scalar(_ raw: String, _ style: LabHistory.DecimalStyle? = .dot) -> LabHistory.Number? { try? LabHistory.number(raw, style: style).get() }
        let earlier = try record("history-earlier", result: "12.00", day: "2026-01-20")
        let later = try record("history-later", result: "18.50", day: "2026-10-20", reference: "20–160")
        let undated = try record("history-undated", result: "7.00", day: nil)
        let qualified = try record("history-qualified", result: "<5,0", day: "2026-05-10")
        let selection = try LabHistory.prepare(recordIDs: [later.id, earlier.id, undated.id, qualified.id], documents: [earlier, later, undated, qualified], now: now)
        check(selection.points.count == 4 && selection.groups.count == 1, "lab history retains every chosen result and keeps differing reported references within an exact test/context group")
        check(selection.points.map(\.record.id) == [later.id, qualified.id, earlier.id, undated.id], "lab history orders known collection days and keeps undated results after them")
        check(selection.points.last?.collectionDay == nil, "record creation, update and review timestamps never fill an absent lab collection day")
        let a = selection.points.first { $0.record.id == earlier.id }!, b = selection.points.first { $0.record.id == later.id }!
        let comparison = LabHistory.compare(b, a, style: .dot, personChecked: true)
        check(comparison.first.id == a.id && comparison.second.id == b.id && comparison.difference == "6.5", "reviewed lab comparison subtracts exact decimal numbers in collection-day order")
        check(comparison.warnings.contains { $0.contains("Reference wording differs") } && a.observation.result == "12.00" && b.observation.result == "18.50", "a numeric difference preserves reported precision and each result's distinct reference wording")
        check(LabHistory.compare(a, b, style: .dot, personChecked: false).difference == nil, "numeric lab comparison requires the intended-person check")
        check(LabHistory.compare(a, b, style: nil, personChecked: true).difference == nil, "lab comparison never guesses decimal punctuation from device region")
        check(scalar("12.00", .literal) == nil && LabHistory.compare(a, b, style: .literal, personChecked: true).difference == nil, "explicit wording-only interpretation never calculates from apparently numeric lab values")
        let wordingPlot = LabHistory.plot(selection.groups[0], style: .literal, personChecked: true)
        check(wordingPlot.points.isEmpty && wordingPlot.blockers == [.wordingOnly] && wordingPlot.omitted.count == 4, "wording-only history retains every result and clearly disables its numeric plot")
        var tiny = a.observation; tiny.result = "1e-100"
        var huge = b.observation; huge.result = "1e100"
        check(scalar(tiny.result) != nil && scalar(huge.result) != nil && LabHistory.compare(.init(record: a.record, observation: tiny), .init(record: b.record, observation: huge), style: .dot, personChecked: true).difference == nil, "individually exact lab numbers with an unrepresentable exact difference withhold arithmetic rather than rounding")
        for (earlierValue, laterValue, expected) in [("-12.25", "18.50", "30.75"), ("12.25", "-18.50", "-30.75"), ("-12.25", "-18.50", "-6.25"), ("0", "18.50", "18.5"), ("18.50", "18.50", "0"), (".000001", "-.000001", "-0.000002")] {
            var left = a.observation; left.result = earlierValue
            var right = b.observation; right.result = laterValue
            check(LabHistory.compare(.init(record: a.record, observation: left), .init(record: b.record, observation: right), style: .dot, personChecked: true).difference == expected, "exact comparison preserves signed subtraction and decimal places: \(laterValue) minus \(earlierValue)")
        }
        check(scalar("1.2300e-9")?.decimal == Decimal(string: "0.00000000123") && scalar("-0.00")?.decimal == 0, "lab numeric interpretation retains exact scientific values and accepts a recorded negative zero")
        check(scalar("-12.25")?.decimal == Decimal(string: "-12.25") && scalar("+0.50")?.decimal == Decimal(string: "0.5"), "negative values and explicit positive signs are not treated as missing lab data")
        check(scalar("5,000", .comma)?.decimal == 5 && scalar("5.000", .dot)?.decimal == 5, "an explicitly chosen decimal mark interprets three following digits as decimals rather than inventing grouping")
        check(scalar("1,234.50", .dot) == nil && scalar("1.234,50", .comma) == nil && scalar("1 234,5", .comma) == nil, "mixed or embedded grouping punctuation is never stripped from lab numbers")
        check(scalar("1.2.3") == nil && scalar("1,2,3", .comma) == nil, "repeated decimal marks do not become a plausible number")
        for text in ["<5.0", ">5,0", "≤5", "≥5", "1–5", "1-5", "Not detected", "null", "false", "5 mg/L", "NaN", "Infinity", "５.０", "5."] {
            check(scalar(text) == nil && scalar(text, .comma) == nil, "qualified or nonnumeric lab result stays literal: " + text)
        }
        check(scalar(String(repeating: "1", count: 39)) == nil, "numbers exceeding exact Decimal precision are withheld instead of rounded")
        check(scalar("1e-999") == nil && scalar("1e999") == nil && scalar("1e999999999999999999999") == nil, "decimal overflow and underflow never become a finite invented value or zero")
        let small = scalar("0.000000000000000000000000000000000000001")
        check(small != nil && small!.decimal != 0, "small representable lab numbers stay nonzero")
        let plot = LabHistory.plot(selection.groups[0], style: .dot, personChecked: true)
        check(plot.points.count == 2 && plot.numericDatedCount == 2 && plot.omitted.count == 2, "numeric history omits qualified and undated points with explicit reasons while retaining them in literal history")
        check(plot.omitted.contains { $0.pointID == selection.points.last?.id && $0.message.contains("No date was inferred") }, "the unplotted undated result has a specific no-inferred-date explanation")
        check(LabHistory.plot(selection.groups[0], style: .dot, personChecked: false).points.isEmpty && LabHistory.plot(selection.groups[0], style: nil, personChecked: true).points.isEmpty, "numeric plots require both person confirmation and an explicit decimal policy")
        let dateWindow = LabHistory.plot(selection.groups[0], style: .dot, personChecked: true, days: "2026-06-01"..."2026-12-31")
        check(dateWindow.points.map(\.point.record.id) == [later.id] && dateWindow.omitted.count == 1, "an explicit collection-day window filters dated points and keeps the undated omission visible")
        for (field, value) in [("unit", "mg/L"), ("laboratory", "Other laboratory"), ("specimen", "Plasma"), ("method", "Other assay"), ("status", "Preliminary"), ("test", "ferritin")] {
            var observation = b.observation
            switch field { case "unit": observation.unit = value; case "laboratory": observation.laboratory = value; case "specimen": observation.specimen = value; case "method": observation.method = value; case "status": observation.reportedStatus = value; default: observation.test = value }
            let changed = LabHistory.Point(record: b.record, observation: observation)
            check(changed.groupID != a.groupID && LabHistory.compare(a, changed, style: .dot, personChecked: true).difference == nil, "different recorded lab \(field) stays in a separate group and withholds arithmetic")
        }
        var decomposed = b.observation; decomposed.test = "Cafe\u{301}"
        var composed = a.observation; composed.test = "Café"
        check(LabHistory.Point(record: a.record, observation: composed).groupID != LabHistory.Point(record: b.record, observation: decomposed).groupID, "lab grouping preserves exact Unicode spelling instead of silently normalizing labels")
        let unicode = try record("history-unicode", result: "12.0", day: "2026-01-20", test: "Café")
        var alteredExcerpt = unicode
        alteredExcerpt.labReport?.observations[0].source.excerpt = unicode.labReport!.observations[0].source.excerpt.replacingOccurrences(of: "Café", with: "Cafe\u{301}")
        check(unicode.labReport?.isCurrent(body: unicode.body) == true && alteredExcerpt.labReport?.isCurrent(body: alteredExcerpt.body) == false, "lab source matching requires exact UTF-8 spelling even when two excerpts are canonically equivalent Unicode")
        rejects("a canonically equivalent but nonliteral source excerpt cannot enter reviewed lab history") { _ = try LabHistory.prepare(recordIDs: [alteredExcerpt.id], documents: [alteredExcerpt], now: now) }
        var missingUnit = a.observation; missingUnit.unit = ""
        var missingLab = b.observation; missingLab.laboratory = ""
        check(LabHistory.compare(LabHistory.Point(record: a.record, observation: missingUnit), b, style: .dot, personChecked: true).difference == nil && LabHistory.compare(a, LabHistory.Point(record: b.record, observation: missingLab), style: .dot, personChecked: true).difference == nil, "missing unit or laboratory cannot establish a numeric lab comparison")
        var sameDay = b.observation; sameDay.collectedOn = a.collectionDay
        check(LabHistory.compare(a, LabHistory.Point(record: b.record, observation: sameDay), style: .dot, personChecked: true).difference == nil, "same-day results retain unknown within-day order instead of inventing a later measurement")
        var invalidDay = b.observation; invalidDay.collectedOn = "2026-02-30"
        check(LabHistory.Point(record: b.record, observation: invalidDay).collectionDay == nil, "invalid externally assembled collection days cannot become history dates")
        let utc = TimeZone(secondsFromGMT: 0)!
        check(PlanDay.string(plot.points.first!.day, timeZone: utc) == plot.points.first!.point.collectionDay, "plot days use the actual recorded calendar day independently of local time-zone offsets")
        var many: [LabHistory.Point] = []
        for i in 0...LabHistory.maxPlotPoints { var observation = a.observation; observation.id = "many-\(i)"; many.append(.init(record: a.record, observation: observation)) }
        let tooMany = LabHistory.plot(.init(id: a.groupID, points: many), style: .dot, personChecked: true)
        check(tooMany.points.isEmpty && tooMany.numericDatedCount == 257 && tooMany.blockers.contains(.tooMany(257)), "a plot exceeding its window bound withholds the entire plot instead of silently prefixing or downsampling results")
        let fullRecords = (0..<LabHistory.maxRecords).map { index -> HealthDocument in
            var document = earlier; document.id = "full-history-\(index)"
            document.labReport?.observations = (0..<LabReport.maxObservations).map { row in var value = a.observation; value.id = "full-history-\(index)-\(row)"; return value }
            return document
        }
        let fullHistory = try LabHistory.prepare(recordIDs: fullRecords.map(\.id), documents: fullRecords, now: now)
        let fullPlot = LabHistory.plot(fullHistory.groups[0], style: .dot, personChecked: true)
        check(fullHistory.points.count == 2560 && fullHistory.groups.count == 1 && fullPlot.points.isEmpty && fullPlot.numericDatedCount == 2560 && fullPlot.blockers.contains(.tooMany(2560)), "the complete ten-record history retains all 2560 reviewed results and refuses an oversized plot without truncating its history")
        rejects("lab history requires a nonempty bounded record selection") { _ = try LabHistory.prepare(recordIDs: [], documents: [earlier]) }
        rejects("duplicate source record selections are rejected") { _ = try LabHistory.prepare(recordIDs: [earlier.id, earlier.id], documents: [earlier]) }
        rejects("deleted source records cannot be silently omitted from history") { _ = try LabHistory.prepare(recordIDs: [earlier.id, later.id], documents: [earlier]) }
        var stale = earlier; stale.body += "\nA changed source"
        rejects("changed-source lab transcriptions are withheld from history") { _ = try LabHistory.prepare(recordIDs: [stale.id], documents: [stale]) }
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("cancelled lab history preparation returns no partial selection") { _ = try LabHistory.prepare(recordIDs: [earlier.id], documents: [earlier], control: cancelled) }
        rejects("lab comparison snapshots require fresh intended-person confirmation") { _ = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: false, acknowledged: true, currentDocuments: [earlier, later, undated, qualified]) }
        rejects("lab comparison snapshots require explicit review") { _ = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: true, acknowledged: false, currentDocuments: [earlier, later, undated, qualified]) }
        rejects("a changed source blocks saving an older comparison draft") { _ = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [stale, later, undated, qualified]) }
        var renamed = earlier; renamed.title += " corrected"
        rejects("source metadata changes require a refreshed comparison") { _ = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [renamed, later, undated, qualified]) }
        var shared = earlier; shared.includeInAssistant = true
        let snapshot = try LabHistory.snapshot(selection, firstID: b.id, secondID: a.id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [shared, later, undated, qualified], now: now)
        check(snapshot.kind == .review && !snapshot.includeInAssistant && snapshot.labReport == nil && snapshot.body.contains("Later minus earlier: 6.5"), "checked comparison saves a separate sharing-off snapshot without manufacturing lab measurements")
        check(snapshot.body.contains("12.00") && snapshot.body.contains("18.50") && snapshot.body.contains(a.observation.source.excerpt) && snapshot.body.contains(b.record.fingerprint), "saved comparison retains both complete literal values, original source excerpt and content identity")
        check(snapshot.body.contains("Later edits or deletion") && shared.includeInAssistant, "a comparison states independent-copy semantics and preserves a newer source sharing choice")
        check(snapshot.labComparison?.isValid(in: snapshot) == true && snapshot.labComparison?.isCurrent(body: snapshot.body) == true, "comparison snapshots retain valid typed source/value metadata beside their portable saved text")
        check(snapshot.labComparison?.sources.map(\.observation.result) == ["12.00", "18.50"], "typed comparison metadata retains literal reported precision in chronological order")
        let capturedSource = snapshot.labComparison!.sources[0]
        var uppercase = snapshot
        var uppercaseMetadata = snapshot.labComparison!
        uppercaseMetadata.bodySHA256 = uppercaseMetadata.bodySHA256.uppercased()
        uppercaseMetadata.sources[0].fingerprint = uppercaseMetadata.sources[0].fingerprint.uppercased()
        uppercase.labComparison = uppercaseMetadata
        check(uppercase.labComparison?.isCurrent(body: uppercase.body) == true && uppercase.labComparison?.sources[0].state(in: [earlier, later]) == .matching, "valid uppercase hexadecimal comparison identities match their captured content")
        var selfReferencing = snapshot; selfReferencing.id = capturedSource.documentID
        check(selfReferencing.labComparison?.isValid(in: selfReferencing) == false, "a comparison cannot replace one of its captured source records under the same identity")
        check(capturedSource.state(in: [earlier, later]) == .matching && capturedSource.state(in: [later]) == .removed, "a saved comparison distinguishes matching source content from a removed source record")
        check(capturedSource.state(in: [renamed, later]) == .changed && capturedSource.state(in: [stale, later]) == .needsReview, "saved comparison source states distinguish changed metadata and stale source review")
        var editedSnapshot = snapshot; editedSnapshot.body = "My separately edited discussion notes."
        check(editedSnapshot.labComparison?.isValid(in: editedSnapshot) == true && editedSnapshot.labComparison?.isCurrent(body: editedSnapshot.body) == false, "editing saved comparison text retains historical metadata without treating it as the current structured comparison")
        check(RecordRetrieval.text(editedSnapshot)?.contains("Earlier lab comparison metadata is withheld") == true && !RecordRetrieval.text(editedSnapshot)!.contains("Later minus earlier: 6.5"), "edited comparison text withholds earlier structured arithmetic from fresh assistant reference text")
        check(editedSnapshot.markdown.contains("Earlier captured lab comparison") && editedSnapshot.markdown.contains("12.00") && editedSnapshot.markdown.contains(a.observation.source.excerpt), "Markdown sharing of an edited comparison retains its separately labelled earlier captured values and source")
        var forgedDifference = snapshot; forgedDifference.labComparison?.numberDifference = "500"
        check(forgedDifference.labComparison?.isValid == false && RecordRetrieval.text(forgedDifference) == nil, "contradictory stored comparison arithmetic is invalid and unavailable to assistant retrieval")
        var forgedSource = snapshot; forgedSource.labComparison?.sources[0].fingerprint = "not-a-source-hash"
        check(forgedSource.labComparison?.isValid == false, "comparison metadata validates its retained source identities")
        var future = snapshot; future.labComparison?.version = 999
        check(future.labComparison?.isValid == false, "unsupported comparison metadata versions are not interpreted as current results")
        let q = selection.points.first { $0.record.id == qualified.id }!
        let literal = try LabHistory.snapshot(selection, firstID: a.id, secondID: q.id, style: .comma, personChecked: true, acknowledged: true, currentDocuments: [earlier, later, undated, qualified], now: now)
        check(literal.body.contains("No numeric difference was calculated") && literal.body.contains("<5,0"), "a reviewed qualitative or qualified comparison remains a literal snapshot with no invented arithmetic")
        let wordingSnapshot = try LabHistory.snapshot(selection, firstID: a.id, secondID: b.id, style: .literal, personChecked: true, acknowledged: true, currentDocuments: [earlier, later, undated, qualified], now: now)
        check(wordingSnapshot.labComparison?.isValid(in: wordingSnapshot) == true && wordingSnapshot.labComparison?.numberDifference == nil && wordingSnapshot.body.contains("Wording only"), "a deliberate wording-only comparison saves valid separate metadata without manufacturing a numeric difference")
        let table = try LabTable.parse(Data("test,result,unit,date,laboratory\nFerritin,12.0,µg/L,2026-01-20,Synthetic laboratory".utf8), filename: "Synthetic history.csv", now: now)
        let imported = try LabFileDraft(table: table, mapping: table.suggestedMapping, subject: "", personChecked: true).document(acknowledged: true, now: now)
        var copy = imported; copy.id = "duplicate-history-copy"
        let duplicated = try LabHistory.prepare(recordIDs: [imported.id, copy.id], documents: [imported, copy], now: now)
        check(LabHistory.plot(duplicated.groups[0], style: .dot, personChecked: true).blockers.contains(.duplicates), "identical input hash, row and mapping cannot become independent plotted measurements through duplicate record copies")
        rejects("a duplicate imported source row cannot be saved as an independent lab comparison") { _ = try LabHistory.snapshot(duplicated, firstID: duplicated.points[0].id, secondID: duplicated.points[1].id, style: .dot, personChecked: true, acknowledged: true, currentDocuments: [imported, copy], now: now) }
        let archive = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [snapshot, literal], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        let legacy = try BackupArchive.read(BackupArchive.make(archive)).1
        check(legacy.documents.map(\.body) == archive.documents.map(\.body) && legacy.documents.map(\.labComparison) == archive.documents.map(\.labComparison), "comparison text and compatible optional source/value metadata survive actual version-one backup round trips")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumenBatch22HistoryChecks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false); defer { try? FileManager.default.removeItem(at: folder) }
        let encrypted = folder.appendingPathComponent("Synthetic.lumenbackup"); try BackupPackage.write(archive, photos: [:], password: "Synthetic history passphrase", to: encrypted)
        let restored = try BackupPackage.read(encrypted, password: "Synthetic history passphrase", temporaryRoot: folder); defer { restored.removeTemporaryFiles() }
        check(restored.snapshot.documents.map(\.body) == archive.documents.map(\.body) && restored.snapshot.documents.map(\.labComparison) == archive.documents.map(\.labComparison), "actual encrypted backups preserve complete typed comparison sources, literal values and explicit interpretation")
        let readable = folder.appendingPathComponent("Synthetic.json"); try ReadableExport.write(archive, to: readable)
        let recovered = try ReadableExport.read(Data(contentsOf: readable))
        check(recovered.snapshot.documents.map(\.body) == archive.documents.map(\.body) && recovered.snapshot.documents.map(\.labComparison) == archive.documents.map(\.labComparison), "actual readable export/recovery retains the independent comparison text and typed source snapshot")
        var corruptArchive = archive; corruptArchive.documents[0] = forgedDifference
        rejects("backup restoration refuses contradictory typed comparison arithmetic") { try BackupArchive.validate(corruptArchive) }
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        var legacyJSON = json; legacyJSON.removeValue(forKey: "labComparison")
        let withoutMetadata = try JSONDecoder().decode(HealthDocument.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        check(withoutMetadata.labComparison == nil && withoutMetadata.body == snapshot.body, "older generic review documents decode without an invented structured comparison")
    }
}
