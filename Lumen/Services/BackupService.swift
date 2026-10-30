import Foundation
import UIKit
import ImageIO

/// Each operation owns a private directory. Releasing a preview/share copy removes it
/// off the main thread; a worker retains ownership until it has stopped using the files.
final class BackupWorkspace: Sendable {
    let directory: URL
    private static let removeAbandonedWork: Void = {
        let fm = FileManager.default
        try? fm.removeItem(at: fm.temporaryDirectory.appendingPathComponent("LumenBackups", isDirectory: true))
        for folder in (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        where folder.lastPathComponent.hasPrefix("LumenBackupWork-") { try? fm.removeItem(at: folder) }
    }()
    init() throws {
        _ = Self.removeAbandonedWork
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LumenBackupWork-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    deinit {
        let folder = directory
        DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: folder) }
    }
}

/// Foundation documents cancel() as immediate and callable from any thread.
/// Only that operation crosses threads; coordinating reads stays on its worker.
private final class BackupCoordinatorCancellation: @unchecked Sendable {
    private let coordinator: NSFileCoordinator
    init(_ coordinator: NSFileCoordinator) { self.coordinator = coordinator }
    func cancel() { coordinator.cancel() }
}

@MainActor
enum BackupService {
    struct Source: Sendable {
        let url: URL
        let name: String
        let encrypted: Bool
        fileprivate let workspace: BackupWorkspace
    }
    struct Export: Sendable {
        let url: URL
        fileprivate let workspace: BackupWorkspace
    }
    struct Preview: Sendable {
        let snapshot: BackupSnapshot
        let createdAt: Date
        let encrypted: Bool
        let photos: [String: URL]
        fileprivate let contents: BackupPackage.Contents?
        fileprivate let workspace: BackupWorkspace?
    }

    /// Metadata is captured on the main actor. Photos stay in files throughout v2 operations.
    static func snapshot(sleep: SleepStore, health: HealthStore) throws -> BackupSnapshot {
        guard !health.isSyncing else { throw BackupError.busy }
        let companion = CompanionStore.shared
        return BackupSnapshot(profile: sleep.profile, goals: health.goals, habits: sleep.habits,
                              sleep: sleep.episodes, meals: health.meals, workouts: health.workouts, water: health.waterLogs,
                              conversations: health.conversations, symptoms: companion.symptoms, checkIns: companion.checkIns,
                              documents: companion.documents, importedDays: companion.importedDays, imports: companion.imports,
                              personalContext: companion.personalContext, photos: [:])
    }
    static func export(password: String, sleep: SleepStore, health: HealthStore, control: BackupOperationControl) async throws -> Export {
        try BackupPackage.validateNewPassword(password)
        let revision = LocalStore.revision
        let snapshot = try snapshot(sleep: sleep, health: health)
        let photos = try photoURLs(snapshot)
        let result = try await Task.detached(priority: .userInitiated) {
            let workspace = try BackupWorkspace()
            var copies: [String: URL] = [:], bytes: Int64 = 0
            control.update(.preparing, total: photos.count)
            for id in photos.keys.sorted() {
                try control.checkCancellation()
                let source = photos[id]!
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= BackupArchive.maxPhotoBytes else { throw BackupError.missingPhoto }
                guard bytes <= BackupPackage.maxFileBytes - Int64(size) else { throw BackupPackage.PackageError.tooLarge }
                guard validPhoto(source) else { throw BackupError.missingPhoto }
                let copy = workspace.directory.appendingPathComponent("photo-\(copies.count).jpg")
                bytes += try copyFile(source, to: copy, limit: Int64(BackupArchive.maxPhotoBytes), control: control)
                copies[id] = copy
                control.update(.preparing, completed: copies.count, total: photos.count, bytes: bytes)
            }
            let createdAt = Date(), formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
            let date = formatter.string(from: createdAt)
            let file = workspace.directory.appendingPathComponent("Lumen-backup-\(date).lumenbackup")
            try BackupPackage.write(snapshot, photos: copies, password: password, to: file, now: createdAt, control: control)
            // Keep only the encrypted share file, never a second unencrypted photo library.
            for copy in copies.values { try FileManager.default.removeItem(at: copy) }
            return Export(url: file, workspace: workspace)
        }.value
        try control.checkCancellation()
        guard LocalStore.revision == revision else { throw BackupError.recordsChanged }
        return result
    }

