import Foundation

@MainActor
enum HealthWriteOrderChecks {
    private final class Gate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if open { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            open = true
            let pending = waiters; waiters = []
            for waiter in pending { waiter.resume() }
        }
    }
    private final class Probe {
        let entered = Gate(), release = Gate()
        var events: [String] = []
        var present = false
        var deleted = 0
        func save() async {
            events.append("save-start"); entered.release()
            await release.wait()
            present = true; events.append("save-finish")
        }
        func delete() {
            events.append("delete")
            deleted = present ? 1 : 0; present = false
        }
    }

    static func run(output: URL? = nil) async throws {
        var passed = 0
        var traces: [[String: String]] = []
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }
            passed += 1; print("PASS: " + message)
        }
        // Deterministic reproduction of the old two-independent-Task shape.
        // The backend is controlled; no real HealthKit or device claim follows.
        for label in ["water", "meal"] {
            let probe = Probe()
            let save = Task { await probe.save() }
            await probe.entered.wait()
            let deletion = Task { probe.delete() }
            await deletion.value
            check(probe.deleted == 0 && !probe.present, "legacy \(label) deletion can complete before a pending save")
            probe.release.release(); await save.value
            check(probe.present && probe.events == ["save-start", "delete", "save-finish"], "legacy \(label) ordering leaves a saved record after deletion")
            traces.append(["case": "legacy-" + label, "events": probe.events.joined(separator: ","), "finalRecord": "present"])
        }
        for key in [OrderedHealthWrites.Key.water("same-id"), .meal("same-id")] {
            let writes = OrderedHealthWrites(), probe = Probe()
            let save = writes.enqueue(key) { await probe.save() }
            await probe.entered.wait()
            let deletion = writes.enqueue(key) { probe.delete() }
            // An unrelated key can complete while the original save is held.
            let other = writes.enqueue(.water("other-id")) { probe.events.append("independent") }
            await other.value
            check(!probe.events.contains("delete") && probe.events.contains("independent"), "same-record deletion waits without blocking another record")
            check(writes.pendingRecordCount == 1, "only the unfinished original record retains a queue tail")
            probe.release.release(); await save.value; await deletion.value
            check(probe.deleted == 1 && !probe.present && probe.events == ["save-start", "independent", "save-finish", "delete"], "ordered save completion precedes deletion and leaves no orphan")
            check(writes.pendingRecordCount == 0, "completed record tasks are released")
            traces.append(["case": "ordered-\(key)", "events": probe.events.joined(separator: ","), "finalRecord": "absent"])
        }
        let writes = OrderedHealthWrites(), first = Gate(), second = Gate(), secondEntered = Gate()
        let probe = Probe()
        let a = writes.enqueue(.water("chain")) { await first.wait(); probe.events.append("a") }
        let b = writes.enqueue(.water("chain")) { secondEntered.release(); await second.wait(); probe.events.append("b") }
        first.release(); await a.value; await secondEntered.wait()
        check(writes.pendingRecordCount == 1, "an older completion cannot remove a newer tail")
        let c = writes.enqueue(.water("chain")) { probe.events.append("c") }
        let barrier = writes.enqueue(.meal("chain")) { probe.events.append("separate-domain") }
        await barrier.value
        check(probe.events == ["a", "separate-domain"], "meal and water namespaces remain independent for identical IDs")
        second.release(); await b.value; await c.value
        check(probe.events == ["a", "separate-domain", "b", "c"] && writes.pendingRecordCount == 0, "a third operation keeps the full record dependency chain")

        let cancelled = OrderedHealthWrites(), held = Probe()
        let saving = cancelled.enqueue(.water("cancel")) { await held.save() }
        await held.entered.wait()
        let deleting = cancelled.enqueue(.water("cancel")) { held.delete() }
        deleting.cancel()
        let cancelledBarrier = cancelled.enqueue(.meal("progress")) { held.events.append("barrier") }
        await cancelledBarrier.value
        check(!held.events.contains("delete"), "cancelling a queued task cannot let deletion overtake a save")
        held.release.release(); await saving.value; await deleting.value
        check(!held.present && held.deleted == 1 && cancelled.pendingRecordCount == 0, "an already-requested ordered deletion finishes after consumer cancellation")

        let failed = OrderedHealthWrites(), failureGate = Gate(), failureEntered = Gate(), failedProbe = Probe()
        let failingSave = failed.enqueue(.meal("failed")) {
            failedProbe.events.append("save-start"); failureEntered.release(); await failureGate.wait()
            // Equivalent to the existing service returning after its caught save error.
            failedProbe.events.append("save-error")
        }
        await failureEntered.wait()
        let afterFailure = failed.enqueue(.meal("failed")) { failedProbe.delete() }
        failureGate.release(); await failingSave.value; await afterFailure.value
        check(failedProbe.events == ["save-start", "save-error", "delete"] && failedProbe.deleted == 0, "a failed save completes before the subsequent delete attempt")
        check(failed.pendingRecordCount == 0, "a handled service failure does not retain a completed tail")

        let stale = OrderedHealthWrites(), staleGate = Gate(), staleEntered = Gate(), staleProbe = Probe()
        let blocker = stale.enqueue(.water("stale")) { staleEntered.release(); await staleGate.wait() }
        await staleEntered.wait()
        let staleSave = stale.enqueueSave(.water("stale"), isCurrent: { true }) { staleProbe.events.append("stale-save") }
        let removal = stale.enqueue(.water("stale")) { staleProbe.delete() }
        stale.invalidatePendingSaves()
        staleGate.release(); await blocker.value; await staleSave.value; await removal.value
        check(staleProbe.events == ["delete"] && stale.pendingRecordCount == 0, "reset/restore invalidates unstarted saves without dropping a requested deletion")
        let notCurrent = stale.enqueueSave(.meal("removed"), isCurrent: { false }) { staleProbe.events.append("removed-save") }
        await notCurrent.value
        check(staleProbe.events == ["delete"], "a removed record cannot start a queued save")
        let currentSave = stale.enqueueSave(.meal("new"), isCurrent: { true }) { staleProbe.events.append("new-save") }
        await currentSave.value
        check(staleProbe.events == ["delete", "new-save"] && stale.pendingRecordCount == 0, "a fresh explicit log can save after invalidation")

        let inFlight = OrderedHealthWrites(), running = Probe()
        let alreadyStarted = inFlight.enqueueSave(.water("running"), isCurrent: { true }) { await running.save() }
        await running.entered.wait()
        let removeRunning = inFlight.enqueue(.water("running")) { running.delete() }
        inFlight.invalidatePendingSaves(); running.release.release()
        await alreadyStarted.value; await removeRunning.value
        check(running.events == ["save-start", "save-finish", "delete"] && !running.present,
              "invalidation cannot skip completion of an already-started save before deleting it")
        if let output {
            let report = Report(checks: passed, traces: traces,
                scope: "Production ordering primitive with manually controlled asynchronous callbacks. Legacy task shape reproduced for water/meal; not real HealthKit writes, physical-device behavior, durable retry or local-persistence fault coverage.")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: output, options: .atomic)
        }
    }
    private struct Report: Encodable { let checks: Int; let traces: [[String: String]]; let scope: String }
}
