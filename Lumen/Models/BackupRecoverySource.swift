import Foundation
import Darwin
import CryptoKit

/// Exact authenticated/archive photo bytes, independent of their temporary path.
struct BackupPhotoIdentity: Codable, Equatable, Sendable {
    let byteCount: Int
    let sha256: String

    func boundary(_ file: URL) throws -> BackupSourceLease.Boundary {
        var value = stat()
        guard byteCount > 0, byteCount <= BackupArchive.maxPhotoBytes,
              lstat(file.path, &value) == 0, value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              value.st_size == Int64(byteCount) else { throw BackupError.recordsChanged }
        return .init(device: Int64(value.st_dev), inode: UInt64(value.st_ino), size: value.st_size,
                     modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanos: Int64(value.st_mtimespec.tv_nsec),
                     changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanos: Int64(value.st_ctimespec.tv_nsec))
    }
    func read(_ file: URL, control: BackupOperationControl = .init()) throws -> Data {
        try checked(file, control: control).data
    }
    func verifiedBoundary(_ file: URL, control: BackupOperationControl) throws -> BackupSourceLease.Boundary {
        try checked(file, control: control).boundary
    }
    private func checked(_ file: URL, control: BackupOperationControl) throws -> (data: Data, boundary: BackupSourceLease.Boundary) {
        try control.checkCancellation()
        let before = try boundary(file)
        let data = try HealthLocalFiles.readRegularData(file, limit: BackupArchive.maxPhotoBytes, control: control)
        try control.checkCancellation()
        guard try BackupPhotoIdentity(data: data) == self, try boundary(file) == before else { throw BackupError.recordsChanged }
        return (data, before)
    }
}
extension BackupPhotoIdentity {
    init(data: Data) throws {
        guard !data.isEmpty, data.count <= BackupArchive.maxPhotoBytes else { throw BackupError.missingPhoto }
        self.init(byteCount: data.count, sha256: BackupArchive.digest(data))
    }
}

/// Owns the selected bytes while review, preparation and installation use them.
/// The cheap final boundary check follows a complete off-thread hash check.
struct BackupSourceLease: Sendable {
    let file: URL
    let identity: BackupSourceIdentity
    let workspace: BackupWorkspace

    struct Boundary: Equatable, Sendable {
        let device: Int64; let inode: UInt64; let size: Int64
        let modifiedSeconds: Int64; let modifiedNanos: Int64
        let changedSeconds: Int64; let changedNanos: Int64
    }
    private func boundary() throws -> Boundary {
        var value = stat()
        guard lstat(file.path, &value) == 0,
              value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_size == identity.byteCount else { throw BackupError.recordsChanged }
        return Boundary(device: Int64(value.st_dev), inode: UInt64(value.st_ino), size: value.st_size,
                        modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanos: Int64(value.st_mtimespec.tv_nsec),
                        changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanos: Int64(value.st_ctimespec.tv_nsec))
    }
    func verifiedBoundary(control: BackupOperationControl) throws -> Boundary {
        defer { workspace.cleanup() }
        let before = try boundary()
        try identity.verify(file, control: control)
        let after = try boundary()
        guard before == after else { throw BackupError.recordsChanged }
        return after
    }
    func verify(_ expected: Boundary) throws {
        guard try boundary() == expected else { throw BackupError.recordsChanged }
    }
}

struct BackupRecoverySource: Sendable {
    let lease: BackupSourceLease
    let photoWorkspace: BackupWorkspace?
    let contents: BackupPackage.Contents?
    var photoIdentities: [String: BackupPhotoIdentity] = [:]
    var omittedPhotoCount: Int = 0
}

/// Cached navigation values share this UI owner instead of retaining files
/// themselves. Each actual worker acquires its own strong value before starting;
/// ending review prevents new work without deleting any active worker's files.
final class BackupReviewLease<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    init(_ value: Value) { self.value = value }
    func acquire(control: BackupOperationControl) throws -> Value {
        try control.checkCancellation()
        lock.lock(); let retained = value; lock.unlock()
        guard let retained else { throw CancellationError() }
        try control.checkCancellation()
        return retained
    }
    func close() {
        lock.lock(); let previous = value; value = nil; lock.unlock()
        withExtendedLifetime(previous) {}
    }
}
