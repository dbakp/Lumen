import Foundation
import Darwin

/// Source, preview and workers share ownership. A cleanup request cannot remove
/// another owner's files; only the final release schedules deletion.
final class BackupWorkspace: Sendable {
    let directory: URL
    private let device: dev_t
    private let inode: ino_t
    private struct Owner: Codable { let version: Int; let pid: Int32; let id: UUID }
    private static let prefix = "LumenBackupWork-v1-"
    private static let marker = ".lumen-workspace-owner.json"
    private static let cleanupQueue = DispatchQueue(label: "Lumen.backup-workspace-cleanup", qos: .utility)

    init(base: URL = FileManager.default.temporaryDirectory) throws {
        let fm = FileManager.default
        var baseFacts = stat()
        guard lstat(base.path, &baseFacts) == 0,
              baseFacts.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw BackupError.invalid }
        Self.reclaimAbandoned(in: base)
        let owner = Owner(version: 1, pid: getpid(), id: UUID())
        directory = base.appendingPathComponent(Self.prefix + String(owner.pid) + "-" + owner.id.uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var facts = stat()
        guard lstat(directory.path, &facts) == 0 else { throw BackupError.invalid }
        device = facts.st_dev; inode = facts.st_ino
        do {
            try JSONEncoder().encode(owner).write(to: directory.appendingPathComponent(Self.marker), options: .atomic)
        } catch { try? fm.removeItem(at: directory); throw error }
    }

    /// Retains the lifetime-fence API used by existing defer callers. Releasing
    /// their Source/Export values permits cleanup after any remaining workers.
    func cleanup() { withExtendedLifetime(self) {} }

    deinit {
        let folder = directory, expectedDevice = device, expectedInode = inode
        Self.cleanupQueue.async {
            var current = stat()
            guard lstat(folder.path, &current) == 0,
                  current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                  current.st_dev == expectedDevice, current.st_ino == expectedInode else { return }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    #if os(macOS)
    static func finishCleanupForVerification() { cleanupQueue.sync {} }
    #endif

    private static func reclaimAbandoned(in base: URL) {
        let fm = FileManager.default
        for candidate in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        where candidate.lastPathComponent.hasPrefix(prefix) {
            var facts = stat()
            guard lstat(candidate.path, &facts) == 0,
                  facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), facts.st_uid == geteuid(),
                  let bytes = try? HealthLocalFiles.readRegularData(candidate.appendingPathComponent(marker), limit: 1024),
                  let owner = try? JSONDecoder().decode(Owner.self, from: bytes), owner.version == 1, owner.pid > 0,
                  candidate.lastPathComponent == prefix + String(owner.pid) + "-" + owner.id.uuidString else { continue }
            // A live/permission-inaccessible/reused PID is not abandoned.
            guard kill(owner.pid, 0) == -1, errno == ESRCH else { continue }
            var latest = stat()
            guard lstat(candidate.path, &latest) == 0, latest.st_dev == facts.st_dev,
                  latest.st_ino == facts.st_ino else { continue }
            try? fm.removeItem(at: candidate)
        }
    }
}
