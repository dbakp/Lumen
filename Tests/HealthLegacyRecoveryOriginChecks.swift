import Foundation
import CryptoKit
import Darwin

/// Checks the observation/provenance primitive only. It is not wired into a
/// recovery transaction yet, and these results must not claim installation.
enum HealthLegacyRecoveryOriginChecks {
    static func run(output: URL) throws {
        typealias Origin = HealthLegacyRecoveryOrigin
        let fm = FileManager.default
        let area = fm.temporaryDirectory.appendingPathComponent("Lumen-legacy-origin-" + UUID().uuidString)
        try fm.createDirectory(at: area, withIntermediateDirectories: false)
        var checks: [[String: Any]] = [], fixtures: [[String: Any]] = []
        func check(_ name: String, _ body: () throws -> Bool) {
            do { checks.append(["name": name, "passed": try body()]) }
            catch { checks.append(["name": name, "passed": false, "error": String(reflecting: error)]) }
        }
        func rejects(_ body: () throws -> Void) -> Bool {
            do { try body(); return false } catch is CancellationError { return false } catch { return true }
        }
        func cancelled(_ body: () throws -> Void) -> Bool {
            do { try body(); return false } catch is CancellationError { return true } catch { return false }
        }
        let malformed = Data("{synthetic legacy damaged".utf8)
        for domain in [HealthLocalFiles.Domain.meals, .workouts, .goals] {
            let root = area.appendingPathComponent(domain.rawValue)
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            let suite = "com.dbakp.lumen.synthetic.legacy-origin." + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suite), let key = domain.legacyKey else { throw HealthLocalFiles.Failure.invalid }
            let read: (String) throws -> Any? = { defaults.object(forKey: $0) }
            defaults.set(malformed, forKey: key)
            guard let original = try Origin.capture(domain, in: root, legacy: read) else { throw HealthLocalFiles.Failure.invalid }
            let dataEnvelope = try original.value.encoded()
            try dataEnvelope.write(to: root.appendingPathComponent("retained-data-origin.json"))
            check(domain.rawValue + " actual malformed Data exact/roundtrip") {
                try original.value.bytes == malformed && Origin.Value.decode(dataEnvelope) == original.value
            }
            check(domain.rawValue + " unchanged actual defaults verifies") { try original.verify(in: root, legacy: read); return true }
            defaults.set(Data("{different damaged legacy".utf8), forKey: key)
            check(domain.rawValue + " changed still-malformed bytes reject") { rejects { try original.verify(in: root, legacy: read) } }
            defaults.removeObject(forKey: key)
            check(domain.rawValue + " removed key rejects old observation/absent not eligible") {
                try rejects { try original.verify(in: root, legacy: read) } && Origin.capture(domain, in: root, legacy: read) == nil
            }
            let healthy = domain == .goals ? try JSONEncoder().encode(HealthGoals()) : Data("[]".utf8)
            defaults.set(healthy, forKey: key)
            check(domain.rawValue + " valid legacy empty/goals not eligible") { try Origin.capture(domain, in: root, legacy: read) == nil }
            defaults.set("synthetic old value e\u{301} 🫖", forKey: key)
            guard let string = try Origin.capture(domain, in: root, legacy: read) else { throw HealthLocalFiles.Failure.invalid }
            let stringEnvelope = try string.value.encoded()
            try stringEnvelope.write(to: root.appendingPathComponent("retained-string-origin.json"))
            check(domain.rawValue + " actual String typed/lossless roundtrip") {
                try string.value.type == .stringUTF16LE && Origin.Value.decode(stringEnvelope) == string.value && string.value != original.value
            }
            defaults.set("synthetic old value é 🫖", forKey: key)
            check(domain.rawValue + " canonically equivalent different UTF16 rejected") { rejects { try string.verify(in: root, legacy: read) } }
            defaults.set(malformed, forKey: key)
            check(domain.rawValue + " changed String to Data rejects") { rejects { try string.verify(in: root, legacy: read) } }
            let file = root.appendingPathComponent(domain.rawValue + ".json")
            try healthy.write(to: file)
            check(domain.rawValue + " newly present healthy file rejects old token") { rejects { try original.verify(in: root, legacy: read) } }
            check(domain.rawValue + " present current file confers no legacy token") { try Origin.capture(domain, in: root, legacy: read) == nil }
            try fm.removeItem(at: file)
            let moved = root.appendingPathExtension("moved")
            try fm.moveItem(at: root, to: moved); try fm.createDirectory(at: root, withIntermediateDirectories: false)
            check(domain.rawValue + " replaced root identity rejects") { rejects { try original.verify(in: root, legacy: read) } }
            try fm.removeItem(at: root); try fm.moveItem(at: moved, to: root)
            fixtures.append(["domain": domain.rawValue, "root": root.path, "suite": suite, "key": key,
                             "finalValueType": "Data", "finalValueBase64": malformed.base64EncodedString(),
                             "dataEnvelope": dataEnvelope.base64EncodedString(), "stringEnvelope": stringEnvelope.base64EncodedString(),
                             "rootDevice": original.root.device, "rootInode": original.root.inode,
                             "synchronized": defaults.synchronize()])
        }
        let root = area.appendingPathComponent("controls"); try fm.createDirectory(at: root, withIntermediateDirectories: false)
        for (label, value) in [("number", 42 as Any), ("bool", true as Any), ("array", ["old"] as Any),
                               ("dictionary", ["old": "value"] as Any), ("date", Date() as Any)] {
            check("unsupported " + label + " no authority") { try Origin.capture(.meals, in: root, legacy: { _ in value }) == nil }
        }
        for domain in [HealthLocalFiles.Domain.water, .today] {
            check("no legacy key " + domain.rawValue) { try Origin.capture(domain, in: root, legacy: { _ in malformed }) == nil }
        }
        for (name, value) in [("valid", Data("[]".utf8)), ("malformed", malformed)] {
            let control = BackupOperationControl()
            check("cancelled " + name + " Data cannot produce observation") {
                cancelled { _ = try Origin.capture(.meals, in: root, legacy: { _ in control.cancel(); return value }, control: control) }
            }
        }
        check("operational defaults error propagates without authority") {
            do { _ = try Origin.capture(.meals, in: root, legacy: { _ in throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }); return false }
            catch let error as NSError { return error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES) }
        }
        var reads = 0
        check("changed during observation recheck rejects") {
            rejects { _ = try Origin.capture(.meals, in: root, legacy: { _ in reads += 1; return reads == 1 ? malformed : Data("{other".utf8) }) }
        }
        let linkedRoot = area.appendingPathComponent("linked-root")
        try fm.createSymbolicLink(atPath: linkedRoot.path, withDestinationPath: root.path)
        check("linked root rejects without following") { rejects { _ = try Origin.capture(.meals, in: linkedRoot, legacy: { _ in malformed }) } }
        let missing = area.appendingPathComponent("never-created")
        check("missing root propagates absence, never creates") { rejects { _ = try Origin.capture(.meals, in: missing, legacy: { _ in malformed }) } && !fm.fileExists(atPath: missing.path) }
        let current = root.appendingPathComponent("meals.json")
        try fm.createSymbolicLink(atPath: current.path, withDestinationPath: "never-present")
        check("dangling current link no authority") { try Origin.capture(.meals, in: root, legacy: { _ in malformed }) == nil }
        try fm.removeItem(at: current)
        guard mkfifo(current.path, 0o600) == 0 else { throw HealthLocalFiles.Failure.invalid }
        check("current FIFO no open/no authority") { try Origin.capture(.meals, in: root, legacy: { _ in malformed }) == nil }
        try fm.removeItem(at: current)
        let exact = Data(repeating: 120, count: Origin.rawLimit)
        check("exact4MiB Data envelope roundtrips within finite limit") {
            guard let origin = try Origin.capture(.meals, in: root, legacy: { _ in exact }) else { return false }
            let envelope = try origin.value.encoded()
            return try envelope.count <= Origin.envelopeLimit && Origin.Value.decode(envelope) == origin.value
        }
        check("plus-one raw Data rejects before encoding") { rejects { _ = try Origin.capture(.meals, in: root, legacy: { _ in Data(repeating: 120, count: Origin.rawLimit + 1) }) } }
        check("exact4MiB String code units roundtrip") {
            let value = String(repeating: "x", count: Origin.rawLimit / 2)
            guard let origin = try Origin.capture(.meals, in: root, legacy: { _ in value }) else { return false }
            return try Origin.Value.decode(origin.value.encoded()) == origin.value
        }
        check("plus-one String code unit rejects") { rejects { _ = try Origin.capture(.meals, in: root, legacy: { _ in String(repeating: "x", count: Origin.rawLimit / 2 + 1) }) } }
        guard let small = try Origin.capture(.meals, in: root, legacy: { _ in malformed }) else { throw HealthLocalFiles.Failure.invalid }
        let encoded = try small.value.encoded()
        var envelope = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        envelope["extra"] = "unexpected"
        check("unexpected provenance field rejects") { rejects { _ = try Origin.Value.decode(JSONSerialization.data(withJSONObject: envelope)) } }
        envelope.removeValue(forKey: "extra"); envelope["key"] = "unrelated.preference"
        check("different fixed key rejects") { rejects { _ = try Origin.Value.decode(JSONSerialization.data(withJSONObject: envelope)) } }
        envelope["key"] = "lumen.health.meals.v1"; envelope["sha256"] = String(repeating: "0", count: 64)
        check("corrupt payload digest rejects") { rejects { _ = try Origin.Value.decode(JSONSerialization.data(withJSONObject: envelope)) } }
        let control = BackupOperationControl(); control.cancel()
        check("cancelled envelope decode propagates") { cancelled { _ = try Origin.Value.decode(encoded, control: control) } }
        check("cancelled final origin verify propagates") { cancelled { try small.verify(in: root, legacy: { _ in malformed }, control: control) } }
        let passed = checks.allSatisfy { $0["passed"] as? Bool == true }
        let report: [String: Any] = ["status": passed ? "PASS observation/provenance primitive only" : "FAILED inspect checks",
                                     "checks": checks, "retainedRoot": area.path, "retainedFixtures": fixtures,
                                     "successfulRecoveryAccepted": false, "integrationImplemented": false,
                                     "scope": "Actual isolated defaults Data/String and bounded pure controls. No LocalStore.standard, transaction, UI, native recovery or install acceptance. Tiny UUID roots/suites retained for live audit and exact GitHub backup before cleanup; limit fixtures only in memory."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        guard passed else { throw HealthLocalFiles.Failure.invalid }
        print("PASS: \(checks.count) failed-legacy observation/provenance checks; integration remains pending")
    }
}


