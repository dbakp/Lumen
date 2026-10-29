import Foundation

enum RetainedEvidenceChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: .init(year: 2026, month: 10, day: 20, hour: 12))!
        let day = calendar.startOfDay(for: now), yesterday = day.addingTimeInterval(-86400)
        let blank = DisplayEvidence(day: day, capturedAt: now, values: [:])
        check(["calories","protein","water","sleep","readiness"].allSatisfy { blank.value($0, at: now, calendar: calendar) == nil }, "empty companion packets cannot create zero measurements")
        let zero = DisplayEvidence(day: day, capturedAt: now, values: ["calories":0,"water":0,"steps":0], estimates:["calories"])
        check(zero.value("water", at: now, calendar: calendar) == 0 && zero.value("protein", at: now, calendar: calendar) == nil, "snapshot presence stays independent for each metric including recorded zero")
        check(DisplayEvidence.decode(zero.encoded()) == zero, "dated presence and estimate status survive packet encoding")
        check(zero.value("water", at: day.addingTimeInterval(86400), calendar: calendar) == nil, "companion readings expire at the next calendar day rather than becoming current zeros")
        let refreshedStale = DisplayEvidence(day: yesterday, capturedAt: now, values:["water":250])
        check(refreshedStale.value("water", at: now, calendar: calendar) == nil, "a new capture time cannot freshen a previous day's observation")
        let oversizedSleep = DisplayEvidence(day:day, capturedAt:now, values:["sleep":Double(Int.max / 4)])
        check(oversizedSleep.value("sleep", at:now, calendar:calendar) == nil, "companion hour-to-second formatting cannot overflow from an oversized packet")
        let future = DisplayEvidence(day: day, capturedAt: now.addingTimeInterval(120), values:["water":250])
        check(future.value("water", at: now, calendar: calendar) == nil, "far-future capture times cannot establish current evidence")
        let invalid = DisplayEvidence(day: day, capturedAt: now, values:["water":.infinity,"calories":-1,"steps":Double(Int.max)])
        check(["water","calories","steps"].allSatisfy { invalid.value($0, at: now, calendar: calendar) == nil }, "nonfinite negative and oversized companion values stay unavailable")
        check(EvidenceFormat.amount(0, unit:"ml") == "0 ml" && EvidenceFormat.amount(nil, unit:"ml") == "Not recorded", "shared formatting distinguishes an absent amount from an explicit zero")
        check(EvidenceFormat.amount(0.001, unit:"kcal") == "<0.01 kcal" && Units.water(0.001, .imperial).hasPrefix("<") && Units.weight(0.001, .metric).hasPrefix("<"), "small positive amounts cannot round into false zeros in either unit system")
        var old = WatchSnapshot(); old.generatedAt = now; old.caloriesEaten = 1200; old.waterML = 0; old.readiness = 80
        let oldData = try JSONEncoder().encode(old)
        let oldDecoded = WatchSnapshot.decode(oldData)!
        check(oldDecoded.caloriesEaten == 1200 && oldDecoded.reading("calories", at: now, calendar: calendar) == nil && oldDecoded.currentReadiness(at: now) == nil, "legacy watch fields still decode without pretending their presence or measurement day is known")
        var modern = old; modern.observations = zero
        check(WatchSnapshot.decode(modern.encoded())?.reading("water", at: now, calendar: calendar) == 0, "new watch snapshots retain explicit zeros across transfer encoding")
        let legacyJSON = try JSONSerialization.jsonObject(with: oldData) as! [String:Any]
        check(legacyJSON["observations"] == nil, "optional packet metadata does not change the required legacy schema")
        var earlier = modern; earlier.observations?.capturedAt = now.addingTimeInterval(-60)
        check(!earlier.canReplace(modern, at:now) && modern.canReplace(earlier, at:now), "a delayed older Watch context cannot overwrite a newer cached snapshot")
        var futureSnapshot = modern; futureSnapshot.observations?.capturedAt = now.addingTimeInterval(120)
        check(!futureSnapshot.canReplace(modern, at:now) && modern.canReplace(futureSnapshot, at:now), "a far-future snapshot is rejected and cannot pin the cache against real updates")
        var scored = modern; scored.observations?.values["readiness"] = 0
        check(scored.currentReadiness(at: now) == 0, "a present readiness zero is not replaced by a missing score")
        scored.observations?.values["readiness"] = 101
        check(scored.currentReadiness(at: now) == nil, "out-of-range scores cannot become a gauge reading")
        let origin = HealthLogOrigin(conversationID:"c", messageID:"m", statement:"I drank 500 ml water", preparedBy:"Local draft", confirmedAt:now)
        var confirmed = HydrationLog(date: now, ml:500); confirmed.logOrigin = origin
        let quick = HydrationLog(date: now.addingTimeInterval(-60), ml:250)
        let futureQuick = HydrationLog(date:now.addingTimeInterval(60), ml:250)
        check(LocalHealthCorrection.latestQuickWater([confirmed], now:now, calendar:calendar) == nil, "the quick undo action cannot silently delete a conversational confirmation")
        check(LocalHealthCorrection.latestQuickWater([quick,confirmed,futureQuick], now:now, calendar:calendar)?.id == quick.id, "quick undo selects the latest eligible quick log rather than a later confirmed or future entry")
        var sleepOnly = DayMetrics.empty; sleepOnly.sleepSeconds = 0
        check(CoachingEngine.readinessIfAvailable(metrics:sleepOnly, sleepDebt:nil, workoutsToday:[], goals:HealthGoals()) == nil, "a recorded zero sleep total alone cannot expose the heuristic's default readiness score")
        sleepOnly.sleepSeconds = 8 * 3600
        check(CoachingEngine.readinessIfAvailable(metrics:sleepOnly, sleepDebt:nil, workoutsToday:[], goals:HealthGoals()) == nil, "one positive sleep total cannot expose readiness without contributing evidence")
        check(CoachingEngine.readinessIfAvailable(metrics:sleepOnly, sleepDebt:0, workoutsToday:[], goals:HealthGoals()) != nil, "a covered zero-debt estimate remains distinct from missing debt")
        func episode(_ wake: Date, hours: Double = 8, source: SleepSource = .manual) -> SleepEpisode { .init(bedtime:wake.addingTimeInterval(-hours*3600), wakeTime:wake, source:source) }
        let today = episode(day.addingTimeInterval(7*3600)), older = episode(day.addingTimeInterval(-30*86400+7*3600)), tomorrow = episode(day.addingTimeInterval(86400+7*3600))
        check(SleepEvidence.today([older,tomorrow,today], now:now, calendar:calendar)?.id == today.id, "a future sleep entry cannot hide a valid current record")
        check(SleepEvidence.latest([older,tomorrow], now:now)?.id == older.id && SleepEvidence.today([older], now:now, calendar:calendar) == nil, "older sleep stays historical and cannot become last night's current reading")
        let none = SleepEvidence.recent([older,tomorrow], now:now, calendar:calendar)
        check(none.entries.isEmpty && none.meanDuration == nil && none.recordedDays == 0, "a seven-day sleep summary leaves gaps unknown instead of borrowing old nights")
        let previous = episode(yesterday.addingTimeInterval(7*3600), hours:6)
        let recent = SleepEvidence.recent([today,previous,older,tomorrow], now:now, calendar:calendar)
        check(recent.entries.count == 2 && recent.recordedDays == 2 && recent.meanDuration == 7*3600, "recorded-entry averages use the declared calendar window and actual entry count")
        check(SleepEvidence.wakeSpread([today], now:now, calendar:calendar) == nil, "one wake time cannot establish a measured consistency spread")
        let early = episode(day.addingTimeInterval(5*60)), late = episode(yesterday.addingTimeInterval(23*3600+55*60))
        let spread = SleepEvidence.wakeSpread([early,late], now:now, calendar:calendar)
        check((spread ?? 0) > 0 && (spread ?? .infinity) < 10*60, "wake spread treats nearby times across midnight as nearby")
        var impossible = today; impossible.asleepSeconds = impossible.timeInBed + 1000
        check(!SleepEvidence.usable(impossible, now:now), "a source duration longer than its recorded window is unusable")
        check(SleepEvidence.predictionEntries([today,today,today], now:now, calendar:calendar).isEmpty, "duplicate records on one day cannot unlock a multi-day timing model")
        let third = episode(day.addingTimeInterval(-2*86400+7*3600))
        check(SleepEvidence.predictionEntries([today,previous,third], now:now, calendar:calendar).count == 3 && SleepEvidence.predictionEntries([older], now:now, calendar:calendar).isEmpty, "optional timing models require distinct recent days and a current record")
        let manualWeek = (0..<7).map { episode(day.addingTimeInterval(Double(-$0)*86400+7*3600)) }
        check(SleepEvidence.needEstimationEntries(manualWeek, now:now, calendar:calendar).isEmpty, "time-in-bed logs cannot silently train a measured-sleep target estimate")
        var measured = manualWeek
        for i in measured.indices { measured[i].source = .wearable; measured[i].asleepSeconds = 7*3600 }
        check(SleepEvidence.needEstimationEntries(measured, now:now, calendar:calendar).count == 7 && SleepEvidence.needEstimationEntries(Array(measured.prefix(4)), now:now, calendar:calendar).isEmpty, "automatic target learning requires enough distinct usable source nights")
    }
}
