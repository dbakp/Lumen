import Foundation
import CryptoKit
import Darwin

/// Capability-gap observations on tiny isolated files. A reproduced rejection
/// is not successful recovery; no production policy is changed here.
enum HealthUnavailableOriginChecks {
    private static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private static func snapshot(_ root: URL) throws -> [String: [String: String]] {
        let fm = FileManager.default
        var result: [String: [String: String]] = [:]
        func visit(_ file: URL, _ name: String) throws {
            var facts = stat()
            guard lstat(file.path, &facts) == 0 else {
                if errno == ENOENT { return }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            let kind = facts.st_mode & mode_t(S_IFMT)
            var row = ["kind": String(kind), "inode": String(facts.st_ino), "device": String(facts.st_dev),
                       "mode": String(facts.st_mode), "size": String(facts.st_size),
                       "modifiedSeconds": String(facts.st_mtimespec.tv_sec), "modifiedNanoseconds": String(facts.st_mtimespec.tv_nsec)]
            if kind == mode_t(S_IFLNK) {
                row["linkDestination"] = try fm.destinationOfSymbolicLink(atPath: file.path)
            } else if kind == mode_t(S_IFREG) {
                let bytes = try HealthLocalFiles.readRegularData(file, limit: 128 * 1024)
                row["sha256"] = digest(bytes); row["base64"] = bytes.base64EncodedString()
            }
            result[name] = row
            if kind == mode_t(S_IFDIR) {
                for child in try fm.contentsOfDirectory(at: file, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, name + "/" + child.lastPathComponent)
                }
            }
        }
        try visit(root, ".")
        return result
    }