/// Review authority/lifetime checks, separate from transaction and native UI.
enum HealthOriginReviewChecks {
    static func run(output: URL) throws {
        typealias Origin = HealthLegacyRecoveryOrigin
        let control = BackupOperationControl(), bad = Data("{damaged".utf8)
        var results: [[String: Any]] = []
        func check(_ name: String, _ body: () throws -> Bool) rethrows {
            results.append(["name": name, "passed": try body()])
        }
        func changed(_ body: () throws -> Void) -> Bool {
            do { try body(); return false } catch HealthLocalFiles.Failure.changed { return true } catch { return false }
        }
        func cancelled(_ body: () throws -> Void) -> Bool {
            do { try body(); return false } catch is CancellationError { return true } catch { return false }
        }
        func project(_ persisted: Any?, _ effective: Any?) throws -> Any? {
            try Origin.checkedPersistentValue(persisted, effective: effective, domain: .meals, control: control)
        }
        try check("identical persisted Data") { try project(bad, bad) as? Data == bad }
        try check("identical persisted String preserves codeunits") { try project("e\u{301}", "e\u{301}") as? String == "e\u{301}" }
        try check("absent persisted key ignores registered malformed fallback") { try project(nil, bad) == nil }
        check("removed effective rejects") { changed { _ = try project(bad, nil) } }
        check("changed raw Data rejects") { changed { _ = try project(bad, Data("{other".utf8)) } }
        check("changed tag rejects") { changed { _ = try project(bad, "{damaged") } }
        check("canonical String equality does not grant raw equality") { changed { _ = try project("e\u{301}", "é") } }
        check("oversized effective is a changed observation") { changed { _ = try project(bad, Data(repeating: 0, count: Origin.rawLimit + 1)) } }
        try check("unsupported persisted remains unsupported") { try project(42, 42) as? Int == 42 }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Lumen-origin-review-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        // Small synthetic root is retained for readback/backup before cleanup.
        try Data("damaged current".utf8).write(to: root.appendingPathComponent("water.json"))
        try fm.createDirectory(at: root.appendingPathComponent("today.json"), withIntermediateDirectories: false)
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("workouts.json").path, withDestinationPath: "absent")
        let snapshot = try Origin.captureReview([.meals, .workouts, .goals, .water, .today], in: root,
            legacy: { key in key == HealthLocalFiles.Domain.meals.legacyKey ? bad : 42 }, control: control)
        check("mixed classification keeps eligible subset") {
            snapshot.metadata.fileDomains == [.water, .today] && snapshot.metadata.legacyDomains == [.meals]
                && snapshot.metadata.ineligibleDomains == [.workouts, .goals]
        }
        let limited = try Origin.captureReview([.meals, .goals], in: root,
            legacy: { key in key == HealthLocalFiles.Domain.meals.legacyKey ? bad : Data(repeating: 0, count: Origin.rawLimit + 1) }, control: control)
        check("per-domain size exclusion does not discard eligible domain") {
            limited.metadata.legacyDomains == [.meals] && limited.metadata.ineligibleDomains == [.goals]
        }
        let healthy = try Origin.captureReview([.meals], in: root, legacy: { _ in Data("[]".utf8) }, control: control)
        check("valid empty legacy is ineligible") { healthy.metadata.ineligibleDomains == [.meals] }
        check("acquisition operational error propagates") {
            do { _ = try Origin.captureReview([.meals], in: root, legacy: { _ in throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }, control: control); return false }
            catch let error as NSError { return error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES) }
        }
        let stopped = BackupOperationControl(); stopped.cancel()
        check("cancelled capture propagates") { cancelled { _ = try Origin.captureReview([.meals], in: root, legacy: { _ in bad }, control: stopped) } }
        let lease = HealthRecoveryOriginReviewLease(), first = BackupOperationControl(), second = BackupOperationControl()
        try lease.begin(first); lease.suspend(first); try lease.begin(second)
        check("late old completion cannot replace newer capture") { cancelled { try lease.finish(snapshot, control: first) } && lease.state == .capturing }
        lease.suspend(first)
        check("old suspend does not cancel newer control") { do { try second.checkCancellation(); return lease.state == .capturing } catch { return false } }
        try lease.finish(snapshot, control: second)
        try check("ready acquisition exact selected origin") { try lease.acquire([.meals], control: control)[.meals]?.value.bytes == bad }
        check("ready snapshot cannot recapture") { cancelled { try lease.begin(BackupOperationControl()) } && lease.metadata == snapshot.metadata }
        lease.suspend(second)
        check("child disappearance cannot reset ready owner") { lease.state == .ready && lease.metadata == snapshot.metadata }
        lease.close()
        check("close clears metadata and denies acquisition") { lease.state == .closed && lease.metadata == nil && cancelled { _ = try lease.acquire([.meals], control: control) } }
        let pending = HealthRecoveryOriginReviewLease(), pendingControl = BackupOperationControl()
        try pending.begin(pendingControl); pending.close()
        check("close cancels pending and denies late finish") { cancelled { try pendingControl.checkCancellation() } && cancelled { try pending.finish(snapshot, control: pendingControl) } }
        let revision = BackupStorageRevision(), before = revision.current
        revision.read { _ = snapshot.metadata }
        check("serialized read leaves generation unchanged") { revision.current == before }
        let writerStarted = DispatchSemaphore(value: 0), writerFinished = DispatchSemaphore(value: 0)
        var blocked = false
        revision.read {
            DispatchQueue.global().async {
                writerStarted.signal()
                revision.write { }
                writerFinished.signal()
            }
            _ = writerStarted.wait(timeout: .now() + 5)
            blocked = writerFinished.wait(timeout: .now() + 0.1) == .timedOut
        }
        let finished = writerFinished.wait(timeout: .now() + 5) == .success
        check("cooperating writer waits for read then increments once") { blocked && finished && revision.current == before + 1 }
        let passed = results.allSatisfy { $0["passed"] as? Bool == true }
        try JSONSerialization.data(withJSONObject: ["status": passed ? "PASS" : "FAIL", "checks": results,
            "retainedRoot": root.path, "scope": "Pure review projection/classification/lease/read barrier only; no LocalStore standard-defaults, native UI or installation acceptance"],
            options: [.prettyPrinted, .sortedKeys]).write(to: output)
        guard passed else { throw HealthLocalFiles.Failure.invalid }
        print("PASS: \(results.count) origin review checks")
    }
}