    /// Own the selected bytes before releasing Files/iCloud access or asking for a password.
    nonisolated static func select(_ url: URL, control: BackupOperationControl) throws -> Source {
        let workspace = try BackupWorkspace(), target = workspace.directory.appendingPathComponent("selected-backup")
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        let cancellation = BackupCoordinatorCancellation(coordinator)
        control.setCancellationHandler { cancellation.cancel() }
        defer { control.setCancellationHandler(nil) }
        var coordinationError: NSError?, result: Result<Void, Error>?
        control.update(.preparing)
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { file in
            result = Result { _ = try copyFile(file, to: target, limit: BackupPackage.maxFileBytes, control: control, report: true) }
        }
        try control.checkCancellation()
        if let coordinationError { throw coordinationError }
        guard let result else { throw BackupError.invalid }
        try result.get(); try control.checkCancellation()
        let input = try FileHandle(forReadingFrom: target); defer { try? input.close() }
        let prefix = try input.read(upToCount: 4)
        let encrypted = prefix == Data("AEA1".utf8)
        if !encrypted {
            let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= BackupArchive.maxBytes else { throw BackupError.tooLarge }
        }
        return Source(url: target, name: url.lastPathComponent, encrypted: encrypted, workspace: workspace)
    }
    nonisolated static func read(_ source: Source, password: String, control: BackupOperationControl) throws -> Preview {
        try control.checkCancellation()
        if source.encrypted {
            let contents = try BackupPackage.read(source.url, password: password, temporaryRoot: source.workspace.directory, control: control)
            var checked = 0
            control.update(.checkingPhotos, total: contents.photos.count)
            for photo in contents.photos.values {
                try control.checkCancellation()
                guard validPhoto(photo) else { throw BackupError.invalid }
                checked += 1
                control.update(.checkingPhotos, completed: checked, total: contents.photos.count)
            }
            return Preview(snapshot: contents.snapshot, createdAt: contents.manifest.createdAt, encrypted: true,
                           photos: contents.photos, contents: contents, workspace: source.workspace)
        }
        control.update(.reading)
        let (archive, decoded) = try BackupArchive.read(Data(contentsOf: source.url, options: .mappedIfSafe))
        try control.checkCancellation()
        let workspace = try BackupWorkspace()
        var photos: [String: URL] = [:]
        for id in decoded.photos.keys.sorted() {
            try control.checkCancellation()
            let file = workspace.directory.appendingPathComponent("photo-\(photos.count).jpg")
            try decoded.photos[id]!.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            guard validPhoto(file) else { throw BackupError.invalid }
            photos[id] = file
            control.update(.reading, completed: photos.count, total: decoded.photos.count)
        }
        var snapshot = decoded; snapshot.photos = [:]
        try control.checkCancellation()
        return Preview(snapshot: snapshot, createdAt: archive.createdAt, encrypted: false, photos: photos, contents: nil, workspace: workspace)
    }

