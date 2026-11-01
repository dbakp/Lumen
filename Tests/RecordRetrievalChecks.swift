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
        try await identifierChecks()
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
        let literalCap = try RecordRetrieval.search(query: "sample ID MISSING42", documents: dense)
        check(literalCap.limited && literalCap.isValid && literalCap.passages.isEmpty, "literal filtering still counts nonmatching prepared passages toward the original index limit")
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
    static func identifierDocuments() -> [HealthDocument] {
        [
            HealthDocument(id: "sample-one", title: "Recorded test wording", kind: .record, body: "Sample TEST-AX1. The exact wording is: not detected.", source: "Synthetic", includeInAssistant: true),
            HealthDocument(id: "sample-two", title: "Recorded test wording", kind: .record, body: "Sample TEST-AX2. The exact wording is: detected.", source: "Synthetic", includeInAssistant: true),
            HealthDocument(id: "invoice-one", title: "Invoice", kind: .record, body: "Invoice AF-740 totals 62.40 EUR. Payment status: paid.", source: "Synthetic", includeInAssistant: true),
            HealthDocument(id: "invoice-two", title: "Invoice", kind: .record, body: "Invoice AF-741 totals 91.20 EUR. Payment status: unpaid.", source: "Synthetic", includeInAssistant: true)
        ]
    }
    static func identifierChecks() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        let docs = identifierDocuments()
        let longID = String(repeating: "X", count: 95) + "1"
        let longRecord = HealthDocument(title: "Long literal reference", kind: .record, body: "Sample " + longID + ". Exact wording: not detected.", source: "Synthetic", includeInAssistant: true)
        let longMatch = try RecordRetrieval.search(query: "Find \"" + longID + "\"", documents: [longRecord])
        check(longMatch.passages.count == 1 && longMatch.passages[0].excerpt.contains(longID), "a complete quoted identifier at the 96-character boundary remains searchable even when ordinary keyword tokenization omits long words")
        for query in ["Find sample ID /TEST-AX1", "Find sample ID \"TEST AX1\"", "Find invoice /AF-740", "Find invoice \"AF 740\"", "Find sample ID (TEST-AX1)", "Find sample ID TEST-AX1:2"] {
            do { _ = try RecordRetrieval.search(query: query, documents: docs); preconditionFailure("unsupported explicit field fell back to broad topic search") }
            catch let error as RecordRetrieval.SearchError { check(error == .identifierFormat, "complete explicit fields reject unsupported leading/spaced/composite syntax: " + query) }
        }
        for query in ["What is the wording for sample TEST-AX3?", "Find invoice AF-742 and its payment status.", "Find sample ID TEST-AX3", "Find sample identifier TEST-AX3", "Find report number AF-742", "Find \"TEST-AX3\"", "Find “AF-742”"] {
            let context = try RecordRetrieval.search(query: query, documents: docs)
            check(context.isValid && context.passages.isEmpty && context.searchedDocuments == docs.count, "missing complete identifier returns no neighboring source: " + query)
        }
        for (query, expected) in [("What is the wording for sample TEST-AX1?", "sample-one"), ("Find invoice af-740", "invoice-one"), ("Find sample code TEST-AX2", "sample-two"), ("Look for \"AF-741\"", "invoice-two")] {
            let context = try RecordRetrieval.search(query: query, documents: docs)
            check(!context.passages.isEmpty && context.passages.allSatisfy { $0.documentID == expected && RecordRetrieval.isCurrent($0, documents: docs) }, "literal lookup preserves exact current source: " + query)
        }
        for query in ["What do my records say about vitamin B12?", "Which HbA1c report is saved?", "What does my report say about COVID-19?", "Find my ICD-10 notes", "What is the sample ID for my ferritin report?", "Find invoices 2026"] {
            let ids = try RecordRetrieval.literalIdentifiers(query)
            check(ids.isEmpty, "ordinary medical topic or unknown-ID question keeps topic matching: " + query)
        }
        for token in ["AF-7400", "XAF-740", "AF-740.1", "AF-740/2", "AF_740", "AF‑740", "AF-0740", "AF-740-", "AF-740_", "AF-740+1", "AF-740@lab", "AF-740#2", "AF-740%2", "AF-740=2", "AF-740|2", "AF-740&2", "AF-740:2", "urn:AF-740"] {
            let other = HealthDocument(title: "Invoice", kind: .record, body: "Invoice \(token).", source: "Synthetic", includeInAssistant: true)
            let context = try RecordRetrieval.search(query: "Find invoice AF-740", documents: [other])
            check(context.passages.isEmpty, "identifier boundaries preserve zeros/version/punctuation: " + token)
        }
        let zero = HealthDocument(id: "zero", title: "Sample", kind: .record, body: "Sample number 00042.", source: "Synthetic", includeInAssistant: true)
        let foundZero = try RecordRetrieval.search(query: "sample number 00042", documents: [zero])
        let wrongZero = try RecordRetrieval.search(query: "sample number 42", documents: [zero])
        check(foundZero.passages.count == 1 && wrongZero.passages.isEmpty, "numeric-only explicit identifiers preserve leading zeros and sentence punctuation")
        let mixed = HealthDocument(id: "mixed", title: "Two samples", kind: .record, body: "Sample TEST-AX1: not detected.\n\nSample TEST-AX2: detected.", source: "Synthetic", includeInAssistant: true)
        let one = try RecordRetrieval.search(query: "sample TEST-AX1", documents: [mixed])
        check(one.passages.count == 1 && one.passages[0].excerpt.contains("not detected") && !one.passages[0].excerpt.contains("TEST-AX2"), "a matching ID elsewhere in the same record cannot authorize the neighboring sample's paragraph")
        let title = HealthDocument(id: "title", title: "Report FE-Q7", kind: .record, body: "Literal ferritin: 18 ng/mL.", source: "Synthetic", includeInAssistant: true)
        let titleMatch = try RecordRetrieval.search(query: "report ID FE-Q7", documents: [title])
        check(titleMatch.passages.count == 1 && titleMatch.passages[0].title == title.title, "an exact identifier in the retained title can identify its record")
        let both = try RecordRetrieval.search(query: "Compare invoice AF-740 and AF-741", documents: docs)
        check(Set(both.passages.map(\.documentID)) == ["invoice-one", "invoice-two"], "combined identifier lookup reserves sources for both requested invoices")
        for query in ["Compare invoices AF-740 and AF-741", "Compare sample IDs TEST-AX1 and TEST-AX2", "Compare samples TEST-AX1 and TEST-AX2", "Compare sample identifiers TEST-AX1 and TEST-AX2"] {
            let context = try RecordRetrieval.search(query: query, documents: docs)
            let expected: Set<String> = query.contains("AF-") ? ["invoice-one", "invoice-two"] : ["sample-one", "sample-two"]
            check(Set(context.passages.map(\.documentID)) == expected, "plural labels preserve complete combined identifier scope: " + query)
        }
        let missingOne = try RecordRetrieval.search(query: "Compare invoice AF-740 and AF-742", documents: docs)
        check(missingOne.passages.isEmpty, "combined literal request cannot silently stand in for a missing ID with its existing neighbor")
        let fourDocs = (0..<4).map { index in HealthDocument(id: "four-\(index)", title: index == 0 ? "Invoice AF-740" : "Invoice", kind: .record, body: index == 0 ? Array(repeating: "Payment status: paid.", count: 30).joined(separator: "\n\n") : "Invoice AF-\(740 + index). Payment status: paid.", source: "Synthetic", includeInAssistant: true) }
        let four = try RecordRetrieval.search(query: "invoice AF-740, AF-741, AF-742 and AF-743", documents: fourDocs)
        check(four.passages.count == 4 && Set(four.passages.map(\.documentID)) == Set(fourDocs.map(\.id)), "four explicit identifiers get four source slots before one titled invoice can consume two")
        let fiveDocs = (0..<5).map { HealthDocument(id: "five-\($0)", title: "Sample", kind: .record, body: "Sample ID X\($0).", source: "Synthetic", includeInAssistant: true) }
        do { _ = try RecordRetrieval.search(query: (0..<5).map { "sample ID X\($0)" }.joined(separator: " and "), documents: fiveDocs); preconditionFailure("partial five-ID packet accepted") }
        catch RecordRetrieval.SearchError.identifierCoverage { print("PASS: literal requests that cannot fit the four-passage packet ask for fewer identifiers instead of silently omitting a requested ID") }
        let sample = try RecordRetrieval.search(query: "sample TEST-AX1", documents: docs)
        let history = [ChatMessage(role: .user, text: "sample TEST-AX1"), ChatMessage(role: .coach, text: "Literal", recordContext: sample)]
        let changed = try RecordRetrieval.search(query: "What about sample TEST-AX2?", documents: docs, history: history)
        let absent = try RecordRetrieval.search(query: "What about sample TEST-AX3?", documents: docs, history: history)
        check(changed.passages.allSatisfy { $0.documentID == "sample-two" } && !changed.passages.isEmpty && absent.passages.isEmpty, "a new explicit follow-up ID replaces prior carried sources")
        let bareChanged = try RecordRetrieval.search(query: "What about TEST-AX2?", documents: docs, history: history)
        let bareAbsent = try RecordRetrieval.search(query: "What about TEST-AX3?", documents: docs, history: history)
        check(bareChanged.passages.count == 1 && bareChanged.passages[0].documentID == "sample-two" && bareAbsent.passages.isEmpty, "a complete unlabelled ID in an identifier follow-up replaces the old constraint without abbreviation expansion")
        let bareHistory = history + [ChatMessage(role: .user, text: "  What about TEST-AX2?"), ChatMessage(role: .coach, text: "Literal", recordContext: bareChanged)]
        let afterBare = try RecordRetrieval.search(query: "  Explain that", documents: docs, history: bareHistory)
        check(afterBare.passages.count == 1 && afterBare.passages[0].documentID == "sample-two", "unqualified follow-up chains preserve an intervening bare-ID change including leading whitespace")
        let missingHistory = history + [ChatMessage(role: .user, text: "What about TEST-AX3?"), ChatMessage(role: .coach, text: "No match", recordContext: bareAbsent)]
        let afterMissing = try RecordRetrieval.search(query: "Tell me more", documents: docs, history: missingHistory)
        check(afterMissing.passages.isEmpty, "a follow-up after a missing bare identifier cannot revive the earlier neighboring sample")
        check(RecordRetrieval.isLibraryQuestion("Find invoice AF-742") && RecordRetrieval.isLibraryQuestion("Find sample ID TEST-AX3"), "absent explicit identifiers retain real built-in Library lookup routing without a debug reply override")
        check(RecordRetrieval.isLibraryQuestion("Explain that", history: missingHistory), "a follow-up after an absent identifier retains Library lookup intent even without prior selected passages")
        for (query, expected) in [("What about TEST-AX3-?", RecordRetrieval.SearchError.identifierFormat), ("What about " + String(repeating: "X", count: 97) + "1?", .identifierLength), ("What about " + (0..<17).map { "X\($0)" }.joined(separator: " "), .identifierCount)] {
            do { _ = try RecordRetrieval.search(query: query, documents: docs, history: history); preconditionFailure("malformed/oversized bare follow-up inherited an old ID") }
            catch let error as RecordRetrieval.SearchError { check(error == expected, "malformed/over-limit bare follow-up fails with its actual reason and cannot inherit an earlier source") }
        }
        let firstFollow = try RecordRetrieval.search(query: "Explain that", documents: docs, history: history)
        let chain = history + [ChatMessage(role: .user, text: "Explain that"), ChatMessage(role: .coach, text: "Literal", recordContext: firstFollow)]
        let secondFollow = try RecordRetrieval.search(query: "Tell me more", documents: docs, history: chain)
        check(secondFollow.passages.allSatisfy { $0.documentID == "sample-one" } && !secondFollow.passages.isEmpty, "consecutive unqualified follow-ups retain the original explicit identifier")
        let newTopic = try RecordRetrieval.search(query: "invoice AF-741", documents: docs, history: chain)
        check(newTopic.passages.count == 1 && newTopic.passages[0].documentID == "invoice-two", "a new non-follow-up question does not inherit an unrelated identifier")
        var privateDocs = docs; privateDocs[0].includeInAssistant = false
        let privateResult = try RecordRetrieval.search(query: "sample TEST-AX1", documents: privateDocs, history: history)
        check(privateResult.passages.isEmpty && RecordRetrieval.history(history, context: privateResult, documents: privateDocs).allSatisfy { $0.role != .coach }, "sharing withdrawal prevents literal lookup, carry and replay of an earlier exact-ID source")
        var edited = docs; edited[0].body = "Sample TEST-AX9: corrected identifier."
        let editResult = try RecordRetrieval.search(query: "sample TEST-AX1", documents: edited, history: history)
        check(editResult.passages.isEmpty && !RecordRetrieval.isCurrent(sample.passages[0], documents: edited), "source edits that remove an identifier cannot be filled from retained earlier wording")
        let late = try RecordRetrieval.search(query: String(repeating: "please ", count: 1200) + "sample ID TEST-AX1", documents: docs)
        check(late.passages.count == 1 && late.passages[0].documentID == "sample-one", "literal IDs after the ordinary keyword prefix are parsed completely and prioritized")
        for (query, expected) in [(String(repeating: "x", count: 32001), RecordRetrieval.SearchError.queryLength), ("sample ID " + String(repeating: "A", count: 97) + "1", .identifierLength), ((0..<17).map { "sample ID X\($0)" }.joined(separator: " and "), .identifierCount), ("invoice AF-740-", .identifierFormat), ("Find \"AF-740-\"", .identifierFormat), ("sample ID urn:uuid:AF740", .identifierFormat)] {
            do { _ = try RecordRetrieval.search(query: query, documents: docs); preconditionFailure("oversized literal query accepted") }
            catch let error as RecordRetrieval.SearchError { check(error == expected, "unsupported or over-limit literal request reports its actual cause without truncation") }
        }
        check(RecordRetrieval.SearchError.identifierCoverage.localizedDescription.contains("fewer at a time") && RecordRetrieval.SearchError.identifierFormat.localizedDescription.contains("format") && RecordRetrieval.SearchError.identifierLength.localizedDescription.contains("96") && RecordRetrieval.SearchError.identifierCount.localizedDescription.contains("16"), "literal lookup failures name the actual format/length/count/packet limit without claiming record absence")
        let quotedVersion = HealthDocument(title: "Invoice", kind: .record, body: "Invoice code \"AF-740.\".", source: "Synthetic", includeInAssistant: true)
        let quotedPrefix = try RecordRetrieval.search(query: "invoice AF-740", documents: [quotedVersion])
        check(quotedPrefix.passages.isEmpty, "a quoted punctuation-bearing source field cannot emit a shorter neighboring identifier token")
        let atBoundary = HealthDocument(id: "boundary", title: "Invoice", kind: .record, body: String(repeating: "x", count: 893) + " AF-740.1", source: "Synthetic", includeInAssistant: true)
        let partial = try RecordRetrieval.search(query: "invoice AF-740", documents: [atBoundary])
        let complete = try RecordRetrieval.search(query: "invoice AF-740.1", documents: [atBoundary])
        check(partial.passages.isEmpty && complete.passages.count == 1 && complete.passages[0].excerpt.contains("AF-740.1") && RecordRetrieval.isCurrent(complete.passages[0], documents: [atBoundary]), "a code clipped at the 900-character edge cannot become a shorter ID; overlap retains the complete original token")
        var combinedBoundary = atBoundary; combinedBoundary.body += "\n\nSample ID BX1."
        let falseCombined = try RecordRetrieval.search(query: "Compare invoice AF-740 and sample ID BX1", documents: [combinedBoundary])
        check(falseCombined.passages.isEmpty, "a valid second ID cannot make a clipped neighboring-code fragment count as complete combined coverage")
        let colon = try RecordRetrieval.search(query: "sample ID TEST-AX1: explain its wording", documents: docs)
        check(colon.passages.count == 1 && colon.passages[0].documentID == "sample-one", "a colon followed by explanation remains sentence punctuation without accepting URI prefixes")
        let named = HealthDocument(title: "Sample", kind: .record, body: "Sample ID \"NONE\". Exact supplied code.", source: "Synthetic", includeInAssistant: true)
        let namedMatch = try RecordRetrieval.search(query: "sample ID \"NONE\"", documents: [named])
        check(namedMatch.passages.count == 1, "an explicitly quoted labelled ID can use a word that would otherwise describe missing information")
        let cancelled = Task { try Task.checkCancellation(); return try RecordRetrieval.search(query: "sample TEST-AX1", documents: docs) }; cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("cancelled literal search returned") } catch is CancellationError { print("PASS: literal search retains cancellation") }
    }
    static func identifierModelChecks(encoder: MiniLMEncoder) async throws {
        let docs = identifierDocuments()
        let longID = String(repeating: "X", count: 95) + "1"
        let longRecord = HealthDocument(id: "long-reference", title: "Long literal reference", kind: .record, body: "Sample " + longID + ". Exact wording: not detected.", source: "Synthetic", includeInAssistant: true)
        let longMatch = try await HybridLibrarySearch.search(query: "Find \"" + longID + "\"", documents: docs + [longRecord], encoder: encoder, enabled: true)
        precondition(longMatch.isValid && longMatch.passages.count == 1 && longMatch.passages[0].documentID == longRecord.id && RecordRetrieval.isCurrent(longMatch.passages[0], documents: [longRecord]))
        precondition(longMatch.meaningSearch?.status == .used || (longMatch.meaningSearch?.status == .unsupportedLanguage && longMatch.meaningSearch?.comparedPassages == 0))
        print("PASS: quoted 96-character identifier remains searchable with the actual topic-policy audit: \(String(describing: longMatch.meaningSearch))")
        let englishQuery = "Please tell me what the record says about \"" + longID + "\"."
        precondition(RecordRetrieval.words(englishQuery).isEmpty)
        let comparedLong = try await HybridLibrarySearch.search(query: englishQuery, documents: docs + [longRecord], encoder: encoder, enabled: true)
        print("English long-ID audit: \(String(describing: comparedLong.meaningSearch))")
        precondition(comparedLong.isValid && comparedLong.passages.count == 1 && comparedLong.passages[0].documentID == longRecord.id && comparedLong.meaningSearch?.status == .used && comparedLong.meaningSearch?.comparedPassages == 1)
        print("PASS: actual CoreML comparison retains a complete quoted 96-character identifier when the English query has no ordinary keyword terms")
        for (query, expected) in [("sample TEST-AX3", Set<String>()), ("invoice AF-742", []), ("sample TEST-AX1", ["sample-one"]), ("Compare invoice AF-740 and AF-741", ["invoice-one", "invoice-two"])] {
            let context = try await HybridLibrarySearch.search(query: query, documents: docs, encoder: encoder, enabled: true)
            precondition(context.isValid && Set(context.passages.map(\.documentID)) == expected && context.passages.allSatisfy { RecordRetrieval.isCurrent($0, documents: docs) })
            print("PASS: actual CoreML topic ranking cannot bypass literal identifier scope: " + query)
        }
        let old = try RecordRetrieval.search(query: "sample TEST-AX1", documents: docs)
        let next = try await HybridLibrarySearch.search(query: "What about sample TEST-AX3?", documents: docs, history: [ChatMessage(role: .user, text: "sample TEST-AX1"), ChatMessage(role: .coach, text: "Literal", recordContext: old)], encoder: encoder, enabled: true)
        precondition(next.passages.isEmpty && next.meaningSearch?.comparedPassages == 0)
        print("PASS: actual topic search with prior cached/carried sources cannot supply a missing new identifier")
    }
}
