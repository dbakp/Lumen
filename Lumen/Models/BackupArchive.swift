import Foundation
import CryptoKit

/// A typed, versioned backup. Credentials and device permissions never enter this format.
struct BackupSnapshot: Codable, Sendable {
    var profile: UserProfile
    var goals: HealthGoals
    var habits: [SleepHabit]
    var sleep: [SleepEpisode]
    var meals: [Meal]
    var workouts: [Workout]
    var water: [HydrationLog]
    var conversations: [HealthConversation]
    var symptoms: [SymptomEntry]
    var checkIns: [WellbeingCheckIn]
    var documents: [HealthDocument]
    var importedDays: [ImportedHealthDay]
    var imports: [ImportReceipt]
    var personalContext: PersonalHealthContext
    var photos: [String: Data]

    var recordCount: Int {
        sleep.count + meals.count + workouts.count + water.count + conversations.count + symptoms.count + checkIns.count + documents.count + importedDays.count + imports.count
    }

    func conflicts(with local: BackupSnapshot) -> Int {
        func common<T: Identifiable>(_ incoming: [T], _ current: [T]) -> Int {
            let ids = Set(current.map(\.id)); return incoming.filter { ids.contains($0.id) }.count
        }
        let activity = common(sleep, local.sleep) + WorkoutReconciliation.matches(workouts, current: local.workouts)
        let nutrition = common(meals, local.meals) + common(water, local.water)
        let journal = common(symptoms, local.symptoms) + common(checkIns, local.checkIns)
        let library = common(conversations, local.conversations) + common(documents, local.documents)
        let history = common(importedDays, local.importedDays) + common(imports, local.imports)
        return activity + nutrition + journal + library + history
    }

    /// Current copies win. Restoring the same archive twice is idempotent.
    func merging(into local: BackupSnapshot, restorePreferences: Bool) -> BackupSnapshot {
        var result = local
        func merge<T: Identifiable>(_ incoming: [T], _ current: [T]) -> [T] {
            var ids = Set(current.map(\.id)); return current + incoming.filter { ids.insert($0.id).inserted }
        }
        result.sleep = merge(sleep, local.sleep).sorted { $0.bedtime < $1.bedtime }
        result.workouts = WorkoutReconciliation.merge(workouts, into: local.workouts, preferExisting: true)
        result.water = merge(water, local.water)
        result.conversations = merge(conversations, local.conversations)
        result.symptoms = merge(symptoms, local.symptoms)
        result.checkIns = merge(checkIns, local.checkIns)
        result.imports = merge(imports, local.imports)
        result.documents = merge(documents.map { var d = $0; d.includeInAssistant = false; return d }, local.documents)
        // A day can contain several metrics. Keep local values, add only missing keys.
        var dayIndices = Dictionary(uniqueKeysWithValues: result.importedDays.enumerated().map { ($0.element.date, $0.offset) })
        for day in importedDays {
            if let index = dayIndices[day.date] {
                for (metric, value) in day.values where result.importedDays[index].values[metric] == nil {
                    result.importedDays[index].values[metric] = value
                    result.importedDays[index].sources[metric] = day.sources[metric]
                }
            } else { dayIndices[day.date] = result.importedDays.count; result.importedDays.append(day) }
        }
        result.importedDays.sort { $0.date < $1.date }
        let currentMealIDs = Set(local.meals.map(\.id))
        var photoMapping: [String: String] = [:]
        let newMeals = meals.filter { !currentMealIDs.contains($0.id) }.map { original in
            var meal = original
            if let photoID = original.photoID, let bytes = photos[photoID] {
                // Never let an archive overwrite another meal's photo on this device.
                let id = photoMapping[photoID] ?? UUID().uuidString
                photoMapping[photoID] = id; result.photos[id] = bytes; meal.photoID = id
            }
            return meal
        }
        result.meals = merge(newMeals, local.meals)
        if restorePreferences {
            result.profile = profile
            result.profile.appLock = local.profile.appLock
            result.profile.isSubscribed = local.profile.isSubscribed
            result.profile.onboardingDone = local.profile.onboardingDone
            result.goals = goals
            result.habits = habits.map { var habit = $0; habit.doneToday = false; return habit }
            result.personalContext = personalContext
            result.personalContext.includeInAssistant = false
        }
        return result
    }
}

