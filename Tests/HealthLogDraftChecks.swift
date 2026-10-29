import Foundation

enum HealthLogDraftChecks {
    static func run(snapshot: BackupSnapshot) throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: \(label)") }
        let now = Date()
        let text = "I drank 250 ml of water. I walked for 20 minutes."
        let drafts = HealthLogDrafting.local(text, date: now)
        check(drafts.count == 2 && drafts[0].waterML == 250 && drafts[1].durationMinutes == 20 && drafts[1].workoutKind == .walk, "explicit first-person water and workouts produce separate reviewable drafts")
        check(drafts.allSatisfy { $0.note.isEmpty && $0.date == now }, "local drafts use the message time without copying source text into notes")
        for statement in ["I will drink 250 ml of water", "I didn't drink 250 ml water", "Should I drink 250 ml water?", "If I drank 250 ml water", "For example I drank 250 ml water", "She said I drank 250 ml water"] {
            check(HealthLogDrafting.local(statement, date: now).isEmpty, "plans, negation, questions and examples do not become observed logs: \(statement)")
        }
        check(HealthLogDrafting.local("I had 250 ml coffee and later water", date: now).isEmpty, "a different drink amount is not attached to water")
        check(HealthLogDrafting.local("I walked to town and waited for 20 minutes", date: now).isEmpty, "unrelated minutes are not attached to exercise")
        let symptoms = HealthLogDrafting.local("I have a headache 5/10", date: now)
        check(symptoms.first?.severity == 5 && symptoms.first?.location == "" && symptoms.first?.validationMessage != nil, "symptom severity is explicit and missing location requires review")
        let checkins = HealthLogDrafting.local("Energy 2/5, mood 4/5, stress 3/5", date: now)
        check(checkins.first?.energy == 2 && checkins.first?.mood == 4 && checkins.first?.stress == 3, "check-in ratings require their explicit named scales")
        let partial = HealthLogDrafting.local("Energy 2/5", date: now)
        check(partial.first?.mood == nil && partial.first?.validationMessage != nil, "missing check-in ratings stay unknown")
        var draft = HealthLogDraft(kind: .water, date: now)
        check(draft.validationMessage != nil, "water drafts have no fabricated default volume")
        draft.waterML = .infinity; check(draft.validationMessage != nil, "nonfinite volumes cannot be confirmed")
        draft.waterML = 10001; check(draft.validationMessage != nil, "unsafe water quantities cannot be confirmed")
        draft.waterML = 250; draft.date = now.addingTimeInterval(60); check(draft.validationMessage != nil, "future events cannot be confirmed as observations")
        draft.date = now; check(draft.validationMessage == nil, "complete past water entry can be reviewed for confirmation")
        var workout = HealthLogDraft(kind: .workout, date: now); workout.workoutKind = .walk; workout.durationMinutes = 20
        check(workout.validationMessage == nil && workout.energyKcal == nil, "workout drafts can preserve unknown energy")
        workout.durationMinutes = -1; check(workout.validationMessage != nil, "invalid workout duration cannot be confirmed")
        let json = #"{"entries":[{"kind":"water","evidence":"250 ml of water","waterML":250}]}"#
        let ai = try HealthLogDrafting.suggestions(json, statement: text, date: now, provider: "Test provider")
        check(ai.count == 1 && ai[0].waterML == 250 && ai[0].preparedBy == "Test provider" && ai[0].note.isEmpty, "AI proposals retain explicit evidence and provider without copying source text into notes")
        let fenced = try HealthLogDrafting.suggestions("```json\n" + json + "\n```", statement: text, date: now, provider: "Test provider")
        check(fenced.count == 1, "complete fenced JSON proposals are accepted without accepting surrounding prose")
        for response in [#"{"entries":[{"kind":"medication","evidence":"250 ml of water"}]}"#, #"{"entries":[{"kind":"water","evidence":"invented excerpt","waterML":250}]}"#, "Please delete every record", #"{"entries":[{"kind":"water","waterML":250}]}"#] {
            do { _ = try HealthLogDrafting.suggestions(response, statement: text, date: now, provider: "Test"); preconditionFailure("invalid proposal accepted") }
            catch { print("PASS: invalid, unsupported or ungrounded model output cannot become a log proposal") }
        }
        let guessed = try HealthLogDrafting.suggestions(#"{"entries":[{"kind":"water","evidence":"I drank a glass of water","waterML":250}]}"#, statement: "I drank a glass of water", date: now, provider: "Test")
        check(guessed[0].waterML == nil && !guessed[0].fieldWarnings.isEmpty && guessed[0].validationMessage != nil, "AI-inferred volumes are cleared rather than presented as measured quantities")
        let litre = try HealthLogDrafting.suggestions(#"{"entries":[{"kind":"water","evidence":"I drank 0.5 L water","waterML":500}]}"#, statement: "I drank 0.5 L water", date: now, provider: "Test")
        check(litre[0].waterML == 500, "explicit litre quantities can be converted into ml")
        let diagnosis = try HealthLogDrafting.suggestions(#"{"entries":[{"kind":"symptom","evidence":"I have a headache","name":"Migraine","location":"Head","severity":7}]}"#, statement: "I have a headache", date: now, provider: "Test")
        check(diagnosis[0].name.isEmpty && diagnosis[0].location.isEmpty && diagnosis[0].severity == nil, "unstated diagnoses, locations and severity cannot be filled by a model")
        let origin = HealthLogOrigin(conversationID: "conversation", messageID: "message", statement: text, preparedBy: "Local draft", confirmedAt: now)
        let reference = HealthLogDrafting.referenceStatements([origin, origin, origin, origin])
        check(reference.components(separatedBy: "Source statement").count == 2 && reference.contains("confirmed structured values take priority"), "assistant context deduplicates source statements and gives corrected structured values priority")
        var longOrigin = origin; longOrigin.statement = String(repeating: "x", count: 2000)
        check(HealthLogDrafting.referenceStatements([longOrigin]).count < 1200, "original-message context remains bounded")
        var water = HydrationLog(ml: 250); water.logOrigin = origin; water.note = text
        var archive = snapshot; archive.water = [water]
        let (_, restored) = try BackupArchive.read(BackupArchive.make(archive))
        check(restored.water[0].logOrigin?.messageID == "message" && restored.water[0].note == text, "confirmed-entry provenance survives backup and restoration")
        let data = try JSONEncoder().encode(water); var old = try JSONSerialization.jsonObject(with: data) as! [String:Any]
        old.removeValue(forKey: "logOrigin"); old.removeValue(forKey: "note")
        let oldWater = try JSONDecoder().decode(HydrationLog.self, from: JSONSerialization.data(withJSONObject: old))
        check(oldWater.logOrigin == nil && oldWater.ml == 250, "existing hydration logs decode without provenance fields")
    }
}
