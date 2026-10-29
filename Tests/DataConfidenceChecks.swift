import Foundation

enum DataConfidenceChecks {
    static func run(snapshot backup: BackupSnapshot) throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { guard condition() else { fatalError("FAIL: " + label) }; print("PASS: " + label) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 20, hour: 12))!
        let day = calendar.startOfDay(for: now), yesterday = day.addingTimeInterval(-86400)
        func query(_ outcome: HealthMetricQuery.Outcome) -> HealthMetricQuery { .init(start: day, end: now, checkedAt: now, outcome: outcome) }
        func live(_ value: Double, start: Date? = nil, aggregate: HealthMetricComponent.Aggregation = .total) -> HealthMetricReading {
            .init(components: [.init(value: value, origin: .healthKit, source: "Apple Health · Watch", start: start ?? day, end: now, lastSampleAt: aggregate == .latest ? now : nil, checkedAt: now, aggregation: aggregate)], healthQuery: query(.recorded))
        }
        func resolve(_ snapshot: DayMetrics = .empty, imported: ImportedHealthDay? = nil, meals: [Meal] = [], water: [HydrationLog] = [], workouts: [Workout] = [], sleep: SleepEpisode? = nil) -> DayMetrics {
            CurrentHealthEvidence.resolve(snapshot: snapshot, imported: imported, meals: meals, water: water, workouts: workouts, sleep: sleep, now: now, calendar: calendar)
        }
        var empty = DayMetrics.empty; empty.date = day
        check(CurrentHealthEvidence.standHours([], start: day, end: now, calendar: calendar) == nil && CurrentHealthEvidence.standHours([.init(start: day, stood: false)], start: day, end: now, calendar: calendar) == 0, "stand-hour absence is distinct from an explicitly recorded idle hour")
        check(CurrentHealthEvidence.standHours([.init(start: day, stood: true), .init(start: day.addingTimeInterval(60), stood: true), .init(start: day.addingTimeInterval(3600), stood: true)], start: day, end: now, calendar: calendar) == 2, "qualifying stand/roll hours deduplicate overlapping source records instead of summing standing duration")
        var legacyStand = empty; legacyStand.standHours = 6
        check(resolve(legacyStand).reading("stand").value == nil, "legacy standing-duration totals cannot be relabelled as qualifying stand-hour counts")
        let zeroFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: zeroFile) }
        try "date,metric,value,unit,source\n2026-01-20,steps,0,count,Zero fixture\n2026-01-20,exercise,0,min,Zero fixture\n2026-01-20,water,0,ml,Zero fixture\n".write(to: zeroFile, atomically: true, encoding: .utf8)
        let parsedZero = try HealthImportService.parse(url: zeroFile)
        check(parsedZero.samples == 3 && parsedZero.days[0].values["steps"] == 0 && parsedZero.days[0].values["water"] == 0, "the real portable import parser preserves explicit activity and water zeros")
        check(HealthMetricCatalog.number(0.001) != "0" && HealthMetricCatalog.display(0, key: "water") == "0 ml", "display precision never rounds a small positive reading into a recorded zero")
        let blank = resolve(empty)
        check(HealthMetricCatalog.keys.allSatisfy { blank.reading($0).value == nil }, "empty current metrics remain unknown in every supported category")
        check(HealthContextPrompt.intakeReply(metrics: blank).contains("Water: unknown") && !HealthContextPrompt.intakeReply(metrics: blank).contains("0 ml"), "the built-in food response never invents zero intake")
        let prompt = HealthContextPrompt.make(metrics: blank, readiness: nil, goals: .init(), workouts: [], estimatedSleepDebt: nil, now: now)
        check(prompt.contains("Steps: unknown") && prompt.contains("Estimated sleep debt: unknown") && !prompt.contains("75 kg"), "assistant context separates missing readings and absent sleep coverage from profile defaults")
        check(prompt.contains("Never recreate missing observations") && prompt.contains("Completing Health authorization never proves read access"), "assistant context protects deleted entries and does not infer read authorization")
        var zero = empty; zero.excludesLumenNutrition = true
        for key in ["steps", "activeEnergy", "exercise", "water", "calories", "protein"] { zero.setReading(live(0), for: key) }
        let imported = ImportedHealthDay(date: day, values: ["steps": 8000, "activeEnergy": 600, "exercise": 45, "water": 2000, "calories": 1800, "protein": 80, "weight": 71], sources: ["weight": "Scale export"])
        let resolvedZero = resolve(zero, imported: imported)
        check(["steps", "activeEnergy", "exercise", "water", "calories", "protein"].allSatisfy { resolvedZero.reading($0).value == 0 }, "the production resolver preserves recorded live zeros over imports across activity, hydration and nutrition")
        check(resolvedZero.reading("weight").value == 71 && resolvedZero.reading("weight").components.first?.origin == .healthImport, "missing live types use a dated imported source independently")
        check(HealthContextPrompt.readingLine("steps", metrics: resolvedZero).contains("Steps: 0 steps"), "assistant context preserves a genuine recorded zero")
        var unavailable = empty
        unavailable.setReading(.init(healthQuery: query(.noData)), for: "steps")
        unavailable.setReading(.init(healthQuery: query(.failed)), for: "water")
        let fallback = resolve(unavailable, imported: imported)
        check(fallback.reading("steps").value == 8000 && fallback.reading("steps").healthQuery?.outcome == .noData, "import fallback retains the actual no-data Health query outcome")
        check(fallback.reading("water").value == 2000 && fallback.reading("water").healthQuery?.outcome == .failed, "import fallback retains a failed query instead of claiming live availability")
        check(HealthContextPrompt.readingLine("steps", metrics: fallback).contains("read permission is unknown"), "empty Health queries are described without asserting denied or granted access")
        check(live(10).components[0].lastSampleAt == nil && live(10).components[0].periodDescription.contains("Latest sample time is unavailable"), "aggregate query windows never masquerade as latest sample dates")
        var legacy = empty; legacy.steps = 1200; legacy.weightKg = 75; legacy.vo2max = 48; legacy.hrvMS = 50; legacy.dietaryCalories = 0
        let migrated = resolve(legacy)
        check(migrated.steps == 1200 && migrated.reading("steps").components.first?.origin == .legacyCache && migrated.dietaryCalories == 0, "legacy daily totals remain readable with explicitly unknown source/check time")
        check(migrated.weightKg == nil && migrated.vo2max == nil && migrated.hrvMS == nil, "undated legacy discrete readings cannot become current observations")
        var stale = empty; stale.date = yesterday; stale.setReading(live(900), for: "steps")
        check(resolve(stale).reading("steps").value == nil, "yesterday's persisted snapshot expires at the day boundary")
        var staleSample = empty; staleSample.setReading(live(71, start: yesterday, aggregate: .latest), for: "weight")
        check(resolve(staleSample).weightKg == nil, "a query timestamp today cannot relabel an older sample as today's weight")
        var futureSample = empty; futureSample.setReading(live(71, start: now.addingTimeInterval(60), aggregate: .latest), for: "weight")
        check(resolve(futureSample).weightKg == nil, "future or reversed sample intervals cannot establish a current measurement")
        var corrupt = empty; corrupt.setReading(live(.infinity), for: "steps")
        check(resolve(corrupt).reading("steps").value == nil && resolve(corrupt).steps == 0, "invalid source values remain unavailable and safe for legacy numeric consumers")
        var old = empty; old.setReading(live(100), for: "steps")
        var failedRefresh = empty; failedRefresh.setReading(.init(healthQuery: query(.failed)), for: "steps")
        let retained = CurrentHealthEvidence.merging(failedRefresh, into: old, now: now, calendar: calendar)
        check(retained.reading("steps").value == 100 && retained.reading("steps").healthQuery?.outcome == .failed && retained.reading("steps").components.first?.checkedAt == now, "failed refreshes retain dated cached evidence and expose the failure separately")
        failedRefresh.setReading(.init(healthQuery: query(.noData)), for: "steps")
        check(CurrentHealthEvidence.merging(failedRefresh, into: old, now: now, calendar: calendar).reading("steps").value == nil, "a successful empty read clears the prior current value")
        var localWeight = empty
        localWeight.setReading(.init(components: [.init(value: 72, origin: .localLog, source: "Lumen weight log", start: now, end: now, lastSampleAt: now, aggregation: .latest)]), for: "weight")
        check(CurrentHealthEvidence.merging(empty, into: localWeight, now: now, calendar: calendar).weightKg == 72, "a local weight observation survives an empty Health refresh")
        let origin = HealthLogOrigin(conversationID: "test-conversation", messageID: "test-message", statement: "I drank 250 ml of water. I walked for 20 minutes.", preparedBy: "Local draft", confirmedAt: now.addingTimeInterval(-3600))
        var glass = HydrationLog(id: "confirmed-water", date: now.addingTimeInterval(-3600), ml: 250); glass.logOrigin = origin
        var workout = Workout(id: "confirmed-workout", kind: .walk, title: "Walk", start: now.addingTimeInterval(-3600), duration: 1200, activeCalories: 0, source: .manual)
        workout.energyKnown = false; workout.logOrigin = origin
        let localOnly = resolve(empty, water: [glass], workouts: [workout])
        check(localOnly.waterML == 250 && localOnly.exerciseMin == 20 && localOnly.reading("activeEnergy").value == nil, "local water and workout duration update the shared resolver without inventing unknown workout energy")
        let mixed = resolve(zero, imported: imported, water: [glass], workouts: [workout])
        check(mixed.exerciseMin == 20 && mixed.waterML == 250 && mixed.reading("activeEnergy").value == 0, "local records combine with actual per-metric live readings while unknown energy contributes nothing")
        let overlap = resolve(empty, imported: imported, water: [glass], workouts: [workout])
        check(overlap.waterML == 2000 && overlap.exerciseMin == 45 && overlap.reading("water").overlapKeptSeparate, "potential import/local overlap is disclosed and never summed")
        let meal = Meal(date: now, type: .lunch, items: [.init(name: "Recorded meal", grams: 100, calories: 400, proteinG: 20, carbsG: 0, fatG: 0)])
        let food = resolve(zero, imported: imported, meals: [meal])
        check(food.dietaryCalories == 400 && food.dietaryProtein == 20 && food.reading("carbs").value == 0, "meal totals count once and preserve explicitly logged zero nutrients")
        let futureGlass = HydrationLog(date: now.addingTimeInterval(60), ml: 250)
        check(resolve(empty, water: [futureGlass]).reading("water").value == nil, "future local logs are excluded from current context")
        var waterDraft = HealthLogDraft(kind: .water, date: now.addingTimeInterval(-1800)); waterDraft.waterML = 500; waterDraft.note = "Corrected amount"
        let correctedWater = try LocalHealthCorrection.water(id: glass.id, draft: waterDraft, records: [glass], now: now)
        check(correctedWater.count == 1 && correctedWater[0].id == glass.id && correctedWater[0].ml == 500 && correctedWater[0].logOrigin?.statement == origin.statement && correctedWater[0].logOrigin?.confirmedAt == origin.confirmedAt && correctedWater[0].lastEditedAt == now, "water correction preserves record and original confirmation provenance with a separate edit time")
        check(resolve(empty, water: correctedWater).waterML == 500, "corrected water reaches dependent totals through the production resolver")
        var workoutDraft = HealthLogDraft(kind: .workout, date: workout.start); workoutDraft.workoutKind = .walk; workoutDraft.name = "Evening walk"; workoutDraft.durationMinutes = 35
        let correctedWorkout = try LocalHealthCorrection.workout(id: workout.id, draft: workoutDraft, records: [workout], now: now)
        check(correctedWorkout[0].id == workout.id && correctedWorkout[0].duration == 2100 && correctedWorkout[0].energyKcal == nil && correctedWorkout[0].logOrigin?.messageID == origin.messageID && correctedWorkout[0].lastEditedAt == now, "workout correction preserves identity/provenance and leaves blank energy unknown")
        workoutDraft.energyKcal = 0
        let recordedEnergyZero = try LocalHealthCorrection.workout(id: workout.id, draft: workoutDraft, records: [workout], now: now)
        check(resolve(empty, workouts: recordedEnergyZero).reading("activeEnergy").value == 0, "a user-confirmed energy zero remains distinct from an empty energy field after correction")
        var earlierWater = waterDraft; earlierWater.date = yesterday
        let movedWater = try LocalHealthCorrection.water(id: glass.id, draft: earlierWater, records: [glass], now: now)
        check(movedWater[0].date == yesterday && resolve(empty, water: movedWater).reading("water").value == nil && movedWater[0].logOrigin?.statement == origin.statement, "moving a correction to yesterday retains provenance and removes it from today's totals")
        var earlierWorkout = workoutDraft; earlierWorkout.date = yesterday
        let movedWorkout = try LocalHealthCorrection.workout(id: workout.id, draft: earlierWorkout, records: [workout], now: now)
        check(movedWorkout[0].start == yesterday && resolve(empty, workouts: movedWorkout).reading("exercise").value == nil, "moving a workout date updates current exercise without deleting the historical entry")
        check(CurrentHealthEvidence.workoutEnergyByDay(correctedWorkout, now: now, calendar: calendar).isEmpty, "workout charts omit sessions whose energy was left unknown")
        let zeroDays = CurrentHealthEvidence.workoutEnergyByDay(recordedEnergyZero, now: now, calendar: calendar)
        check(zeroDays.count == 1 && zeroDays[0].date == day && zeroDays[0].kcal == 0, "workout charts retain one recorded zero without inventing six other zero days")
        var futureWorkout = recordedEnergyZero[0]; futureWorkout.start = now.addingTimeInterval(60)
        check(CurrentHealthEvidence.recentWorkouts([futureWorkout], now: now, calendar: calendar).isEmpty, "future workouts cannot inflate past-week counts or charts")
        var legacyZeroWorkout = recordedEnergyZero[0]; legacyZeroWorkout.energyKnown = nil
        check(legacyZeroWorkout.energyKcal == nil && recordedEnergyZero[0].energyKcal == 0, "an ambiguous legacy workout zero stays unknown while an explicit correction zero stays recorded")
        check(HealthLogDrafting.preparationDescription("Local draft") == "Prepared on this iPhone" && HealthLogDrafting.preparationDescription("Provider").contains("Provider"), "provenance uses plain local preparation copy and retains a named provider")
        let historyUnknown = TrendEvidence.includingLocal([], workouts: movedWorkout, water: movedWater, sleep: [], since: yesterday, now: now, calendar: calendar)
        check(historyUnknown.first?.values["exercise"] == 35 && historyUnknown.first?.values["water"] == 500 && historyUnknown.first?.values["activeEnergy"] == 0, "corrected dates and explicit zero energy reach historical Insights evidence")
        let blankHistory = TrendEvidence.includingLocal([], workouts: [], water: [], sleep: [], since: yesterday, now: now, calendar: calendar)
        check(blankHistory.isEmpty, "deleting local records removes historical totals instead of retaining stale days")
        var unknownEnergyYesterday = correctedWorkout[0]; unknownEnergyYesterday.start = yesterday
        let unknownHistory = TrendEvidence.includingLocal([], workouts: [unknownEnergyYesterday], water: [], sleep: [], since: yesterday, now: now, calendar: calendar)
        check(unknownHistory.first?.values["exercise"] == 35 && unknownHistory.first?.values["activeEnergy"] == nil, "historical exercise remains available while missing workout energy stays unknown")
        let externalZero = ImportedHealthDay(date: yesterday, values: ["water": 0, "activeEnergy": 0], sources: ["water": "Export", "activeEnergy": "Apple Health"])
        let preservedSource = TrendEvidence.includingLocal([externalZero], workouts: [], water: [], sleep: [], since: yesterday, now: now, calendar: calendar)
        check(preservedSource.first?.values["water"] == 0 && preservedSource.first?.values["activeEnergy"] == 0, "deleting local logs preserves separate external recorded-zero history")
        let deletedWater = try LocalHealthCorrection.water(id: glass.id, draft: nil, records: correctedWater, now: now)
        let deletedWorkout = try LocalHealthCorrection.workout(id: workout.id, draft: nil, records: correctedWorkout, now: now)
        let afterDelete = resolve(empty, water: deletedWater, workouts: deletedWorkout)
        check(deletedWater.isEmpty && deletedWorkout.isEmpty && afterDelete.reading("water").value == nil && afterDelete.reading("exercise").value == nil, "deleting confirmed local entries removes dependent current readings rather than recording zeros")
        check(HealthContextPrompt.intakeReply(metrics: afterDelete).contains("Water: unknown"), "deletion immediately removes the amount from the assistant's intake summary")
        var external = workout; external.source = .healthKit
        var importedWorkout = workout; importedWorkout.importOrigin = .init(sourceName: "Export", activityType: "Walk", end: now)
        for protected in [external, importedWorkout] {
            do { _ = try LocalHealthCorrection.workout(id: protected.id, draft: workoutDraft, records: [protected], now: now); fatalError("external workout edited") }
            catch LocalHealthCorrection.Failure.protectedRecord { print("PASS: external and imported workouts reject local correction") }
        }
        do { _ = try LocalHealthCorrection.water(id: "quick-water", draft: waterDraft, records: [.init(id: "quick-water", date: now, ml: 250)], now: now); fatalError("write-back water edited as local-only") }
        catch LocalHealthCorrection.Failure.protectedRecord { print("PASS: quick water cannot be mistaken for a local-only conversational confirmation") }
        waterDraft.waterML = -1
        do { _ = try LocalHealthCorrection.water(id: glass.id, draft: waterDraft, records: [glass], now: now); fatalError("invalid correction accepted") }
        catch LocalHealthCorrection.Failure.invalid { print("PASS: invalid corrections leave original arrays untouched") }
        check(glass.ml == 250 && workout.duration == 1200, "validation operates on copies and never mutates caller state on failure")
        var editedBackup = backup; editedBackup.water = correctedWater; editedBackup.workouts = correctedWorkout
        let restored = try BackupArchive.read(BackupArchive.make(editedBackup)).1
        check(restored.water[0].lastEditedAt == now && restored.workouts[0].lastEditedAt == now && restored.water[0].logOrigin?.statement == origin.statement, "backup version 1 preserves correction timestamps and original provenance")
        let encoded = try JSONEncoder().encode(resolvedZero)
        let decoded = try JSONDecoder().decode(DayMetrics.self, from: encoded)
        check(decoded.reading("steps") == resolvedZero.reading("steps") && decoded.reading("weight") == resolvedZero.reading("weight"), "per-metric query, source and precision evidence survives snapshot persistence")
        var oneBodySignal = blank; oneBodySignal.setReading(live(50, aggregate: .latest), for: "hrv")
        let uncertainReadiness = CoachingEngine.readiness(metrics: oneBodySignal, sleepDebt: nil, workoutsToday: [], goals: .init())
        check(!uncertainReadiness.factors.contains { $0.id == "sleep" || $0.detail.contains("well rested") }, "readiness never treats missing sleep-debt coverage as zero debt or proven rest")
        let knownDebt = CoachingEngine.readiness(metrics: oneBodySignal, sleepDebt: 0, workoutsToday: [], goals: .init())
        check(knownDebt.factors.contains { $0.id == "sleep" && $0.detail.contains("14 recorded nights") }, "a covered zero sleep-debt estimate retains its recorded-window qualification")
        let uncertainPlan = CoachingEngine.dayPlan(metrics: blank, readiness: nil, goals: .init(), sleepDebt: nil, eaten: 0, protein: 0, waterML: 0)
        check(uncertainPlan.bullets.contains { $0.contains("Protein intake is unknown") } && uncertainPlan.bullets.contains { $0.contains("Water intake is unknown") }, "generated wellness plans cannot interpret missing intake as a measured deficit")
        check(HealthLogDrafting.amount("500") == 500 && HealthLogDrafting.amount("0") == 0 && HealthLogDrafting.amount("") == nil && HealthLogDrafting.amount("1,50", decimalSeparator: ",") == 1.5, "amount input preserves trailing zeros, explicit zero, empty values and locale decimal separators")
        check(HealthLogDrafting.amount("invalid")?.isNaN == true, "invalid nonempty amount input stays invalid instead of silently becoming an optional blank")
        var oversizedSleep = empty; oversizedSleep.setReading(live(Double(Int.max / 4)), for: "sleep")
        check(resolve(oversizedSleep).sleepSeconds == nil && resolve(oversizedSleep).reading("sleep").value == nil, "hour-to-second conversion rejects oversized sleep readings before native integer consumers")
        var tinyEnergy = recordedEnergyZero[0]; tinyEnergy.activeCalories = 0.001
        check(tinyEnergy.energyDescription == "<0.01 kcal", "workout details never round a small positive corrected energy value into zero")
        tinyEnergy.activeCalories = .infinity
        check(tinyEnergy.energyKcal == nil && tinyEnergy.energyDescription == "Energy not provided", "nonfinite workout energy cannot reach native integer or chart consumers")
        var nights: [SleepEpisode] = []
        for offset in 0..<14 {
            let wake = day.addingTimeInterval(Double(-offset) * 86400 + 7 * 3600)
            nights.append(.init(bedtime: wake.addingTimeInterval(-8 * 3600), wakeTime: wake, source: .manual))
        }
        check(CurrentHealthEvidence.hasCompleteSleepWindow(nights, now: now, calendar: calendar) && !CurrentHealthEvidence.hasCompleteSleepWindow(Array(nights.dropFirst()), now: now, calendar: calendar), "sleep-debt context requires fourteen actual calendar nights rather than zero-filled gaps")
        check(!CurrentHealthEvidence.hasCompleteSleepWindow(nights + [nights[0]], now: now, calendar: calendar), "ambiguous duplicate sleep nights cannot establish complete debt coverage")
        check(CurrentHealthEvidence.estimatedSleepDebt(nights, sleepNeed: 8 * 3600, now: now, calendar: calendar) == 0 && CurrentHealthEvidence.estimatedSleepDebt(Array(nights.dropFirst()), sleepNeed: 8 * 3600, now: now, calendar: calendar) == nil, "sleep-debt calculation uses a complete recorded calendar window and preserves a covered zero")
        let futureNight = SleepEpisode(bedtime: now.addingTimeInterval(3600), wakeTime: now.addingTimeInterval(7200), source: .manual)
        var shorterNights = nights; shorterNights[0].bedtime = shorterNights[0].wakeTime.addingTimeInterval(-6 * 3600)
        let coveredDebt = CurrentHealthEvidence.estimatedSleepDebt(shorterNights, sleepNeed: 8 * 3600, now: now, calendar: calendar)
        check((coveredDebt ?? 0) > 0 && CurrentHealthEvidence.estimatedSleepDebt([futureNight] + shorterNights.reversed(), sleepNeed: 8 * 3600, now: now, calendar: calendar) == coveredDebt, "future nights and input ordering cannot contaminate a nonzero completed-night estimate")
        var invalidNight = nights[0]; invalidNight.asleepSeconds = -1
        check(CurrentHealthEvidence.estimatedSleepDebt(nights + [invalidNight], sleepNeed: 8 * 3600, now: now, calendar: calendar) == nil, "an extra unusable night cannot be ignored to claim an unambiguous sleep-debt window")
        let sleep = resolve(empty, sleep: nights[0])
        check(sleep.sleepSeconds == 8 * 3600 && sleep.reading("sleep").isEstimate && sleep.reading("sleep").components[0].origin == .sleepHistory && sleep.reading("sleep").components[0].lastSampleAt == nights[0].wakeTime, "manual overnight sleep retains its actual wake date and time-in-bed estimate status")
    }
}
