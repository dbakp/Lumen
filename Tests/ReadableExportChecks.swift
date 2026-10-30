import Foundation

/// Synthetic historical exports and the actual streaming writer/converter/merge.
enum ReadableExportChecks {
    static func fixtures(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date(), yesterday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86400)
        var profile = UserProfile.default; profile.name = "Synthetic recovered profile"
        var goals = HealthGoals(); goals.stepGoal = 4321
        var plan = HealthDocument(id: "readable-plan", title: "Synthetic recovered plan", kind: .plan, body: "A flexible synthetic plan. Not medical advice.", steps: [PlanStep(id: "readable-step", title: "Review the saved note", dueDate: now.addingTimeInterval(86400))], source: "Synthetic readable fixture", includeInAssistant: true)
        plan.extraction = nil
        plan.body += "\n\n" + (1...65).map { "Synthetic saved paragraph \($0). This is a review and pagination fixture, not a patient's record or a treatment instruction." }.joined(separator: "\n\n")
        let messages = [ChatMessage(id: "readable-question", role: .user, text: "Synthetic recovery question"), ChatMessage(id: "readable-answer", role: .coach, text: "Synthetic saved reply. Not medical advice.", provider: "Synthetic fixture")] + (2..<52).map { ChatMessage(id: "readable-message-\($0)", role: .user, text: "Synthetic archived message \($0). Not patient data.") }
        let snapshot = BackupSnapshot(profile: profile, goals: goals, habits: SleepHabit.defaults(), sleep: [SleepEpisode(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, bedtime: yesterday.addingTimeInterval(-8 * 3600), wakeTime: yesterday, source: .manual)],
            meals: [Meal(id: "readable-meal", type: .breakfast, items: [FoodItem(id: "readable-food", name: "Synthetic oats", grams: 42, calories: 150, proteinG: 6, carbsG: 24, fatG: 3)], photoID: "readable-missing-photo")],
            workouts: [Workout(id: "readable-workout", kind: .walk, title: "Synthetic recovery walk", start: yesterday.addingTimeInterval(12 * 3600), duration: 1200, activeCalories: 0, source: .manual)],
            water: [HydrationLog(id: "readable-water", ml: 375)], conversations: [HealthConversation(id: "readable-conversation", title: "Synthetic recovered conversation", messages: messages)],
            symptoms: [SymptomEntry(id: "readable-symptom", name: "Synthetic shoulder note", location: "Shoulder", severity: 2, note: "SYNTHETIC RECOVERY DATA", triggers: [])],
            checkIns: [WellbeingCheckIn(id: "readable-checkin", energy: 4, mood: 3, stress: 2, note: "Synthetic check-in")], documents: [plan],
            importedDays: [ImportedHealthDay(date: yesterday, values: ["steps": 8421, "water": 0], sources: ["steps": "Synthetic export", "water": "Synthetic export"])],
            imports: [ImportReceipt(id: "readable-receipt", filename: "Synthetic earlier import.csv", days: 1, samples: 2, skipped: 0)], personalContext: PersonalHealthContext(focus: "Synthetic private focus", includeInAssistant: true), photos: [:])
        let canonical = folder.appendingPathComponent("Lumen-readable-current.json")
        try ReadableExport.write(snapshot, reminders: ReminderPreferences(enabled: true), to: canonical)
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: canonical)) as! [String: Any]
        root.removeValue(forKey: "readableVersion")
        root["chat"] = try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(messages))
        root["today"] = ["steps": 99999]; root["future-section"] = ["note": "Synthetic ignored content"]
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Lumen-readable-full.json"))
        let partial: [String: Any] = ["app": "Lumen", "exportedAt": "2026-10-29T12:00:00.125Z", "water": try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode([HydrationLog(id: "readable-partial-water", ml: 175)]))]
        try JSONSerialization.data(withJSONObject: partial).write(to: folder.appendingPathComponent("Lumen-readable-partial.json"))
        try Data("{\"app\":\"Lumen\",\"exportedAt\":\"2026-10-29T12:00:00Z\",\"water\":[],\"water\":[]}".utf8).write(to: folder.appendingPathComponent("Lumen-readable-invalid.json"))
        var large = snapshot; large.meals = []
        large.water = (0..<100_000).map { HydrationLog(id: "readable-large-\($0)", date: now.addingTimeInterval(-Double($0) * 3600), ml: 125) }
        try ReadableExport.write(large, to: folder.appendingPathComponent("Lumen-readable-large.json"))
    }
    static func run(in parent: URL, sample: BackupSnapshot) throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); print("PASS: " + name) }
        let passage = String(repeating: "Ångström 👩🏽‍⚕️ synthetic saved paragraph.\n\n", count: 140)
        let sections = ReadableExport.reviewSections(passage)
        check(sections.map(String.init).joined() == passage && sections.allSatisfy { $0.count <= 2000 } && sections.dropLast().allSatisfy { $0.hasSuffix("\n\n") },
              "reader pages keep exact Unicode text and prefer complete paragraph boundaries")
        let unbroken = String(repeating: "🩺", count: 4100)
        check(ReadableExport.reviewSections(unbroken).map(String.init).joined() == unbroken && ReadableExport.reviewSections(unbroken).allSatisfy { $0.count <= 2000 } && ReadableExport.reviewSections("").count == 1,
              "unbroken and empty saved text remain lossless within the reader page bound")
        let folder = parent.appendingPathComponent("readable-checks"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var input = sample; input.photos = [:]
        let file = folder.appendingPathComponent("export.json"), control = BackupOperationControl()
        try ReadableExport.write(input, to: file, control: control)
        let bytes = try Data(contentsOf: file), converted = try ReadableExport.read(bytes)
        check(converted.present == Set(ReadableExport.Domain.allCases) && converted.snapshot.recordCount == input.recordCount, "streamed readable export covers all typed data domains without a backup wrapper")
        check(converted.missingPhotos == input.meals.filter { $0.photoID != nil }.count && converted.snapshot.meals.allSatisfy { $0.photoID == nil }, "readable recovery explicitly accounts for missing photos without dropping meal text")
        check(control.progress.completed == control.progress.total && control.progress.total > 0 && control.progress.bytes > 0, "plain JSON writing reports actual streamed items and bytes")
        check(!converted.defaultSelection.contains(.profile) && !converted.defaultSelection.contains(.personalContext), "readable recovery leaves every preference replacement off by default")
        let selected = try converted.selected([.documents, .water])
        check(selected.0.meals.isEmpty && selected.0.symptoms.isEmpty && selected.0.documents.count == input.documents.count && selected.1.isEmpty, "selected history categories cannot implicitly import other records or preferences")
        var local = sample; local.photos = [:]; local.meals = []; local.documents = []; local.water = []
        local.profile.name = "Keep local name"; local.personalContext.includeInAssistant = true
        local.habits[0].doneToday = true
        let merged = try selected.0.mergingFileBacked(into: local, preferences: selected.1, photoFiles: [:]).snapshot
        check(merged.profile.name == "Keep local name" && merged.personalContext.includeInAssistant && merged.habits[0].doneToday, "unselected preferences retain local notes sharing and routine completion")
        check(merged.documents.allSatisfy { !$0.includeInAssistant }, "readable recovery retains fresh document-sharing consent")
        let onlyProfile = try converted.selected([.profile])
        let profileMerge = try onlyProfile.0.mergingFileBacked(into: local, preferences: onlyProfile.1, photoFiles: [:]).snapshot
        check(profileMerge.profile.name == input.profile.name && profileMerge.habits[0].doneToday && profileMerge.personalContext.includeInAssistant, "profile-only replacement cannot reset routines or unrelated personal-note sharing")
        let onlyContext = try converted.selected([.personalContext])
        let notesMerge = try onlyContext.0.mergingFileBacked(into: local, preferences: onlyContext.1, photoFiles: [:]).snapshot
        check(!notesMerge.personalContext.includeInAssistant && notesMerge.profile.name == local.profile.name && notesMerge.habits[0].doneToday, "selected personal-note replacement resets only its own sharing permission")
        let again = try selected.0.mergingFileBacked(into: merged, preferences: [], photoFiles: [:]).snapshot
        check(again.recordCount == merged.recordCount, "repeated readable recovery keeps current identities instead of duplicating records")
        var root = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        root["chat"] = try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(input.conversations.first!.messages))
        root["today"] = ["steps": 99999]; root["unknown-source-domain"] = ["private": "NOT-RECOVERED"]
        let legacy = try ReadableExport.read(JSONSerialization.data(withJSONObject: root))
        check(legacy.mirroredMessages == input.conversations[0].messages.count && legacy.snapshot.conversations.count == input.conversations.count, "active-chat mirrors do not duplicate an archived conversation")
        check(Set(legacy.omittedKeys) == ["today", "unknown-source-domain"], "cached and unsupported domains are enumerated as omissions and never converted into health records")
        root.removeValue(forKey: "conversations")
        let chatOnly = try ReadableExport.read(JSONSerialization.data(withJSONObject: root))
        let chatAgain = try ReadableExport.read(JSONSerialization.data(withJSONObject: root))
        check(chatOnly.recoveredChat && chatOnly.snapshot.conversations[0].id == chatAgain.snapshot.conversations[0].id, "legacy chat recovery creates a stable conversation identity across repeated selections")
        var partial: [String: Any] = ["app": "Lumen", "exportedAt": "2026-10-29T12:00:00.125Z", "water": try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(input.water))]
        let sparse = try ReadableExport.read(JSONSerialization.data(withJSONObject: partial))
        check(sparse.present == [.water] && sparse.snapshot.documents.isEmpty, "fractional ISO dates and partial historical exports retain explicit domain absence")
        check(abs(sparse.exportedAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) - 0.125) < 0.000001,
              "fractional export metadata is decoded without losing its subsecond instant")
        do { _ = try sparse.selected([.profile]); preconditionFailure("absent preference selected") } catch { print("PASS: missing preferences cannot be selected or replaced by generated defaults") }
        partial["documents"] = NSNull()
        do { _ = try ReadableExport.read(JSONSerialization.data(withJSONObject: partial)); preconditionFailure("null accepted") } catch { print("PASS: a present null domain is rejected instead of silently becoming empty") }
        func reject(_ data: Data, _ name: String) {
            do { _ = try ReadableExport.read(data); preconditionFailure(name) } catch { print("PASS: " + name) }
        }
        func encoded(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
        let minimal: [String: Any] = ["app": "Lumen", "exportedAt": "2026-10-29T12:00:00Z", "water": []]
        for version: Any in [true, NSNull(), "1", 2] {
            var value = minimal; value["readableVersion"] = version
            reject(try encoded(value), "unsupported or incorrectly typed readable version is refused: \(version)")
        }
        var conflicting = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        var copiedMessages = input.conversations[0].messages
        copiedMessages[0].text += " conflicting copy"
        conflicting["chat"] = try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(copiedMessages))
        reject(try encoded(conflicting), "an altered active-chat mirror cannot replace an archived message")
        copiedMessages = input.conversations[0].messages
        copiedMessages.append(ChatMessage(id: "readable-extra-message", role: .user, text: "Synthetic unmatched continuation"))
        conflicting["chat"] = try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(copiedMessages))
        let continued = try ReadableExport.read(encoded(conflicting))
        check(continued.recoveredChat && continued.mirroredMessages == input.conversations[0].messages.count && continued.snapshot.conversations.last?.messages.count == copiedMessages.count,
              "partially mirrored chat retains its full continuation as an explicitly separate conversation")
        var badWater = minimal
        badWater["water"] = [["id": "bad-water", "date": "2026-10-29T12:00:00Z", "ml": -1]]
        reject(try encoded(badWater), "negative recorded water cannot enter recovery")
        badWater["water"] = [["id": "same-water", "date": "2026-10-29T12:00:00Z", "ml": 125], ["id": "same-water", "date": "2026-10-29T12:00:00Z", "ml": 250]]
        reject(try encoded(badWater), "two incoming records cannot share a water identity")
        var demo = input
        demo.meals = [Meal(id: "readable-demo-food", type: .lunch, items: [], source: .sample)]
        demo.workouts = [Workout(id: "readable-demo-workout", kind: .walk, title: "Demo walk", start: Date(), duration: 60, activeCalories: 0, source: .sample)]
        let demoFile = folder.appendingPathComponent("demo.json"); try ReadableExport.write(demo, to: demoFile)
        let withoutDemo = try ReadableExport.read(Data(contentsOf: demoFile))
        check(withoutDemo.omittedSampleMeals == 1 && withoutDemo.omittedSampleWorkouts == 1 && withoutDemo.snapshot.meals.isEmpty && withoutDemo.snapshot.workouts.isEmpty,
              "historical demonstration meals and workouts are explicitly excluded before review counts")
        var current = sample; current.photos = [:]
        let incomingMeals = try converted.selected([.meals])
        let keptPhotos = try incomingMeals.0.mergingFileBacked(into: current, preferences: [], photoFiles: [:]).snapshot
        check(keptPhotos.meals.first?.photoID == sample.meals.first?.photoID && keptPhotos.meals.count == sample.meals.count,
              "readable recovery cannot strip an existing matching meal's local photo")
        var zeroDays = minimal
        zeroDays["imported-days"] = [["date": "2026-10-28T00:00:00Z", "values": ["steps": 0], "sources": ["steps": "Synthetic zero export"]]]
        let zeros = try ReadableExport.read(encoded(zeroDays))
        check(zeros.snapshot.importedDays.first?.values["steps"] == 0 && zeros.snapshot.importedDays.first?.values["water"] == nil,
              "recorded zero survives conversion while an absent metric stays absent")
        reject(Data(("{\"app\":\"Lumen\",\"exportedAt\":\"2026-10-29T12:00:00Z\",\"water\":[],\"unknown\":" + String(repeating: "[", count: 66) + "0" + String(repeating: "]", count: 66) + "}").utf8),
               "overdeep unsupported content is bounded before Foundation conversion")
        let tooMany = "{\"app\":\"Lumen\",\"exportedAt\":\"2026-10-29T12:00:00Z\",\"water\":[" + Array(repeating: "{\"id\":\"bounded\",\"date\":\"2026-10-29T12:00:00Z\",\"ml\":125}", count: 200_001).joined(separator: ",") + "]}"
        reject(Data(tooMany.utf8), "a 200001-record section is rejected without a partial preview")
        reject(Data("{\"app\":\"Lumen\",\"exportedAt\":\"2026-10-29T12:00:00Z\",\"water\":[],\"water\":[]}".utf8), "ambiguous repeated top-level fields are rejected before Foundation discards a value")
        reject(Data(#"{"app":"Lumen","exportedAt":"2026-10-29T12:00:00Z","water":[],"\u0077ater":[]}"#.utf8), "escaped equivalent JSON keys cannot bypass ambiguity checks")
        reject(Data(#"{"app":"Lumen","exportedAt":"2026-10-29T12:00:00Z","documents":[{"title":"one","title":"two"}]}"#.utf8), "repeated nested record fields are rejected too")
        reject(Data(), "empty readable files report an invalid format without inventing sections")
        reject(Data("[1,2]".utf8), "a metrics array is not mistaken for a readable Lumen export")
        reject(try BackupArchive.make(sample), "a typed backup is kept separate from readable export conversion")
        let cancelled = BackupOperationControl(); cancelled.cancel()
        do { _ = try ReadableExport.read(bytes, control: cancelled); preconditionFailure("cancelled") } catch is CancellationError { print("PASS: cancelled readable conversion publishes no partial preview") }
        let interrupted = folder.appendingPathComponent("cancelled.json")
        let holder = CancellationHolder()
        let writer = BackupOperationControl(observer: { progress in if progress.stage == .writing && progress.completed >= 2 { holder.cancel() } })
        holder.bind(writer)
        do { try ReadableExport.write(input, to: interrupted, control: writer); preconditionFailure("cancelled write") } catch is CancellationError { print("PASS: cancellation during plain JSON writing leaves no shareable destination") }
        check(!FileManager.default.fileExists(atPath: interrupted.path) && !(try! FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasSuffix(".partial") }, "cancelled readable creation removes its partial working file")
        var large = input; large.meals = []; large.water = (0..<2000).map { HydrationLog(id: "readable-large-\($0)", ml: 125) }
        let largeFile = folder.appendingPathComponent("large.json"); try ReadableExport.write(large, to: largeFile)
        let stop = CancellationHolder()
        let reader = BackupOperationControl(observer: { progress in if progress.detail == "Water entries" && progress.completed >= 256 { stop.cancel() } })
        stop.bind(reader)
        do { _ = try ReadableExport.read(Data(contentsOf: largeFile), control: reader); preconditionFailure("cancelled read") } catch is CancellationError { print("PASS: cancellation inside a large typed section discards all conversion results") }
        do { try ReadableExport.write(input, to: file); preconditionFailure("overwritten") } catch { print("PASS: plain export writer refuses to overwrite an existing file") }
    }
    private final class CancellationHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var control: BackupOperationControl?
        func bind(_ control: BackupOperationControl) { lock.lock(); self.control = control; lock.unlock() }
        func cancel() { lock.lock(); let value = control; lock.unlock(); value?.cancel() }
    }
}