    static func baseline(output: URL, requiringNoMutation: Bool = false) throws {
        let fm = FileManager.default
        let outer = fm.temporaryDirectory.appendingPathComponent("Lumen-unavailable-origins-" + UUID().uuidString)
        try fm.createDirectory(at: outer, withIntermediateDirectories: false)
        // Parent retains this owned root through independent live audit and exact backup.
        print("Retained synthetic baseline root: " + outer.path)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let conversations = try ConversationFiles.encoded([], activeID: nil)
        let water = try encoder.encode([HydrationLog(id: "synthetic-origin-water", date: Date(timeIntervalSince1970: 1_700_000_000), ml: 137)])
        let replacement = Data("[]".utf8)
        var observations: [[String: Any]] = []
        for name in ["missing-current-malformed-legacy", "missing-current-nondata-legacy", "relative-selected-domain-link", "absolute-selected-domain-link", "dangling-selected-domain-link"] {
            let area = outer.appendingPathComponent(name), root = area.appendingPathComponent("LumenData")
            let prior = root.appendingPathExtension("previous"), target = area.appendingPathComponent("synthetic-reference.json")
            try fm.createDirectory(at: area, withIntermediateDirectories: false)
            for folder in [root, prior] {
                try fm.createDirectory(at: folder, withIntermediateDirectories: false)
                for (key, value) in conversations { try value.write(to: folder.appendingPathComponent(key)) }
                try water.write(to: folder.appendingPathComponent("water.json"))
                try replacement.write(to: folder.appendingPathComponent("workouts.json"))
                try encoder.encode(HealthGoals()).write(to: folder.appendingPathComponent("goals.json"))
                try encoder.encode(HealthWriteJournal()).write(to: folder.appendingPathComponent(HealthWriteFiles.name))
            }
            try replacement.write(to: prior.appendingPathComponent("meals.json"))
            let privateRoot = root.appendingPathComponent(".health-recovery")
            try fm.createDirectory(at: privateRoot, withIntermediateDirectories: false)
            try Data("synthetic unrelated retained bytes".utf8).write(to: privateRoot.appendingPathComponent("sentinel.bin"))
            let suiteName = "com.dbakp.lumen.synthetic.origin." + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suiteName) else { throw HealthLocalFiles.Failure.invalid }
            // The parent removes only these recorded synthetic domains after backup.
            print("Retained synthetic defaults suite: " + suiteName)
            let key = HealthLocalFiles.Domain.meals.legacyKey!
            if name == "missing-current-malformed-legacy" { defaults.set(Data("{synthetic malformed legacy".utf8), forKey: key) }
            if name == "missing-current-nondata-legacy" { defaults.set("synthetic nonData legacy", forKey: key) }
            let mealFile = root.appendingPathComponent("meals.json")
            if name.contains("domain-link") {
                if !name.hasPrefix("dangling") { try replacement.write(to: target) }
                let destination = name.hasPrefix("relative") ? "../synthetic-reference.json" : name.hasPrefix("absolute") ? target.path : "../synthetic-missing-reference.json"
                try fm.createSymbolicLink(atPath: mealFile.path, withDestinationPath: destination)
            }
            let defaultsSynchronizedBeforeRead = defaults.synchronize()
            func legacy() throws -> Data? {
                guard let value = defaults.object(forKey: key) else { return nil }
                guard let data = value as? Data else { throw HealthLocalFiles.Failure.invalid }
                return data
            }
            func legacyFacts() -> [String: String] {
                guard let value = defaults.object(forKey: key) else { return ["kind": "absent", "storageType": "absent"] }
                if let data = value as? Data { return ["kind": "Data", "storageType": "Data", "base64": data.base64EncodedString(), "sha256": digest(data)] }
                return ["kind": String(reflecting: type(of: value)), "storageType": value is String ? "String" : "other", "description": String(describing: value)]
            }
            let before = try snapshot(area), oldLegacy = legacyFacts()
            var readError: String?, preparationError: String?, unexpectedlyPrepared = false
            do { _ = try HealthLocalFiles.read([Meal].self, domain: .meals, from: root, legacy: legacy) }
            catch { readError = String(reflecting: error) }
            let legacyAfterRead = legacyFacts()
            let afterRead = try snapshot(area)
            do {
                let transaction = try ConversationFiles.prepareHealthRecovery(["meals.json": replacement], photoFiles: [:], domains: [.meals], photoDigests: [:], into: root, control: .init())
                unexpectedlyPrepared = true; transaction.discard()
            } catch { preparationError = String(reflecting: error) }
            let defaultsSynchronizedAfterPreparation = defaults.synchronize()
            let after = try snapshot(area)
            let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
            let children = try fm.contentsOfDirectory(at: area, includingPropertiesForKeys: nil).map(\.lastPathComponent)
            let stages = children.filter { $0.hasPrefix("LumenData.restore-") }
            let currentMealsStillUnavailable = (try? HealthLocalFiles.read([Meal].self, domain: .meals, from: root, legacy: legacy)) == nil
            let retainedWater = try HealthLocalFiles.readRegularData(root.appendingPathComponent("water.json"), limit: 1024) == water
            let targetBefore = before["./synthetic-reference.json"], targetAfter = after["./synthetic-reference.json"]
            let reproduced = readError != nil && preparationError != nil && !unexpectedlyPrepared && currentMealsStillUnavailable && oldLegacy == legacyAfterRead && oldLegacy == legacyFacts() && retainedWater && targetBefore == targetAfter && stages.isEmpty && (!requiringNoMutation || before == after)
            observations.append(["case": name, "areaPath": area.path, "suiteName": suiteName, "legacyKey": key, "defaultsSynchronizedBeforeRead": defaultsSynchronizedBeforeRead, "defaultsSynchronizedAfterPreparation": defaultsSynchronizedAfterPreparation, "legacyAfterRead": legacyAfterRead, "currentMealsStillUnavailable": currentMealsStillUnavailable, "readerError": readError.map { $0 as Any } ?? NSNull(), "preparationError": preparationError.map { $0 as Any } ?? NSNull(), "unexpectedlyPrepared": unexpectedlyPrepared, "capabilityGapReproduced": reproduced, "readerTreeExact": before == afterRead, "legacyBefore": oldLegacy, "legacyAfter": legacyFacts(), "before": before, "afterRead": afterRead, "afterPreparation": after, "changedPaths": changed, "noStageRemains": stages.isEmpty, "externalTargetExact": targetBefore == targetAfter, "healthyWaterExact": retainedWater, "scope": "Isolated suite and production reader/prepare calls; LocalStore.standard and native UI unexecuted. Changes from preparation, including prior retirement/private discovery, explicitly retained."])
        }
        let controlRoot = outer.appendingPathComponent("controls"); try fm.createDirectory(at: controlRoot, withIntermediateDirectories: false)
        let absent = try HealthLocalFiles.read([Meal].self, domain: .meals, from: controlRoot)
        try replacement.write(to: controlRoot.appendingPathComponent("meals.json"))
        var legacyCalls = 0
        let empty = try HealthLocalFiles.read([Meal].self, domain: .meals, from: controlRoot, legacy: { legacyCalls += 1; return Data("{broken".utf8) })
        let controls = absent.value == nil && absent.boundary == .missing(legacy: nil) && empty.value?.isEmpty == true && legacyCalls == 0
        let allReproduced = observations.allSatisfy { $0["capabilityGapReproduced"] as? Bool == true } && controls
        let report: [String: Any] = ["status": allReproduced ? "BASELINE_REPRODUCED capability gaps; recovery feature remains unimplemented" : "BASELINE_MISMATCH inspect actual outcomes", "successfulRecoveryAccepted": false, "observations": observations, "controls": ["trulyAbsentNotUnavailable": absent.value == nil && absent.boundary == .missing(legacy: nil), "emptyCurrentDoesNotReadLegacy": empty.value?.isEmpty == true && legacyCalls == 0], "temporaryRoot": outer.path, "fixturesRetained": true, "isolatedSuitesRetained": true, "cleanupAuthority": "Parent independent live audit and exact GitHub readback required before scoped UUIDroot/suite cleanup", "scope": "Five tiny pure Foundation capability-gap baselines, not native/full-product acceptance. Temporary files and isolated defaults retained for independent live audit and exact backup before parent scoped cleanup."]
        let outputReport = report.merging([
            "earlyRejectionNoMutationRequired": requiringNoMutation,
            "status": requiringNoMutation
                ? (allReproduced ? "PASS five early rejections preserve complete case trees; origin recovery remains unimplemented" : "FAILED early rejection preservation; inspect actual outcomes")
                : report["status"]!
        ]) { _, new in new }
        try JSONSerialization.data(withJSONObject: outputReport, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        guard allReproduced else { throw HealthLocalFiles.Failure.invalid }
        print(requiringNoMutation
              ? "Five early rejections preserve complete case trees; two no-resurrection controls passed. No recovery acceptance."
              : "Five unavailable-origin capability gaps reproduced; two no-resurrection controls passed. No recovery acceptance.")
    }