struct BackupArchive: Codable, Sendable {
    let format: String
    let version: Int
    let createdAt: Date
    let payload: Data
    let sha256: String
    static let maxBytes = 100 * 1024 * 1024
    static let maxPhotoBytes = 5 * 1024 * 1024

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func make(_ snapshot: BackupSnapshot, now: Date = Date()) throws -> Data {
        try validate(snapshot)
        let payload = try encoder().encode(snapshot)
        let archive = BackupArchive(format: "LumenBackup", version: 1, createdAt: now, payload: payload, sha256: digest(payload))
        let data = try encoder().encode(archive)
        guard data.count <= maxBytes else { throw BackupError.tooLarge }
        return data
    }
    static func read(_ data: Data) throws -> (BackupArchive, BackupSnapshot) {
        guard data.count <= maxBytes else { throw BackupError.tooLarge }
        let archive: BackupArchive
        do { archive = try decoder().decode(Self.self, from: data) } catch { throw BackupError.invalid }
        guard archive.format == "LumenBackup" else { throw BackupError.invalid }
        guard archive.version == 1 else { throw BackupError.version }
        guard digest(archive.payload) == archive.sha256 else { throw BackupError.integrity }
        let snapshot: BackupSnapshot
        do { snapshot = try decoder().decode(BackupSnapshot.self, from: archive.payload) } catch { throw BackupError.invalid }
        try validate(snapshot)
        return (archive, snapshot)
    }
    static func safePhotoID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 100 && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }
    static func validate(_ snapshot: BackupSnapshot) throws {
        func unique<T: Identifiable>(_ records: [T]) -> Bool {
            records.count <= 200_000 && Set(records.map(\.id)).count == records.count
        }
        func bounded(_ value: Double) -> Bool { value.isFinite && value >= 0 && value <= 1_000_000_000 }
        func optionalBounded(_ value: Double?) -> Bool { value.map(bounded) ?? true }
        guard snapshot.recordCount <= 500_000 else { throw BackupError.invalid }
        guard unique(snapshot.sleep), unique(snapshot.meals), unique(snapshot.workouts), unique(snapshot.water),
              unique(snapshot.conversations), unique(snapshot.symptoms), unique(snapshot.checkIns), unique(snapshot.documents),
              unique(snapshot.importedDays), unique(snapshot.imports), unique(snapshot.habits) else { throw BackupError.invalid }
        guard snapshot.conversations.allSatisfy({ unique($0.messages) }),
              snapshot.documents.allSatisfy({ unique($0.steps) }) else { throw BackupError.invalid }
        guard snapshot.photos.allSatisfy({ safePhotoID($0.key) && !$0.value.isEmpty && $0.value.count <= maxPhotoBytes }),
              snapshot.meals.allSatisfy({ $0.photoID.map { safePhotoID($0) && snapshot.photos[$0] != nil } ?? true }) else { throw BackupError.invalid }
        guard snapshot.symptoms.allSatisfy({ (1...10).contains($0.severity) }),
              snapshot.checkIns.allSatisfy({ (1...5).contains($0.energy) && (1...5).contains($0.mood) && (1...5).contains($0.stress) }),
              snapshot.water.allSatisfy({ $0.ml.isFinite && $0.ml > 0 && $0.ml <= 10000 }) else { throw BackupError.invalid }
        guard snapshot.sleep.allSatisfy({ $0.wakeTime >= $0.bedtime && bounded($0.duration) }),
              snapshot.importedDays.allSatisfy({ $0.values.values.allSatisfy(bounded) }) else { throw BackupError.invalid }
        guard snapshot.workouts.allSatisfy({ workout in
            guard bounded(workout.duration), bounded(workout.activeCalories), optionalBounded(workout.distanceM), optionalBounded(workout.avgHR) else { return false }
            guard let origin = workout.importOrigin else { return true }
            return origin.end >= workout.start && origin.end.timeIntervalSince(workout.start) <= 7 * 86400 && workout.duration <= origin.end.timeIntervalSince(workout.start) + 60
        }) else { throw BackupError.invalid }
        for meal in snapshot.meals {
            guard unique(meal.items) else { throw BackupError.invalid }
            for food in meal.items {
                guard (0...1).contains(food.confidence) else { throw BackupError.invalid }
                guard [food.grams, food.calories, food.proteinG, food.carbsG, food.fatG, food.fiberG].allSatisfy(bounded) else { throw BackupError.invalid }
            }
        }
        guard [snapshot.goals.stepGoal, snapshot.goals.activeCalGoal, snapshot.goals.exerciseGoalMin].allSatisfy(bounded),
              optionalBounded(snapshot.goals.weightKg), optionalBounded(snapshot.goals.heightCm),
              (0...150).contains(snapshot.goals.age ?? 30), (0...24).contains(snapshot.goals.standGoal) else { throw BackupError.invalid }
        if let year = snapshot.profile.birthYear {
            guard (1850...Calendar.current.component(.year, from: Date())).contains(year) else { throw BackupError.invalid }
        }
        guard (0...1).contains(snapshot.profile.sleepNeedConfidence) else { throw BackupError.invalid }
        for episode in snapshot.sleep {
            guard optionalBounded(episode.deepSeconds), optionalBounded(episode.remSeconds),
                  optionalBounded(episode.coreSeconds), optionalBounded(episode.awakeSeconds),
                  (1...5).contains(episode.quality ?? 3) else { throw BackupError.invalid }
        }
        guard snapshot.habits.allSatisfy({ $0.offset.isFinite && abs($0.offset) <= 604800 }),
              snapshot.profile.sleepNeed.isFinite, (3600...86400).contains(snapshot.profile.sleepNeed) else { throw BackupError.invalid }
    }
}

