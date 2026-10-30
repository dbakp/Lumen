import Foundation

/// Synthetic records exercise the production SQLite index, citation validator and history policy.
enum RecordRetrievalChecks {
    static func documents(now: Date = Date()) -> [HealthDocument] {
        var target = HealthDocument(id: "retrieval-target", createdAt: now.addingTimeInterval(-86400 * 30), updatedAt: now.addingTimeInterval(-86400 * 30), title: "Autumn appointment record", kind: .record,
                                    body: "## Page 1\n\n" + String(repeating: "Synthetic background text. ", count: 160) + "\n\n## Page 2\n\nSynthetic ferritin note: 12.5 mg/L. Sample code LAB-42. Review the original; no diagnosis is provided.", source: "Synthetic appointment.txt", includeInAssistant: true)
        target.extraction = RecordExtraction(filename: "Synthetic appointment.txt", sha256: String(repeating: "a", count: 64), readAt: now.addingTimeInterval(-86400 * 30), reviewedAt: now.addingTimeInterval(-86400 * 30), pages: [.init(number: 1, method: .plainText, edited: false, lowConfidenceLines: 0), .init(number: 2, method: .plainText, edited: false, lowConfidenceLines: 0)])
        let newer = (0..<7).map { HealthDocument(id: "retrieval-newer-\($0)", title: "Recent walking note \($0 + 1)", kind: .note, body: "Synthetic walking route near the park.", source: "Synthetic fixture", includeInAssistant: true) }
        let privateRecord = HealthDocument(id: "retrieval-private", title: "Private ferritin detail", kind: .record, body: "PRIVATE-CANARY-729 ferritin private text", source: "Synthetic private fixture")
        return newer + [target, privateRecord]
    }
    static func fixtures(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var profile = UserProfile.default; profile.name = "Synthetic Library profile"
        let snapshot = BackupSnapshot(profile: profile, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: documents(), importedDays: [], imports: [], personalContext: .init(), photos: [:])
        try BackupArchive.make(snapshot).write(to: folder.appendingPathComponent("Lumen-backup-retrieval.json"))
        // Restored historical layout fixture only. No model or provider is called.
        let packet = try RecordRetrieval.search(query: "ferritin walking", documents: snapshot.documents)
        let resolved = RecordRetrieval.resolving("Synthetic saved reply for layout checks. No provider request was sent. The saved excerpt is reference [\(packet.passages[0].id)]. Unrecognized reference: [record_unknown_9].", context: packet)
        var historical = snapshot
        historical.conversations = [HealthConversation(title: "Reference layout fixture", messages: [ChatMessage(role: .coach, text: "Synthetic earlier reply without source metadata."), ChatMessage(role: .user, text: "Synthetic source-layout question. No provider request was sent."), ChatMessage(role: .coach, text: resolved.0, provider: "Synthetic fixture · no live provider request", recordContext: resolved.1)])]
        try BackupArchive.make(historical).write(to: folder.appendingPathComponent("Lumen-backup-reference-layout.json"))
    }
    static func run(snapshot: BackupSnapshot) async throws {
        func check(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(), name); print("PASS: " + name) }
        let docs = documents()
        let query = "What does my record say about ferritin?"
        let found = try RecordRetrieval.search(query: query, documents: docs)
        check(found.isValid && found.searchedDocuments == 8 && found.sharedDocuments == 8, "real SQLite FTS searches all shared documents, beyond the five newest")
        let passage = found.passages.first!
        check(passage.documentID == "retrieval-target" && passage.start > 3000 && passage.page == 2 && passage.excerpt.contains("12.5 mg/L"), "retrieval finds page two beyond the old 3000-character prefix")
        check(!RecordRetrieval.prompt(found).contains("PRIVATE-CANARY") && !found.passages.contains { $0.documentID == "retrieval-private" }, "unshared record text stays out of selected passages and provider prompt")
        check(RecordRetrieval.prompt(found).contains("UNTRUSTED") && RecordRetrieval.prompt(found).contains(passage.id), "provider receives explicit untrusted JSON and request-specific source IDs")
        let again = try RecordRetrieval.search(query: query, documents: docs)
        check(again.passages.first!.id != passage.id, "reference IDs are never reused between questions")
        let resolved = RecordRetrieval.resolving("Literal 12.5 mg/L [\(passage.id)]", context: found)
        check(resolved.0 == "Literal 12.5 mg/L [1]" && resolved.1.passages[0].referenced, "only a current request ID becomes a linked human reference")
        let unknown = RecordRetrieval.resolving("Old [\(again.passages[0].id)] bare [1] unknown [record_fake_9]", context: found)
        check(unknown.1.invalidCitations == 3 && unknown.1.passages.allSatisfy { !$0.referenced } && !unknown.0.contains("[1]"), "stale fabricated and bare numeric citations cannot link to unrelated text")
        let linked = RecordRetrieval.resolving("Valid [\(passage.id)](https://untrusted.example/fake) bare [1](https://untrusted.example/other) upper [RECORD_UNKNOWN_9]", context: found)
        check(linked.0 == "Valid [1] bare [reference unavailable] upper [reference unavailable]" && linked.1.invalidCitations == 2, "Library citation markers cannot carry a model-supplied external link and case-varied fake IDs are rejected")
        let user = ChatMessage(role: .user, text: query)
        let reply = ChatMessage(role: .coach, text: resolved.0, recordContext: resolved.1)
        let follow = try RecordRetrieval.search(query: "Explain that", documents: docs, history: [user, reply])
        let replay = RecordRetrieval.history([user, reply], context: follow, documents: docs)
        check(replay.count == 2 && replay[1].text.contains(follow.passages[0].id) && !replay[1].text.contains(passage.id), "follow-up carries exact current sources with newly mapped IDs")
        let unrelated = try RecordRetrieval.search(query: "walking", documents: docs, history: [user, reply])
        check(!unrelated.passages.contains { $0.documentID == passage.documentID }, "a short new topic does not force prior unrelated sources into the request")
        check(RecordRetrieval.history([user, reply], context: unrelated, documents: docs).count == 1, "prior sourced replies are omitted when their exact sources are not in the new request")
        check(RecordRetrieval.isLibraryQuestion("Explain that", history: [user, reply]), "record follow-ups retain lookup intent even when permission later removes all matches")
        var withdrawn = docs; withdrawn[7].includeInAssistant = false
        check(!RecordRetrieval.isCurrent(passage, documents: withdrawn) && RecordRetrieval.history([user, reply], context: follow, documents: withdrawn).count == 1, "withdrawing sharing blocks reuse of old source-bearing replies")
        var edited = docs; edited[7].body += " Changed after reply."
        check(!RecordRetrieval.isCurrent(passage, documents: edited) && RecordRetrieval.history([reply], context: follow, documents: edited).isEmpty, "edited records invalidate past excerpts for future model history")
        check(!RecordRetrieval.isCurrent(passage, documents: Array(docs.prefix(7))), "deleted records cannot be replayed as current context")
        var malformed = passage; malformed.start = -1
        check(!RecordRetrieval.isCurrent(malformed, documents: docs), "damaged retained source offsets are rejected before slicing current text")
        var dateOnly = docs; dateOnly[7].updatedAt = Date()
        check(RecordRetrieval.isCurrent(passage, documents: dateOnly), "consent timestamps and storage precision alone do not invalidate unchanged source text")
        check(RecordRetrieval.history([ChatMessage(role: .coach, text: "Legacy unknown record text"), user], context: found, documents: docs).count == 1, "legacy replies without source maps remain local and are not silently replayed")
        let afterGuide = try RecordRetrieval.search(query: "Explain that", documents: docs, history: [user, reply, ChatMessage(role: .user, text: "xylophonium"), ChatMessage(role: .coach, text: "A guide", recordContext: .guide())])
        check(afterGuide.passages.isEmpty, "follow-ups do not jump over the latest guide reply to unrelated older references")
        var combining = docs[7]; combining.body = String(repeating: "a" + String(repeating: "\u{0301}", count: 1000), count: 600)
        let byteBound = try RecordRetrieval.search(query: "ferritin", documents: [combining])
        check(byteBound.limited && byteBound.passages.isEmpty, "UTF-8 byte limits bound pathological combining sequences independently of character counts")
        let guide = ChatMessage(role: .coach, text: "A general guide", recordContext: .guide())
        check(RecordRetrieval.history([guide], context: found, documents: docs).count == 1, "new unsourced guide replies retain conversation continuity")
        let (local, context) = RecordRetrieval.localReply(found, query: query)
        check(context.mode == .lookup && context.isValid && local.contains("12.5 mg/L") && context.passages.allSatisfy(\.referenced), "built-in lookup returns literal excerpts and retained reference metadata")
        let missing = try RecordRetrieval.search(query: "xylophonium", documents: docs)
        check(missing.passages.isEmpty && RecordRetrieval.localReply(missing, query: "xylophonium").0.contains("shared documents searched"), "no lexical match does not claim the information is absent")
        let empty = try RecordRetrieval.search(query: "What do my records say?", documents: docs)
        check(empty.passages.isEmpty && RecordRetrieval.localReply(empty, query: "What do my records say?").0.contains("Name a record"), "vague record questions request a topic instead of arbitrary recent text")
        var plan = HealthDocument(title: "Tuesday plan", kind: .plan, body: "Synthetic prose.", steps: [PlanStep(title: "Call physiotherapist")], source: "Synthetic", includeInAssistant: true)
        let planHash = RecordRetrieval.fingerprint(plan)
        plan.steps[0].isDone = true
        let planMatch = try RecordRetrieval.search(query: "physiotherapist", documents: [plan])
        check(planHash != RecordRetrieval.fingerprint(plan) && planMatch.passages[0].excerpt.contains("[done]"), "plan retrieval includes current checklist state and fingerprints its changes")
        let stateHash = RecordRetrieval.fingerprint(plan); plan.planState = .archived
        check(stateHash != RecordRetrieval.fingerprint(plan) && RecordRetrieval.text(plan)!.contains("Current plan status: archived"), "plan status changes are explicit in retrieved text and source fingerprints")
        let localMessage = ChatMessage(role: .coach, text: local, recordContext: context)
        let localSaved = RecordRetrieval.savedDocument(from: localMessage, history: [user, localMessage])
        check(localSaved.title == query && !localSaved.body.hasPrefix("Matching saved text") && localSaved.recordContext?.isValid == true, "saved lookups use the question as title without repeating the generic heading")
        var unicode = HealthDocument(title: "Café", kind: .note, body: "🧑🏽‍⚕️ Synthetic café møde. Ferritin at 12.5 mg/L.", source: "Synthetic", includeInAssistant: true)
        let unicodeMatch = try RecordRetrieval.search(query: "cafe", documents: [unicode])
        check(!unicodeMatch.passages.isEmpty && RecordRetrieval.isCurrent(unicodeMatch.passages[0], documents: [unicode]), "FTS folds diacritics while excerpt offsets preserve extended graphemes")
        unicode.body = String(repeating: "x", count: 200001)
        let oversized = try RecordRetrieval.search(query: "cafe", documents: [unicode])
        check(oversized.limited && oversized.passages.isEmpty && oversized.searchedDocuments == 0, "oversized records disclose incomplete coverage and do not silently truncate")
        let many = (0...RecordRetrieval.maxDocuments).map { HealthDocument(id: "bounded-\($0)", title: "Boundary", kind: .note, body: "Bounded synthetic data", source: "Synthetic", includeInAssistant: true) }
        let capped = try RecordRetrieval.search(query: "bounded", documents: many)
        check(capped.limited && capped.searchedDocuments == RecordRetrieval.maxDocuments && capped.passages.count <= 4, "document limit is enforced and coverage remains explicit")
        let longMatch = HealthDocument(id: "long-match", title: "Ferritin ferritin ferritin", kind: .note, body: Array(repeating: "Ferritin ferritin synthetic paragraph.", count: 200).joined(separator: "\n\n"), source: "Synthetic", includeInAssistant: true)
        let secondMatch = HealthDocument(id: "second-match", title: "Another result", kind: .note, body: "Ferritin. " + String(repeating: "Other synthetic context. ", count: 25), source: "Synthetic", includeInAssistant: true)
        let diverse = try RecordRetrieval.search(query: "ferritin", documents: [longMatch, secondMatch])
        check(Set(diverse.passages.map(\.documentID)).count == 2 && diverse.passages.filter { $0.documentID == "long-match" }.count == 2, "one long matching document cannot crowd other records out of the candidate set")
        let dense = (0..<2).map { HealthDocument(id: "dense-\($0)", title: "Dense fixture", kind: .note, body: Array(repeating: "Narrow", count: 20_000).joined(separator: "\n\n"), source: "Synthetic", includeInAssistant: true) }
        let passageCap = try RecordRetrieval.search(query: "narrow", documents: dense)
        check(passageCap.limited && passageCap.isValid && passageCap.passages.count == 4, "passage-count limits preserve usable references while disclosing partial coverage")
        let cancelled = Task { try Task.checkCancellation(); return try RecordRetrieval.search(query: query, documents: docs) }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("cancelled search returned") } catch is CancellationError { print("PASS: cancelled retrieval discards its result") }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let roundTrip = try decoder.decode(ChatMessage.self, from: encoder.encode(reply))
        check(roundTrip.recordContext?.isValid == true && roundTrip.recordContext?.passages[0].excerpt == passage.excerpt, "reply sources persist with exact excerpts and compatible date encoding")
        let preparedQuote = RecordRetrieval.quotedQuestion(from: reply)
        check(preparedQuote.contains(reply.text) && preparedQuote.hasSuffix("My question: ") && !preparedQuote.hasSuffix("\n"), "prepared legacy quotes stay editable and cannot trigger the composer's newline-to-send behavior")
        let legacy = try JSONDecoder().decode(ChatMessage.self, from: Data("{\"id\":\"old\",\"role\":\"coach\",\"text\":\"Old\",\"date\":0}".utf8))
        check(legacy.recordContext == nil, "older saved conversations decode without reference metadata")
        var sample = snapshot
        var conversation = HealthConversation(title: "Synthetic retrieval", messages: [user, reply]); conversation.id = "retrieval-conversation"
        sample.conversations = [conversation]
        let saved = HealthDocument(title: "Saved reply", kind: .note, body: resolved.0, source: "Synthetic", recordContext: resolved.1)
        sample.documents = [saved]
        let archive = try BackupArchive.read(BackupArchive.make(sample)).1
        check(archive.conversations[0].messages[1].recordContext?.passages[0].excerpt == passage.excerpt && archive.documents[0].recordContext?.isValid == true, "backup and restore preserve reply and saved document sources")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-retrieval-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var streamed = sample; streamed.photos = [:]; streamed.meals = []
        let encryptedFile = temporary.appendingPathComponent("references.lumenbackup")
        try BackupPackage.write(streamed, photos: [:], password: "Synthetic reference passphrase", to: encryptedFile)
        let encrypted = try BackupPackage.read(encryptedFile, password: "Synthetic reference passphrase", temporaryRoot: temporary)
        defer { encrypted.removeTemporaryFiles() }
        check(encrypted.snapshot.conversations[0].messages[1].recordContext?.passages[0].excerpt == passage.excerpt && encrypted.snapshot.documents[0].recordContext?.isValid == true, "actual encrypted streamed backups preserve reply and saved document references")
        check(saved.markdown.contains(passage.excerpt) && !HealthDocument(title: "Unused", kind: .note, body: "No source", source: "Synthetic", recordContext: found).markdown.contains(passage.excerpt), "readable exports include referenced excerpts but omit uncited provider context")
        sample.documents[0].recordContext!.passages[0].id = "record_forged_1"
        do { _ = try BackupArchive.make(sample); preconditionFailure("invalid references accepted") } catch { print("PASS: backup validation rejects malformed source maps") }
    }
}
