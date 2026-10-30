import Foundation
import Darwin

@main struct ImportTests {
    static func main() async throws {
        setbuf(stdout, nil)
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--backup-ui-fixtures" {
            try BackupUIFixtures.write(to: URL(fileURLWithPath: CommandLine.arguments[2])); return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func parse(_ name: String, _ text: String) throws -> HealthImportPreview {
            let url = directory.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return try HealthImportService.parse(url: url)
        }
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { fatalError("FAIL: \(label)") }; print("PASS: \(label)")
        }
        let csv = try parse("metrics.csv", "date,metric,value,unit,source\n2026-01-01,water,1.5,L,\"Bottle, manual\"\n2026-01-01,weight,150,lb,Scale\n2026-01-01,hrv,0.05,s,Watch\n2026-01-01,steps,8421,count,Watch\n2026-01-01,steps,8421,count,Watch\n2026-01-01,steps,-1,count,Watch\n2026-01-01,steps,nan,count,Watch\n2026-01-01,water,5,bananas,Other\n")
        check(csv.days.count == 1 && csv.samples == 4 && csv.skipped == 4, "duplicates, invalid values and unsupported units are skipped")
        check(csv.days[0].values["water"] == 1500, "litres convert to ml")
        check(abs(csv.days[0].values["weight"]! - 68.0388555) < 0.00001, "pounds convert to kg")
        check(csv.days[0].values["hrv"] == 50, "seconds convert to milliseconds")
        check(csv.days[0].sources["water"] == "Bottle, manual", "quoted CSV source is preserved")
        let json = try parse("metrics.json", "[{\"date\":\"2026-01-02\",\"metric\":\"steps\",\"value\":2000,\"unit\":\"count\",\"source\":\"Watch\"},{\"date\":\"2026-01-02\",\"metric\":\"steps\",\"value\":3000,\"unit\":\"count\",\"source\":\"Watch\"},{\"date\":\"2026-01-02\",\"metric\":\"steps\",\"value\":7000,\"unit\":\"count\",\"source\":\"Phone\"}]")
        check(json.days[0].values["steps"] == 5000 && json.days[0].sources["steps"] == "Watch", "multiple sources never double count")
        let xml = try parse("export.xml", """
        <?xml version="1.0"?><HealthData>
        <Record type="HKCategoryTypeIdentifierSleepAnalysis" value="HKCategoryValueSleepAnalysisAsleepUnspecified" startDate="2026-01-01 23:00:00 +0000" endDate="2026-01-02 07:00:00 +0000" sourceName="Watch"/>
        <Record type="HKCategoryTypeIdentifierSleepAnalysis" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="2026-01-02 01:00:00 +0000" endDate="2026-01-02 03:00:00 +0000" sourceName="Watch"/>
        <Record type="HKCategoryTypeIdentifierSleepAnalysis" value="HKCategoryValueSleepAnalysisInBed" startDate="2026-01-01 22:00:00 +0000" endDate="2026-01-02 08:00:00 +0000" sourceName="Watch"/>
        <Record type="HKQuantityTypeIdentifierDietaryWater" value="0.5" unit="L" startDate="2026-01-02 10:00:00 +0000" endDate="2026-01-02 10:00:00 +0000" sourceName="Bottle"/>
        </HealthData>
        """)
        check(xml.days.count == 1 && xml.days[0].values["sleep"] == 8, "asleep intervals are unioned, in-bed is excluded and night belongs to wake day")
        check(xml.days[0].values["water"] == 500 && xml.skipped == 1, "Apple Health XML units and unsupported categories handled")
        do { _ = try parse("bad.xml", "<HealthData><Record>"); fatalError("invalid XML accepted") } catch { print("PASS: malformed XML rejected") }
        do { _ = try parse("bad.csv", "date,metric,value,unit\n\"oops"); fatalError("invalid CSV accepted") } catch { print("PASS: unclosed CSV quote rejected") }
        do { _ = try parse("bad-date.json", "[{\"date\":\"2026-02-30\",\"metric\":\"sleep\",\"value\":8,\"unit\":\"h\"}]"); fatalError("invalid date accepted") } catch { print("PASS: invalid dates rejected") }
        do { _ = try parse("future.csv", "date,metric,value,unit\n2099-01-01,steps,123,count"); fatalError("future accepted") } catch { print("PASS: future readings rejected") }
        let multiline = try HealthImportService.csvRows("date,source\n2026-01-01,\"Line one\nLine \"\"two\"\"\"\n")
        check(multiline[1][1] == "Line one\nLine \"two\"", "quoted newlines and escaped quotes parsed")
        let encoded = try JSONEncoder().encode(SymptomEntry(name: "Headache", location: "Head", severity: 3, note: "Dull ache", triggers: ["Stress"]))
        let decoded = try JSONDecoder().decode(SymptomEntry.self, from: encoded)
        check(decoded.isActive && decoded.severity == 3 && decoded.note == "Dull ache", "symptom persistence round-trip preserves details")
        check(ReminderPolicy.isQuiet(hour: 23, start: 21, end: 8), "quiet hours cross midnight")
        check(ReminderPolicy.isQuiet(hour: 7, start: 21, end: 8), "early morning quiet hours")
        check(!ReminderPolicy.isQuiet(hour: 8, start: 21, end: 8), "quiet end boundary allows daytime")
        check(ReminderPolicy.isQuiet(hour: 12, start: 8, end: 8), "equal boundaries mean quiet all day")
        check(ReminderPolicy.isQuiet(hour: 13, start: 12, end: 16) && !ReminderPolicy.isQuiet(hour: 17, start: 12, end: 16), "same-day quiet window works")
        check(HealthTotals.nutrient(local: 600, external: 800, imported: nil, excludesLumen: true) == 1400, "external meals and local meals are counted once")
        check(HealthTotals.nutrient(local: 600, external: 1000, imported: nil, excludesLumen: false) == 1000, "legacy inclusive snapshots do not double count local meals")
        check(HealthTotals.nutrient(local: 600, external: nil, imported: 1400, excludesLumen: true) == 1400, "imported daily totals are not added to overlapping local logs")
        check(HealthTotals.water(local: 250, snapshot: 1000, imported: nil, excludesLumen: true) == 1250, "external water and local glass combine immediately")
        check(HealthTotals.water(local: 250, snapshot: 0, imported: 2000, excludesLumen: true) == 250, "recorded external water zero wins over an overlapping import")
        check(HealthTotals.water(local: 250, snapshot: nil, imported: 2000, excludesLumen: true) == 2000, "an absent water query allows imported coverage without adding overlapping local logs")
        check(HealthTotals.water(local: 250, snapshot: 1000, imported: 2000, excludesLumen: false) == 1000, "legacy inclusive live water avoids both local and imported double counting")

