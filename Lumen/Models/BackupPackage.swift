import Foundation
import AppleArchive
import System

/// Password-protected, framed records inside an Apple Encrypted Archive.
/// Photos and archive bytes are streamed; no whole-archive/base64 payload is built.
enum BackupPackage {
    static let maxFileBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let maxMetadataBytes = 100 * 1024 * 1024
    static let maxRecordBytes = 32 * 1024 * 1024
    static let bufferBytes = 64 * 1024
    private static let profile = ArchiveEncryptionContext.Profile.hkdf_sha256_aesctr_hmac__scrypt__none
    private static let kinds = ["profile", "goals", "habits", "sleep", "meals", "workouts", "water", "conversations", "symptoms", "checkIns", "documents", "importedDays", "imports", "personalContext"]

    struct Manifest: Codable, Sendable {
        var format = "LumenStreamBackup"
        var version = 2
        var createdAt: Date
        var counts: [String: Int]
        var photoCount: Int
        func validate() throws {
            guard format == "LumenStreamBackup" else { throw PackageError.invalid }
            guard version == 2 else { throw BackupError.version }
            guard createdAt.timeIntervalSince1970.isFinite, Set(counts.keys) == Set(kinds), (0...200_000).contains(photoCount),
                  counts.values.allSatisfy({ (0...200_000).contains($0) }),
                  ["profile", "goals", "personalContext"].allSatisfy({ counts[$0] == 1 }),
                  counts.values.reduce(0, +) <= 700_003 else { throw PackageError.invalid }
        }
    }
    private struct Frame: Codable { var kind: String; var length: Int; var id: String? }

