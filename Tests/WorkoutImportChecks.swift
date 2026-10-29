import Foundation

enum WorkoutImportChecks {
    static func run(in directory: URL, snapshot: BackupSnapshot) throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); print("PASS: \(label)")
        }
        func parse(_ xml: String) throws -> HealthImportPreview {
            let url = directory.appendingPathComponent("workouts.xml")
            try ("<HealthData>" + xml + "</HealthData>").write(to: url, atomically: true, encoding: .utf8)
            return try HealthImportService.parse(url: url)
        }
        let attributes = "workoutActivityType=\"HKWorkoutActivityTypeRunning\" sourceName=\"Fixture Watch\" startDate=\"2026-01-01 10:00:00 +0000\" endDate=\"2026-01-01 11:00:00 +0000\" duration=\"45\" durationUnit=\"min\""
        let session = "<Workout \(attributes)/>"
        let preview = try parse(session + session)
        check(preview.days.isEmpty && preview.coveredDays.count == 1 && preview.workouts.count == 1, "workout-only exports are accepted and duplicate sessions kept once")
        let workout = preview.workouts[0]
        check(workout.duration == 2700, "reported workout duration preserves pauses")
        check(workout.energyKcal == nil && workout.energyDescription == "Energy not provided", "missing energy remains unknown without a MET estimate")
        check(workout.sourceDescription == "Health export · Fixture Watch", "export workout source is retained")
        let stats = try parse("<Workout \(attributes)><WorkoutStatistics type=\"HKQuantityTypeIdentifierActiveEnergyBurned\" sum=\"418.4\" unit=\"kJ\"/><WorkoutStatistics type=\"HKQuantityTypeIdentifierDistanceWalkingRunning\" sum=\"5\" unit=\"km\"/><WorkoutStatistics type=\"HKQuantityTypeIdentifierHeartRate\" average=\"140\" unit=\"count/min\"/><WorkoutActivity><WorkoutStatistics type=\"HKQuantityTypeIdentifierActiveEnergyBurned\" sum=\"999\" unit=\"kcal\"/></WorkoutActivity></Workout>")
        let measured = stats.workouts[0]
        check(abs((measured.energyKcal ?? 0) - 100) < 0.001 && measured.distanceM == 5000 && measured.avgHR == 140, "workout root statistics convert units and ignore nested activity totals")
        check(measured.id == workout.id, "workout identity remains stable when measurements change")
        check(WorkoutReconciliation.merge([measured], into: [workout]).count == 1, "reimporting measured sessions is idempotent")
        check(WorkoutReconciliation.merge([measured], into: [workout])[0].distanceM == 5000, "reimport updates imported session details")
        var live = measured; live.id = "live"; live.importOrigin = nil
        check(WorkoutReconciliation.merge([workout], into: [live])[0].id == "live", "live source takes priority over an exported copy")
        check(WorkoutReconciliation.merge([live], into: [workout])[0].id == "live", "live sync replaces an imported duplicate")
        check(WorkoutReconciliation.merge([measured], into: [workout], preferExisting: true)[0].distanceM == nil, "backup reconciliation keeps the local session")
        var manual = live; manual.id = "manual"; manual.source = .manual
        check(WorkoutReconciliation.merge([workout], into: [manual]).count == 2, "matching user-entered sessions are preserved")
        var nearby = live; nearby.id = "nearby"; nearby.start = nearby.start.addingTimeInterval(120)
        check(WorkoutReconciliation.merge([nearby], into: [workout]).count == 2, "nearby distinct sessions are not merged by a ten-minute heuristic")
        let invalidField = try parse("<Workout \(attributes) totalEnergyBurned=\"100\" totalEnergyBurnedUnit=\"bananas\"/>")
        check(invalidField.workouts[0].energyKcal == nil && invalidField.workoutFieldWarnings == 1, "bad optional units preserve workout with a review warning")
        let conflicting = try parse("<Workout \(attributes)>" + ["100", "200", "100"].map { "<WorkoutStatistics type=\"HKQuantityTypeIdentifierActiveEnergyBurned\" sum=\"\($0)\" unit=\"kcal\"/>" }.joined() + "</Workout>")
        check(conflicting.workouts[0].energyKcal == nil, "conflicting repeated statistics remain unknown after further repeats")
        let fallback = try parse(session.replacingOccurrences(of: " duration=\"45\" durationUnit=\"min\"", with: ""))
        check(fallback.workouts[0].duration == 3600 && fallback.workouts[0].importOrigin?.durationWasReported == false, "elapsed duration fallback is explicit in provenance")
        let other = try parse(session.replacingOccurrences(of: "Running", with: "Pickleball"))
        check(other.workouts[0].kind == .other && other.workouts[0].title == "Pickleball", "additional Apple activity types retain their identity")
        let differentOther = try parse(session.replacingOccurrences(of: "Running", with: "Tennis"))
        check(!WorkoutReconciliation.sameSession(other.workouts[0], differentOther.workouts[0]), "different unclassified activities are not merged")
        var nearExport = workout; nearExport.id = "different-export"; nearExport.start = workout.start.addingTimeInterval(30)
        check(!WorkoutReconciliation.sameSession(workout, nearExport), "different same-source export identities stay separate")
        let invalidDurations = try parse(session + session.replacingOccurrences(of: "duration=\"45\"", with: "duration=\"90\"") + session.replacingOccurrences(of: "2026-01-01 10:00:00", with: "2026-02-30 10:00:00"))
        check(invalidDurations.workouts.count == 1 && invalidDurations.skipped == 2, "impossible dates and duration beyond elapsed time are skipped")
        let oldStyle = try parse(session.replacingOccurrences(of: "/>", with: " totalEnergyBurned=\"125\" totalEnergyBurnedUnit=\"kcal\" totalDistance=\"3.1\" totalDistanceUnit=\"mi\"/>"))
        check(oldStyle.workouts[0].energyKcal == 125 && abs((oldStyle.workouts[0].distanceM ?? 0) - 4988.9664) < 0.01, "legacy workout totals retain explicit units")
        let manyURL = directory.appendingPathComponent("many-workouts.xml")
        try ("<HealthData>" + String(repeating: session, count: 1100) + "</HealthData>").write(to: manyURL, atomically: true, encoding: .utf8)
        let cancelWorkouts = HealthImportControl()
        do {
            _ = try HealthImportService.parse(url: manyURL, control: cancelWorkouts, progress: { if $0 >= 512 { cancelWorkouts.cancel() } })
            preconditionFailure("workout cancellation ignored")
        } catch is CancellationError { print("PASS: cancellation during workout parsing discards the partial preview") }
        let encoded = try JSONEncoder().encode(measured)
        let decoded = try JSONDecoder().decode(Workout.self, from: encoded)
        check(decoded.importOrigin?.activityType == measured.importOrigin?.activityType && decoded.energyKcal == measured.energyKcal, "new workout metadata survives persistence")
        var old = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        for key in ["importOrigin", "energyKnown", "energyIsEstimate"] { old.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(Workout.self, from: JSONSerialization.data(withJSONObject: old))
        check(legacy.importOrigin == nil && legacy.activeCalories == measured.activeCalories, "existing workout records still decode")
        var archiveSnapshot = snapshot
        archiveSnapshot.workouts = [measured]
        archiveSnapshot.importedDays = [ImportedHealthDay(date: Calendar.current.startOfDay(for: measured.start), values: ["spo2":98], sources: ["spo2":"Fixture Watch"])]
        let archiveData = try BackupArchive.make(archiveSnapshot)
        let (_, restored) = try BackupArchive.read(archiveData)
        check(restored.workouts[0].importOrigin?.sourceName == "Fixture Watch" && restored.importedDays[0].values["spo2"] == 98, "backup round trip retains imported workouts and added health signals")
        var localSnapshot = snapshot; localSnapshot.workouts = [live]
        let merged = restored.merging(into: localSnapshot, restorePreferences: false)
        check(merged.workouts.count == 1 && merged.workouts[0].id == live.id, "backup restore reconciles exported copies without replacing live local records")
        check(restored.conflicts(with: localSnapshot) >= 1, "backup preview counts a matching physical session as a conflict")
        func record(_ type: String, _ value: String, _ unit: String, hour: Int = 10) -> String {
            "<Record type=\"HKQuantityTypeIdentifier\(type)\" value=\"\(value)\" unit=\"\(unit)\" startDate=\"2026-01-01 \(hour):00:00 +0000\" endDate=\"2026-01-01 \(hour):00:00 +0000\" sourceName=\"Fixture Watch\"/>"
        }
        let vitals = try parse(record("OxygenSaturation", "0.98", "%") + record("OxygenSaturation", "0.96", "%", hour: 11) + record("BodyFatPercentage", "0.23", "%") + record("RespiratoryRate", "0.25", "count/s") + record("VO2Max", "44", "ml/(kg*min)") + record("BodyMassIndex", "22", "count") + record("HeartRate", "100", "count/min") + record("HeartRate", "120", "count/min", hour: 11))
        let values = vitals.days[0].values
        check(abs((values["spo2"] ?? 0) - 97) < 0.001 && values["bodyFat"] == 23, "XML HealthKit fraction percentages become display percentages")
        check(values["respiratoryRate"] == 15 && values["vo2max"] == 44 && values["bmi"] == 22, "additional health signals use explicit canonical units")
        check(values["heartRate"] == 110, "discrete samples use a mean rather than a sum")
        let invalid = try parse(session + record("OxygenSaturation", "98", "%"))
        check(invalid.days.isEmpty && invalid.skipped == 1, "invalid HealthKit XML fraction is not guessed as a percentage")
        let csvURL = directory.appendingPathComponent("vitals.csv")
        try "date,metric,value,unit,source\n2026-01-01,spo2,98,%,Fixture\n2026-01-01,bodyFat,0.23,fraction,Fixture\n".write(to: csvURL, atomically: true, encoding: .utf8)
        let csv = try HealthImportService.parse(url: csvURL)
        check(csv.days[0].values["spo2"] == 98 && csv.days[0].values["bodyFat"] == 23, "portable percentages are display values or explicit fractions")
        check(ImportedMetrics.displayUnit("bmi").isEmpty && ImportedMetrics.displayUnit("spo2") == "%", "BMI is unitless while percentage readings retain their unit")
        let control = HealthImportControl(); control.cancel()
        do { _ = try HealthImportService.parse(url: csvURL, control: control); preconditionFailure("cancel ignored") }
        catch is CancellationError { print("PASS: expanded imports preserve cancellation") }
    }
}
