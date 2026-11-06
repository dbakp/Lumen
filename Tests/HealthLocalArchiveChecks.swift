import Foundation

/// Uses frozen pre-repair payloads through the actual archive entry points.
enum HealthLocalArchiveChecks {
    static func encryptedCancellation(input: URL? = nil, output: URL? = nil) throws -> Bool {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("Lumen-encrypted-read-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let password = "Synthetic encrypted read passphrase 61"
        let focus = String(repeating: "encrypted chunk boundary ", count: 8192)
        let file: URL
        if let input { file = input }
        else {
            file = root.appendingPathComponent("original.lumenbackup")
            var value = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [],
                                       conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
            value.water = [.init(id: "encrypted-read-water", date: Date(timeIntervalSince1970: 1_700_000_000), ml: 137)]
            value.personalContext.focus = focus
            try BackupPackage.write(value, photos: [:], password: password, to: file, now: Date(timeIntervalSince1970: 1_700_000_000))
        }
        let original = try Data(contentsOf: file)
        if input == nil, let output { try original.write(to: output.deletingPathExtension().appendingPathExtension("lumenbackup")) }
        var rows: [[String: Any]] = []
        final class Stop: @unchecked Sendable {
            weak var control: BackupOperationControl?
            let unlock: Bool
            var reached = false, completed = 0, total = 0
            var previousBytes: Int64 = 0, largestStep: Int64 = 0, stoppedBytes: Int64 = 0
            init(unlock: Bool) { self.unlock = unlock }
            func observe(_ progress: BackupOperationControl.Progress) {
                if progress.stage == .reading {
                    largestStep = max(largestStep, progress.bytes - previousBytes); previousBytes = progress.bytes
                }
                if !reached && ((unlock && progress.stage == .unlocking) || (!unlock && progress.stage == .reading && progress.bytes >= 64 * 1024)) {
                    reached = true; completed = progress.completed; total = progress.total; stoppedBytes = progress.bytes; control?.cancel()
                }
            }
        }
        for (label, supplied, unlock) in [("correct password cancelled at unlock", password, true),
                                          ("wrong password cancelled at unlock", "Wrong synthetic encrypted passphrase 61", true),
                                          ("cancel within a multi-chunk record", password, false)] {
            let stop = Stop(unlock: unlock), control = BackupOperationControl(observer: { stop.observe($0) }); stop.control = control
            var observed = "accepted"
            do { let contents = try BackupPackage.read(file, password: supplied, temporaryRoot: root, control: control); contents.removeTemporaryFiles() }
            catch is CancellationError { observed = "CancellationError" }
            catch { observed = String(reflecting: error) }
            let passed = stop.reached && observed == "CancellationError" && (unlock || (stop.completed < stop.total && stop.largestStep <= 64 * 1024))
            rows.append(["case": label, "passed": passed, "observed": observed, "actualStageReached": stop.reached,
                         "completedAtCancel": stop.completed, "totalAtCancel": stop.total, "bytesAtCancel": stop.stoppedBytes, "largestReadingProgressStep": stop.largestStep])
            print((passed ? "PASS: " : "FAIL: ") + label + ": " + observed)
        }
        let retry = try BackupPackage.read(file, password: password, temporaryRoot: root)
        let healthy = retry.snapshot.water.first?.ml == 137 && retry.snapshot.personalContext.focus == focus
        retry.removeTemporaryFiles()
        var wrongPassword = false
        do { let invalid = try BackupPackage.read(file, password: "Wrong synthetic encrypted passphrase 61", temporaryRoot: root); invalid.removeTemporaryFiles() }
        catch BackupPackage.PackageError.unlock { wrongPassword = true }
        for (label, passed) in [("fresh encrypted retry returns every original field", healthy),
                                ("uncancelled incorrect password keeps unlock error", wrongPassword),
                                ("all cancelled and retried reads retain exact encrypted input bytes", try Data(contentsOf: file) == original),
                                ("failed and explicitly released preview directories are removed", try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).allSatisfy { !$0.lastPathComponent.hasPrefix("LumenBackupPreview-") })] {
            rows.append(["case": label, "passed": passed]); print((passed ? "PASS: " : "FAIL: ") + label)
        }
        let passed = rows.allSatisfy { $0["passed"] as? Bool == true }
        if let output {
            try JSONSerialization.data(withJSONObject: ["status": passed ? "passed" : "failed", "checks": rows,
                "passed": rows.filter { $0["passed"] as? Bool == true }.count, "failed": rows.filter { $0["passed"] as? Bool == false }.count,
                "inputBytes": original.count, "inputSHA256": BackupArchive.digest(original), "focusBytes": focus.utf8.count,
                "scope": "Actual encrypted file/password/decryption, cancellation at actual unlock progress and within large final record progress, healthy exact-field retry, wrong-password error and failed-preview cleanup. No native held stream/FD proof or atomic key-derivation preemption/full capacity acceptance."], options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
        return passed
    }
    static func payloadCancellation(output: URL? = nil) throws {
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label); print("PASS: " + label) }
        func cancellation(_ label: String, _ work: () throws -> Void) {
            var cancelled = false
            do { try work() } catch is CancellationError { cancelled = true } catch { }
            check(cancelled, label)
        }
        var value = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [],
                                   conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        value.water = (0..<2048).map { .init(id: "payload-water-\($0)", date: Date(timeIntervalSince1970: 1_700_000_000), ml: 137) }
        let bytes = try BackupArchive.make(value, now: Date(timeIntervalSince1970: 1_700_000_000))
        var envelope = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        envelope["sha256"] = String(repeating: "0", count: 64)
        let wrongHash = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        for (name, data) in [("valid", bytes), ("malformed", Data("{".utf8)), ("wrong hash", wrongHash)] {
            let control = BackupOperationControl(); control.cancel()
            cancellation("shared control cancels " + name + " legacy decode before interpretation") { _ = try BackupArchive.read(data, control: control) }
        }
        var malformed = false, integrity = false
        do { _ = try BackupArchive.read(Data("{".utf8)) } catch BackupError.invalid { malformed = true }
        do { _ = try BackupArchive.read(wrongHash) } catch BackupError.integrity { integrity = true }
        check(malformed, "uncancelled malformed legacy input keeps its format error")
        check(integrity, "uncancelled changed payload keeps its integrity error")
        final class Stop: @unchecked Sendable {
            weak var control: BackupOperationControl?
            var observed: Int64 = 0
            func observe(_ progress: BackupOperationControl.Progress) {
                if progress.bytes >= 64 * 1024 { observed = progress.bytes; control?.cancel() }
            }
        }
        let hashStop = Stop(), hashing = BackupOperationControl(observer: { hashStop.observe($0) }); hashStop.control = hashing
        cancellation("actual legacy payload hashing stops after its first64KiB chunk") { _ = try BackupArchive.read(bytes, control: hashing) }
        precondition(hashStop.observed == 64 * 1024)
        check(try BackupArchive.read(bytes).1.water.count == 2048, "fresh legacy retry verifies the same multi-chunk payload")
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("Lumen-payload-read-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let readableFile = root.appendingPathComponent("readable.json")
        try ReadableExport.write(value, to: readableFile, now: Date(timeIntervalSince1970: 1_700_000_000))
        let readable = try Data(contentsOf: readableFile)
        var boundaries: [[String: Any]] = []
        for (kind, data, limit) in [("legacy", bytes, BackupArchive.maxBytes), ("readable", readable, ReadableExport.maxBytes)] {
            let file = root.appendingPathComponent(kind + "-source.json"); try data.write(to: file)
            precondition(data.count > 64 * 1024)
            let stop = Stop(), control = BackupOperationControl(observer: { stop.observe($0) }); stop.control = control
            cancellation("actual " + kind + " file load stops after first64KiB without yielding payload") {
                _ = try HealthLocalFiles.readRegularData(file, limit: limit, control: control)
            }
            precondition(stop.observed == 64 * 1024)
            let fresh = BackupOperationControl(), read = try HealthLocalFiles.readRegularData(file, limit: limit, control: fresh)
            let count = kind == "legacy" ? try BackupArchive.read(read, control: fresh).1.water.count : try ReadableExport.read(read, control: fresh).snapshot.water.count
            check(count == 2048, "fresh " + kind + " actual file/decode retry returns every original record")
            check(try Data(contentsOf: file) == data, "cancelled and retried " + kind + " load retains exact source bytes")
            boundaries.append(["format": kind, "bytes": data.count, "sha256": BackupArchive.digest(data), "cancelledAfterBytes": stop.observed, "retryRecords": count])
        }
        if let output {
            try JSONSerialization.data(withJSONObject: ["status": "passed", "checks": checks, "passed": checks.count, "boundaries": boundaries,
                "scope": "Actual shared-control legacy decode/hash and bounded real legacy/readable file reads with fresh2048record retries and exact bytes. No mid-Foundation-decoder preemption, actual service/native route hold, encrypted unlock or capacity/full-contract acceptance."], options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }
    /// A cancelled worker must not return a preview or reinterpret cancellation
    /// as a malformed/integrity error. Each task cancels itself before entering
    /// the actual decoder; the parent and healthy retry use fresh tasks.
    static func decodeCancellation(output: URL? = nil) async throws -> Bool {
        var value = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [],
                                   conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        value.water = [.init(id: "decode-cancellation-water", date: Date(timeIntervalSince1970: 1_700_000_000), ml: 137)]
        let valid = try BackupArchive.make(value, now: Date(timeIntervalSince1970: 1_700_000_000))
        var envelope = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
        envelope["sha256"] = String(repeating: "0", count: 64)
        let wrongHash = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        let readable = Data("{\"app\":\"Lumen\",\"readableVersion\":1,\"exportedAt\":\"2023-11-14T22:13:20Z\",\"water\":[{\"id\":\"decode-cancellation-water\",\"date\":\"2023-11-14T22:13:20Z\",\"ml\":137}]}".utf8)
        var rows: [[String: Any]] = []
        for (kind, label, bytes) in [("legacy", "valid", valid), ("legacy", "malformed", Data("{".utf8)),
                                    ("legacy", "wrong hash", wrongHash), ("readable", "valid", readable),
                                    ("readable", "malformed", Data("{".utf8))] {
            let result = await Task.detached { () -> (observed: String, cancelled: Bool) in
                withUnsafeCurrentTask { $0?.cancel() }
                let cancelled = Task.isCancelled
                do {
                    if kind == "legacy" { _ = try BackupArchive.read(bytes) }
                    else { _ = try ReadableExport.read(bytes) }
                    return ("accepted", cancelled)
                } catch is CancellationError { return ("CancellationError", cancelled) }
                catch { return (String(reflecting: error), cancelled) }
            }.value
            let observed = result.observed, passed = result.cancelled && result.observed == "CancellationError"
            rows.append(["case": kind + " " + label + " cancelled worker", "passed": passed, "observed": observed, "workerWasCancelled": result.cancelled,
                         "inputBytes": bytes.count, "inputSHA256": BackupArchive.digest(bytes)])
            print((passed ? "PASS: " : "FAIL: ") + kind + " " + label + " cancelled worker: " + observed)
        }
        let legacyRetry = try await Task.detached { try BackupArchive.read(valid).1.water.first?.ml == 137 }.value
        let readableRetry = try await Task.detached { try ReadableExport.read(readable).snapshot.water.first?.ml == 137 }.value
        for (label, passed) in [("healthy legacy retry", legacyRetry), ("healthy readable retry", readableRetry),
                                ("parent task remains uncancelled", !Task.isCancelled)] {
            rows.append(["case": label, "passed": passed]); print((passed ? "PASS: " : "FAIL: ") + label)
        }
        let passed = rows.allSatisfy { $0["passed"] as? Bool == true }
        if let output {
            try JSONSerialization.data(withJSONObject: ["status": passed ? "passed" : "failed", "checks": rows,
                "passed": rows.filter { $0["passed"] as? Bool == true }.count, "failed": rows.filter { $0["passed"] as? Bool == false }.count,
                "scope": "Actual precancelled Swift worker decoder calls and fresh healthy retries. No mid-decoder interruption, actual service/native read, capacity or full-contract acceptance."], options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
        return passed
    }
    private struct Input: Decodable { let acceptedInvalidCases: [Row] }
    private struct Row: Decodable {
        let name: String; let domain: String; let currentBytes: Data
        enum CodingKeys: String, CodingKey { case name = "case", domain, currentBytes }
    }
    static func run(output: URL? = nil) throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let inputFile = repo.appendingPathComponent("Design/native/health-write-order/local-values-baseline-r1-report.json")
        let originalInput = try Data(contentsOf: inputFile)
        let input = try JSONDecoder().decode(Input.self, from: originalInput)
        var checks: [String] = [], payloads: [[String: String]] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label); print("PASS: " + label) }
        func rejects(_ label: String, _ work: () throws -> Void) {
            var failed = false
            do { try work() } catch { failed = true }
            check(failed, label)
        }
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("Lumen-local-value-archives-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let empty = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [],
                                   conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        let decoder = BackupArchive.decoder(), encoder = BackupArchive.encoder()
        let now = Date(timeIntervalSince1970: 1_700_000_000), password = "Synthetic value archive passphrase 43"
        for (index, row) in input.acceptedInvalidCases.enumerated() where row.domain != "today" {
            var value = empty
            switch row.domain {
            case "water": value.water = try decoder.decode([HydrationLog].self, from: row.currentBytes)
            case "meals": value.meals = try decoder.decode([Meal].self, from: row.currentBytes)
            case "workouts": value.workouts = try decoder.decode([Workout].self, from: row.currentBytes)
            case "goals": value.goals = try decoder.decode(HealthGoals.self, from: row.currentBytes)
            default: preconditionFailure("Unknown frozen archive domain")
            }
            payloads.append(["case": row.name, "domain": row.domain, "sha256": BackupArchive.digest(row.currentBytes)])
            rejects(row.name + " rejects legacy backup creation") { _ = try BackupArchive.make(value, now: now) }
            // Construct a correctly hashed envelope directly, so read validation
            // is tested independently of the writer's rejection above.
            let payload = try encoder.encode(value)
            let envelope = BackupArchive(format: "LumenBackup", version: 1, createdAt: now, payload: payload, sha256: BackupArchive.digest(payload))
            let bytes = try encoder.encode(envelope)
            rejects(row.name + " rejects a correctly hashed invalid legacy backup on read") { _ = try BackupArchive.read(bytes) }
            let raw = try JSONSerialization.jsonObject(with: row.currentBytes)
            let readable = try JSONSerialization.data(withJSONObject: ["app": "Lumen", "readableVersion": 1, "exportedAt": "2023-11-14T22:13:20Z", row.domain: raw])
            rejects(row.name + " rejects invalid readable import") { _ = try ReadableExport.read(readable) }
            let plainFile = root.appendingPathComponent("invalid-\(index).json")
            rejects(row.name + " rejects readable export before creating a file") {
                try ReadableExport.write(value, to: plainFile, now: now)
                precondition(fm.fileExists(atPath: plainFile.path))
            }
            precondition(!fm.fileExists(atPath: plainFile.path), "Rejected readable payload created output")
            let encryptedFile = root.appendingPathComponent("invalid-\(index).lumenbackup")
            rejects(row.name + " rejects encrypted export before creating a file") {
                try BackupPackage.write(value, photos: [:], password: password, to: encryptedFile, now: now)
                precondition(fm.fileExists(atPath: encryptedFile.path))
            }
            precondition(!fm.fileExists(atPath: encryptedFile.path), "Rejected encrypted payload created output")
        }
        check(payloads.count == 12, "all twelve backed-up invalid value cases use the exact frozen baseline inputs")
        let valid = try BackupArchive.make(empty, now: now)
        check(try BackupArchive.read(valid).1.goals.weightKg == 75, "healthy legacy backup still creates and reads")
        let readableFile = root.appendingPathComponent("healthy.json")
        try ReadableExport.write(empty, to: readableFile, now: now)
        check(try ReadableExport.read(Data(contentsOf: readableFile)).snapshot.goals.weightKg == 75, "healthy readable export still writes and reads")
        let encryptedFile = root.appendingPathComponent("healthy.lumenbackup")
        try BackupPackage.write(empty, photos: [:], password: password, to: encryptedFile, now: now)
        let contents = try BackupPackage.read(encryptedFile, password: password, temporaryRoot: root)
        check(contents.snapshot.goals.weightKg == 75, "healthy actual encrypted archive still writes and decrypts")
        check(try Data(contentsOf: inputFile) == originalInput, "all archive checks preserve the exact frozen baseline input")
        if let output {
            let report: [String: Any] = ["status": "passed", "count": checks.count, "checks": checks,
                                        "baselineSHA256": BackupArchive.digest(originalInput), "payloads": payloads,
                                        "excluded": "Three today-cache cases are not backup domains; native/local-file checks cover them.",
                                        "scope": "Actual backup writer and correctly hashed legacy reader, readable import/export and encrypted export rejection, plus healthy actual archive controls. No failed-domain replacement recovery or previous-copy repair acceptance."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }
}
