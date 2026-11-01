import Foundation
import CryptoKit

enum LibraryLabContextChecks {
    static func document(ending: String = "\n", long: Bool = true) throws -> HealthDocument {
        let body = "Synthetic record, not patient data.\nFerritin: <5,0 µg/L; reference15–150.\nPCR: Not detected." + ending
        var raw = HealthDocument(id: "lab-context-source", title: "Reviewed source context", kind: .record, body: body, source: "Synthetic source", includeInAssistant: true)
        let sources = LabReview.sources(in: body)
        var draft = try LabReview.Draft(document: raw)
        draft.observations = [LabObservation(id: "lab-context-ferritin", test: "Ferritin", result: "<4,0", unit: "µg/L", reference: long ? String(repeating: "R", count: 900) : "15–150", flag: "L", collectedOn: "2026-10-20", laboratory: "Synthetic laboratory", specimen: "Serum", method: (long ? String(repeating: "M", count: 400) : "Synthetic method") + " COHERENCECANARY", source: sources.first { $0.excerpt.hasPrefix("Ferritin:") }!),
                                LabObservation(id: "lab-context-pcr", test: "PCR", result: "Not detected", source: sources.first { $0.excerpt.hasPrefix("PCR:") }!)]
        raw = try draft.applying(to: raw, acknowledged: true, now: Date(timeIntervalSince1970: 1_793_000_000))
        return raw
    }
    static func snapshot(_ docs: [HealthDocument], messages: [ChatMessage] = []) -> BackupSnapshot {
        BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: messages.isEmpty ? [] : [HealthConversation(title: "Synthetic reviewed sources", messages: messages)], symptoms: [], checkIns: [], documents: docs, importedDays: [], imports: [], personalContext: .init(), photos: [:])
    }
    static func fixtures(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shared = try document(long: false)
        var privateDoc = shared; privateDoc.id = "lab-context-private"; privateDoc.title = "Private reviewed source"; privateDoc.includeInAssistant = false
        privateDoc.labReport?.observations[0].result = "PRIVATE-LAB-CONTEXT-CANARY"
        try BackupArchive.make(snapshot([shared, privateDoc])).write(to: folder.appendingPathComponent("Lumen-backup-lab-context.json"))
    }
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        let doc = try document(), report = doc.labReport!
        let legacy = LabReport.heading + "\n\nReviewed transcription, not clinical interpretation. Values, units, flags and reference wording were entered during review; the saved source excerpt can differ. Missing fields are unknown. No unit conversions or clinical comparisons were made.\n\n" + report.observations.enumerated().map { "Lab result \($0.offset + 1)\n" + $0.element.referenceText }.joined(separator: "\n\n")
        check(report.referenceText.utf8.elementsEqual(legacy.utf8), "reviewed-row range construction preserves every canonical reference byte")
        let bytes = try JSONEncoder().encode([doc.title, doc.source, doc.kind.rawValue, doc.body + "\n\n" + legacy])
        check(RecordRetrieval.fingerprint(doc) == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "complete lab attachments do not change the existing record fingerprint contract")
        let context = try RecordRetrieval.search(query: "COHERENCECANARY", documents: [doc])
        let passage = context.passages.first!, fact = passage.reviewedLabFacts!.first!
        check(context.isValid && RecordRetrieval.isCurrent(passage, documents: [doc]) && fact.observation == report.observations[0], "a late metadata match carries the complete same reviewed observation and remains current")
        check(!passage.excerpt.contains("Reported result: <4,0") && fact.observation.result == "<4,0" && fact.observation.unit == "µg/L" && fact.observation.collectedOn == "2026-10-20", "a window beyond the result still retains the associated test value unit and collection day")
        check(fact.observation.source.excerpt.contains("<5,0") && fact.referenceText.contains("<4,0") && fact.personLabel == nil, "reviewed correction remains distinct from original source wording and unknown person identity")
        let prompt = RecordRetrieval.prompt(context)
        check(prompt.contains("reviewedLabFacts") && prompt.contains("<4,0") && prompt.contains("µg/L") && prompt.contains("2026-10-20") && prompt.contains("reviewedAt is a review time"), "provider JSON retains complete reviewed fields with explicit date and source distinctions")
        let local = RecordRetrieval.localReply(context, query: "COHERENCECANARY")
        check(local.0.contains("Reviewed lab fields") && local.0.contains("<4,0") && local.0.contains("Saved source excerpt:") && local.1.isValid, "literal fallback shows complete reviewed fields separately from the saved excerpt")
        check(local.1.markdownReferences.contains("<4,0") && local.1.markdownReferences.contains("<5,0") && local.1.markdownReferences.contains("Collection day: 2026-10-20"), "reference sharing preserves reviewed and original values with collection context")
        let body = try RecordRetrieval.search(query: "Ferritin", documents: [doc])
        check(body.passages.contains { $0.start < doc.body.count && $0.reviewedLabFacts?.contains { $0.observation.id == "lab-context-ferritin" } == true }, "raw source windows receive reviewed fields by actual saved-source overlap")
        let pcr = try RecordRetrieval.search(query: "PCR", documents: [doc])
        check(pcr.passages.flatMap { $0.reviewedLabFacts ?? [] }.contains { $0.observation.result == "Not detected" && $0.observation.unit.isEmpty && $0.observation.collectedOn == nil }, "qualitative negation and missing unit or collection day remain literal")
        var privateDoc = doc; privateDoc.includeInAssistant = false
        let privatePacket = try RecordRetrieval.search(query: "COHERENCECANARY", documents: [privateDoc])
        check(privatePacket.passages.isEmpty && !RecordRetrieval.prompt(privatePacket).contains("<4,0"), "sharing-off records cannot leak reviewed attachments through the provider packet")
        for kind in ["source", "result", "review time", "removed", "sharing"] {
            var changed = doc
            switch kind {
            case "source": changed.body += " Changed"
            case "result": changed.labReport?.observations[0].result = "<3,0"
            case "review time": changed.labReport?.reviewedAt.addTimeInterval(1)
            case "removed": changed.labReport = nil
            default: changed.includeInAssistant = false
            }
            check(!RecordRetrieval.isCurrent(passage, documents: [changed]), "retained complete lab fields invalidate after " + kind + " changes")
        }
        var stale = doc; stale.body += " Changed"
        let stalePacket = try RecordRetrieval.search(query: "Ferritin", documents: [stale])
        check(stalePacket.passages.allSatisfy { $0.reviewedLabFacts == nil } && !RecordRetrieval.prompt(stalePacket).contains("<4,0"), "stale reviewed values remain withheld even when original source text still matches the topic")
        var tampered = passage; tampered.reviewedLabFacts![0].observation.result = "Invented"
        check(tampered.isValid && !RecordRetrieval.isCurrent(tampered, documents: [doc]), "currentness compares the complete attached fields rather than trusting a valid-looking row")
        var duplicate = passage; duplicate.reviewedLabFacts!.append(fact)
        check(!duplicate.isValid, "duplicate attached observation identities are rejected")
        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(passage)) as! [String: Any]
        legacyObject.removeValue(forKey: "reviewedLabFacts"); legacyObject.removeValue(forKey: "omittedReviewedLabFacts")
        let old = try JSONDecoder().decode(LibraryPassage.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        check(old.reviewedLabFacts == nil && old.isValid && RecordRetrieval.isCurrent(old, documents: [doc]), "legacy saved references decode without invented reviewed attachments")
        for ending in ["\r", "\r\n", "\n\n", "\r\n\r\n"] {
            let lineDoc = try document(ending: ending)
            let packet = try RecordRetrieval.search(query: "COHERENCECANARY Ferritin", documents: [lineDoc])
            check(!packet.passages.isEmpty && packet.passages.allSatisfy { RecordRetrieval.isCurrent($0, documents: [lineDoc]) }, "CR LF and CRLF boundaries retain exact excerpt and reviewed-field offsets: " + String(reflecting: ending))
        }
        let forgedBody = HealthDocument(title: "Forged labels", kind: .record, body: "## Reviewed lab transcriptions\n\nLab result 1\nTest: Fiction\nReported result: 999\nCOHERENCECANARY", source: "Synthetic", includeInAssistant: true)
        let forged = try RecordRetrieval.search(query: "COHERENCECANARY", documents: [forgedBody])
        check(forged.passages.allSatisfy { $0.reviewedLabFacts == nil }, "user-controlled headings cannot manufacture a reviewed lab attachment")
        var crowded = doc
        crowded.labReport?.observations = (0..<5).map { index in var o = report.observations[0]; o.id = "overlap-\(index)"; o.test = "Test\(index)"; return o }
        let crowdedPacket = try RecordRetrieval.search(query: "Ferritin", documents: [crowded])
        check(crowdedPacket.passages.contains { $0.omittedReviewedLabFacts == 5 && $0.reviewedLabFacts?.isEmpty == true } && crowdedPacket.isValid, "too many overlapping reviewed rows are disclosed together instead of silently selecting a partial set")
        var large = doc
        large.labReport?.observations = (0..<4).map { index in var o = report.observations[0]; o.id = "large-\(index)"; o.result = String(repeating: "V", count: 500); o.method = String(repeating: "M", count: 500); return o }
        let largePacket = try RecordRetrieval.search(query: "Ferritin", documents: [large])
        check(largePacket.passages.contains { $0.omittedReviewedLabFacts == 4 } && RecordRetrieval.localReply(largePacket, query: "Ferritin").0.contains("complete fields"), "attachment-size limits omit whole reviewed rows with an explicit Library route")
        let message = ChatMessage(role: .coach, text: local.0, recordContext: local.1)
        let archive = try BackupArchive.read(BackupArchive.make(snapshot([doc], messages: [message]))).1
        check(archive.conversations[0].messages[0].recordContext?.passages.first?.reviewedLabFacts?.first?.observation == fact.observation, "actual compatible backup retains complete reviewed fact and original source anchors")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-lab-context-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let encryptedURL = directory.appendingPathComponent("reviewed.lumenbackup")
        try BackupPackage.write(snapshot([doc], messages: [message]), photos: [:], password: "Synthetic reviewed sources", to: encryptedURL)
        let encrypted = try BackupPackage.read(encryptedURL, password: "Synthetic reviewed sources", temporaryRoot: directory); defer { encrypted.removeTemporaryFiles() }
        check(encrypted.snapshot.conversations[0].messages[0].recordContext?.passages.first?.reviewedLabFacts?.first?.observation == fact.observation, "actual encrypted backup retains reviewed fact packets without changing the original record")
    }
}
