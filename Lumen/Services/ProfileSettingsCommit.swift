import Foundation

/// A birth-year change and initial setup each own two existing JSON domains.
/// Keep their disk commit and subsequent live installation on the main actor.
@MainActor enum ProfileSettingsCommit {
    static func birthYear(_ year: Int?, sleep: SleepStore, health: HealthStore) async throws {
        guard !health.isSyncing else { throw BackupError.busy }
        let pair = try ProfileSettings.birthYear(year, profile: sleep.profile, goals: health.goals)
        try await commit(profile: pair.profile, goals: pair.goals, sleep: sleep, health: health)
    }

    static func onboarding(profile: UserProfile, goals: HealthGoals, sleep: SleepStore, health: HealthStore) async throws {
        guard !health.isSyncing else { throw BackupError.busy }
        let pair = try ProfileSettings.birthYear(profile.birthYear, profile: profile, goals: goals)
        try await commit(profile: pair.profile, goals: pair.goals, sleep: sleep, health: health)
    }

    private static func commit(profile: UserProfile, goals: HealthGoals, sleep: SleepStore, health: HealthStore) async throws {
        let boundary = try health.requireLocalHealthBoundary(.goals)
        try await LocalStore.saveProfileGoalsChecked(profile: profile, goals: goals, healthBoundaries: [.goals: boundary], canCommit: { !health.isSyncing }) {
            sleep.installCheckedProfile(profile)
            health.installCheckedGoals(goals)
            SyncCoordinator.propagate(sleep: sleep, health: health)
        }
    }
}