        var recordedZero = DayMetrics.empty
        for key in DayMetrics.cumulativeKeys { recordedZero.recordTotal(0, for: key) }
        recordedZero.fillMissingActivity(from: ["steps": 8000, "activeEnergy": 600, "exercise": 45])
        check(recordedZero.recordedTotal("steps") == 0 && recordedZero.recordedTotal("activeEnergy") == 0 && recordedZero.recordedTotal("exercise") == 0, "recorded activity zeros survive import reconciliation")
        var missingTotals = DayMetrics.empty
        check(DayMetrics.cumulativeKeys.allSatisfy { missingTotals.recordedTotal($0) == nil }, "unrecorded cumulative defaults are unknown")
        missingTotals.fillMissingActivity(from: ["steps": 0, "exercise": 20])
        check(missingTotals.recordedTotal("steps") == 0 && missingTotals.recordedTotal("exercise") == 20 && missingTotals.recordedTotal("activeEnergy") == nil, "imports fill missing readings, including recorded zero, without inventing other metrics")
        let zeroRoundTrip = try JSONDecoder().decode(DayMetrics.self, from: JSONEncoder().encode(recordedZero))
        check(DayMetrics.cumulativeKeys.allSatisfy { zeroRoundTrip.recordedTotal($0) == 0 }, "recorded zero presence survives snapshot persistence")
        var legacySnapshot = DayMetrics.empty
        legacySnapshot.steps = 1234
        let legacyRoundTrip = try JSONDecoder().decode(DayMetrics.self, from: JSONEncoder().encode(legacySnapshot))
        check(legacyRoundTrip.recordedTotalKeys == nil && legacyRoundTrip.recordedTotal("steps") == 1234 && legacyRoundTrip.recordedTotal("exercise") == nil, "legacy snapshots decode with positive readings and ambiguous zeros kept unknown")
        legacySnapshot.recordTotal(0, for: "exercise")
        check(legacySnapshot.recordedTotal("steps") == 1234 && legacySnapshot.recordedTotal("exercise") == 0, "adding presence to a legacy snapshot preserves its other known readings")
        var invalidTotals = DayMetrics.empty
        invalidTotals.recordTotal(.infinity, for: "steps"); invalidTotals.recordTotal(-1, for: "exercise")
        invalidTotals.recordTotal(Double(Int.max), for: "stand"); invalidTotals.recordTotal(1, for: "unsupported")
        check(invalidTotals.recordedTotalKeys == nil, "invalid totals and overflowing stand hours cannot establish recorded readings")
        let manualWorkout = Workout(kind: .walk, title: "Walk", start: Date(), duration: 1200, activeCalories: 80, source: .manual)
        var unknownEnergy = manualWorkout; unknownEnergy.energyKnown = false
        var manualOnly = DayMetrics.empty
        manualOnly.reconcileActivity(from: [:], manualWorkouts: [unknownEnergy])
        check(manualOnly.recordedTotal("exercise") == 20 && manualOnly.recordedTotal("activeEnergy") == nil, "a manual workout with unknown energy establishes duration without inventing zero calories")
        var importedWithManual = DayMetrics.empty
        importedWithManual.reconcileActivity(from: ["activeEnergy": 500, "exercise": 60], manualWorkouts: [manualWorkout])
        check(importedWithManual.recordedTotal("activeEnergy") == 500 && importedWithManual.recordedTotal("exercise") == 60, "imports and manual sessions are not added without an actual live reading")
        var partialLive = DayMetrics.empty
        partialLive.recordTotal(0, for: "activeEnergy")
        partialLive.reconcileActivity(from: ["activeEnergy": 500, "exercise": 60], manualWorkouts: [manualWorkout])
        check(partialLive.recordedTotal("activeEnergy") == 80 && partialLive.recordedTotal("exercise") == 60, "each live metric independently controls whether manual sessions can be added")
        var externalWorkout = manualWorkout; externalWorkout.source = .healthKit
        var externalOnly = DayMetrics.empty
        externalOnly.reconcileActivity(from: [:], manualWorkouts: [externalWorkout])
        check(externalOnly.recordedTotal("exercise") == nil && externalOnly.recordedTotal("activeEnergy") == nil, "external workout summaries do not invent whole-day activity totals")
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let summary = HealthHistorySummary.summarize([ImportedHealthDay(date: reference, values: ["steps": 2000], sources: [:])], now: reference)
        check(summary.contains("2000.0 count mean; 1/7 days"), "history summaries preserve missing-day coverage rather than averaging gaps as zeros")
        check(PlanBuilder.isRequest("Make a flexible plan for today"), "explicit planning requests save a plan")
        check(!PlanBuilder.isRequest("I have an implant") && !PlanBuilder.isRequest("I don't want a plan"), "incidental and negated plan mentions do not create documents")
        check(PlanBuilder.steps(from: "My plan\n1. Check energy\n2) Take a break\n- [ ] Review tomorrow").map(\.title) == ["Check energy", "Take a break"], "numbered plan actions take priority over evidence bullets")
        check(PlanBuilder.steps(from: "- [ ] Walk if comfortable\n- Review tomorrow").map(\.title) == ["Walk if comfortable", "Review tomorrow"], "bullet-only plans become editable checklist steps")
        let oldStep = try JSONDecoder().decode(PlanStep.self, from: Data("{\"id\":\"old\",\"title\":\"Walk\",\"isDone\":false}".utf8))
        check(oldStep.dueDate == nil, "legacy plan steps decode without dates")
        var context = PersonalHealthContext(); context.allergies = "Peanuts"
        check(!context.assistantText.contains("Peanuts"), "personal context is excluded until explicitly shared")
        context.includeInAssistant = true
        check(context.assistantText.contains("Peanuts"), "consented personal context is included")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let due = PlanStep(title: "Review", dueDate: yesterday)
        check(PlanSchedule.isOverdue(due), "unfinished past-date steps are overdue")
        check(!PlanSchedule.isOverdue(PlanStep(title: "Done", isDone: true, dueDate: yesterday)), "completed steps are never overdue")
        let activePlan = HealthDocument(title: "Plan", kind: .plan, body: "Draft", steps: [due], source: "Test")
        let archivedPlan = HealthDocument(title: "Archived", kind: .plan, body: "Draft", steps: [due], source: "Test", planState: .archived)
        check(PlanSchedule.pending([activePlan, archivedPlan]).count == 1, "archived plans do not surface unfinished actions")
        check(HealthDocument(title: "Done", kind: .plan, body: "Draft", steps: [PlanStep(title: "Done", isDone: true)], source: "Test").status == .completed, "finishing every step completes a plan")
        let legacy = [ChatMessage(role: .user, text: "Help me plan tomorrow")]
        let migrated = ConversationArchive.migrate(legacy: legacy, existing: [])
        check(migrated.count == 1 && migrated[0].messages[0].id == legacy[0].id, "legacy conversation migration preserves messages and identifiers")
        check(ConversationArchive.migrate(legacy: legacy, existing: migrated).count == 1, "conversation migration does not duplicate existing history")
        let other = HealthConversation(title: "Other")
        let answered = ConversationArchive.appending(ChatMessage(role: .coach, text: "Answer"), to: migrated[0].id, in: migrated + [other])
        check(answered[0].messages.count == 2 && answered[1].messages.isEmpty, "a reply stays in its originating conversation")
        check(ConversationArchive.appending(ChatMessage(role: .coach, text: "Answer"), to: "deleted", in: migrated)[0].messages.count == 1, "a deleted conversation is not recreated by a late reply")
        let today = Calendar.current.startOfDay(for: Date())
        func day(_ offset: Int, _ value: Double) -> ImportedHealthDay { ImportedHealthDay(date: Calendar.current.date(byAdding: .day, value: offset, to: today)!, values: ["steps": value], sources: ["steps":"Test source"]) }
        let trend = TrendEvidence.compare([day(-1, 2000), day(-2, 2000), day(-3, 2000), day(-8, 1000), day(-9, 1000), day(-10, 1000), day(0, 99999)], metric: "steps", window: 7)
        check(trend.currentMean == 2000 && trend.current.count == 3, "trend averages use recorded days and exclude incomplete today")
        check(trend.changePercent == 100 && trend.previous.count == 3, "trend compares the correct adjacent periods")
        check(trend.sources == ["Test source"], "trend evidence retains source names")
        check(!TrendEvidence.compare([day(-1, 2000), day(-8, 1000)], metric: "steps", window: 7).comparable, "sparse periods are not presented as meaningful comparisons")
        let zero = TrendEvidence.compare([day(-1, 2), day(-2, 2), day(-3, 2), day(-8, 0), day(-9, 0), day(-10, 0)], metric: "steps", window: 7)
        check(zero.changePercent == nil && zero.change == 2, "zero baselines yield an absolute change without dividing by zero")
        let oldSymptom = SymptomEntry(date: Calendar.current.date(byAdding: .day, value: -90, to: today)!, name: "Headache", location: "Head", severity: 3, note: "Behind eyes", triggers: ["Stress"])
        let report = AppointmentSummary.make(symptoms: [oldSymptom], checkIns: [], workouts: [], days: 7)
        check(report.body.contains("Behind eyes") && report.body.contains("Still marked ongoing"), "appointment summaries include older unresolved symptom descriptions")
        check(!report.includeInAssistant && report.kind == .review, "appointment summaries remain excluded from assistant context by default")
        let blocks = DocumentBlocks.parse("## Symptoms\n\nHeadache notes\n\n- First question\n2. Second question")
        check(blocks.map(\.kind) == [.heading(2), .paragraph, .listItem("•"), .listItem("2.")], "document headings and lists render as block structure instead of raw markers")
        check(DocumentBlocks.parse("```\n## literal\n```")[0].kind == .code, "code-fenced record text is not misinterpreted as headings")
        var backup = BackupSnapshot(profile: .default, goals: HealthGoals(), habits: SleepHabit.defaults(), sleep: [], meals: [], workouts: [], water: [], conversations: migrated, symptoms: [oldSymptom], checkIns: [], documents: [report], importedDays: [day(-1, 2000)], imports: [], personalContext: PersonalHealthContext(), photos: [:])
        let photoBytes = Data([0xff, 0xd8, 0xff, 0xd9])
        backup.photos["photo-1"] = photoBytes
        backup.meals = [Meal(type: .lunch, items: [], photoID: "photo-1")]
        backup.documents[0].includeInAssistant = true
        backup.personalContext.focus = "Imported focus"; backup.personalContext.includeInAssistant = true
        let archiveBytes = try BackupArchive.make(backup)
        let (archive, roundTrip) = try BackupArchive.read(archiveBytes)
        check(archive.version == 1 && roundTrip.photos["photo-1"] == photoBytes && roundTrip.symptoms[0].id == oldSymptom.id, "versioned backup round-trip preserves records, IDs and photo bytes")
        var local = backup
        local.symptoms[0].note = "Current edit"; local.meals = []; local.photos = ["photo-1": Data([1, 2, 3])]
        local.documents = []; local.conversations = []; local.personalContext.focus = "Current focus"
        local.importedDays[0].values["steps"] = 3333
        backup.importedDays[0].values["water"] = 250
        let merged = backup.merging(into: local, restorePreferences: false)
        check(merged.symptoms[0].note == "Current edit" && merged.conversations.count == 1, "restore keeps current edits and adds missing conversation history")
        check(merged.importedDays[0].values["steps"] == 3333 && merged.importedDays[0].values["water"] == 250, "restore adds missing metrics while keeping current daily values")
        check(merged.meals[0].photoID != "photo-1" && merged.photos[merged.meals[0].photoID!] == photoBytes && merged.photos["photo-1"] == Data([1, 2, 3]), "restore remaps photo collisions without overwriting existing photos")
        check(!merged.documents[0].includeInAssistant && merged.personalContext.focus == "Current focus", "restored documents require sharing consent and preferences are opt-in")
        let preferred = backup.merging(into: local, restorePreferences: true)
        check(preferred.personalContext.focus == "Imported focus" && !preferred.personalContext.includeInAssistant && preferred.profile.appLock == local.profile.appLock, "profile restore resets context sharing while preserving device lock settings")
        let repeated = backup.merging(into: merged, restorePreferences: false)
        check(repeated.recordCount == merged.recordCount && repeated.photos.count == merged.photos.count, "repeated restore does not duplicate records or meal photos")
        check(backup.conflicts(with: local) > 0, "backup preview reports matching record IDs")
        func rejects(_ bytes: Data, _ message: String) {
            do { _ = try BackupArchive.read(bytes); fatalError(message) } catch { print("PASS: " + message) }
        }
        rejects(Data("{}".utf8), "malformed and legacy exports are rejected")
        rejects(try BackupArchive.encoder().encode(BackupArchive(format: "LumenBackup", version: 99, createdAt: Date(), payload: archive.payload, sha256: archive.sha256)), "future backup versions are rejected")
        rejects(try BackupArchive.encoder().encode(BackupArchive(format: "LumenBackup", version: 1, createdAt: Date(), payload: archive.payload + Data([0]), sha256: archive.sha256)), "corrupted backup payloads are rejected")
        var unsafe = backup; unsafe.meals[0].photoID = "../outside"; unsafe.photos["../outside"] = photoBytes
        do { _ = try BackupArchive.make(unsafe); fatalError("unsafe photo path accepted") } catch { print("PASS: photo path traversal rejected") }
        var duplicate = backup; duplicate.symptoms.append(duplicate.symptoms[0])
        do { _ = try BackupArchive.make(duplicate); fatalError("duplicate IDs accepted") } catch { print("PASS: duplicate IDs rejected before restore") }
        var invalidGoal = backup; invalidGoal.goals.weightKg = 1e300
        do { _ = try BackupArchive.make(invalidGoal); fatalError("unsafe numeric value accepted") } catch { print("PASS: numeric overflow rejected before restore") }
        var invalidBirthYear = backup; invalidBirthYear.profile.birthYear = Int.min
        do { _ = try BackupArchive.make(invalidBirthYear); fatalError("unsafe birth year accepted") } catch { print("PASS: birth-year overflow rejected before restore") }
        let restoreDir = directory.appendingPathComponent("restore-data")
        try FileManager.default.createDirectory(at: restoreDir, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: restoreDir.appendingPathComponent("keep.json"))
        try BackupFiles.install(["new.json": Data("new".utf8), "photos/photo.jpg": photoBytes], into: restoreDir)
        let keptText = try String(contentsOf: restoreDir.appendingPathComponent("keep.json"), encoding: .utf8)
        check(keptText == "original", "transaction preserves domains outside the backup")
        let restoredPhoto = try Data(contentsOf: restoreDir.appendingPathComponent("photos/photo.jpg"))
        check(restoredPhoto == photoBytes, "transaction installs photo bytes with records")
        do { try BackupFiles.install(["../escape": Data()], into: restoreDir); fatalError("unsafe file path accepted") } catch { print("PASS: failed staging leaves current records intact") }
        check(FileManager.default.fileExists(atPath: restoreDir.appendingPathComponent("new.json").path), "failed staging retains the installed backup")
        try FileManager.default.moveItem(at: restoreDir, to: restoreDir.appendingPathExtension("previous"))
        try BackupFiles.recover(restoreDir)
        check(FileManager.default.fileExists(atPath: restoreDir.appendingPathComponent("keep.json").path), "interrupted installation recovers the previous data directory")
        let importCSV = directory.appendingPathComponent("progress.csv")
        let manyRows = "date,metric,value,unit,source\n" + (1...1100).map { "2026-01-01,steps,\($0),count,Watch" }.joined(separator: "\n")
        try manyRows.write(to: importCSV, atomically: true, encoding: .utf8)
        let progressControl = HealthImportControl()
        let progressPreview = try HealthImportService.parse(url: importCSV, control: progressControl)
        check(progressControl.recordsProcessed == 1100 && progressPreview.samples == 1100, "import progress counts actual reviewed records")
        let cancelledCSV = HealthImportControl()
        do {
            _ = try HealthImportService.parse(url: importCSV, control: cancelledCSV, progress: { count in if count >= 512 { cancelledCSV.cancel() } })
            fatalError("cancelled CSV yielded a partial preview")
        } catch is CancellationError { print("PASS: cancellation during CSV parsing discards partial results") }
        let cancelledBefore = HealthImportControl(); cancelledBefore.cancel()
        do { _ = try HealthImportService.parse(url: importCSV, control: cancelledBefore); fatalError("pre-cancelled import started") }
        catch is CancellationError { print("PASS: cancelled imports stop before reading") }
        let importXML = directory.appendingPathComponent("progress.xml")
        let xmlRecord = "<Record type=\"HKQuantityTypeIdentifierStepCount\" value=\"10\" unit=\"count\" startDate=\"2026-01-01 10:00:00 +0000\" endDate=\"2026-01-01 10:01:00 +0000\" sourceName=\"Watch\"/>"
        try ("<HealthData>" + String(repeating: xmlRecord, count: 1100) + "</HealthData>").write(to: importXML, atomically: true, encoding: .utf8)
        let cancelledXML = HealthImportControl()
        do {
            _ = try HealthImportService.parse(url: importXML, control: cancelledXML, progress: { count in if count >= 512 { cancelledXML.cancel() } })
            fatalError("cancelled XML yielded a partial preview")
        } catch is CancellationError { print("PASS: XML parser abortion reports cancellation rather than malformed data") }
        let importJSON = directory.appendingPathComponent("progress.json")
        let jsonRow = "{\"date\":\"2026-01-01\",\"metric\":\"steps\",\"value\":10,\"unit\":\"count\"}"
        try ("[" + Array(repeating: jsonRow, count: 1100).joined(separator: ",") + "]").write(to: importJSON, atomically: true, encoding: .utf8)
        let cancelledJSON = HealthImportControl()
        do {
            _ = try HealthImportService.parse(url: importJSON, control: cancelledJSON, progress: { count in if count >= 512 { cancelledJSON.cancel() } })
            fatalError("cancelled JSON yielded a partial preview")
        } catch is CancellationError { print("PASS: cancellation during JSON parsing discards partial results") }
        let csvLexing = HealthImportControl(); csvLexing.cancel()
        do { _ = try HealthImportService.csvRows(manyRows, control: csvLexing); fatalError("CSV tokenization ignored cancellation") }
        catch is CancellationError { print("PASS: CSV tokenization honors cancellation") }
        try ZIPImportChecks.run(in: directory)
        try WorkoutImportChecks.run(in: directory, snapshot: backup)
        try HealthLogDraftChecks.run(snapshot: backup)
        try DataConfidenceChecks.run(snapshot: backup)
        try RetainedEvidenceChecks.run()
        try await HealthSyncChecks.run()
        try BackupPackageChecks.run(in: directory, sample: backup)
        print("All import, model, totals, history, plan, conversation, evidence, document and reminder checks passed.")
    }
}