    static func preflightBranches(output: URL) throws {
        let fm = FileManager.default
        let outer = fm.temporaryDirectory.appendingPathComponent("Lumen-recovery-preflight-" + UUID().uuidString)
        try fm.createDirectory(at: outer, withIntermediateDirectories: false)
        print("Retained synthetic preflight branch root: " + outer.path)
        let conversations = try ConversationFiles.encoded([], activeID: nil)
        let bad = Data("{synthetic unavailable meals".utf8)
        let good = Data("[]".utf8)
        func seed(_ folder: URL) throws {
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            for (name, bytes) in conversations { try bytes.write(to: folder.appendingPathComponent(name)) }
            try bad.write(to: folder.appendingPathComponent("meals.json"))
            try Data("synthetic unrelated water bytes".utf8).write(to: folder.appendingPathComponent("water.json"))
        }
        var rows: [[String: Any]] = []
        for name in ["missing-root-with-prior", "missing-root-without-prior", "root-link", "root-regular-file", "already-cancelled", "selected-fifo"] {
            let area = outer.appendingPathComponent(name), root = area.appendingPathComponent("LumenData")
            let previous = root.appendingPathExtension("previous")
            try fm.createDirectory(at: area, withIntermediateDirectories: false)
            if name != "missing-root-without-prior" { try seed(previous) }
            if name == "root-link" {
                let target = area.appendingPathComponent("owned-reference")
                try seed(target); try fm.createSymbolicLink(at: root, withDestinationURL: target)
            } else if name == "root-regular-file" {
                try Data("synthetic root is not a directory".utf8).write(to: root)
            } else if name == "already-cancelled" || name == "selected-fifo" {
                try seed(root)
                if name == "selected-fifo" {
                    let fifo = root.appendingPathComponent("meals.json")
                    try fm.removeItem(at: fifo)
                    guard mkfifo(fifo.path, mode_t(0o600)) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                }
            }
            let control = BackupOperationControl()
            if name == "already-cancelled" { control.cancel() }
            let before = try snapshot(area)
            var prepared = false, observedCancellation = false, errorText: String?
            do {
                let transaction = try ConversationFiles.prepareHealthRecovery(["meals.json": good], photoFiles: [:], domains: [.meals], photoDigests: [:], into: root, control: control)
                prepared = true; transaction.discard()
            } catch {
                observedCancellation = error is CancellationError
                errorText = String(reflecting: error)
            }
            let after = try snapshot(area)
            let noStages = !after.keys.contains { $0.hasPrefix("./LumenData.restore-") }
            let passed: Bool
            if name == "missing-root-with-prior" {
                let priorRows = before.filter { $0.key.hasPrefix("./LumenData.previous") }
                passed = prepared && errorText == nil && noStages
                    && !after.keys.contains { $0.hasPrefix("./LumenData.previous") }
                    && priorRows.allSatisfy { key, value in
                        after[key.replacingOccurrences(of: "./LumenData.previous", with: "./LumenData")] == value
                    }
            } else if name == "missing-root-without-prior" {
                passed = !prepared && errorText != nil && noStages && after["./LumenData"] == nil && after["./LumenData.previous"] == nil
            } else {
                passed = !prepared && errorText != nil && noStages && before == after
                    && (name != "already-cancelled" || observedCancellation)
            }
            rows.append(["case": name, "areaPath": area.path, "passed": passed,
                         "prepared": prepared, "observedCancellation": observedCancellation,
                         "error": errorText.map { $0 as Any } ?? NSNull(), "noStageRemains": noStages,
                         "before": before, "after": after,
                         "scope": name.hasPrefix("missing-root") ? "Existing interrupted-open behavior, outside early-no-mutation guarantee; no commit." : "Present-root early rejection/cancellation; exact whole case tree comparison; no commit."])
        }
        let passed = rows.allSatisfy { $0["passed"] as? Bool == true }
        let report: [String: Any] = ["status": passed ? "PASS six actual preflight branch checks" : "FAILED preflight branch checks; inspect actual outcomes",
                                   "temporaryRoot": outer.path, "fixturesRetained": true, "observations": rows,
                                   "successfulRecoveryAccepted": false,
                                   "scope": "Actual production preparation/metadata/cancellation branches on tiny retained synthetic fixtures. Missing-root-with-prior prepares/discards but never commits; other cases reject. No native UI, all-interleaving or origin-recovery acceptance."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        guard passed else { throw HealthLocalFiles.Failure.invalid }
        print("Six preflight branches passed; tiny fixtures retained for independent audit and backup")
    }
}
