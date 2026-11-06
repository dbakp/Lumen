import Foundation
import Darwin

@MainActor enum HealthWriteRecoveryChecks {
    typealias Journal = HealthWriteJournal
    @MainActor private final class Gate {
        var waiting: CheckedContinuation<Void, Never>?
        var entered: CheckedContinuation<Void, Never>?
        var started = false
        func hold() async {
            started = true; entered?.resume(); entered = nil
            await withCheckedContinuation { waiting = $0 }
        }
        func waitForStart() async { if !started { await withCheckedContinuation { entered = $0 } } }
        func release() { waiting?.resume(); waiting = nil }
    }
    @MainActor private final class Disk {
        let root: URL
        var rejectReceipt = false
        var trace: [String] = []
        var failedMetric: Journal.Metric?
        var gate: Gate?
        var beforeReceipt: (() throws -> Void)?
        init(_ root: URL) { self.root = root }
        func read() throws -> Journal { try HealthWriteFiles.read(from: root) }
        func commit(_ journal: Journal) throws {
            if rejectReceipt { throw Journal.Failure.invalid }
            try journal.encoded().write(to: root.appendingPathComponent(HealthWriteFiles.name), options: .atomic)
        }
        func operate(_ claim: Journal.Claim) async throws {
            trace.append(claim.action.rawValue + ":" + claim.component.metric.rawValue)
            if let gate, claim.component.metric == .water, claim.action == .save { await gate.hold() }
            if failedMetric == claim.component.metric { throw HealthWriteOperationFailure(issue: .permission) }
            let file = root.deletingLastPathComponent().appendingPathComponent("external.json")
            var records = (try? JSONDecoder().decode([String: Double].self, from: Data(contentsOf: file))) ?? [:]
            if claim.action == .save { records[claim.syncIdentifier] = claim.component.value }
            else { records[claim.syncIdentifier] = nil }
            try JSONEncoder().encode(records).write(to: file, options: .atomic)
        }
        func worker() -> HealthWriteRecovery {
            HealthWriteRecovery(read: { try self.read() }, commit: { value, expected in
                let hook = self.beforeReceipt; self.beforeReceipt = nil; try hook?()
                guard try self.read() == expected else { throw Journal.Failure.staleClaim }
                try self.commit(value)
            }, operate: { try await self.operate($0) })
        }
    }
    private static func component(_ metric: Journal.Metric, _ value: Double = 1) -> Journal.Component {
        .init(metric: metric, value: value, date: Date(timeIntervalSince1970: 1_790_000_000))
    }
    private static func appendAll(_ journal: inout Journal) throws {
        try journal.append(domain: .water, localID: "water-43", components: [component(.water, 250)])
        try journal.append(domain: .meal, localID: "meal-43", components: [.calories, .protein, .carbs, .fat, .fiber].map { component($0) })
        try journal.append(domain: .weight, localID: "weight-43", components: [component(.weight, 75)])
    }
    static func run(output: URL? = nil) async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-durable-check-" + UUID().uuidString)
        let root = parent.appendingPathComponent("LumenData")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        var passed = 0
        func check(_ value: Bool, _ text: String) { precondition(value, text); passed += 1; print("PASS: " + text) }
        func rejects(_ label: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(label) } catch { check(true, label) }
        }
        var journal = Journal(); try appendAll(&journal)
        check(journal.events.count == 3 && journal.pendingEvents.count == 3, "water, all meal components and independent weight event are durable intents")
        check(try Journal.decode(journal.encoded()) == journal, "journal roundtrip retains exact payload, identities and lifecycle")
        let original = journal.next()!
        check(original.syncVersion == 1 && original.syncIdentifier.contains(journal.owner.uuidString), "stable component sync identity includes device owner and event")
        var other = Journal(); try appendAll(&other)
        check(other.next()!.syncIdentifier != original.syncIdentifier, "same local ID on another installation cannot collide")
        rejects("duplicate local record cannot acquire a second external identity") { try journal.append(domain: .water, localID: "water-43", components: [component(.water)]) }
        rejects("wrong-domain component is rejected") { try journal.append(domain: .water, localID: "bad", components: [component(.weight)]) }
        rejects("non-finite payload is rejected") { try journal.append(domain: .weight, localID: "bad", components: [component(.weight, .infinity)]) }
        rejects("duplicate meal component is rejected") { try journal.append(domain: .meal, localID: "bad", components: [component(.protein), component(.protein)]) }
        let encoded = try journal.encoded()
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object["version"] = 2
        rejects("unknown journal version cannot silently migrate to empty") { _ = try Journal.decode(JSONSerialization.data(withJSONObject: object)) }
        let duplicate = Data(("{\"version\":0," + String(decoding: encoded, as: UTF8.self).dropFirst()).utf8)
        rejects("repeated JSON fields are refused before Foundation decoding") { _ = try Journal.decode(duplicate) }
        try journal.acknowledge(original)
        check(journal.events[0].complete && journal.pendingEvents.count == 2, "receipt completes only its own component")
        try journal.requestDeletion(domain: .water, localID: "water-43")
        check(!journal.events[0].complete && journal.events[0].components == [original.component], "undo retains immutable payload and reopens deletion receipt")
        rejects("late save receipt cannot acknowledge the later deletion") { try journal.acknowledge(original) }
        let deleting = journal.next()!
        check(deleting.action == .delete && deleting.syncIdentifier == original.syncIdentifier, "delete targets the exact original external identity")
        let previousLifecycle = journal.lifecycle
        journal.rotateLifecycle()
        check(journal.lifecycle != previousLifecycle && journal.pendingEvents.count == 1, "lifecycle rotation withdraws old saves while retaining pending delete")
        try journal.acknowledge(deleting)
        check(journal.pendingEvents.isEmpty && journal.events.count == 3, "old-lifecycle delete receipt can finish without creating new-lifecycle work")
        try journal.requestDeletion(domain: .meal, localID: "legacy-meal")
        check(journal.next()!.identity == .legacyDeletion && journal.next()!.action == .delete, "legacy records only authorize source-scoped deletion")

        // Real linked-file staging failure, install failure and complete commit.
        let disk = Disk(root)
        try Data("old water".utf8).write(to: root.appendingPathComponent("water.json"))
        var fresh = Journal(); try appendAll(&fresh); try disk.commit(fresh)
        let oldIntent = try Data(contentsOf: root.appendingPathComponent(HealthWriteFiles.name))
        let blocked = root.appendingPathComponent("blocked.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        rejects("failed combined staging leaves local file and journal unchanged") { _ = try HealthWriteFiles.prepare(["blocked.json": Data()], journal: fresh, into: root) }
        check(try Data(contentsOf: root.appendingPathComponent(HealthWriteFiles.name)) == oldIntent, "failed staging preserves exact previous journal bytes")
        try FileManager.default.removeItem(at: blocked)
        let staged = try HealthWriteFiles.prepare(["water.json": Data("new water".utf8)], journal: fresh, into: root)
        let stage = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("LumenData.restore-") }!
        try FileManager.default.removeItem(at: stage)
        rejects("failed directory installation surfaces the combined commit error") { try staged.commit() }
        check(try Data(contentsOf: root.appendingPathComponent(HealthWriteFiles.name)) == oldIntent && String(contentsOf: root.appendingPathComponent("water.json"), encoding: .utf8) == "old water", "failed install recovers exact old local and intent files")
        try HealthWriteFiles.prepare(["water.json": Data("new water".utf8)], journal: fresh, into: root).commit()
        check(try disk.read() == fresh && String(contentsOf: root.appendingPathComponent("water.json"), encoding: .utf8) == "new water", "combined directory transaction installs local records and journal together")

        disk.failedMetric = .protein
        let worker = disk.worker(); worker.kick(); await worker.waitForCurrentWork()
        let partial = try disk.read()
        check(partial.events[0].complete && partial.events[2].complete, "denied meal type does not prevent independent water and weight completion")
        check(partial.events[1].acknowledged == [.calories] && partial.events[1].issue == .permission, "partial meal preserves confirmed component and exact failed type")
        check(worker.activeCount == 0 && partial.pendingEvents.count == 1, "denied work stays pending without a busy retry loop")
        disk.failedMetric = nil; worker.kick(); await worker.waitForCurrentWork()
        check(try disk.read().pendingEvents.isEmpty && disk.trace.filter { $0 == "save:calories" }.count == 1, "retry completes remaining meal types without resending acknowledged calories")

        // Save completion is held while a durable undo supersedes its receipt.
        var ordered = Journal(); try ordered.append(domain: .water, localID: "held", components: [component(.water)])
        try ordered.append(domain: .weight, localID: "independent", components: [component(.weight)])
        try disk.commit(ordered); disk.trace = []; disk.gate = Gate()
        worker.kick(); await disk.gate!.waitForStart()
        var undo = try disk.read(); try undo.requestDeletion(domain: .water, localID: "held"); try disk.commit(undo)
        worker.kick()
        for _ in 0..<20 { if disk.trace.contains("save:weight") { break }; await Task.yield() }
        check(disk.trace.contains("save:weight") && !disk.trace.contains("delete:water"), "held save blocks only its own deletion, not independent weight")
        disk.gate!.release(); await worker.waitForCurrentWork(); disk.gate = nil
        check(disk.trace.filter { $0.hasSuffix(":water") } == ["save:water", "delete:water"], "durable undo follows actual save callback, ignoring stale save acknowledgement")
        check(try disk.read().pendingEvents.isEmpty && disk.read().events[0].action == .delete, "delete has its own durable completion receipt")

        var retry = Journal(); try retry.append(domain: .weight, localID: "receipt-failure", components: [component(.weight)])
        try disk.commit(retry); disk.rejectReceipt = true; worker.kick(); await worker.waitForCurrentWork()
        check(try worker.storageIssue && disk.read().pendingEvents.count == 1, "receipt write failure leaves exact operation pending after external success")
        let identity = retry.next()!.syncIdentifier
        disk.rejectReceipt = false
        let restartedWorker = disk.worker(); restartedWorker.kick(); await restartedWorker.waitForCurrentWork()
        let external = try JSONDecoder().decode([String: Double].self, from: Data(contentsOf: parent.appendingPathComponent("external.json")))
        check(try disk.read().pendingEvents.isEmpty && external[identity] == 1, "new worker replays same stable identity and completes durable acknowledgement")

        var lifecycle = Journal(); try lifecycle.append(domain: .water, localID: "withdrawn", components: [component(.water)])
        try disk.commit(lifecycle); disk.gate = Gate(); worker.kick(); await disk.gate!.waitForStart()
        lifecycle.rotateLifecycle(); try disk.commit(lifecycle); disk.gate!.release(); await worker.waitForCurrentWork()
        disk.gate = nil
        check(try disk.read().events[0].acknowledged.isEmpty && disk.read().pendingEvents.isEmpty, "late old-lifecycle callback cannot acknowledge or start new lifecycle work")
        let intentFile = root.appendingPathComponent(HealthWriteFiles.name)
        try Data("{invalid".utf8).write(to: intentFile, options: .atomic)
        let invalidBytes = try Data(contentsOf: intentFile); disk.trace = []; worker.kick(); await worker.waitForCurrentWork()
        check(try worker.storageIssue && disk.trace.isEmpty && Data(contentsOf: intentFile) == invalidBytes, "corrupt intent is preserved and blocks external dispatch")

        // A file copied through an OS backup must not inherit the receiving
        // device's permission to send its older operations.
        let copiedRoot = parent.appendingPathComponent("CopiedData")
        try FileManager.default.createDirectory(at: copiedRoot, withIntermediateDirectories: true)
        let receiver = UUID()
        check(try HealthWriteFiles.read(from: copiedRoot, owner: receiver).owner == receiver, "missing intent starts with the receiving device owner, never a file-derived identity")
        var copied = Journal(); try appendAll(&copied)
        try copied.requestDeletion(domain: .water, localID: "water-43")
        let copiedBytes = try copied.encoded()
        try copiedBytes.write(to: copiedRoot.appendingPathComponent(HealthWriteFiles.name))
        try Data("retained local history".utf8).write(to: copiedRoot.appendingPathComponent("water.json"))
        rejects("copied save and deletion intent refuses a different device owner") { _ = try HealthWriteFiles.read(from: copiedRoot, owner: receiver) }
        check(try Data(contentsOf: copiedRoot.appendingPathComponent(HealthWriteFiles.name)) == copiedBytes, "foreign-owner rejection preserves exact copied intent bytes")
        var foreignOperations = 0
        let foreignWorker = HealthWriteRecovery(read: { try HealthWriteFiles.read(from: copiedRoot, owner: receiver) },
                                               commit: { _, _ in preconditionFailure("foreign receipt") },
                                               operate: { _ in foreignOperations += 1 })
        foreignWorker.kick(); await foreignWorker.waitForCurrentWork()
        check(foreignWorker.storageIssue && foreignOperations == 0, "foreign journal cannot dispatch either a save or a deletion")
        let setup = try HealthWriteFiles.prepareDeviceSetup(into: copiedRoot, owner: receiver)
        let setupStage = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("CopiedData.restore-") }!
        try FileManager.default.removeItem(at: setupStage)
        rejects("failed explicit device-setup installation surfaces its error") { try setup.commit() }
        check(try Data(contentsOf: copiedRoot.appendingPathComponent(HealthWriteFiles.name)) == copiedBytes, "failed setup recovers original copied intent without publishing an empty queue")
        try HealthWriteFiles.prepareDeviceSetup(into: copiedRoot, owner: receiver).commit()
        let receiving = try HealthWriteFiles.read(from: copiedRoot, owner: receiver)
        check(receiving.events.isEmpty && receiving.owner == receiver && foreignOperations == 0, "confirmed setup starts an empty device-owned journal and never resends imported history")
        check(try String(contentsOf: copiedRoot.appendingPathComponent("water.json"), encoding: .utf8) == "retained local history", "device setup preserves local record bytes")
        rejects("ordinary retry cannot accidentally reset a same-device journal") { _ = try HealthWriteFiles.prepareDeviceSetup(into: copiedRoot, owner: receiver) }
        var owned = Journal(owner: receiver); try appendAll(&owned)
        try owned.requestDeletion(domain: .water, localID: "water-43")
        try owned.requestDeletion(domain: .meal, localID: "meal-43")
        let deleteIDs = owned.events.filter { $0.action == .delete }.map(\.id)
        try owned.encoded().write(to: copiedRoot.appendingPathComponent(HealthWriteFiles.name), options: .atomic)
        try HealthWriteFiles.prepareReset(into: copiedRoot, owner: receiver).commit()
        let reset = try HealthWriteFiles.read(from: copiedRoot, owner: receiver)
        check(reset.owner == receiver && reset.lifecycle != owned.lifecycle && reset.events.map(\.id) == deleteIDs,
              "checked reset retains the same-device pending water/meal deletion identities and changes lifecycle")
        check(reset.events.allSatisfy { $0.action == .delete && $0.components.allSatisfy { $0.value == 0 && $0.date.timeIntervalSince1970 == 0 } },
              "reset scrubs quantities/dates and discards old saves while preserving minimal deletion intent")
        check(!FileManager.default.fileExists(atPath: copiedRoot.appendingPathComponent("water.json").path), "reset replacement removes local history instead of preserving it by accident")
        let nextReceiver = UUID()
        try HealthWriteFiles.prepareReset(into: copiedRoot, owner: nextReceiver).commit()
        check(try HealthWriteFiles.read(from: copiedRoot, owner: nextReceiver).events.isEmpty,
              "explicit reset of a foreign journal cannot carry its deletions onto the receiving device")

        // Bound the active batch and keep draining work beyond the first four.
        var many = Journal()
        for index in 0..<9 { try many.append(domain: .weight, localID: "bounded-\(index)", components: [component(.weight)]) }
        try disk.commit(many); disk.trace = []; worker.kick()
        check(worker.activeCount == 4, "backlog starts at most four independent event tasks")
        await worker.waitForCurrentWork()
        check(try disk.read().pendingEvents.isEmpty && disk.trace.count == 9 && worker.activeCount == 0, "bounded drain completes all nine records without waiting for another foreground retry")

        var competing = Journal(); try competing.append(domain: .water, localID: "receipt-race", components: [component(.water)])
        try disk.commit(competing)
        disk.beforeReceipt = {
            var newer = try disk.read()
            try newer.append(domain: .weight, localID: "newer-during-receipt", components: [component(.weight)])
            try disk.commit(newer)
        }
        worker.kick(); await worker.waitForCurrentWork()
        let afterRace = try disk.read()
        check(worker.storageIssue && afterRace.events.count == 2 && !afterRace.events[0].complete && afterRace.events[1].complete,
              "checked receipt comparison preserves a competing newer intent and leaves only its old operation pending")
        worker.kick(); await worker.waitForCurrentWork()
        check(try disk.read().pendingEvents.isEmpty, "receipt-race retry acknowledges original stable identity without losing newer work")
        if let output {
            try JSONSerialization.data(withJSONObject: ["passed": passed, "scope": "Production journal, recovery worker and linked Foundation transactions with controlled adapter; no HealthKit/native UI/device acceptance"], options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
    }

    /// Separate process phases: external outcome is a small durable adapter file,
    /// with the same stable sync-identity contract as the proposed Health bridge.
    static func processPhase(_ phase: String, root: URL) async throws {
        let disk = Disk(root)
        if phase == "prepare" || phase == "success-before-receipt" {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var journal = Journal(); try appendAll(&journal)
            try HealthWriteFiles.prepare(["water.json": Data("250mL".utf8), "meals.json": Data("synthetic meal".utf8), "goals.json": Data("75kg".utf8)], journal: journal, into: root).commit()
            try String(getpid()).write(to: root.deletingLastPathComponent().appendingPathComponent("prepare-pid"), atomically: true, encoding: .utf8)
            if phase == "success-before-receipt" {
                disk.rejectReceipt = true; let worker = disk.worker(); worker.kick(); await worker.waitForCurrentWork()
                let pending = try disk.read().pendingEvents.count
                precondition(worker.storageIssue && pending == 3)
            }
            _exit(0)
        }
        precondition(phase == "resume")
        let previous = try String(contentsOf: root.deletingLastPathComponent().appendingPathComponent("prepare-pid"), encoding: .utf8)
        precondition(previous != String(getpid()))
        let before = try disk.read(); precondition(before.pendingEvents.count == 3)
        let worker = disk.worker(); worker.kick(); await worker.waitForCurrentWork()
        let after = try disk.read()
        let external = try JSONDecoder().decode([String: Double].self, from: Data(contentsOf: root.deletingLastPathComponent().appendingPathComponent("external.json")))
        precondition(after.pendingEvents.isEmpty && external.count == 7 && after.owner == before.owner && after.lifecycle == before.lifecycle)
        let report: [String: Any] = ["status": "passed", "originalPID": previous, "resumedPID": getpid(), "events": after.events.count, "externalComponents": external.count, "sourceOwnedIdentifiers": external.keys.sorted(), "scope": "Actual process restart and production persistence/recovery; controlled idempotent adapter, not HealthKit"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.deletingLastPathComponent().appendingPathComponent("resume.json"), options: .atomic)
        print("PASS: new process recovers water, five meal components and weight with seven unique adapter identities.")
    }
}
