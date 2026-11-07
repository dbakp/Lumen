import Foundation

/// The same observations reproduce the old defects or verify the repair.
/// Fault activation observes a populated actual stage, never a fixed read count.
enum HealthLegacyRecoveryBoundaryChecks {
    static func run(output: URL, expectingDefects: Bool) throws {
        let fm = FileManager.default
        let area = fm.temporaryDirectory.appendingPathComponent("Lumen-legacy-boundaries-" + UUID().uuidString)
        try fm.createDirectory(at: area, withIntermediateDirectories: false)
        let bad = Data("{synthetic stage-boundary legacy".utf8)
        var checks: [[String: Any]] = [], cases: [[String: Any]] = [], completed = false
        defer {
            let report: [String: Any] = ["status": completed ? (expectingDefects ? "BASELINE_REPRODUCED three stage leaks/two incomplete-copy installs; no recovery acceptance" : "PASS five stage cleanup/retained-shape rejection boundaries") : "FAILED boundary expectation; partial evidence retained",
                                         "expectingDefects": expectingDefects, "checks": checks, "cases": cases,
                                         "retainedRoot": area.path, "successfulRecoveryAccepted": false,
                                         "scope": "Actual isolated defaults/direct production backend boundary observations. Baseline may intentionally retain unsafe synthetic stages/installs. No UI/LocalStore.standard/native or fullparent acceptance; retain fixtures/suites through independent audit/exact backup."]
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output) }
            catch { print("Boundary report retention failed: " + String(reflecting: error)) }
        }
        func check(_ name: String, _ value: Bool) throws {
            checks.append(["name": name, "passed": value]); guard value else { throw HealthLocalFiles.Failure.invalid }
        }
        func files(_ root: URL) throws -> [String: String] {
            let base = root.resolvingSymlinksInPath().path
            var values: [String: String] = [:]
            guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { throw HealthLocalFiles.Failure.invalid }
            for case let file as URL in entries {
                let attributes = try fm.attributesOfItem(atPath: file.path)
                guard let type = attributes[.type] as? FileAttributeType, type == .typeDirectory || type == .typeRegular else { throw HealthLocalFiles.Failure.invalid }
                if type == .typeRegular {
                    let path = file.resolvingSymlinksInPath().path
                    guard path.hasPrefix(base + "/") else { throw HealthLocalFiles.Failure.invalid }
                    values[String(path.dropFirst(base.count + 1))] = try Data(contentsOf: file).base64EncodedString()
                }
            }
            return values
        }
        for fault in ["post-stage-change", "post-stage-cancel", "post-stage-operational", "extra-origin", "dual-domain"] {
            let root = area.appendingPathComponent(fault), owner = UUID(), control = BackupOperationControl()
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            for (name, bytes) in try ConversationFiles.encoded([], activeID: nil) { try bytes.write(to: root.appendingPathComponent(name)) }
            let encoder = BackupArchive.encoder()
            let water = try encoder.encode([HydrationLog(id: "stage-healthy-water", date: Date(timeIntervalSince1970: 1_700_000_000), ml: 137)])
            try water.write(to: root.appendingPathComponent("water.json"))
            try Data("[]".utf8).write(to: root.appendingPathComponent("workouts.json"))
            try encoder.encode(HealthGoals()).write(to: root.appendingPathComponent("goals.json"))
            try HealthWriteJournal(owner: owner).encoded().write(to: root.appendingPathComponent(HealthWriteFiles.name))
            let suite = "com.dbakp.lumen.synthetic.legacy-boundary." + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suite) else { throw HealthLocalFiles.Failure.invalid }
            let key = HealthLocalFiles.Domain.meals.legacyKey!; defaults.set(bad, forKey: key)
            let index = cases.count
            cases.append(["fault": fault, "root": root.path, "suite": suite, "key": key, "phase": "fixture created"])
            final class Reader: @unchecked Sendable {
                let defaults: UserDefaults, root: URL, control: BackupOperationControl
                let fault: String
                var reads = 0, activated = false
                init(_ defaults: UserDefaults, root: URL, control: BackupOperationControl, fault: String) {
                    self.defaults = defaults; self.root = root; self.control = control; self.fault = fault
                }
                func stages() throws -> [URL] {
                    try FileManager.default.contentsOfDirectory(at: root.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                        .filter { $0.lastPathComponent.hasPrefix(root.lastPathComponent + ".restore-") }
                }
                func read(_ key: String) throws -> Any? {
                    reads += 1
                    if fault.hasPrefix("post-stage"), !activated,
                       let stage = try stages().first,
                       FileManager.default.fileExists(atPath: stage.appendingPathComponent("meals.json").path),
                       let iterator = FileManager.default.enumerator(at: stage.appendingPathComponent(HealthRecoveryCopies.name), includingPropertiesForKeys: nil),
                       iterator.allObjects.compactMap({ $0 as? URL }).contains(where: { $0.lastPathComponent == "legacy-origin-meals.json" }) {
                        activated = true
                        if fault == "post-stage-change" { defaults.set(Data("{changed at populated stage".utf8), forKey: key) }
                        if fault == "post-stage-cancel" { control.cancel() }
                        if fault == "post-stage-operational" { throw NSError(domain: NSPOSIXErrorDomain, code: 13) }
                    }
                    return defaults.object(forKey: key)
                }
            }
            let reader = Reader(defaults, root: root, control: control, fault: fault)
            let legacy: @Sendable (String) throws -> Any? = { try reader.read($0) }
            guard let origin = try HealthLegacyRecoveryOrigin.capture(.meals, in: root, legacy: legacy) else { throw HealthLocalFiles.Failure.invalid }
            let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
            let unbound = try HealthRecoverySelection.backup(snapshot, photos: [:], domains: [.meals], validPhoto: { _ in true })
            let payload = try HealthRecoverySelection.bindingLegacyOrigins([.meals: origin], to: unbound)
            let before = try files(root)
            var prepared = false, committed = false, errorKind: String?, failureText: String?
            do {
                let transaction = try HealthRecoverySelection.prepare(payload, into: root, owner: owner, control: control, legacy: legacy)
                prepared = true
                guard !fault.hasPrefix("post-stage") else { throw HealthLocalFiles.Failure.invalid }
                guard let stage = try reader.stages().first else { throw HealthLocalFiles.Failure.invalid }
                let copies = try fm.contentsOfDirectory(at: stage.appendingPathComponent(HealthRecoveryCopies.name), includingPropertiesForKeys: nil)
                guard copies.count == 1 else { throw HealthLocalFiles.Failure.invalid }
                let path = fault == "extra-origin" ? "legacy-origin-unexpected.json" : "meals.json"
                try Data("[]".utf8).write(to: copies[0].appendingPathComponent(path))
                do { try transaction.commit(control: control); committed = true }
                catch { errorKind = error is CancellationError ? "CancellationError" : String(reflecting: type(of: error)); failureText = String(reflecting: error) }
                transaction.discard()
            } catch {
                errorKind = error is CancellationError ? "CancellationError" : String(reflecting: type(of: error)); failureText = String(reflecting: error)
            }
            let stages = try reader.stages(), after = try files(root)
            var stageFiles: [String: [String: String]] = [:]
            for stage in stages { stageFiles[stage.path] = try files(stage) }
            let incomplete = try HealthRecoveryCopies.previews(in: root).contains { !$0.complete }
            cases[index] = ["fault": fault, "root": root.path, "suite": suite, "key": key,
                            "before": before, "after": after, "stageFilesAfter": stageFiles,
                            "readerReadsDiagnostic": reader.reads, "populatedStageFaultActivated": reader.activated,
                            "prepared": prepared, "committed": committed, "errorKind": errorKind.map { $0 as Any } ?? NSNull(),
                            "error": failureText.map { $0 as Any } ?? NSNull(), "catalogHasIncompleteCopy": incomplete,
                            "currentDefaultsData": (defaults.object(forKey: key) as? Data).map { $0.base64EncodedString() as Any } ?? NSNull(),
                            "synchronized": defaults.synchronize()]
            if fault.hasPrefix("post-stage") {
                try check(fault + " activated on observed populated stage", reader.activated)
                try check(fault + " rejected before transaction ownership returned", !prepared && !committed && errorKind != nil)
                try check(fault + " current bytes unchanged", before == after)
                try check(fault + (expectingDefects ? " old stage leak reproduced" : " no unowned stage remains"), expectingDefects ? stages.count == 1 : stages.isEmpty)
                if fault == "post-stage-cancel" { try check("actual cancellation type propagated", errorKind == "CancellationError") }
            } else {
                try check(fault + " prepared actual original transaction", prepared)
                try check(fault + (expectingDefects ? " old bad commit reproduced" : " rejects before installing"), committed == expectingDefects)
                try check(fault + (expectingDefects ? " incomplete installed copy reproduced" : " current bytes unchanged/no copy installed"), expectingDefects ? incomplete && before != after : before == after && !incomplete)
            }
        }
        completed = true
        print(expectingDefects ? "BASELINE_REPRODUCED: three actual stage leaks and two incomplete-copy installs; no recovery acceptance" : "PASS: final-prepare cleanup and final retained-copy shape boundaries")
    }
}
