import Foundation

enum HealthSyncChecks {
    @MainActor static func run() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL: " + name) }; print("PASS: " + name)
        }
        let now = Date(), bed = now.addingTimeInterval(-10 * 3600), wake = now.addingTimeInterval(-2 * 3600)
        let id = UUID().uuidString, second = UUID().uuidString
        let sample = HealthSleepSample(id: id, start: bed, end: wake, value: 3, source: "Synthetic Watch")
        var ledger = HealthSyncLedger(now: now)
        try ledger.applySleep([sample], deleted: [], anchor: Data([1]))
        check(ledger.pendingApplication && ledger.sleepAnchor == Data([1]) && ledger.sleep.count == 1, "Health sleep page saves cursor and replay records together")
        let episode = ledger.reconciledSleep([])[0]
        check(episode.id == UUID(uuidString: id) && episode.duration == 8 * 3600, "Health sleep replay uses stable sample identity and measured duration")
        ledger.markApplied()
        check(!ledger.pendingApplication && ledger.managedSleepIDs == [episode.id], "applied Health cache retains ownership for later deletions")
        let manual = SleepEpisode(bedtime: bed, wakeTime: wake, source: .manual)
        let imported = Workout(id: "imported", kind: .run, title: "Synthetic import", start: bed, duration: 600, activeCalories: 50, source: .healthKit)
        var local = Workout(id: UUID().uuidString, kind: .walk, title: "Local", start: bed, duration: 600, activeCalories: 20, source: .manual)
        var live = local; live.id = second; live.source = .healthKit
        try ledger.applyWorkouts([live], deleted: [], anchor: Data([2]))
        check(ledger.reconciledWorkouts([local]).count == 2, "anchored Health workouts preserve manual sessions")
        let persisted = try JSONDecoder().decode(HealthSyncLedger.self, from: JSONEncoder().encode(ledger))
        check(persisted.sleep.count == 1 && persisted.workouts.count == 1 && persisted.pendingApplication, "Health cache survives process loss before view-store application")
        try ledger.applySleep([], deleted: [id], anchor: Data([3]))
        check(ledger.reconciledSleep([episode, manual]).map(\.id) == [manual.id], "Health sleep tombstone removes only managed measured night and preserves manual log")
        ledger.markApplied()
        check(ledger.reconciledSleep([episode]).isEmpty, "deleted Health night ownership survives application and prevents an old backup from resurrecting it")
        try ledger.applyWorkouts([], deleted: [second], anchor: Data([4]))
        check(ledger.reconciledWorkouts([live, local, imported]).map(\.id).sorted() == [local.id, imported.id].sorted(), "Health workout deletion removes matching live UUID without deleting other records")
        try ledger.applyWorkouts([], deleted: [], anchor: Data([5]))
        check(ledger.deletedWorkouts.contains(second), "empty Health page never clears prior deletion evidence")
        try ledger.applyWorkouts([live], deleted: [], anchor: Data([6]))
        check(!ledger.deletedWorkouts.contains(second) && ledger.workouts[second] != nil, "explicit reappearance reconciles a previously deleted Health UUID")
        let oldAnchor = ledger.sleepAnchor
        do { var bad = sample; bad.end = bad.start; try ledger.applySleep([bad], deleted: [], anchor: Data([7])); fatalError("bad sleep accepted") }
        catch { check(ledger.sleepAnchor == oldAnchor, "invalid Health page does not advance its cursor") }
        do { try ledger.applyWorkouts(Array(repeating: live, count: 501), deleted: [], anchor: Data([8])); fatalError("unbounded page accepted") }
        catch { check(ledger.workoutAnchor == Data([6]), "Health page size bound rejects before changing state") }
        do { try ledger.applyWorkouts([local], deleted: [], anchor: Data([9])); fatalError("local page accepted") }
        catch { check(ledger.workoutAnchor == Data([6]), "Health cache cannot claim a manual workout as a live record") }
        let overlap = HealthSleepSample(id: second, start: bed.addingTimeInterval(3600), end: wake, value: 4, source: "Synthetic Watch")
        let stages = HealthSleepSample.episodes([sample, overlap])[0]
        check(stages.duration == 8 * 3600 && stages.deepSeconds == 7 * 3600, "sleep intervals are unioned across overlapping source samples")
        var changed = sample; changed.end = bed.addingTimeInterval(4 * 3600)
        try ledger.applySleep([changed], deleted: [], anchor: Data([10]))
        check(ledger.reconciledSleep([])[0].duration == 4 * 3600, "changed Health sample replaces its previous cached value")
        let encoded = try JSONEncoder().encode(manual), decoded = try JSONDecoder().decode(SleepEpisode.self, from: encoded)
        check(decoded == manual, "existing sleep record encoding remains compatible")
        let lock = NSLock(); var count = 0
        let delivery = HealthDeliveryCompletion { lock.lock(); count += 1; lock.unlock() }
        DispatchQueue.concurrentPerform(iterations: 50) { _ in delivery.finish() }
        check(count == 1, "racing Health delivery completion callbacks finish exactly once")
        do { let abandoned = HealthDeliveryCompletion { count += 1 }; _ = abandoned }
        check(count == 2, "abandoned Health delivery completion still acknowledges its platform callback")
        local.id = second
        check(ledger.reconciledWorkouts([local]).contains { $0.source == .manual }, "manual identity collision is not removed by a Health tombstone")

        var rescanned = ledger
        rescanned.rescanPermissions()
        check(rescanned.sleepAnchor == nil && rescanned.workoutAnchor == nil && rescanned.sleep.count == ledger.sleep.count && rescanned.workouts.count == ledger.workouts.count && rescanned.managedSleepIDs == ledger.managedSleepIDs,
              "reviewing Health access resets cursors for expanded history while preserving known records and deletion ownership")
        var corrupt = ledger; corrupt.sleep["wrong-key"] = sample
        do { try corrupt.validate(); fatalError("corrupt Health cache accepted") }
        catch { print("PASS: inconsistent Health cache identities are rejected before application") }
        corrupt = ledger; corrupt.workoutAnchor = Data(repeating: 0, count: 1024 * 1024 + 1)
        do { try corrupt.validate(); fatalError("oversized anchor accepted") }
        catch { print("PASS: oversized persisted Health anchors are rejected") }
        enum SimulatedFailure: Error { case disk }
        var durable = HealthSyncLedger(now: now), attempts = 0
        let fetch: (Bool, Date, Data?) async throws -> HealthChangePage = { sleep, _, anchor in
            attempts += 1
            if sleep { return HealthChangePage(sleep: [sample], deleted: [], anchor: Data([20]), more: false) }
            return HealthChangePage(workouts: [live], deleted: [], anchor: Data([21]), more: false)
        }
        do {
            _ = try await HealthSyncReplay.drain(durable, check: {}, query: fetch, save: { value in
                if value.workoutAnchor != nil { throw SimulatedFailure.disk }; durable = value
            })
            fatalError("disk failure accepted")
        } catch {
            check(durable.sleepAnchor == Data([20]) && durable.workoutAnchor == nil && durable.pendingApplication,
                  "a failed workout-page save retains only the previously durable sleep cursor")
        }
        var queriedSleepAnchor: Data?
        durable = try await HealthSyncReplay.drain(durable, check: {}, query: { sleep, start, anchor in
            if sleep { queriedSleepAnchor = anchor }
            return try await fetch(sleep, start, anchor)
        }, save: { durable = $0 })
        check(queriedSleepAnchor == Data([20]) && durable.workouts.count == 1 && attempts == 4,
              "retry resumes the durable cursor and replays the failed page without duplicates")
        var cancelled = false, reads = 0
        let before = durable.workoutAnchor
        do {
            _ = try await HealthSyncReplay.drain(durable, check: { if cancelled { throw CancellationError() } }, query: { _, _, _ in
                reads += 1; cancelled = true
                return HealthChangePage(deleted: [], anchor: Data([30]), more: true)
            }, save: { durable = $0 })
            fatalError("cancelled page accepted")
        } catch {
            check(reads == 1 && durable.workoutAnchor == before && durable.sleepAnchor == Data([20]),
                  "disconnect or expiration during a read prevents any late cursor save")
        }
        var pageIndex = 0
        let paged = try await HealthSyncReplay.drain(HealthSyncLedger(now: now), check: {}, query: { sleep, _, anchor in
            if !sleep { return HealthChangePage(deleted: [], anchor: Data([42]), more: false) }
            pageIndex += 1
            if pageIndex == 1 { return HealthChangePage(sleep: [sample], deleted: [], anchor: Data([40]), more: true) }
            check(anchor == Data([40]), "second Health page uses the saved preceding cursor")
            return HealthChangePage(deleted: [sample.id], anchor: Data([41]), more: false)
        }, save: { _ in })
        check(paged.sleep.isEmpty && paged.sleepAnchor == Data([41]), "a later-page tombstone removes a sample from the initial page")
        do {
            _ = try await HealthSyncReplay.drain(durable, check: {}, query: { _, _, anchor in
                HealthChangePage(deleted: [], anchor: anchor!, more: true)
            }, save: { _ in fatalError("stalled cursor was saved") })
            fatalError("stalled cursor accepted")
        } catch { print("PASS: a non-advancing full Health page fails instead of looping forever") }
        let queue = HealthSyncQueue()
        var passes: [Bool] = [], unblock: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            await queue.run(includeProviders: false) { include in
                passes.append(include)
                if passes.count == 1 { await withCheckedContinuation { unblock = $0 } }
            }
        }
        while unblock == nil { await Task.yield() }
        var joined = 0
        let burst = (0..<8).map { index in Task { @MainActor in joined += 1; await queue.run(includeProviders: index == 3) { _ in fatalError("second concurrent worker") } } }
        // Let each event join the existing drain before releasing its first pass.
        while joined < 8 { await Task.yield() }
        unblock?.resume(); await first.value
        for task in burst { await task.value }
        check(passes == [false, true], "observer burst coalesces into one follow-up pass while retaining the foreground provider request")
        await queue.run(includeProviders: false) { passes.append($0) }
        check(passes == [false, true, false], "an event after drain completion starts a fresh worker")
    }
}