enum BackupError: LocalizedError {
    case tooLarge, invalid, version, integrity, busy, missingPhoto
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "This backup is over the 100 MB limit. Keep the original file; no records were changed."
        case .invalid: return "This file isn’t a valid Lumen backup. Choose a file created from Backup & restore. Older data exports can’t be restored here."
        case .version: return "This backup needs a newer version of Lumen. Update the app, then try again."
        case .integrity: return "This backup failed its integrity check. Choose another copy; no records were changed."
        case .busy: return "Wait for health syncing to finish, then try again."
        case .missingPhoto: return "A meal photo is missing or unreadable. Your records are unchanged. Remove the missing photo from its meal before making a backup."
        }
    }
}

/// Stage a complete directory, retain the old copy until the new one is installed.
/// After interruption, recovery restores the previous directory if installation didn't finish.
enum BackupFiles {
    static func recover(_ directory: URL) throws {
        let fm = FileManager.default
        let previous = directory.appendingPathExtension("previous")
        if !fm.fileExists(atPath: directory.path), fm.fileExists(atPath: previous.path) {
            try fm.moveItem(at: previous, to: directory)
        }
        if fm.fileExists(atPath: directory.path), fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
    }
    static func install(_ files: [String: Data], into directory: URL) throws {
        let fm = FileManager.default
        try recover(directory)
        let stage = directory.appendingPathExtension("restore")
        let previous = directory.appendingPathExtension("previous")
        if fm.fileExists(atPath: stage.path) { try fm.removeItem(at: stage) }
        defer { try? fm.removeItem(at: stage) }
        if fm.fileExists(atPath: directory.path) { try fm.copyItem(at: directory, to: stage) }
        else { try fm.createDirectory(at: stage, withIntermediateDirectories: true) }
        for (path, bytes) in files {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\\") else { throw BackupError.invalid }
            let target = stage.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if fm.fileExists(atPath: directory.path) { try fm.moveItem(at: directory, to: previous) }
        do { try fm.moveItem(at: stage, to: directory) }
        catch { try? recover(directory); throw error }
        try? fm.removeItem(at: previous)
    }
}
