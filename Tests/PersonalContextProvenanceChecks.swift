import Foundation

enum PersonalContextProvenanceChecks {
    static func run() throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: " + name) }
        var notes = PersonalHealthContext()
        notes.focus = "SYNTHETIC-PERSONAL-CANARY-40 · café 🫀"
        let off = PersonalContextProvenance.included(notes)
        check(off == .withoutNotes, "saved-off notes create explicit no-note provenance without retaining a canary")
        notes.includeInAssistant = true
        let original = PersonalContextProvenance.included(notes)
        check(original.isValid && original.notesSHA256?.count == 64, "saved-on exact included note text has valid versioned provenance")
        let serialized = try JSONEncoder().encode(original)
        check(!String(decoding: serialized, as: UTF8.self).contains(notes.focus), "message provenance contains a digest rather than another plaintext note copy")
        check(PersonalContextProvenance.included(notes) == original, "identical committed included notes have stable provenance across requests")
        notes.focus += " changed"
        let changed = PersonalContextProvenance.included(notes)
        check(changed != original, "a changed included note changes its reply provenance")
        check(!original.allowsHistory(current: changed), "a reply made with earlier notes cannot enter a request using changed notes")
        check(!original.allowsHistory(current: off), "withdrawing note sharing excludes earlier note-derived assistant prose")
        check(original.allowsHistory(current: original), "a matching shared-note reply stays eligible subject to Library reference checks")
        check(off.allowsHistory(current: original) && off.allowsHistory(current: changed), "explicit no-note replies remain eligible when the saved note choice changes")
        var invalid = original; invalid.version = 2
        check(!invalid.isValid && !invalid.allowsHistory(current: original), "unknown provenance versions cannot positively authorize history reuse")
        invalid = original; invalid.notesSHA256 = "not-a-digest"
        check(!invalid.isValid && !invalid.allowsHistory(current: original), "malformed note provenance cannot authorize historical assistant text")
        invalid = original; invalid.notesSHA256 = String(repeating: "A", count: 64)
        check(!invalid.isValid, "noncanonical uppercase provenance fails closed")
        var bounded = PersonalHealthContext(); bounded.includeInAssistant = true
        bounded.notes = String(repeating: "é", count: 2000) + "before"
        let before = PersonalContextProvenance.included(bounded)
        bounded.notes = String(repeating: "é", count: 2000) + "after"
        check(before == PersonalContextProvenance.included(bounded), "only the exact existing bounded note text determines provenance, not excluded suffixes")
        var empty = PersonalHealthContext(); empty.includeInAssistant = true; empty.notes = " \n "
        check(PersonalContextProvenance.included(empty) == .withoutNotes, "enabled blank or whitespace-only notes do not invent shared private input")

        let user = ChatMessage(role: .user, text: "Literal user question café 🫀", date: Date(timeIntervalSince1970: 1_790_000_000))
        let old = ChatMessage(role: .coach, text: "Earlier synthetic note-derived prose", recordContext: .guide(), personalContext: original)
        let known = ChatMessage(role: .coach, text: "Reply made without personal notes", recordContext: .guide(), personalContext: .withoutNotes)
        let legacy = ChatMessage(role: .coach, text: "Legacy reply with Library map but unknown note provenance", recordContext: .guide())
        let all = [user, old, known, legacy]
        let withdrawn = PersonalContextProvenance.history(all, current: off)
        check(withdrawn.map(\.id) == [user.id, known.id], "withdrawn-note history keeps user questions and known no-note replies while excluding stale and unknown assistants")
        check(PersonalContextProvenance.history(all, current: original).map(\.id) == [user.id, old.id, known.id], "matching current-note history includes the right assistant without upgrading unknown legacy provenance")
        check(all.count == 4 && all[1].text == old.text && all[3].personalContext == nil, "history filtering never erases or rewrites visible saved conversations")
        let references = RecordRetrieval.history(withdrawn, context: .guide(), documents: [])
        check(references.map(\.id) == [user.id, known.id], "personal-note eligibility composes with the existing production Library history filter")
        var referenced = old
        referenced.personalContext = .withoutNotes; referenced.recordContext = nil
        check(RecordRetrieval.history(PersonalContextProvenance.history([referenced], current: off), context: .guide(), documents: []).isEmpty,
              "known personal-note provenance cannot bypass an unknown Library source map")
        check(RecordRetrieval.quotedQuestion(from: old).contains(old.text) && RecordRetrieval.quotedQuestion(from: old).hasSuffix("My question: "),
              "explicit quotation remains a literal editable unsent question rather than an automatic history exception")

        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("Lumen-personal-provenance-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let archive = HealthConversation(title: "Synthetic Unicode recovery", messages: all)
        let files = try ConversationFiles.encoded([archive], activeID: archive.id)
        let transaction = try BackupFileTransaction.prepare(files, photoFiles: [:], into: root, preserveByLink: true)
        try transaction.commit()
        let reopened = try ConversationFiles.load(from: root)
        let actual = reopened.conversations[0].messages
        check(actual.map(\.id) == all.map(\.id) && actual[0].text == user.text, "actual linked conversation files and startup reader preserve exact Unicode questions and message identities")
        check(actual[1].personalContext == original && actual[2].personalContext == .withoutNotes && actual[3].personalContext == nil,
              "actual archive/mirror reopening preserves shared, no-note and unknown legacy provenance distinctly")
        check(PersonalContextProvenance.history(actual, current: off).map(\.id) == withdrawn.map(\.id),
              "relaunch decoding cannot make an old note-derived reply eligible after withdrawal")

        let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [archive], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: notes, photos: [:])
        let encrypted = root.appendingPathComponent("synthetic.lumenbackup")
        try BackupPackage.write(snapshot, photos: [:], password: "Synthetic provenance passphrase 40", to: encrypted)
        let restored = try BackupPackage.read(encrypted, password: "Synthetic provenance passphrase 40", temporaryRoot: root.appendingPathComponent("preview"))
        defer { restored.removeTemporaryFiles() }
        let restoredMessages = restored.snapshot.conversations[0].messages
        check(restoredMessages[1].personalContext == original && restoredMessages[2].personalContext == .withoutNotes && restoredMessages[3].personalContext == nil,
              "actual encrypted package round trip preserves provenance without manufacturing legacy consent")
        check(restoredMessages[0].text == user.text && restoredMessages[1].text == old.text,
              "encrypted provenance recovery retains literal question and earlier reply text")
        let readable = root.appendingPathComponent("readable.json")
        try ReadableExport.write(snapshot, to: readable)
        let converted = try ReadableExport.read(Data(contentsOf: readable)).snapshot.conversations[0].messages
        check(converted[1].personalContext == original && converted[2].personalContext == .withoutNotes && converted[3].personalContext == nil,
              "actual readable-export conversion keeps known/no-note/unknown provenance separate")
        check(PersonalContextProvenance.history(converted, current: off).map(\.id) == withdrawn.map(\.id),
              "readable recovery preserves the withdrawal history boundary without erasing user questions")
    }
}
