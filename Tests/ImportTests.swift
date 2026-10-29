import Foundation

@main struct ImportTests {
    static func main() throws {
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
        print("All import, model, totals, history, plan and reminder checks passed.")
    }
}
