import Foundation

/// Prepares a complete replacement off the main actor. Installing it remains a short,
/// explicit commit after the caller checks that the captured local revision is current.
final class BackupFileTransaction: @unchecked Sendable {
    private let directory: URL
    private let stage: URL
    private var committed = false
    private let lock = NSLock()
    private init(directory: URL, stage: URL) { self.directory = directory; self.stage = stage }
    deinit {
        if !committed {
            let folder = stage
            DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: folder) }
        }
    }

    static func prepare(_ files: [String: Data], photoFiles: [String: URL], into directory: URL,
                        control: BackupOperationControl = .init()) throws -> BackupFileTransaction {
        let fm = FileManager.default
        try control.checkCancellation()
        try BackupFiles.recover(directory)
        let stage = directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + ".restore-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var prepared = false
        defer { if !prepared { try? fm.removeItem(at: stage) } }
        control.update(.restoring)
        var copied: Int64 = 0
        let basePath = directory.resolvingSymlinksInPath().path
        if fm.fileExists(atPath: directory.path) {
            var enumerationError: Error?
            guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw BackupError.invalid }
            for case let source as URL in entries {
                try control.checkCancellation()
                let attributes = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                let sourcePath = source.resolvingSymlinksInPath().path
                guard attributes.isSymbolicLink != true, sourcePath.hasPrefix(basePath + "/") else { throw BackupError.invalid }
                let relative = String(sourcePath.dropFirst(basePath.count + 1))
                guard safe(relative) else { throw BackupError.invalid }
                let target = stage.appendingPathComponent(relative)
                if attributes.isDirectory == true { try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
                else {
                    guard attributes.isRegularFile == true else { throw BackupError.invalid }
                    copied += try copyFile(source, to: target, control: control)
                    control.update(.restoring, bytes: copied)
                }
            }
            if let enumerationError { throw enumerationError }
        }
        var completed = 0
        let total = files.count + photoFiles.count
        for path in files.keys.sorted() {
            try control.checkCancellation()
            guard safe(path), photoFiles[path] == nil else { throw BackupError.invalid }
            let target = stage.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files[path]!.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            completed += 1; control.update(.restoring, completed: completed, total: total, bytes: copied)
        }
        for path in photoFiles.keys.sorted() {
            try control.checkCancellation()
            guard safe(path), path.hasPrefix("photos/"), path.hasSuffix(".jpg") else { throw BackupError.invalid }
            let source = photoFiles[path]!
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= BackupArchive.maxPhotoBytes else { throw BackupError.invalid }
            copied += try copyFile(source, to: stage.appendingPathComponent(path), control: control)
            completed += 1; control.update(.restoring, completed: completed, total: total, bytes: copied)
        }
        try control.checkCancellation()
        prepared = true
        return BackupFileTransaction(directory: directory, stage: stage)
    }

    func commit() throws {
        lock.lock(); defer { lock.unlock() }
        guard !committed else { throw BackupError.invalid }
        let fm = FileManager.default, previous = directory.appendingPathExtension("previous")
        try BackupFiles.recover(directory)
        if fm.fileExists(atPath: directory.path) { try fm.moveItem(at: directory, to: previous) }
        do { try fm.moveItem(at: stage, to: directory); committed = true }
        catch { try? BackupFiles.recover(directory); throw error }
        if fm.fileExists(atPath: previous.path) {
            let retired = directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + ".retired-" + UUID().uuidString)
            if (try? fm.moveItem(at: previous, to: retired)) != nil {
                DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: retired) }
            }
        }
    }
    func discard() {
        lock.lock(); defer { lock.unlock() }
        if !committed { try? FileManager.default.removeItem(at: stage) }
    }
    private static func safe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
        && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func copyFile(_ source: URL, to target: URL, control: BackupOperationControl) throws -> Int64 {
        let fm = FileManager.default
        let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, let size = attributes.fileSize, size >= 0 else { throw BackupError.invalid }
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