    /// Validate and decode one bounded JPEG at a time, off the main actor.
    nonisolated static func validPhoto(_ url: URL) -> Bool {
        autoreleasepool {
            guard let image = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetType(image) as String? == "public.jpeg",
                  CGImageSourceGetCount(image) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 4096, height <= 4096,
                  CGImageSourceGetStatus(image) == .statusComplete,
                  CGImageSourceCreateImageAtIndex(image, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else { return false }
            return CGImageSourceGetStatusAtIndex(image, 0) == .statusComplete
        }
    }
    static func restore(_ incoming: Preview, preferences: Bool, sleep: SleepStore, health: HealthStore, control: BackupOperationControl) async throws {
        guard !health.isSyncing else { throw BackupError.busy }
        let revision = LocalStore.revision
        let local = try snapshot(sleep: sleep, health: health)
        let directory = LocalStore.directory
        let transaction = try await Task.detached(priority: .userInitiated) {
            try control.checkCancellation()
            try BackupArchive.validate(incoming.snapshot, availablePhotoIDs: Set(incoming.photos.keys))
            let merged = try incoming.snapshot.mergingFileBacked(into: local, restorePreferences: preferences, photoFiles: incoming.photos)
            let availableIDs = Set(local.meals.compactMap(\.photoID)).union(merged.photos.keys)
            try BackupArchive.validate(merged.snapshot, availablePhotoIDs: availableIDs)
            var files: [String: Data] = [:]
            func add<T: Encodable>(_ value: T, _ name: String) throws {
                try control.checkCancellation()
                files[name + ".json"] = try BackupArchive.encoder().encode(value)
            }
            let value = merged.snapshot
            try add(value.profile, "profile"); try add(value.goals, "goals"); try add(value.habits, "habits"); try add(value.sleep, "sleep")
            try add(value.meals, "meals"); try add(value.workouts, "workouts"); try add(value.water, "water")
            try add(value.conversations, "conversations"); try add(value.symptoms, "symptoms"); try add(value.checkIns, "check-ins")
            try add(value.documents, "documents"); try add(value.importedDays, "imported-days"); try add(value.imports, "import-receipts")
            try add(value.personalContext, "personal-context")
            guard files.values.reduce(0, { $0 + $1.count }) <= BackupPackage.maxMetadataBytes else { throw BackupPackage.PackageError.metadataTooLarge }
            // Keep incoming ownership alive until its file-backed photos have been copied.
            return try withExtendedLifetime(incoming) {
                try BackupFileTransaction.prepare(files, photoFiles: Dictionary(uniqueKeysWithValues: merged.photos.map { ("photos/\($0.key).jpg", $0.value) }), into: directory, control: control)
            }
        }.value
        try control.checkCancellation()
        guard !health.isSyncing else { throw BackupError.busy }
        try LocalStore.commitRestore(transaction, revision: revision)
        CompanionStore.shared.reloadAfterRestore()
        health.reloadAfterRestore()
        sleep.reloadAfterRestore()
        SyncCoordinator.propagate(sleep: sleep, health: health)
    }

    private static func photoURLs(_ snapshot: BackupSnapshot) throws -> [String: URL] {
        var photos: [String: URL] = [:]
        for id in Set(snapshot.meals.compactMap(\.photoID)) {
            guard BackupArchive.safePhotoID(id) else { throw BackupError.missingPhoto }
            photos[id] = PhotoStore.url(id)
        }
        return photos
    }
    nonisolated private static func copyFile(_ source: URL, to target: URL, limit: Int64,
                                             control: BackupOperationControl, report: Bool = false) throws -> Int64 {
        try control.checkCancellation()
        let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, let size = attributes.fileSize, size > 0 else { throw BackupError.invalid }
        guard Int64(size) <= limit else { throw BackupPackage.PackageError.tooLarge }
        try Data().write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: target)
        defer { try? input.close(); try? output.close() }
        var copied = 0
        while copied < size {
            try control.checkCancellation()
            guard let data = try input.read(upToCount: min(BackupPackage.bufferBytes, size - copied)), !data.isEmpty else { throw BackupError.invalid }
            try output.write(contentsOf: data); copied += data.count
            if report { control.update(.preparing, bytes: Int64(copied)) }
        }
        guard try input.read(upToCount: 1)?.isEmpty != false else { throw BackupError.invalid }
        try output.close(); try control.checkCancellation()
        return Int64(size)
    }
}
