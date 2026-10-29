import Foundation
import UIKit
import ImageIO

@MainActor
enum BackupService {
    static func snapshot(sleep: SleepStore, health: HealthStore) throws -> BackupSnapshot {
        guard !health.isSyncing else { throw BackupError.busy }
        let companion = CompanionStore.shared
        var photos: [String: Data] = [:]
        var photoBytes = 0
        for id in Set(health.meals.compactMap(\.photoID)) {
            guard BackupArchive.safePhotoID(id) else { throw BackupError.missingPhoto }
            let size = (try? PhotoStore.url(id).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size <= BackupArchive.maxPhotoBytes else { throw BackupError.missingPhoto }
            photoBytes += size
            guard photoBytes <= BackupArchive.maxBytes / 2 else { throw BackupError.tooLarge }
            guard let data = try? Data(contentsOf: PhotoStore.url(id)), validPhoto(data) else { throw BackupError.missingPhoto }
            photos[id] = data
        }
        return BackupSnapshot(profile: sleep.profile, goals: health.goals, habits: sleep.habits,
                              sleep: sleep.episodes, meals: health.meals, workouts: health.workouts, water: health.waterLogs,
                              conversations: health.conversations, symptoms: companion.symptoms, checkIns: companion.checkIns,
                              documents: companion.documents, importedDays: companion.importedDays, imports: companion.imports,
                              personalContext: companion.personalContext, photos: photos)
    }
    static func export(sleep: SleepStore, health: HealthStore) async throws -> URL {
        let snapshot = try snapshot(sleep: sleep, health: health)
        return try await Task.detached(priority: .userInitiated) {
            let data = try BackupArchive.make(snapshot)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumenBackups", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // One shareable backup per session; remove old temporary copies on the next export.
            for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] { try? FileManager.default.removeItem(at: file) }
            let file = folder.appendingPathComponent("Lumen-backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json")
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return file
        }.value
    }
    nonisolated static func read(_ url: URL) throws -> (BackupArchive, BackupSnapshot) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<(BackupArchive, BackupSnapshot), Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { file in
            result = Result {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= BackupArchive.maxBytes else { throw BackupError.tooLarge }
                let parsed = try BackupArchive.read(Data(contentsOf: file, options: .mappedIfSafe))
                guard parsed.1.photos.values.allSatisfy(validPhoto) else { throw BackupError.invalid }
                return parsed
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BackupError.invalid }
        return try result.get()
    }
    nonisolated static func validPhoto(_ data: Data) -> Bool {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(image) as String? == "public.jpeg",
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width > 0 && height > 0 && width <= 4096 && height <= 4096
    }
    static func restore(_ incoming: BackupSnapshot, preferences: Bool, sleep: SleepStore, health: HealthStore) throws {
        try BackupArchive.validate(incoming)
        guard incoming.photos.values.allSatisfy({ validPhoto($0) }) else { throw BackupError.invalid }
        let merged = incoming.merging(into: try snapshot(sleep: sleep, health: health), restorePreferences: preferences)
        var files: [String: Data] = [:]
        func add<T: Encodable>(_ value: T, _ name: String) throws { files[name + ".json"] = try BackupArchive.encoder().encode(value) }
        try add(merged.profile, "profile"); try add(merged.goals, "goals"); try add(merged.habits, "habits"); try add(merged.sleep, "sleep")
        try add(merged.meals, "meals"); try add(merged.workouts, "workouts"); try add(merged.water, "water")
        try add(merged.conversations, "conversations"); try add(merged.symptoms, "symptoms"); try add(merged.checkIns, "check-ins")
        try add(merged.documents, "documents"); try add(merged.importedDays, "imported-days"); try add(merged.imports, "import-receipts")
        try add(merged.personalContext, "personal-context")
        for (id, bytes) in merged.photos { files["photos/\(id).jpg"] = bytes }
        try BackupFiles.install(files, into: LocalStore.directory)
        CompanionStore.shared.reloadAfterRestore()
        health.reloadAfterRestore()
        sleep.reloadAfterRestore()
        SyncCoordinator.propagate(sleep: sleep, health: health)
    }
}
