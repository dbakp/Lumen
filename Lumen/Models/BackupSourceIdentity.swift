import Foundation
import CryptoKit
import Darwin

/// Identifies selected bytes, not their author or authenticity. Never contains
/// a password, local path, device owner or imported Health work.
struct BackupSourceIdentity: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case encryptedBackup, legacyJSONBackup, readableExport }
    let fileName: String
    let format: Format
    let byteCount: Int64
    let sha256: String

    func reclassified(_ format: Format) -> Self {
        Self(fileName: fileName, format: format, byteCount: byteCount, sha256: sha256)
    }

    static func measure(_ file: URL, named name: String, format: Format, limit: Int64,
                        control: BackupOperationControl = .init()) throws -> Self {
        try control.checkCancellation()
        guard limit > 0, limit <= Int64(Int.max), !name.isEmpty,
              name.utf8.count <= 4096, !name.contains("\0") else { throw BackupError.invalid }
        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            #if DEBUG && targetEnvironment(simulator)
            var closed = false
            do { try input.close(); closed = true } catch { }
            HealthReadUIFixture.didClose(control: control, descriptor: descriptor, succeeded: closed)
            #else
            try? input.close()
            #endif
        }
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), before.st_size > 0 else { throw BackupError.invalid }
        guard before.st_size <= limit else { throw BackupPackage.PackageError.tooLarge }
        var hash = SHA256(), count: Int64 = 0
        while true {
            try control.checkCancellation()
            let remaining = limit - count
            let block = try input.read(upToCount: remaining >= 64 * 1024 ? 64 * 1024 : Int(remaining) + 1) ?? Data()
            if block.isEmpty { break }
            guard Int64(block.count) <= limit - count else { throw BackupPackage.PackageError.tooLarge }
            hash.update(data: block); count += Int64(block.count)
            control.update(.reading, bytes: count)
            #if DEBUG && targetEnvironment(simulator)
            try HealthReadUIFixture.pause(control: control, file: file, descriptor: descriptor, bytesRead: Int(count))
            #endif
        }
        try control.checkCancellation()
        var after = stat(), path = stat()
        guard fstat(descriptor, &after) == 0, lstat(file.path, &path) == 0,
              path.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              path.st_dev == after.st_dev, path.st_ino == after.st_ino,
              path.st_size == after.st_size,
              before.st_size == after.st_size, count == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              path.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              path.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              path.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              path.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw BackupError.recordsChanged }
        return Self(fileName: name, format: format, byteCount: count,
                    sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    func verify(_ file: URL, control: BackupOperationControl = .init()) throws {
        let current = try Self.measure(file, named: fileName, format: format, limit: byteCount, control: control)
        guard current == self else { throw BackupError.recordsChanged }
    }
}
