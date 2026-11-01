import Foundation

enum ProfileSettingsChecks {
    static func run() throws {
        func check(_ condition: Bool, _ label: String) { precondition(condition, label); print("PASS: " + label) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        var profile = UserProfile.default
        profile.name = "Synthetic profile"; profile.units = .imperial; profile.appLock = true
        profile.createdAt = now; profile.sleepNeed = 8 * 3600; profile.wakeGoal.hour = 6
        var goals = HealthGoals(); goals.weightKg = 88.2; goals.stepGoal = 12_500; goals.goal = .gain
        let pair = try ProfileSettings.birthYear(1988, profile: profile, goals: goals, now: now, calendar: calendar)
        check(pair.profile.birthYear == 1988 && pair.goals.age == 38, "birth year and calculation age are prepared as one consistent pair")
        check(pair.profile.name == profile.name && pair.profile.units == .imperial && pair.profile.appLock == true && pair.profile.createdAt == now, "birth-year preparation preserves name, units, privacy and creation fields")
        check(pair.profile.sleepNeed == profile.sleepNeed && pair.profile.wakeGoal.hour == 6 && !pair.profile.onboardingDone, "birth-year preparation does not change sleep preferences or advance onboarding")
        check(pair.goals.weightKg == 88.2 && pair.goals.stepGoal == 12_500 && pair.goals.goal == .gain, "birth-year preparation preserves current weight and other goals")
        check(profile.birthYear == nil && goals.age == 30, "preparation does not mutate either original preference value")
        let cleared = try ProfileSettings.birthYear(nil, profile: pair.profile, goals: pair.goals, now: now, calendar: calendar)
        check(cleared.profile.birthYear == nil && cleared.goals.age == nil, "explicit Not recorded clears birth year and its derived age together")
        check(cleared.goals.weightKg == 88.2 && cleared.profile.appLock == true, "clearing birth year cannot remove a weight log or privacy preference")
        for year in [Int.min, 1929, 2014, 2026, Int.max] {
            do { _ = try ProfileSettings.birthYear(year, profile: profile, goals: goals, now: now, calendar: calendar); preconditionFailure("invalid birth year accepted") }
            catch BackupError.invalid { check(true, "invalid birth year \(year) is rejected before arithmetic or persistence") }
        }
        check(try ProfileSettings.birthYear(1930, profile: profile, goals: goals, now: now, calendar: calendar).goals.age == 96, "earliest selectable birth year remains supported")
        check(try ProfileSettings.birthYear(2013, profile: profile, goals: goals, now: now, calendar: calendar).goals.age == 13, "latest selectable birth year remains supported")
        let nextYear = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let refreshed = ProfileSettings.refreshedAge(goals: pair.goals, birthYear: 1988, now: nextYear, calendar: calendar)
        check(refreshed.age == 39 && refreshed.weightKg == 88.2, "a known birth year refreshes current estimate age after year rollover without changing weight")
        check(ProfileSettings.refreshedAge(goals: goals, birthYear: nil, now: nextYear, calendar: calendar).age == 30, "legacy age-only preferences remain readable when birth year is unknown")
        check(ProfileSettings.refreshedAge(goals: goals, birthYear: Int.min, now: now, calendar: calendar).age == 30, "an invalid saved birth year cannot overflow age refresh")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let loadedProfile = try decoder.decode(UserProfile.self, from: encoder.encode(pair.profile))
        let loadedGoals = try decoder.decode(HealthGoals.self, from: encoder.encode(pair.goals))
        check(loadedProfile.birthYear == 1988 && loadedGoals.age == 38 && loadedProfile.createdAt == now, "paired preferences keep their existing JSON/date decoding contract")
        let unknownProfile = try decoder.decode(UserProfile.self, from: encoder.encode(cleared.profile))
        let unknownGoals = try decoder.decode(HealthGoals.self, from: encoder.encode(cleared.goals))
        check(unknownProfile.birthYear == nil && unknownGoals.age == nil && unknownGoals.weightKg == 88.2,
              "Not recorded survives existing JSON encoding and decoding without restoring a default age or losing weight")
    }
}
