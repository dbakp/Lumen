import Foundation

enum ProfileSettings {
    /// Legacy age-only preferences remain readable; a valid saved birth year
    /// takes priority when recomputing current estimates, including year change.
    static func refreshedAge(goals: HealthGoals, birthYear: Int?, now: Date = Date(), calendar: Calendar = .current) -> HealthGoals {
        let currentYear = calendar.component(.year, from: now)
        guard let birthYear, birthYear >= 1930, birthYear <= currentYear - 13 else { return goals }
        var goals = goals; goals.age = currentYear - birthYear; return goals
    }

    static func birthYear(_ year: Int?, profile: UserProfile, goals: HealthGoals, now: Date = Date(), calendar: Calendar = .current) throws -> (profile: UserProfile, goals: HealthGoals) {
        let currentYear = calendar.component(.year, from: now)
        if let year { guard year >= 1930, year <= currentYear - 13 else { throw BackupError.invalid } }
        var profile = profile, goals = goals
        profile.birthYear = year
        goals.age = year.map { currentYear - $0 }
        return (profile, goals)
    }
}
