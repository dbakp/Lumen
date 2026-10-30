import Foundation

enum ScheduledPlanChecks {
    static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); print("PASS: " + name) }
        let request = ScheduledPlanRequest(goal: "Make time to review my routine.", startDay: "2026-10-24", weeks: 2)
        let promptData = Data(request.prompt.components(separatedBy: "\n").dropFirst().joined(separator: "\n").utf8)
        let payload = try JSONSerialization.jsonObject(with: promptData) as! [String: Any]
        check(payload["startDay"] as? String == "2026-10-24" && payload["startWeekdayMondayIs1"] as? Int == 6 && payload["days"] as? Int == 14, "provider requests include the chosen start date and actual weekday so named-day routines need not assume today")
        let valid = #"{"version":1,"title":"A steady routine","reason":"An editable routine; missing logs are unknown.","steps":[{"day":14,"title":"Review and adapt"},{"day":1,"title":"Choose one small step"}]}"#
        let draft = try ScheduledPlanDraft.parse(valid, request: request, source: "Synthetic test provider")
        check(draft.actions.map(\.day) == [14, 1], "plan parsing preserves every action before explicit review without silently sorting or trimming text")
        check(request.lastDay == "2026-11-06", "a two-week plan spans calendar days across the daylight-saving transition")
        do { _ = try draft.document(acknowledged: false); preconditionFailure("unchecked plan saved") } catch { print("PASS: a generated plan requires explicit review acknowledgement") }
        let doc = try draft.document(acknowledged: true)
        check(doc.steps.map(\.plannedDay) == ["2026-10-24", "2026-11-06"] && doc.steps.map(\.title) == ["Choose one small step", "Review and adapt"], "confirmed plans have actual dated steps in chronological order")
        check(doc.id == draft.id && Set(doc.steps.map(\.id)) == Set(draft.actions.map(\.id)) && !doc.includeInAssistant && doc.status == .active, "plan confirmation preserves stable identities and starts assistant sharing off")
        let again = try draft.document(acknowledged: true)
        check(again.id == doc.id && again.steps.map(\.id) == doc.steps.map(\.id), "retrying the same confirmed plan cannot create new identities")
        let restored = try JSONDecoder().decode(HealthDocument.self, from: JSONEncoder().encode(doc))
        check(restored.steps.map(\.plannedDay) == doc.steps.map(\.plannedDay) && restored.body.contains(request.goal), "plan dates and literal requested goal survive document coding")
        let early = TimeZone(identifier: "Pacific/Kiritimati")!, late = TimeZone(identifier: "Pacific/Honolulu")!
        let civil = "2026-11-06"
        check(PlanDay.string(PlanDay.date(civil, timeZone: early)!, timeZone: early) == civil && PlanDay.string(PlanDay.date(civil, timeZone: late)!, timeZone: late) == civil, "planned calendar days remain literal across opposite travel time zones")
        check(PlanDay.date("2026-02-30") == nil && PlanDay.date("2026-2-03") == nil && PlanDay.date("2026-11-06T00:00:00Z") == nil && PlanDay.adding(1, to: "2028-02-28") == "2028-02-29", "calendar plans reject normalized impossible dates and retain leap days")
        var step = restored.steps[0]; step.setDate(nil)
        check(step.calendarDate == nil && step.plannedDay == nil && step.dueDate == nil, "clearing a plan date clears both calendar and legacy representations")
        step.setDate(PlanDay.date(civil))
        check(step.plannedDay == civil && step.calendarDate != nil, "editing a plan date updates its persistent calendar day")
        let old = try JSONDecoder().decode(PlanStep.self, from: Data(#"{"id":"old","title":"Legacy step","isDone":false,"dueDate":0}"#.utf8))
        check(old.plannedDay == nil && old.calendarDate == old.dueDate, "old plans retain their existing absolute dates without a forced migration")
        for broken in [valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"), valid.replacingOccurrences(of: "\"day\":14", with: "\"day\":15"), valid.replacingOccurrences(of: "\"day\":1,", with: "\"day\":0,"), valid.replacingOccurrences(of: "\"day\":14", with: "\"day\":7"), valid.replacingOccurrences(of: "\"day\":14", with: "\"day\":true"), valid.replacingOccurrences(of: "\"day\":14", with: "\"day\":1.5"), valid.replacingOccurrences(of: "\"title\":\"A steady routine\"", with: "\"title\":\"\""), valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"version\":1"), valid.replacingOccurrences(of: "\"reason\":", with: "\"extra\":true,\"reason\":"), "```json\n" + valid + "\n```", String(valid.dropLast()), "I cannot prepare that routine."] {
            do { _ = try ScheduledPlanDraft.parse(broken, request: request, source: "Synthetic"); preconditionFailure("malformed plan accepted") }
            catch { print("PASS: incomplete, ambiguous, unsupported or out-of-period plan replies create no draft") }
        }
        var tooMany = draft; tooMany.actions = (0..<57).map { .init(day: 1, title: "Action \($0)") }
        check(!tooMany.isValid, "overlarge plans are rejected as a whole rather than silently losing steps")
        var duplicate = draft; duplicate.actions.append(duplicate.actions[0]); check(!duplicate.isValid, "duplicate action identities cannot reach confirmation")
        var repeated = draft; repeated.actions.append(.init(day: draft.actions[0].day, title: draft.actions[0].title)); check(!repeated.isValid, "the same action on the same day requires correction before save")
        var edit = draft; edit.actions[0].title = ""; check(!edit.isValid, "empty edited steps cannot be silently dropped during confirmation")
        for weeks in [1,2,4,8] {
            let r = ScheduledPlanRequest(goal: request.goal, startDay: request.startDay, weeks: weeks)
            let t = try ScheduledPlanDraft.template(request: r)
            check(t.isValid && t.actions.count == weeks * 3 && Set(t.actions.map { ($0.day - 1) / 7 }).count == weeks, "the explicitly selected local template covers every requested week (\(weeks))")
        }
        let huge = ScheduledPlanRequest(goal: request.goal, startDay: request.startDay, weeks: .max)
        check(!huge.isValid && huge.lastDay == nil, "unsupported or overflowing planning horizons fail safely")
        let invalid = ScheduledPlanRequest(goal: "a" + String(repeating: "\u{301}", count: 9000), startDay: request.startDay, weeks: 2)
        check(!invalid.isValid, "planning requests bound UTF-8 bytes as well as visible characters")
        let current = RecordRetrieval.text(doc)!
        check(current.contains("planned calendar day 2026-11-06") && doc.markdown.contains("Review and adapt"), "assistant retrieval and readable sharing retain current planned-day semantics")
        var snapshot = BackupSnapshot(profile: .default, goals: HealthGoals(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: PersonalHealthContext(), photos: [:])
        snapshot.documents = [doc]
        try BackupArchive.validate(snapshot)
        let roundTrip = try JSONDecoder().decode(BackupSnapshot.self, from: JSONEncoder().encode(snapshot))
        check(roundTrip.documents[0].steps.map(\.plannedDay) == doc.steps.map(\.plannedDay), "backup snapshots retain new calendar-day plans with legacy models intact")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-plan-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("plan.json")
        try ReadableExport.write(snapshot, to: file)
        let readable = try ReadableExport.read(Data(contentsOf: file))
        check(readable.snapshot.documents[0].steps.map(\.plannedDay) == doc.steps.map(\.plannedDay), "readable exports and reviewed recovery preserve planned calendar days")
        snapshot.documents[0].steps[0].plannedDay = "2026-02-30"
        do { try BackupArchive.validate(snapshot); preconditionFailure("invalid calendar day restored") } catch { print("PASS: backup validation rejects impossible planned days before restore") }
        var sameDay = draft; sameDay.actions.insert(.init(day: 1, title: "A second action on the first day"), at: 0)
        let sameDayDoc = try sameDay.document(acknowledged: true)
        check(sameDayDoc.steps.prefix(2).map(\.title) == ["A second action on the first day", "Choose one small step"], "same-day actions retain review order when the plan is confirmed")
        let later = PlanDay.date("2026-11-07", timeZone: late)!
        check(PlanSchedule.isOverdue(doc.steps[1], now: later, calendar: PlanDay.calendar(late)) && !PlanSchedule.isOverdue(doc.steps[1], now: PlanDay.date(civil, timeZone: early)!, calendar: PlanDay.calendar(early)), "overdue status compares calendar days in the caller's time zone")
        let eight = ScheduledPlanRequest(goal: request.goal, startDay: request.startDay, weeks: 8)
        let full: [String: Any] = ["version": 1, "title": "Full schedule", "reason": "Synthetic complete eight-week boundary.", "steps": (1...56).map { ["day": $0, "title": "Synthetic action \($0)"] as [String: Any] }]
        let complete = try ScheduledPlanDraft.parse(String(data: JSONSerialization.data(withJSONObject: full), encoding: .utf8)!, request: eight, source: "Synthetic")
        let completeDocument = try complete.document(acknowledged: true)
        check(complete.actions.count == 56 && completeDocument.steps.count == 56, "the full supported eight-week 56-step schedule survives parsing and confirmation without truncation")
        var overlong = draft; overlong.actions[0].title = String(repeating: "x", count: 501)
        check(!overlong.isValid, "overlong action wording stays invalid until explicitly shortened")
        check(PlanDay.string(Date(timeIntervalSince1970: .nan)).isEmpty, "non-finite dates cannot become planned calendar days")
        var done = doc
        for index in done.steps.indices { done.steps[index].isDone = true }
        check(done.status == .completed && PlanSchedule.pending([done]).isEmpty, "completing every scheduled step finishes the plan and removes it from pending actions")
    }
}
