import Foundation
import CryptoKit
import Darwin

enum BackupSourceOwnershipChecks {
    static func completedTaskRetention(output: URL? = nil) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Lumen-task-result-ownership-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let raw = Task.detached {
            let workspace = try BackupWorkspace(base: root)
            try Data("Synthetic task result".utf8).write(to: workspace.directory.appendingPathComponent("selected-backup"))
            return workspace
        }
        let rawDirectory = try await raw.value.directory
        BackupWorkspace.finishCleanupForVerification()
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label); print("PASS: " + label) }
        check(fm.fileExists(atPath: rawDirectory.appendingPathComponent("selected-backup").path), "actual completed Task result retains a raw temporary workspace with no separate UI value")
        let cached = Task.detached {
            let workspace = try BackupWorkspace(base: root)
            try Data("Synthetic closable result".utf8).write(to: workspace.directory.appendingPathComponent("selected-backup"))
            return BackupReviewLease(workspace)
        }
        let owner = try await cached.value
        let ownedDirectory = try owner.acquire(control: .init()).directory
        owner.close()
        BackupWorkspace.finishCleanupForVerification()
        check(!fm.fileExists(atPath: ownedDirectory.path), "closing a returned owner releases temporary files while the actual completed Task result remains cached")
        withExtendedLifetime(raw) {}; withExtendedLifetime(cached) {}
        if let output {
            try JSONSerialization.data(withJSONObject: ["status": "passed", "count": checks.count, "checks": checks,
                "scope": "Actual completed Swift Task results and Foundation workspace lifetime. All tasks completed; no in-flight deletion or native UI acceptance inferred."], options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }
    static func leaveAbandonedWorkspace(at base: URL) throws {
        let workspace = try BackupWorkspace(base: base)
        try withExtendedLifetime(workspace) {
            try FileHandle.standardOutput.write(contentsOf: Data((workspace.directory.path + "\n").utf8))
            // Test executable only: terminate before Swift deinit can retire
            // the operation. This never enters the application target.
            _exit(0)
        }
    }
    private final class Action: @unchecked Sendable {
        private let lock = NSLock()
        private var operation: (() -> Void)?
        func install(_ value: @escaping () -> Void) { lock.lock(); operation = value; lock.unlock() }
        func once() { lock.lock(); let value = operation; operation = nil; lock.unlock(); value?() }
    }

    static func run(output: URL? = nil) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Lumen-source-ownership-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label); print("PASS: " + label) }
        func rejects(_ label: String, _ body: () throws -> Void) { var rejected = false; do { try body() } catch { rejected = true }; check(rejected, label) }
        let source = root.appendingPathComponent("input.json")
        let bytes = Data(repeating: 0x61, count: 192 * 1024 + 17)
        try bytes.write(to: source)
        let identity = try BackupSourceIdentity.measure(source, named: "Original export 🧭.json", format: .readableExport, limit: Int64(bytes.count))
        check(identity.fileName == "Original export 🧭.json" && identity.format == .readableExport && identity.byteCount == Int64(bytes.count), "source identity retains literal original name, declared format and exact byte length")
        check(identity.sha256 == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "chunked source fingerprint matches all original bytes across multiple chunks")
        try identity.verify(source)
        check(try JSONDecoder().decode(BackupSourceIdentity.self, from: JSONEncoder().encode(identity)) == identity, "source identity roundtrips without passwords, device state or local paths")
        let relabeled = identity.reclassified(.legacyJSONBackup)
        check(relabeled.sha256 == identity.sha256 && relabeled.byteCount == identity.byteCount && relabeled.fileName == identity.fileName, "format classification does not replace the checked file fingerprint")
        rejects("oversized input rejects before source hashing") { _ = try BackupSourceIdentity.measure(source, named: "input", format: .readableExport, limit: Int64(bytes.count - 1)) }
        rejects("invalid source limit rejects") { _ = try BackupSourceIdentity.measure(source, named: "input", format: .readableExport, limit: 0) }
        let wide = try BackupSourceIdentity.measure(source, named: "wide", format: .readableExport, limit: Int64.max)
        check(wide.byteCount == Int64(bytes.count), "maximum representable source ceiling does not overflow chunk arithmetic")
        let empty = root.appendingPathComponent("empty"); try Data().write(to: empty)
        rejects("empty input is not a selected backup source") { _ = try BackupSourceIdentity.measure(empty, named: "empty", format: .legacyJSONBackup, limit: 10) }
        let link = root.appendingPathComponent("input-link"); try fm.createSymbolicLink(at: link, withDestinationURL: source)
        rejects("source fingerprint never follows a symbolic link") { _ = try BackupSourceIdentity.measure(link, named: "link", format: .readableExport, limit: Int64(bytes.count)) }
        rejects("source fingerprint rejects directory input") { _ = try BackupSourceIdentity.measure(root, named: "directory", format: .readableExport, limit: 100) }
        let fifo = root.appendingPathComponent("input-fifo"); precondition(mkfifo(fifo.path, 0o600) == 0)
        rejects("source fingerprint rejects a FIFO without blocking") { _ = try BackupSourceIdentity.measure(fifo, named: "fifo", format: .readableExport, limit: 100) }
        var changed = bytes; changed[0] ^= 1; try changed.write(to: source, options: .atomic)
        rejects("same-length changed source bytes reject the original reviewed identity") { try identity.verify(source) }
        try bytes.write(to: source, options: .atomic)
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("source fingerprint observes cancellation before opening") { _ = try BackupSourceIdentity.measure(source, named: "cancel", format: .readableExport, limit: Int64(bytes.count), control: cancelled) }
        let stop = Action(), cancellation = BackupOperationControl(observer: { _ in stop.once() })
        stop.install { cancellation.cancel() }
        var stopped = false
        do { _ = try BackupSourceIdentity.measure(source, named: "cancel", format: .readableExport, limit: Int64(bytes.count), control: cancellation) }
        catch is CancellationError { stopped = true }
        check(stopped, "source fingerprint stops between actual read chunks when its operation is cancelled")
        let replacement = Action(), replaceControl = BackupOperationControl(observer: { _ in replacement.once() })
        replacement.install { try! changed.write(to: source, options: .atomic) }
        rejects("path replacement during an open descriptor read rejects even when original bytes were read") { _ = try BackupSourceIdentity.measure(source, named: "replace", format: .readableExport, limit: Int64(bytes.count), control: replaceControl) }

        let base = root.appendingPathComponent("workspaces"); try fm.createDirectory(at: base, withIntermediateDirectories: false)
        var first: BackupWorkspace? = try BackupWorkspace(base: base)
        let owned = first!.directory, payload = owned.appendingPathComponent("selected-backup")
        try bytes.write(to: payload)
        var worker = first
        first!.cleanup(); first = nil
        check(fm.fileExists(atPath: payload.path), "a cleanup request and UI-owner release cannot delete a worker-owned selected file")
        var other: BackupWorkspace? = try BackupWorkspace(base: base)
        check(fm.fileExists(atPath: payload.path) && other!.directory != owned, "a new operation preserves another live workspace instead of globally clearing temporary sources")
        worker!.cleanup()
        check(try Data(contentsOf: payload) == bytes, "worker can still read exact source bytes after another owner requests cleanup")
        worker = nil
        BackupWorkspace.finishCleanupForVerification()
        check(!fm.fileExists(atPath: owned.path), "last workspace release removes only its own private directory")
        let original = other!.directory, moved = base.appendingPathComponent("held-original")
        try fm.moveItem(at: original, to: moved)
        try fm.createDirectory(at: original, withIntermediateDirectories: false)
        let unrelated = original.appendingPathComponent("different-owner.txt"); try Data("keep".utf8).write(to: unrelated)
        other = nil
        BackupWorkspace.finishCleanupForVerification()
        check(fm.fileExists(atPath: unrelated.path), "final release does not erase a replacement directory at the old workspace path")
        let outside = root.appendingPathComponent("outside"); try fm.createDirectory(at: outside, withIntermediateDirectories: false)
        let sentinel = outside.appendingPathComponent("keep"); try Data("keep".utf8).write(to: sentinel)
        let candidate = base.appendingPathComponent("LumenBackupWork-v1-123-" + UUID().uuidString)
        try fm.createSymbolicLink(at: candidate, withDestinationURL: outside)
        let legacy = base.appendingPathComponent("LumenBackupWork-legacy-unknown")
        try fm.createDirectory(at: legacy, withIntermediateDirectories: false)
        let child = Process(), childOutput = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = ["--backup-workspace-exit-check", base.path]
        child.standardOutput = childOutput
        try child.run(); child.waitUntilExit()
        check(child.terminationStatus == 0, "actual child process creates a private workspace and terminates before cleanup")
        let abandoned = URL(fileURLWithPath: String(decoding: childOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        var actualParent = stat(), expectedParent = stat()
        let sameParent = lstat(abandoned.deletingLastPathComponent().path, &actualParent) == 0 && lstat(base.path, &expectedParent) == 0 && actualParent.st_dev == expectedParent.st_dev && actualParent.st_ino == expectedParent.st_ino
        check(sameParent && fm.fileExists(atPath: abandoned.path), "terminated child's actual owned directory remains available for checked reclamation")
        let final = try BackupWorkspace(base: base)
        check(!fm.fileExists(atPath: abandoned.path), "new operation reclaims an actual terminated owner's marked workspace")
        check(fm.fileExists(atPath: sentinel.path) && fm.fileExists(atPath: candidate.path), "abandoned-work scan never follows or removes a symbolic-link workspace")
        check(fm.fileExists(atPath: legacy.path), "unknown legacy workspace is not treated as proven abandoned")
        withExtendedLifetime(final) {}
        func reviewLease() throws -> (BackupReviewLease<BackupWorkspace>, URL) {
            let workspace = try BackupWorkspace(base: base)
            try bytes.write(to: workspace.directory.appendingPathComponent("selected-backup"))
            return (BackupReviewLease(workspace), workspace.directory)
        }
        let (review, reviewDirectory) = try reviewLease()
        let cachedNavigationValue = review
        var cancelledAcquire = false
        do { _ = try review.acquire(control: cancelled) } catch is CancellationError { cancelledAcquire = true }
        var reviewWorker: BackupWorkspace? = try review.acquire(control: .init())
        check(cancelledAcquire && reviewWorker?.directory == reviewDirectory, "cancelled review acquisition preserves the UI owner for a fresh worker")
        let reviewFile = reviewDirectory.appendingPathComponent("selected-backup")
        let activeDescriptor = try FileHandle(forReadingFrom: reviewFile)
        review.close(); cachedNavigationValue.close()
        check(fm.fileExists(atPath: reviewFile.path), "closing review and cached navigation owners preserves an already acquired worker file")
        var closedAcquire = false
        do { _ = try cachedNavigationValue.acquire(control: .init()) } catch is CancellationError { closedAcquire = true }
        check(closedAcquire, "closed cached navigation cannot start a new file worker")
        check(try activeDescriptor.read(upToCount: 65_536) == Data(bytes.prefix(65_536)), "actual open worker descriptor still reads exact bytes after UI review closes")
        try activeDescriptor.close(); reviewWorker = nil
        BackupWorkspace.finishCleanupForVerification()
        check(!fm.fileExists(atPath: reviewDirectory.path), "last worker release cleans files while obsolete closed navigation handles remain cached")
        withExtendedLifetime(cachedNavigationValue) {}
        if let output {
            let report: [String: Any] = ["status": "passed", "count": checks.count, "checks": checks,
                "scope": "Actual Foundation descriptor/hash/cancellation and shared-workspace file lifetime. No actual UIKit service ownership, held native navigation, capacity, recovery receipt or device acceptance."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }
}