    /// Caller owns this private directory until preview/restore finishes.
    final class Contents: Sendable {
        let manifest: Manifest
        let snapshot: BackupSnapshot
        let photos: [String: URL]
        let directory: URL
        init(manifest: Manifest, snapshot: BackupSnapshot, photos: [String: URL], directory: URL) {
            self.manifest = manifest; self.snapshot = snapshot; self.photos = photos; self.directory = directory
        }
        deinit {
            let folder = directory
            DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: folder) }
        }
        func removeTemporaryFiles() { try? FileManager.default.removeItem(at: directory) }
    }

    static func validateNewPassword(_ password: String) throws {
        guard password.count >= 12, password.utf8.count <= 256 else { throw PackageError.passwordLength }
    }

    static func write(_ snapshot: BackupSnapshot, photos: [String: URL], password: String, to destination: URL,
                      now: Date = Date(), control: BackupOperationControl = .init()) throws {
        try validateNewPassword(password)
        try control.checkCancellation()
        guard snapshot.photos.isEmpty, Set(photos.keys) == Set(snapshot.meals.compactMap(\.photoID)) else { throw PackageError.invalid }
        try BackupArchive.validate(snapshot, availablePhotoIDs: Set(photos.keys))
        let counts = ["profile": 1, "goals": 1, "habits": snapshot.habits.count, "sleep": snapshot.sleep.count,
                      "meals": snapshot.meals.count, "workouts": snapshot.workouts.count, "water": snapshot.water.count,
                      "conversations": snapshot.conversations.count, "symptoms": snapshot.symptoms.count, "checkIns": snapshot.checkIns.count,
                      "documents": snapshot.documents.count, "importedDays": snapshot.importedDays.count, "imports": snapshot.imports.count, "personalContext": 1]
        let manifest = Manifest(createdAt: now, counts: counts, photoCount: photos.count)
        try manifest.validate()
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw PackageError.file }
        let partial = destination.deletingLastPathComponent().appendingPathComponent(".lumen-backup-\(UUID().uuidString).partial")
        defer { try? fm.removeItem(at: partial) }
        let context = ArchiveEncryptionContext(profile: profile, compressionAlgorithm: .lzfse, compressionBlockSize: 1 << 20)
        try context.setPassword(password)
        guard let file = fileStream(partial, writing: true) else { throw PackageError.file }
        defer { try? file.close() }
        guard let encrypted = ArchiveByteStream.encryptionStream(writingTo: file, encryptionContext: context, threadCount: 1) else { throw PackageError.file }
        defer { try? encrypted.close() }
        var expanded: Int64 = 0, metadata = 0, completed = 0
        let total = counts.values.reduce(0, +) + photos.count
        func writeBytes(_ bytes: Data) throws {
            try control.checkCancellation()
            guard expanded <= maxFileBytes - Int64(bytes.count) else { throw PackageError.tooLarge }
            try bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    try control.checkCancellation()
                    let written = try encrypted.write(from: UnsafeRawBufferPointer(rebasing: buffer[offset...]))
                    guard written > 0, written <= buffer.count - offset else { throw PackageError.file }
                    offset += written
                }
            }
            expanded += Int64(bytes.count)
        }
        func frame(_ header: Frame) throws {
            let bytes = try BackupArchive.encoder().encode(header)
            guard bytes.count <= 16_384 else { throw PackageError.invalid }
            var length = UInt32(bytes.count).bigEndian
            try withUnsafeBytes(of: &length) { try writeBytes(Data($0)) }
            try writeBytes(bytes)
        }
        func record<T: Encodable>(_ kind: String, _ value: T, counted: Bool = true) throws {
            try control.checkCancellation()
            let bytes = try BackupArchive.encoder().encode(value)
            guard bytes.count <= maxRecordBytes, metadata <= maxMetadataBytes - bytes.count else { throw PackageError.metadataTooLarge }
            metadata += bytes.count
            try frame(.init(kind: kind, length: bytes.count)); try writeBytes(bytes)
            if counted { completed += 1; control.update(.writing, completed: completed, total: total, bytes: expanded) }
        }
        control.update(.writing, completed: 0, total: total)
        try record("manifest", manifest, counted: false)
        try record("profile", snapshot.profile); try record("goals", snapshot.goals)
        for value in snapshot.habits { try record("habits", value) }
        for value in snapshot.sleep { try record("sleep", value) }
        for value in snapshot.meals { try record("meals", value) }
        for value in snapshot.workouts { try record("workouts", value) }
        for value in snapshot.water { try record("water", value) }
        for value in snapshot.conversations { try record("conversations", value) }
        for value in snapshot.symptoms { try record("symptoms", value) }
        for value in snapshot.checkIns { try record("checkIns", value) }
        for value in snapshot.documents { try record("documents", value) }
        for value in snapshot.importedDays { try record("importedDays", value) }
        for value in snapshot.imports { try record("imports", value) }
        try record("personalContext", snapshot.personalContext)
        for id in photos.keys.sorted() {
            try control.checkCancellation()
            let url = photos[id]!
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  let size = attributes.fileSize, size > 0, size <= BackupArchive.maxPhotoBytes else { throw BackupError.missingPhoto }
            try frame(.init(kind: "photo", length: size, id: id))
            let source = try FileHandle(forReadingFrom: url); defer { try? source.close() }
            var remaining = size
            while remaining > 0 {
                try control.checkCancellation()
                guard let chunk = try source.read(upToCount: min(bufferBytes, remaining)), !chunk.isEmpty else { throw BackupError.missingPhoto }
                try writeBytes(chunk); remaining -= chunk.count
            }
            guard try source.read(upToCount: 1)?.isEmpty != false else { throw BackupError.missingPhoto }
            completed += 1; control.update(.writing, completed: completed, total: total, bytes: expanded)
        }
        try frame(.init(kind: "end", length: 0))
        try encrypted.close(); try file.close()
        try control.checkCancellation()
        let size = try partial.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, Int64(size) <= maxFileBytes else { throw PackageError.tooLarge }
        // Never replace an existing user-owned destination. The service supplies a fresh owned name.
        guard !fm.fileExists(atPath: destination.path) else { throw PackageError.file }
        try fm.moveItem(at: partial, to: destination)
    }

    static func read(_ source: URL, password: String, temporaryRoot: URL = FileManager.default.temporaryDirectory,
                     control: BackupOperationControl = .init()) throws -> Contents {
        try control.checkCancellation()
        guard !password.isEmpty, password.utf8.count <= 1024 else { throw PackageError.unlock }
        let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, let size = attributes.fileSize, size > 0 else { throw PackageError.invalid }
        guard Int64(size) <= maxFileBytes else { throw PackageError.tooLarge }
        guard let file = fileStream(source, writing: false) else { throw PackageError.file }
        defer { try? file.close() }
        guard let context = ArchiveEncryptionContext(from: file), context.profile == profile else { throw PackageError.invalid }
        control.update(.unlocking)
        do { try context.setPassword(password) } catch { throw PackageError.unlock }
        guard context.decryptAttributes() else { throw PackageError.unlock }
        try control.checkCancellation()
        guard context.rawSize > 0, context.rawSize <= maxFileBytes,
              (1...4 * 1024 * 1024).contains(context.compressionBlockSize), context.compressionAlgorithm == .lzfse else { throw PackageError.tooLarge }
        guard context.containerSize == size else { throw PackageError.invalid }
        guard let decrypted = ArchiveByteStream.decryptionStream(readingFrom: file, encryptionContext: context, threadCount: 1) else { throw PackageError.unlock }
        defer { try? decrypted.close() }
        let directory = temporaryRoot.appendingPathComponent("LumenBackupPreview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
        var expanded: Int64 = 0, metadata = 0
        func bytes(_ count: Int) throws -> Data {
            try control.checkCancellation()
            guard count >= 0, expanded <= maxFileBytes - Int64(count) else { throw PackageError.tooLarge }
            var data = Data(count: count)
            try data.withUnsafeMutableBytes { buffer in
                var offset = 0
                while offset < count {
                    try control.checkCancellation()
                    let n: Int
                    do { n = try decrypted.read(into: UnsafeMutableRawBufferPointer(rebasing: buffer[offset...])) } catch { throw PackageError.unlock }
                    guard n > 0, n <= count - offset else { throw PackageError.invalid }
                    offset += n
                }
            }
            expanded += Int64(count)
            return data
        }
        func frame() throws -> Frame {
            let prefix = try bytes(4)
            let length = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= 16_384 else { throw PackageError.invalid }
            do { return try BackupArchive.decoder().decode(Frame.self, from: bytes(Int(length))) }
            catch let error as PackageError { throw error }
            catch is CancellationError { throw CancellationError() }
            catch { throw PackageError.invalid }
        }
        func record<T: Decodable>(_ header: Frame, as type: T.Type) throws -> T {
            guard header.id == nil, header.length > 0, header.length <= maxRecordBytes,
                  metadata <= maxMetadataBytes - header.length else { throw PackageError.metadataTooLarge }
            metadata += header.length
            let data = try bytes(header.length)
            do { return try BackupArchive.decoder().decode(type, from: data) } catch { throw PackageError.invalid }
        }
        let first = try frame()
        guard first.kind == "manifest" else { throw PackageError.invalid }
        let manifest = try record(first, as: Manifest.self); try manifest.validate()
        var snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        var photos: [String: URL] = [:], counts: [String: Int] = [:], completed = 0
        let total = manifest.counts.values.reduce(0, +) + manifest.photoCount
        while true {
            let header = try frame()
            if header.kind == "end" {
                guard header.length == 0, header.id == nil else { throw PackageError.invalid }
                break
            }
            if header.kind == "photo" {
                guard let id = header.id, BackupArchive.safePhotoID(id), photos[id] == nil, photos.count < manifest.photoCount,
                      header.length > 0, header.length <= BackupArchive.maxPhotoBytes else { throw PackageError.invalid }
                let url = directory.appendingPathComponent("photo-\(photos.count).jpg")
                try Data().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
                var remaining = header.length
                while remaining > 0 {
                    let chunk = try bytes(min(bufferBytes, remaining)); try output.write(contentsOf: chunk); remaining -= chunk.count
                }
                try output.close(); photos[id] = url
            } else {
                guard kinds.contains(header.kind), counts[header.kind, default: 0] < manifest.counts[header.kind, default: 0] else { throw PackageError.invalid }
                counts[header.kind, default: 0] += 1
                switch header.kind {
                case "profile": snapshot.profile = try record(header, as: UserProfile.self)
                case "goals": snapshot.goals = try record(header, as: HealthGoals.self)
                case "habits": snapshot.habits.append(try record(header, as: SleepHabit.self))
                case "sleep": snapshot.sleep.append(try record(header, as: SleepEpisode.self))
                case "meals": snapshot.meals.append(try record(header, as: Meal.self))
                case "workouts": snapshot.workouts.append(try record(header, as: Workout.self))
                case "water": snapshot.water.append(try record(header, as: HydrationLog.self))
                case "conversations": snapshot.conversations.append(try record(header, as: HealthConversation.self))
                case "symptoms": snapshot.symptoms.append(try record(header, as: SymptomEntry.self))
                case "checkIns": snapshot.checkIns.append(try record(header, as: WellbeingCheckIn.self))
                case "documents": snapshot.documents.append(try record(header, as: HealthDocument.self))
                case "importedDays": snapshot.importedDays.append(try record(header, as: ImportedHealthDay.self))
                case "imports": snapshot.imports.append(try record(header, as: ImportReceipt.self))
                case "personalContext": snapshot.personalContext = try record(header, as: PersonalHealthContext.self)
                default: throw PackageError.invalid
                }
            }
            completed += 1; control.update(.reading, completed: completed, total: total, bytes: expanded)
        }
        guard kinds.allSatisfy({ counts[$0, default: 0] == manifest.counts[$0] }), photos.count == manifest.photoCount,
              Set(photos.keys) == Set(snapshot.meals.compactMap(\.photoID)) else { throw PackageError.invalid }
        var trailing = Data(count: 1)
        let end: Int
        do { end = try trailing.withUnsafeMutableBytes { try decrypted.read(into: $0) }; try decrypted.close() }
        catch { throw PackageError.unlock }
        guard end == 0, expanded == context.rawSize else { throw PackageError.invalid }
        try BackupArchive.validate(snapshot, availablePhotoIDs: Set(photos.keys))
        try control.checkCancellation()
        succeeded = true
        return .init(manifest: manifest, snapshot: snapshot, photos: photos, directory: directory)
    }

    private static func fileStream(_ url: URL, writing: Bool) -> ArchiveByteStream? {
        ArchiveByteStream.fileStream(path: FilePath(url.path), mode: writing ? .writeOnly : .readOnly,
                                     options: writing ? [.create, .exclusiveCreate] : [], permissions: FilePermissions(rawValue: 0o600))
    }

    enum PackageError: LocalizedError {
        case passwordLength, unlock, invalid, tooLarge, metadataTooLarge, file
        var errorDescription: String? {
            switch self {
            case .passwordLength: return "Use a password with at least 12 characters. If it’s very long, shorten it."
            case .unlock: return "The password may be incorrect or this file may be damaged. Check the password or choose another copy. No records were changed."
            case .invalid: return "This file isn’t a supported Lumen backup. No records were changed."
            case .tooLarge: return "This backup exceeds the 2 GB archive or expanded-data limit. No records were changed."
            case .metadataTooLarge: return "The records exceed the 100 MB metadata or 32 MB single-record limit. Meal photos have a separate allowance. No records were changed."
            case .file: return "The backup file couldn’t be completed. Your current records and previous backup are unchanged."
            }
        }
    }
}

