import Foundation

enum LocalCommitChecks {
    static func run(output: URL? = nil) throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("Lumen-local-commit-" + UUID().uuidString)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }
        var passed = 0
        func check(_ value: Bool, _ label: String) {
            precondition(value, label); passed += 1; print("PASS: " + label)
        }
        func bytes(_ text: String) -> Data { Data(text.utf8) }
        func read(_ root: URL, _ file: String) throws -> String { try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8) }
        func inode(_ path: URL) throws -> UInt64 { (try fm.attributesOfItem(atPath: path.path)[.systemFileNumber] as! NSNumber).uint64Value }
        let root = parent.appendingPathComponent("LumenData")
        try fm.createDirectory(at: root.appendingPathComponent("photos"), withIntermediateDirectories: true)
        for (name, value) in ["goals.json":"old-goals", "today.json":"old-today", "water.json":"unchanged-water", "photos/one.jpg":"owned-photo"] {
            try bytes(value).write(to: root.appendingPathComponent(name), options: .atomic)
        }
        let originalPhotoInode = try inode(root.appendingPathComponent("photos/one.jpg"))
        let changes = ["goals.json":bytes("new-goals"), "today.json":bytes("new-today")]
        let revision = BackupStorageRevision()
        let captured = revision.current
        let transaction = try BackupFileTransaction.prepare(changes, photoFiles: [:], into: root, preserveByLink: true)
        check(try read(root,"goals.json") == "old-goals" && read(root,"today.json") == "old-today", "staged weight pair does not change either original file")
        let stage = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("LumenData.restore-") }!
        check(try inode(stage.appendingPathComponent("photos/one.jpg")) == originalPhotoInode, "unchanged meal photo is hard-linked without copying its bytes")
        check(try inode(stage.appendingPathComponent("goals.json")) != inode(root.appendingPathComponent("goals.json")), "atomic staged replacement does not overwrite the original hard-linked goal inode")
        try revision.commit(ifUnchanged: captured) { try transaction.commit() }
        check(try read(root,"goals.json") == "new-goals" && read(root,"today.json") == "new-today", "guarded commit installs both new weight files")
        check(try read(root,"water.json") == "unchanged-water" && read(root,"photos/one.jpg") == "owned-photo", "weight commit preserves other domains and photo bytes")
        check(try inode(root.appendingPathComponent("photos/one.jpg")) == originalPhotoInode, "committed unchanged photo retains its inode")

        let staleRevision = revision.current
        let stale = try BackupFileTransaction.prepare(["goals.json":bytes("stale")], photoFiles: [:], into: root, preserveByLink: true)
        try revision.write { try bytes("newer-water").write(to: root.appendingPathComponent("water.json"), options: .atomic) }
        do { try revision.commit(ifUnchanged: staleRevision) { try stale.commit() }; preconditionFailure("stale commit accepted") }
        catch BackupError.recordsChanged { check(true,"concurrent local write rejects the stale staged weight commit") }
        stale.discard()
        check(try read(root,"goals.json") == "new-goals" && read(root,"water.json") == "newer-water", "rejected stale commit preserves existing weight and newer records")

        let failed = try BackupFileTransaction.prepare(changes, photoFiles: [:], into: root, preserveByLink: true)
        let stages = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("LumenData.restore-") }
        for stage in stages { try fm.removeItem(at: stage) }
        do { try failed.commit(); preconditionFailure("missing stage accepted") }
        catch { check(true,"actual missing-stage installation failure is surfaced") }
        check(try read(root,"goals.json") == "new-goals" && read(root,"today.json") == "new-today", "failed installation recovers the complete old pair")

        let blocked = root.appendingPathComponent("blocked.json")
        try fm.createDirectory(at: blocked, withIntermediateDirectories: true)
        do { _ = try BackupFileTransaction.prepare(["blocked.json":bytes("cannot-write")], photoFiles: [:], into: root, preserveByLink: true); preconditionFailure("directory destination accepted") }
        catch { check(true,"real file write failure during staging is surfaced") }
        check(try read(root,"goals.json") == "new-goals" && read(root,"today.json") == "new-today", "failed staging cannot install a partial weight update")
        try fm.removeItem(at: blocked)
        let outside = parent.appendingPathComponent("outside")
        try bytes("outside-bytes").write(to: outside)
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        do { _ = try BackupFileTransaction.prepare(changes, photoFiles: [:], into: root, preserveByLink: true); preconditionFailure("symbolic link accepted") }
        catch { check(true,"linked staging rejects a symbolic link instead of following it") }
        check(try String(contentsOf: outside, encoding: .utf8) == "outside-bytes", "rejected symbolic link leaves its external target unchanged")
        try fm.removeItem(at: link)
        let rootLink = parent.appendingPathComponent("root-link")
        try fm.createSymbolicLink(at: rootLink, withDestinationURL: root)
        do { _ = try BackupFileTransaction.prepare(changes, photoFiles: [:], into: rootLink, preserveByLink: true); preconditionFailure("linked root accepted") }
        catch { check(true,"staging rejects a symbolic-link root") }
        let cancelled = BackupOperationControl(); cancelled.cancel()
        do { _ = try BackupFileTransaction.prepare(changes, photoFiles: [:], into: root, control: cancelled, preserveByLink: true); preconditionFailure("cancelled preparation accepted") }
        catch is CancellationError { check(true,"cancelled preparation cannot publish weight files") }
        let final = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("LumenData.restore-") }
        check(final.isEmpty,"failed and discarded stages leave no live preparation directories")
        if let output {
            try JSONSerialization.data(withJSONObject: ["passed":passed,"scope":"Actual Foundation disk operations and production staged transaction/revision; not HealthStore UI or HealthKit"], options: [.prettyPrinted,.sortedKeys]).write(to: output, options: .atomic)
        }
    }
}
