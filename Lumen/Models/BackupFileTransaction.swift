import Foundation
import CryptoKit
import Darwin

/// Prepares a complete replacement off the main actor. Installing it remains a short,
/// explicit commit after the caller checks that the captured local revision is current.
final class BackupFileTransaction: @unchecked Sendable {
    private let directory: URL
    private let stage: URL
    private let preserveHealthCopies: Bool
    private let cachePreviousSnapshot: [String: Stamp]?
    private let sourceSnapshot: [String: Stamp]
    private let legacyOrigins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin]
    private let legacy: @Sendable (String) throws -> Any?
    private let legacyRetention: HealthRecoveryCopies.LegacyRetention?
    private struct Stamp: Equatable {
        let kind: FileAttributeType; let inode: UInt64; let device: UInt64; let size: UInt64; let modified: Date?
    }
    private var committed = false
    private let lock = NSLock()
    private var selectedSource: (BackupRecoverySource, BackupSourceLease.Boundary)?
    private struct CheckedPhoto {
        let identity: BackupPhotoIdentity
        let stageBoundary: BackupSourceLease.Boundary
        let sourceURL: URL
        let sourceBoundary: BackupSourceLease.Boundary?
        let sourceInCurrentRoot: Bool
    }
    private let stagedPhotos: [String: CheckedPhoto]
    private init(directory: URL, stage: URL, preserveHealthCopies: Bool, sourceSnapshot: [String: Stamp],
                 stagedPhotos: [String: CheckedPhoto], cachePreviousSnapshot: [String: Stamp]? = nil,
                 legacyOrigins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin],
                 legacy: @escaping @Sendable (String) throws -> Any?, legacyRetention: HealthRecoveryCopies.LegacyRetention?) {
        self.directory = directory; self.stage = stage; self.preserveHealthCopies = preserveHealthCopies; self.sourceSnapshot = sourceSnapshot
        self.stagedPhotos = stagedPhotos
        self.cachePreviousSnapshot = cachePreviousSnapshot
        self.legacyOrigins = legacyOrigins; self.legacy = legacy; self.legacyRetention = legacyRetention
    }
    deinit {
        if !committed {
            let folder = stage
            DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: folder) }
        }
    }

    static func prepare(_ files: [String: Data], photoFiles: [String: URL], into directory: URL,
                        control: BackupOperationControl = .init(), preserveByLink: Bool = false,
                        preserveExisting: Bool = true,
                        recoveringHealthDomains: Set<HealthLocalFiles.Domain> = [],
                        replacingDailyCache: Bool = false,
                        expectedPhotoDigests: [String: String] = [:],
                        legacyOrigins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin] = [:],
                        legacy: @escaping @Sendable (String) throws -> Any? = { UserDefaults.standard.object(forKey: $0) }) throws -> BackupFileTransaction {
        let fm = FileManager.default
        guard recoveringHealthDomains.isEmpty || (preserveExisting && recoveringHealthDomains.allSatisfy { files[$0.rawValue + ".json"] != nil }),
              Set(expectedPhotoDigests.keys).isSubset(of: Set(photoFiles.keys)),
              Set(legacyOrigins.keys).isSubset(of: recoveringHealthDomains),
              legacyOrigins.allSatisfy({ $0.key == $0.value.value.domain }),
              legacyOrigins.values.reduce(0, { $0 + $1.value.bytes.count }) <= HealthLegacyRecoveryOrigin.aggregateLimit,
              !replacingDailyCache || (preserveExisting && recoveringHealthDomains.isEmpty && files["today.json"] != nil) else { throw BackupError.invalid }
        try control.checkCancellation()
        for origin in legacyOrigins.values { try origin.verify(in: directory, legacy: legacy, control: control) }
        // Explicit cache replacement must not retire .previous merely because
        // preparation began. It uses an atomic directory exchange at commit.
        if replacingDailyCache { try BackupFiles.openDirectory(directory, createIfMissing: false) }
        else { try BackupFiles.recover(directory, recoveringLegacyDomains: Set(legacyOrigins.keys)) }
        let cachePreviousSnapshot = replacingDailyCache ? try snapshot(directory.appendingPathExtension("previous")) : nil
        let sourceSnapshot = preserveExisting ? try snapshot(directory) : [:]
        if fm.fileExists(atPath: directory.path) {
            let root = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard root.isDirectory == true, root.isSymbolicLink != true else { throw BackupError.invalid }
        }
        let stage = directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + ".restore-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var prepared = false
        defer { if !prepared { try? fm.removeItem(at: stage) } }
        control.update(.restoring)
        #if DEBUG && targetEnvironment(simulator)
        if !recoveringHealthDomains.isEmpty || replacingDailyCache {
            try HealthRecoveryCancelUIFixture.pause(control: control, stage: stage, root: directory)
        }
        #endif
        var copied: Int64 = 0
        let basePath = directory.resolvingSymlinksInPath().path
        if preserveExisting, fm.fileExists(atPath: directory.path) {
            var enumerationError: Error?
            guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw BackupError.invalid }
            for case let source as URL in entries {
                try control.checkCancellation()
                if source.resolvingSymlinksInPath().path == basePath + "/" + HealthRecoveryCopies.name {
                    // Discovery can publish private copies while this unlocked
                    // clone runs. Carry the latest private tree at commit,
                    // under the common lock, rather than racing pending names.
                    entries.skipDescendants(); continue
                }
                let attributes = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                let sourcePath = source.resolvingSymlinksInPath().path
                guard attributes.isSymbolicLink != true, sourcePath.hasPrefix(basePath + "/") else { throw BackupError.invalid }
                let relative = String(sourcePath.dropFirst(basePath.count + 1))
                guard safe(relative) else { throw BackupError.invalid }
                let target = stage.appendingPathComponent(relative)
                if attributes.isDirectory == true { try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
                else {
                    guard attributes.isRegularFile == true else { throw BackupError.invalid }
                    // Local multi-file changes retain existing regular-file inodes.
                    // Every LocalStore writer replaces its file atomically; staged
                    // replacements below must do the same. Never link directories
                    // or follow symbolic links. Restore keeps its independent copy.
                    if preserveByLink { try fm.linkItem(at: source, to: target) }
                    else { copied += try copyFile(source, to: target, control: control) }
                    control.update(.restoring, bytes: copied)
                }
            }
            if let enumerationError { throw enumerationError }
        }
        let legacyRetention = try HealthRecoveryCopies.preserveReplacedDomains(in: stage, domains: recoveringHealthDomains,
                                                                             legacyOrigins: legacyOrigins, control: control)
        if replacingDailyCache {
            // Seed immutable current copies before comparing prior incidents;
            // otherwise each cache action duplicates unrelated failed history.
            try HealthRecoveryCopies.serialized {
                try control.checkCancellation()
                try HealthRecoveryCopies.carryPrivateCopies(from: directory, into: stage)
            }
            try HealthRecoveryCopies.preservePrevious(in: stage, from: directory.appendingPathExtension("previous"), control: control)
            try HealthRecoveryCopies.preserveDailyCache(in: stage)
        }
        var completed = 0
        let total = files.count + photoFiles.count
        for path in files.keys.sorted() {
            try control.checkCancellation()
            guard safe(path), photoFiles[path] == nil else { throw BackupError.invalid }
            let target = stage.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if DEBUG && targetEnvironment(simulator)
            try QuickLogDiskFault.write(domain: preserveByLink ? path : "restore", target: target) {
                try files[path]!.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            #else
            try files[path]!.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #endif
            completed += 1; control.update(.restoring, completed: completed, total: total, bytes: copied)
        }
        var stagedPhotos: [String: CheckedPhoto] = [:]
        for path in photoFiles.keys.sorted() {
            try control.checkCancellation()
            guard safe(path), path.hasPrefix("photos/"), path.hasSuffix(".jpg") else { throw BackupError.invalid }
            let source = photoFiles[path]!
            let size = (try fm.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= BackupArchive.maxPhotoBytes else { throw BackupError.invalid }
            copied += try copyFile(source, to: stage.appendingPathComponent(path), control: control, limit: BackupArchive.maxPhotoBytes)
            let copiedFile = stage.appendingPathComponent(path)
            let identity = try BackupPhotoIdentity(data: HealthLocalFiles.readRegularData(copiedFile, limit: BackupArchive.maxPhotoBytes))
            if let expected = expectedPhotoDigests[path], identity.sha256 != expected { throw BackupError.recordsChanged }
            try BackupFiles.openDirectory(source.deletingLastPathComponent(), createIfMissing: false)
            stagedPhotos[path] = CheckedPhoto(identity: identity,
                stageBoundary: try identity.verifiedBoundary(copiedFile, control: control), sourceURL: source,
                sourceBoundary: expectedPhotoDigests[path] == nil ? nil : try identity.verifiedBoundary(source, control: control),
                sourceInCurrentRoot: source.resolvingSymlinksInPath().path.hasPrefix(basePath + "/"))
            completed += 1; control.update(.restoring, completed: completed, total: total, bytes: copied)
        }
        try control.checkCancellation()
        for origin in legacyOrigins.values { try origin.verify(in: directory, legacy: legacy, control: control) }
        let transaction = BackupFileTransaction(directory: directory, stage: stage, preserveHealthCopies: preserveExisting, sourceSnapshot: sourceSnapshot, stagedPhotos: stagedPhotos, cachePreviousSnapshot: cachePreviousSnapshot,
                                                legacyOrigins: legacyOrigins, legacy: legacy, legacyRetention: legacyRetention)
        // Until every throwing check succeeds, this function still owns stage
        // cleanup. Only the initialized transaction can take that ownership.
        prepared = true
        return transaction
    }

    func commit() throws { try commit(control: nil) }

    func retainSource(_ source: BackupRecoverySource, boundary: BackupSourceLease.Boundary) throws {
        lock.lock(); defer { lock.unlock() }
        guard !committed else { throw BackupError.invalid }
        try source.lease.verify(boundary)
        selectedSource = (source, boundary)
    }

    func commit(control: BackupOperationControl?) throws {
        lock.lock(); defer { lock.unlock() }
        try HealthRecoveryCopies.serialized {
        guard !committed else { throw BackupError.invalid }
        try control?.checkCancellation()
        let fm = FileManager.default, previous = directory.appendingPathExtension("previous")
        try BackupFiles.openDirectory(directory, createIfMissing: false)
        // Check source identities before retiring any prior copy. This catches
        // actual external file replacement/removal during detached preparation,
        // in addition to the caller's revision and health payload boundaries.
        if preserveHealthCopies, try Self.snapshot(directory) != sourceSnapshot { throw BackupError.recordsChanged }
        try control?.checkCancellation()
        if let cachePreviousSnapshot {
            guard try Self.snapshot(previous) == cachePreviousSnapshot else { throw BackupError.recordsChanged }
        } else { try BackupFiles.recover(directory) }
        // Retained photos can live inside the root whose private copies we
        // carry below. Check their full source token before making hardlinks.
        for observed in stagedPhotos.values {
            try control?.checkCancellation()
            if let boundary = observed.sourceBoundary {
                try BackupFiles.openDirectory(observed.sourceURL.deletingLastPathComponent(), createIfMissing: false)
                guard try observed.identity.boundary(observed.sourceURL) == boundary else { throw BackupError.recordsChanged }
            }
        }
        if preserveHealthCopies { try HealthRecoveryCopies.carryPrivateCopies(from: directory, into: stage) }
        if cachePreviousSnapshot != nil { try HealthRecoveryCopies.carryPrivateCopies(from: previous, into: stage) }
        // This is the cancellation boundary, inside both commit locks and
        // after preparation/validation. Once directory installation starts,
        // finish it and report its actual saved outcome.
        try control?.checkCancellation()
        if let (source, boundary) = selectedSource { try source.lease.verify(boundary) }
        if !stagedPhotos.isEmpty { try BackupFiles.openDirectory(stage.appendingPathComponent("photos"), createIfMissing: false) }
        // Full byte checks ran during preparation. Detect any replacement or
        // in-place stage mutation immediately before installation using stats.
        for (path, observed) in stagedPhotos {
            try control?.checkCancellation()
            guard try observed.identity.boundary(stage.appendingPathComponent(path)) == observed.stageBoundary else { throw BackupError.recordsChanged }
            if let boundary = observed.sourceBoundary {
                try BackupFiles.openDirectory(observed.sourceURL.deletingLastPathComponent(), createIfMissing: false)
                let current = try observed.identity.boundary(observed.sourceURL)
                if observed.sourceInCurrentRoot {
                    // Our own private-copy hardlinks update inode ctime. The
                    // earlier full check and copied-byte digest remain required;
                    // identity/size/mtime must still match after preservation.
                    guard current.device == boundary.device, current.inode == boundary.inode, current.size == boundary.size,
                          current.modifiedSeconds == boundary.modifiedSeconds, current.modifiedNanos == boundary.modifiedNanos else { throw BackupError.recordsChanged }
                } else { guard current == boundary else { throw BackupError.recordsChanged } }
            }
        }
        if cachePreviousSnapshot != nil {
            // Both directories are on the same volume. Failure leaves both
            // paths unchanged; success has no missing-root interruption window.
            // The prior root remains untouched throughout this cache operation.
            guard renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, directory.path, UInt32(RENAME_SWAP)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            committed = true
            let oldCurrent = stage
            DispatchQueue.global(qos: .utility).async { try? fm.removeItem(at: oldCurrent) }
            return
        }
        // Called inside the existing commit locks. This direct fixed-key reader
        // must never reenter LocalStore's nonrecursive write/revision lock.
        if let legacyRetention { try HealthRecoveryCopies.verifyLegacyRetention(legacyRetention, in: stage, control: control ?? .init()) }
        for origin in legacyOrigins.values { try origin.verify(in: directory, legacy: legacy, control: control ?? .init()) }
        try control?.checkCancellation()
        if fm.fileExists(atPath: directory.path) { try fm.moveItem(at: directory, to: previous) }
        do { try fm.moveItem(at: stage, to: directory); committed = true }
        catch { try? BackupFiles.recover(directory); throw error }
        if fm.fileExists(atPath: previous.path) {
            let retired = directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + ".retired-" + UUID().uuidString)
            if (try? fm.moveItem(at: previous, to: retired)) != nil {
                DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: retired) }
            }
        }
        // A failed retirement leaves the marker in the committed reset root;
        // next recovery erases that prior root rather than reviving its copies.
        if !fm.fileExists(atPath: previous.path) { try? HealthRecoveryCopies.finishErasure(in: directory) }
        }
    }
    func discard() {
        lock.lock(); defer { lock.unlock() }
        if !committed { try? FileManager.default.removeItem(at: stage) }
    }
    private static func snapshot(_ root: URL) throws -> [String: Stamp] {
        let fm = FileManager.default
        let rootFacts: [FileAttributeKey: Any]
        do { rootFacts = try fm.attributesOfItem(atPath: root.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return [:] }
        guard rootFacts[.type] as? FileAttributeType == .typeDirectory else { throw BackupError.currentDataInvalid }
        var enumerationError: Error?
        // Foundation may preserve the /var spelling when resolving URLs while
        // its enumerator returns /private/var. Use the filesystem's physical
        // spelling for both enumeration and relative-path boundaries.
        guard let physicalPath = Darwin.realpath(root.path, nil) else { throw BackupError.currentDataInvalid }
        let canonicalRoot = URL(fileURLWithPath: String(cString: physicalPath), isDirectory: true)
        free(physicalPath)
        guard let entries = fm.enumerator(at: canonicalRoot, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw BackupError.currentDataInvalid }
        var result: [String: Stamp] = [:]
        for case let url as URL in entries {
            guard url.path.hasPrefix(canonicalRoot.path + "/") else { throw BackupError.currentDataInvalid }
            let relative = String(url.path.dropFirst(canonicalRoot.path.count + 1))
            if relative == HealthRecoveryCopies.name { entries.skipDescendants(); continue }
            let facts = try fm.attributesOfItem(atPath: url.path)
            guard let kind = facts[.type] as? FileAttributeType, kind == .typeDirectory || kind == .typeRegular,
                  let inode = facts[.systemFileNumber] as? NSNumber, let device = facts[.systemNumber] as? NSNumber else { throw BackupError.currentDataInvalid }
            result[relative] = Stamp(kind: kind, inode: inode.uint64Value, device: device.uint64Value,
                                     size: kind == .typeRegular ? (facts[.size] as? NSNumber)?.uint64Value ?? 0 : 0,
                                     modified: kind == .typeRegular ? facts[.modificationDate] as? Date : nil)
            guard result.count <= 1_000_000 else { throw BackupError.currentDataInvalid }
        }
        if let enumerationError { throw enumerationError }
        return result
    }
    private static func safe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
        && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func copyFile(_ source: URL, to target: URL, control: BackupOperationControl, limit: Int = Int.max) throws -> Int64 {
        let fm = FileManager.default
        // A selected URL can be reused after a rejected operation. Its cached
        // resource values can describe an older file, including an old size.
        let attributes = try fm.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let sizeValue = attributes[.size] as? NSNumber, sizeValue.int64Value >= 0,
              sizeValue.int64Value <= limit else { throw BackupError.invalid }
        let size = sizeValue.intValue
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: target)
        defer { try? input.close(); try? output.close() }
        var remaining = size
        while remaining > 0 {
            try control.checkCancellation()
            guard let data = try input.read(upToCount: min(BackupPackage.bufferBytes, remaining)), !data.isEmpty else { throw BackupError.invalid }
            try output.write(contentsOf: data); remaining -= data.count
        }
        guard try input.read(upToCount: 1)?.isEmpty != false else { throw BackupError.invalid }
        try output.close()
        return Int64(size)
    }
}