final class BackupOperationControl: @unchecked Sendable {
    enum Stage: Sendable { case preparing, writing, unlocking, reading, checkingPhotos, restoring }
    struct Progress: Sendable { var stage: Stage; var completed: Int; var total: Int; var bytes: Int64; var detail: String? = nil }
    private let lock = NSLock()
    private var cancelled = false
    private var cancellationHandler: (@Sendable () -> Void)?
    private let observer: (@Sendable (Progress) -> Void)?
    init(observer: (@Sendable (Progress) -> Void)? = nil) { self.observer = observer }
    private var state = Progress(stage: .preparing, completed: 0, total: 0, bytes: 0)
    var progress: Progress { lock.lock(); defer { lock.unlock() }; return state }
    func cancel() {
        lock.lock(); cancelled = true; let handler = cancellationHandler; lock.unlock()
        handler?()
    }
    func setCancellationHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock(); cancellationHandler = handler; let stop = cancelled; lock.unlock()
        if stop { handler?() }
    }
    func checkCancellation() throws { lock.lock(); let stop = cancelled; lock.unlock(); if stop || Task.isCancelled { throw CancellationError() } }
    func update(_ stage: Stage, completed: Int = 0, total: Int = 0, bytes: Int64 = 0, detail: String? = nil) {
        let value = Progress(stage: stage, completed: completed, total: total, bytes: bytes, detail: detail)
        lock.lock(); state = value; lock.unlock()
        observer?(value)
    }
}
