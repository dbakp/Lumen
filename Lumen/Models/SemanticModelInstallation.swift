import Foundation
import CoreML
import CryptoKit

enum SemanticModelInstallation {
    enum Phase: Sendable { case cleaning, downloading, checking, preparing }
    enum Source: Sendable {
        case remote
        #if DEBUG
        case fixture(URL, delayNanoseconds: UInt64)
        #endif
    }
    struct File: Codable, Sendable, Equatable { var path: String; var bytes: Int64; var sha256: String }
    struct Receipt: Codable, Sendable {
        var version = 1
        var modelID = SemanticModelPackage.identifier
        var installationID: String
        var files: [File]
    }
    enum InstallError: Error { case existing, space, invalid, response }
    static let compiledName = "Model.mlmodelc"

    static func prepare(at destination: URL, source: Source = .remote, vocabulary: Data, installationID: UUID,
                        progress: @escaping @Sendable (Phase, Int64?) -> Void) async throws {
        try Task.checkCancellation()
        let fm = FileManager.default, parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try removeAbandonedStages(in: parent)
        guard !fm.fileExists(atPath: destination.path) else { throw InstallError.existing }
        // The owner has no installed encoder when beginning a fresh download.
        // Reclaim verified old runtime copies before checking preparation space.
        progress(.cleaning, nil)
        try MiniLMRuntimeCache.purgeCurrentApp()
        let free = (try fm.attributesOfFileSystem(forPath: parent.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free >= 250_000_000 else { throw InstallError.space }
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var protectedParent = parent; try protectedParent.setResourceValues(excluded)
        let stage = parent.appendingPathComponent(".pending-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        #if os(iOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: stage.path)
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 240
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var completed: Int64 = 0
        for asset in SemanticModelPackage.assets {
            try Task.checkCancellation()
            progress(.downloading, completed)
            let output = stage.appendingPathComponent(asset.path)
            try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let base = completed
            let update: @Sendable (Int64) -> Void = { current in progress(.downloading, base + min(asset.bytes, current)) }
            switch source {
            case .remote:
                let delegate = TransferProgress(limit: asset.bytes, update: update)
                let (temporary, response) = try await session.download(for: URLRequest(url: asset.url), delegate: delegate)
                defer { try? fm.removeItem(at: temporary) }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw InstallError.response }
                try Task.checkCancellation()
                try fm.moveItem(at: temporary, to: output)
            #if DEBUG
            case let .fixture(directory, delay):
                let input = try FileHandle(forReadingFrom: directory.appendingPathComponent(asset.path))
                defer { try? input.close() }
                guard fm.createFile(atPath: output.path, contents: nil) else { throw InstallError.invalid }
                let writer = try FileHandle(forWritingTo: output); defer { try? writer.close() }
                var written: Int64 = 0
                while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                    try Task.checkCancellation(); written += Int64(data.count)
                    guard written <= asset.bytes else { throw InstallError.invalid }
                    try writer.write(contentsOf: data); update(written)
                    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                }
            #endif
            }
            progress(.checking, nil)
            try SemanticModelPackage.validate(output, asset: asset)
            completed += asset.bytes
            progress(.checking, completed)
        }
        try Task.checkCancellation()
        progress(.preparing, nil)
        let compiled = try await MLModel.compileModel(at: stage.appendingPathComponent("all-minilm-l6-v2.mlpackage"))
        defer { try? fm.removeItem(at: compiled) }
        try Task.checkCancellation()
        let inventory = try files(in: compiled)
        let check = try MiniLMEncoder(compiledModel: compiled, vocabulary: vocabulary)
        do { _ = try await check.queryVector("Check the local Library search model.") }
        catch { await check.stop(); throw error }
        await check.stop()
        // The private self-check can create a second runtime-compiled weight
        // copy. No MiniLM encoder is active here; remove only pinned caches
        // before the final installed-path load creates its reusable cache.
        try MiniLMRuntimeCache.purgeCurrentApp()
        try Task.checkCancellation()
        try fm.moveItem(at: compiled, to: stage.appendingPathComponent(compiledName, isDirectory: true))
        // Compilation/self-check finished. Retain only the usable compiled model,
        // not another 45 MB copy of its downloaded weights.
        try fm.removeItem(at: stage.appendingPathComponent("all-minilm-l6-v2.mlpackage"))
        let receipt = try JSONEncoder().encode(Receipt(installationID: installationID.uuidString, files: inventory))
        try receipt.write(to: stage.appendingPathComponent("installation.json"), options: .atomic)
        try Task.checkCancellation()
        try fm.moveItem(at: stage, to: destination)
        do { try Task.checkCancellation() }
        catch { try? fm.removeItem(at: destination); throw error }
    }

    static func load(at directory: URL, vocabulary: Data) throws -> MiniLMEncoder {
        try validateDirectory(directory)
        let receiptURL = directory.appendingPathComponent("installation.json")
        guard (try receiptURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])).isSymbolicLink != true,
              ((try receiptURL.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? .max) <= 64_000 else { throw InstallError.invalid }
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL))
        guard receipt.version == 1, receipt.modelID == SemanticModelPackage.identifier, UUID(uuidString: receipt.installationID) != nil,
              receipt.files == (try files(in: directory.appendingPathComponent(compiledName))) else { throw InstallError.invalid }
        return try MiniLMEncoder(compiledModel: directory.appendingPathComponent(compiledName), vocabulary: vocabulary)
    }

    static func removeNewInstallation(at directory: URL, installationID: UUID) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try validateDirectory(directory)
        let url = directory.appendingPathComponent("installation.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true,
              (values.fileSize ?? .max) <= 64_000 else { throw InstallError.invalid }
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: url))
        guard receipt.installationID == installationID.uuidString else { return }
        try FileManager.default.removeItem(at: directory)
    }

    static func files(in directory: URL) throws -> [File] {
        try validateDirectory(directory)
        // macOS exposes /var through /private/var; the enumerator returns the
        // canonical spelling even when Core ML returns the shorter root URL.
        // Check the root itself for symlinks first, then normalize its ancestors.
        let directory = directory.resolvingSymlinksInPath().standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
            enumerationError = error; return false
        }) else { throw InstallError.invalid }
        var result: [File] = [], bytes: Int64 = 0
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw InstallError.invalid }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, let size = values.fileSize, size >= 0, result.count < 128 else { throw InstallError.invalid }
            bytes += Int64(size); guard bytes <= 128_000_000 else { throw InstallError.invalid }
            let path = file.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(directory.path + "/") else { throw InstallError.invalid }
            let relative = String(path.dropFirst(directory.path.count + 1))
            guard !relative.isEmpty, relative.utf8.count <= 1000, !relative.hasPrefix("/"), !relative.contains("\\"),
                  relative.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw InstallError.invalid }
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
            result.append(File(path: relative, bytes: Int64(size), sha256: hash.finalize().map { String(format: "%02x", $0) }.joined()))
        }
        if let enumerationError { throw enumerationError }
        guard !result.isEmpty else { throw InstallError.invalid }
        return result.sorted { $0.path < $1.path }
    }

    private static func validateDirectory(_ directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw InstallError.invalid }
    }

    /// The owner calls this only before starting a new installation, after any
    /// earlier worker has stopped. A terminated process can leave its private
    /// stage behind; unrelated names and symlinks are never traversed.
    static func removeAbandonedStages(in parent: URL) throws {
        try validateDirectory(parent)
        for item in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            try Task.checkCancellation()
            let name = item.lastPathComponent
            guard name.hasPrefix(".pending-"), UUID(uuidString: String(name.dropFirst(9))) != nil else { continue }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            try FileManager.default.removeItem(at: item)
        }
    }

    private final class TransferProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let limit: Int64
        let update: @Sendable (Int64) -> Void
        init(limit: Int64, update: @escaping @Sendable (Int64) -> Void) { self.limit = limit; self.update = update }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if totalBytesWritten > limit { downloadTask.cancel() } else { update(totalBytesWritten) }
        }
    }
}
