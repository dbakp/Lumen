import Foundation
import UIKit
import ImageIO

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
        let identity: BackupSourceIdentity
        fileprivate let workspace: BackupWorkspace
        func cleanup() { workspace.cleanup() }
        nonisolated func verify(control: BackupOperationControl) throws {
            defer { workspace.cleanup() }
            try identity.verify(url, control: control)
        }
    }
    struct Export: Sendable {
        let url: URL
        fileprivate let workspace: BackupWorkspace
        func cleanup() { workspace.cleanup() }
    }
    struct Preview: Sendable {
        let snapshot: BackupSnapshot
        let createdAt: Date
        let encrypted: Bool
        let photos: [String: URL]
        fileprivate let photoIdentities: [String: BackupPhotoIdentity]
        fileprivate let contents: BackupPackage.Contents?
        fileprivate let workspace: BackupWorkspace?
        fileprivate let source: Source?
        fileprivate init(snapshot: BackupSnapshot, createdAt: Date, encrypted: Bool, photos: [String: URL], photoIdentities: [String: BackupPhotoIdentity],
             contents: BackupPackage.Contents?, workspace: BackupWorkspace?, source: Source? = nil) {
            self.snapshot = snapshot; self.createdAt = createdAt; self.encrypted = encrypted
            self.photos = photos; self.contents = contents; self.workspace = workspace; self.source = source
            self.photoIdentities = photoIdentities
        }
    }

    struct RecoveryInput: Sendable {
        #if DEBUG && targetEnvironment(simulator)
        var verificationSource: URL { resources.lease.file }
        #endif
        let snapshot: BackupSnapshot
        let createdAt: Date
        let present: Set<HealthLocalFiles.Domain>
        let missingPhotos: Int
        let identity: BackupSourceIdentity
        fileprivate let photos: [String: URL]
        fileprivate let resources: BackupRecoverySource
        nonisolated func records(_ domain: HealthLocalFiles.Domain, control: BackupOperationControl = .init()) throws -> Data {
            defer { withExtendedLifetime(self) {} }
            try control.checkCancellation()
            guard present.contains(domain) else { throw BackupError.invalid }
            _ = try resources.lease.verifiedBoundary(control: control)
            let encoder = BackupArchive.encoder()
            let data: Data
            switch domain {
            case .water: data = try encoder.encode(snapshot.water)
            case .meals: data = try encoder.encode(snapshot.meals)
            case .workouts: data = try encoder.encode(snapshot.workouts)
            case .goals: data = try encoder.encode(snapshot.goals)
            case .today: throw BackupError.invalid
            }
            try control.checkCancellation()
            return data
        }
        nonisolated func count(_ domain: HealthLocalFiles.Domain) -> Int {
            switch domain {
            case .water: return snapshot.water.count
            case .meals: return snapshot.meals.count
            case .workouts: return snapshot.workouts.count
            case .goals: return 1
            case .today: return 0
            }
        }
        nonisolated var photoIDs: Set<String> { Set(snapshot.meals.compactMap(\.photoID)) }
        nonisolated func photoData(_ id: String, control: BackupOperationControl = .init()) throws -> Data {
            defer { withExtendedLifetime(self) {} }
            try control.checkCancellation()
            _ = try resources.lease.verifiedBoundary(control: control)
            guard photoIDs.contains(id), let file = photos[id], let expected = resources.photoIdentities[id] else { throw BackupError.missingPhoto }
            #if DEBUG && targetEnvironment(simulator)
            HealthReadUIFixture.willReadSelectedPhoto(control: control, source: resources.lease.file, photo: file)
            #endif
            return try expected.read(file, control: control)
        }
        nonisolated func payload(domains: Set<HealthLocalFiles.Domain>, omitPhotos: Bool,
                                 control: BackupOperationControl) throws -> HealthRecoverySelection.Payload {
            defer { withExtendedLifetime(self) {} }
            guard domains.isSubset(of: present) else { throw BackupError.invalid }
            if domains.contains(.meals), missingPhotos > 0, !omitPhotos { throw BackupError.missingPhoto }
            let omitted = domains.contains(.meals) && omitPhotos ? photoIDs : []
            var ownership = resources
            ownership.omittedPhotoCount = domains.contains(.meals) ? missingPhotos + omitted.count : 0
            return try HealthRecoverySelection.backup(snapshot, photos: photos, domains: domains,
                omittingPhotos: omitted, control: control, source: ownership, validPhoto: BackupService.validPhoto)
        }
    }

    static func recoveryInput(_ preview: Preview) -> RecoveryInput? {
        guard let source = preview.source else { return nil }
        let resources = BackupRecoverySource(lease: BackupSourceLease(file: source.url, identity: source.identity, workspace: source.workspace),
                                            photoWorkspace: preview.workspace, contents: preview.contents, photoIdentities: preview.photoIdentities)
        return RecoveryInput(snapshot: preview.snapshot, createdAt: preview.createdAt, present: [.water, .meals, .workouts, .goals],
                             missingPhotos: 0, identity: source.identity, photos: preview.photos, resources: resources)
    }
    static func recoveryInput(_ conversion: ReadableExport.Conversion, source: Source) -> RecoveryInput? {
        guard source.identity.format == .readableExport, source.identity.sha256 == conversion.sha256 else { return nil }
        let present = Set(conversion.present.compactMap { HealthLocalFiles.Domain(rawValue: $0.rawValue) })
        let resources = BackupRecoverySource(lease: BackupSourceLease(file: source.url, identity: source.identity, workspace: source.workspace),
                                            photoWorkspace: nil, contents: nil)
        return RecoveryInput(snapshot: conversion.snapshot, createdAt: conversion.exportedAt, present: present,
                             missingPhotos: conversion.missingPhotos, identity: source.identity, photos: [:], resources: resources)
    }

    /// Metadata is captured on the main actor. Photos stay in files throughout v2 operations.
    static func snapshot(sleep: SleepStore, health: HealthStore) throws -> BackupSnapshot {
        guard !health.isSyncing else { throw BackupError.busy }
        guard health.conversationReady else { throw BackupError.currentDataInvalid }
        try health.requireAllLocalHealthData()
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
    nonisolated static func select(_ url: URL, control: BackupOperationControl, limit: Int64 = BackupPackage.maxFileBytes) throws -> Source {
        do { return try selectOwnedCopy(url, control: control, limit: limit) }
        catch { throw BackupError.importReadFailure(error) }
    }
    nonisolated private static func selectOwnedCopy(_ url: URL, control: BackupOperationControl, limit: Int64) throws -> Source {
        let workspace = try BackupWorkspace(), target = workspace.directory.appendingPathComponent("selected-backup")
        var retained = false
        defer { if !retained { workspace.cleanup() } }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        let cancellation = BackupCoordinatorCancellation(coordinator)
        control.setCancellationHandler { cancellation.cancel() }
        defer { control.setCancellationHandler(nil) }
        var coordinationError: NSError?, result: Result<Void, Error>?
        control.update(.preparing)
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { file in
            result = Result { _ = try copyFile(file, to: target, limit: limit, control: control, report: true) }
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
        retained = true
        let identity = try BackupSourceIdentity.measure(target, named: url.lastPathComponent,
            format: encrypted ? .encryptedBackup : .legacyJSONBackup, limit: limit, control: control)
        return Source(url: target, name: url.lastPathComponent, encrypted: encrypted, identity: identity, workspace: workspace)
    }
    nonisolated static func read(_ source: Source, password: String, control: BackupOperationControl) throws -> Preview {
        defer { source.cleanup() }
        try control.checkCancellation()
        try source.verify(control: control)
        if source.encrypted {
            let contents = try BackupPackage.read(source.url, password: password, temporaryRoot: source.workspace.directory, control: control)
            var checked = 0
            control.update(.checkingPhotos, total: contents.photos.count)
            for id in contents.photos.keys.sorted() {
                try control.checkCancellation()
                guard let photo = contents.photos[id], let identity = contents.photoIdentities[id],
                      validPhotoData(try identity.read(photo, control: control)) else { throw BackupError.invalid }
                checked += 1
                control.update(.checkingPhotos, completed: checked, total: contents.photos.count)
            }
            try source.verify(control: control)
            return Preview(snapshot: contents.snapshot, createdAt: contents.manifest.createdAt, encrypted: true,
                           photos: contents.photos, photoIdentities: contents.photoIdentities, contents: contents, workspace: source.workspace, source: source)
        }
        control.update(.reading)
        let data = try readPayload(source, limit: BackupArchive.maxBytes, control: control, invalid: BackupError.invalid)
        let (archive, decoded) = try BackupArchive.read(data, control: control)
        try control.checkCancellation()
        let workspace = try BackupWorkspace()
        var photos: [String: URL] = [:]
        var photoIdentities: [String: BackupPhotoIdentity] = [:]
        for id in decoded.photos.keys.sorted() {
            try control.checkCancellation()
            let file = workspace.directory.appendingPathComponent("photo-\(photos.count).jpg")
            try decoded.photos[id]!.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let identity = try BackupPhotoIdentity(data: decoded.photos[id]!)
            guard validPhotoData(try identity.read(file, control: control)) else { throw BackupError.invalid }
            photos[id] = file
            photoIdentities[id] = identity
            control.update(.reading, completed: photos.count, total: decoded.photos.count)
        }
        var snapshot = decoded; snapshot.photos = [:]
        try control.checkCancellation()
        try source.verify(control: control)
        return Preview(snapshot: snapshot, createdAt: archive.createdAt, encrypted: false, photos: photos, photoIdentities: photoIdentities, contents: nil, workspace: workspace, source: source)
    }

    /// Validate and decode one bounded JPEG at a time, off the main actor.
    nonisolated static func validPhoto(_ url: URL) -> Bool {
        guard let data = try? HealthLocalFiles.readRegularData(url, limit: BackupArchive.maxPhotoBytes) else { return false }
        return validPhotoData(data)
    }
    nonisolated private static func validPhotoData(_ data: Data) -> Bool {
        autoreleasepool {
            guard let image = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
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
        try await restore(incoming, selection: preferences ? .all : [], sleep: sleep, health: health, control: control)
    }
    private static func restore(_ incoming: Preview, selection: BackupPreferenceSelection, sleep: SleepStore, health: HealthStore, control: BackupOperationControl) async throws {
        defer { withExtendedLifetime(incoming) {} }
        guard !health.isSyncing else { throw BackupError.busy }
        if let source = incoming.source {
            try await Task.detached(priority: .userInitiated) { try source.verify(control: control) }.value
        }
        try control.checkCancellation()
        let revision = LocalStore.revision
        let local = try snapshot(sleep: sleep, health: health)
        let directory = try LocalStore.checkedDirectory()
        var healthIntent = try LocalStore.healthWriteJournalChecked()
        healthIntent.rotateLifecycle()
        let healthIntentData = try healthIntent.encoded()
        let transaction = try await Task.detached(priority: .userInitiated) {
            try control.checkCancellation()
            try BackupArchive.validate(incoming.snapshot, availablePhotoIDs: Set(incoming.photos.keys))
            let merged = try incoming.snapshot.mergingFileBacked(into: local, preferences: selection, photoFiles: incoming.photos)
            var identitiesByURL: [URL: BackupPhotoIdentity] = [:]
            for (id, url) in incoming.photos {
                guard let identity = incoming.photoIdentities[id] else { throw BackupError.missingPhoto }
                identitiesByURL[url] = identity
            }
            var expectedPhotoDigests: [String: String] = [:]
            for (id, url) in merged.photos {
                guard let identity = identitiesByURL[url] else { throw BackupError.missingPhoto }
                _ = try identity.read(url, control: control)
                expectedPhotoDigests["photos/" + id + ".jpg"] = identity.sha256
            }
            let availableIDs = Set(local.meals.compactMap(\.photoID)).union(merged.photos.keys)
            try BackupArchive.validate(merged.snapshot, availablePhotoIDs: availableIDs)
            var files: [String: Data] = [:]
            // Preserve this installation's pending deletes, withdraw its older
            // saves, and never import another archive's external work.
            files[HealthWriteFiles.name] = healthIntentData
            func add<T: Encodable>(_ value: T, _ name: String) throws {
                try control.checkCancellation()
                files[name + ".json"] = try BackupArchive.encoder().encode(value)
            }
            let value = merged.snapshot
            try add(value.profile, "profile"); try add(value.goals, "goals"); try add(value.habits, "habits"); try add(value.sleep, "sleep")
            try add(value.meals, "meals"); try add(value.workouts, "workouts"); try add(value.water, "water")
            // Restore archive, compatibility mirror and explicit unsent selection
            // in the same directory commit; reload must not repair them afterward.
            files.merge(try ConversationFiles.encoded(value.conversations, activeID: nil)) { _, incoming in incoming }
            try add(value.symptoms, "symptoms"); try add(value.checkIns, "check-ins")
            try add(value.documents, "documents"); try add(value.importedDays, "imported-days"); try add(value.imports, "import-receipts")
            try add(value.personalContext, "personal-context")
            guard files.values.reduce(0, { $0 + $1.count }) <= BackupPackage.maxMetadataBytes else { throw BackupPackage.PackageError.metadataTooLarge }
            // Keep incoming ownership alive until its file-backed photos have been copied.
            return try withExtendedLifetime(incoming) {
                let transaction = try ConversationFiles.prepareRestore(files, photoFiles: Dictionary(uniqueKeysWithValues: merged.photos.map { ("photos/\($0.key).jpg", $0.value) }), into: directory, control: control, photoDigests: expectedPhotoDigests)
                if let source = incoming.source {
                    let resources = BackupRecoverySource(lease: .init(file: source.url, identity: source.identity, workspace: source.workspace),
                                                        photoWorkspace: incoming.workspace, contents: incoming.contents, photoIdentities: incoming.photoIdentities)
                    try transaction.retainSource(resources, boundary: resources.lease.verifiedBoundary(control: control))
                }
                return transaction
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

    static func exportReadable(sleep: SleepStore, health: HealthStore, control: BackupOperationControl) async throws -> Export {
        let revision = LocalStore.revision, value = try snapshot(sleep: sleep, health: health)
        let reminders = CompanionStore.shared.reminders
        let result = try await Task.detached(priority: .userInitiated) {
            let workspace = try BackupWorkspace()
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
            let file = workspace.directory.appendingPathComponent("Lumen-export-" + formatter.string(from: Date()) + ".json")
            try ReadableExport.write(value, reminders: reminders, to: file, control: control)
            return Export(url: file, workspace: workspace)
        }.value
        do {
            try control.checkCancellation()
            guard LocalStore.revision == revision else { throw ReadableExport.Failure.recordsChanged }
            return result
        } catch { result.cleanup(); throw error }
    }
    nonisolated static func selectReadable(_ url: URL, control: BackupOperationControl) throws -> Source {
        do {
            let source = try select(url, control: control, limit: Int64(ReadableExport.maxBytes))
            guard !source.encrypted else { throw ReadableExport.Failure.format }
            return Source(url: source.url, name: source.name, encrypted: false,
                          identity: source.identity.reclassified(.readableExport), workspace: source.workspace)
        }
        catch BackupError.invalid { throw ReadableExport.Failure.format }
        catch BackupError.tooLarge { throw ReadableExport.Failure.tooLarge }
        catch BackupPackage.PackageError.tooLarge { throw ReadableExport.Failure.tooLarge }
    }
    nonisolated static func convertReadable(_ source: Source, control: BackupOperationControl) throws -> ReadableExport.Conversion {
        defer { source.cleanup() }
        guard !source.encrypted else { throw ReadableExport.Failure.format }
        control.update(.reading)
        try source.verify(control: control)
        let data = try readPayload(source, limit: ReadableExport.maxBytes, control: control, invalid: ReadableExport.Failure.format)
        let conversion = try ReadableExport.read(data, control: control)
        try source.verify(control: control)
        return conversion
    }
    static func restoreReadable(_ conversion: ReadableExport.Conversion, domains: Set<ReadableExport.Domain>, sleep: SleepStore, health: HealthStore, control: BackupOperationControl, source: Source? = nil) async throws {
        let (snapshot, preferences) = try conversion.selected(domains)
        let preview = Preview(snapshot: snapshot, createdAt: conversion.exportedAt, encrypted: false, photos: [:], photoIdentities: [:], contents: nil, workspace: nil, source: source)
        try await restore(preview, selection: preferences, sleep: sleep, health: health, control: control)
    }

    /// The selected source remains owned by the caller throughout this bounded
    /// read; provenance is checked before and after decoding at the call sites.
    nonisolated private static func readPayload(_ source: Source, limit: Int, control: BackupOperationControl, invalid: Error) throws -> Data {
        #if DEBUG && targetEnvironment(simulator)
        HealthReadUIFixture.willReadOriginalPayload(control: control)
        #endif
        do { return try HealthLocalFiles.readRegularData(source.url, limit: limit, control: control) }
        catch is CancellationError { throw CancellationError() }
        catch HealthLocalFiles.Failure.changed { throw BackupError.recordsChanged }
        catch { try control.checkCancellation(); throw invalid }
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
        #if DEBUG && targetEnvironment(simulator)
        let inputDescriptor = input.fileDescriptor, outputDescriptor = output.fileDescriptor
        var outputClosed = false
        defer {
            var inputClosed = false
            do { try input.close(); inputClosed = true } catch { }
            if !outputClosed { do { try output.close(); outputClosed = true } catch { } }
            HealthReadUIFixture.didClose(control: control, descriptor: inputDescriptor, succeeded: inputClosed)
            HealthReadUIFixture.didClose(control: control, descriptor: outputDescriptor, succeeded: outputClosed)
        }
        #else
        defer { try? input.close(); try? output.close() }
        #endif
        var copied = 0
        while copied < size {
            try control.checkCancellation()
            guard let data = try input.read(upToCount: min(BackupPackage.bufferBytes, size - copied)), !data.isEmpty else { throw BackupError.invalid }
            try output.write(contentsOf: data); copied += data.count
            if report { control.update(.preparing, bytes: Int64(copied)) }
            #if DEBUG && targetEnvironment(simulator)
            if report {
                try HealthReadUIFixture.pause(control: control, file: source, descriptor: inputDescriptor, bytesRead: data.count,
                                              copyTarget: target, outputDescriptor: outputDescriptor)
            }
            #endif
        }
        guard try input.read(upToCount: 1)?.isEmpty != false else { throw BackupError.invalid }
        try output.close()
        #if DEBUG && targetEnvironment(simulator)
        outputClosed = true
        #endif
        try control.checkCancellation()
        return Int64(size)
    }
}
