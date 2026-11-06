import Foundation

enum HealthTodayQueryChecks {
    private enum Failure: Error { case timedOut, query }
    private final class Counts: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Int] = [:]
        func add(_ key: String) { lock.lock(); values[key, default: 0] += 1; lock.unlock() }
        func get(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key, default: 0] }
    }
    private final class HeldQueries: @unchecked Sendable {
        struct Row {
            let gate: HealthReadingQuery<HealthMetricReading>
            let start: Date
            let end: Date
        }
        private let lock = NSLock()
        private var rows: [String: Row] = [:]
        let counts = Counts()
        var started: Int { lock.lock(); defer { lock.unlock() }; return rows.count }
        func query(_ key: String, _ start: Date, _ end: Date, _ group: HealthReadingQueryGroup) async throws -> HealthMetricReading {
            let gate = HealthReadingQuery<HealthMetricReading>()
            let token = group.register { gate.cancel() }
            defer { group.detach(token) }
            return try await gate.value(start: {
                self.lock.lock(); self.rows[key] = Row(gate: gate, start: start, end: end); self.lock.unlock()
                self.counts.add("starts")
            }, stop: { self.counts.add("stops") })
        }
        func release(water: Double?, failed: Bool = false) {
            lock.lock(); let rows = self.rows; lock.unlock()
            for (key, row) in rows {
                let outcome: HealthMetricQuery.Outcome = failed ? .failed : key == "water" && water != nil ? .recorded : .noData
                let query = HealthMetricQuery(start: row.start, end: row.end, checkedAt: row.end, outcome: outcome)
                let components: [HealthMetricComponent] = outcome == .recorded
                    ? [.init(value: water!, origin: .healthKit, source: "Held synthetic source", start: row.start, end: row.end, checkedAt: row.end, aggregation: .total)] : []
                row.gate.complete(.success(.init(components: components, healthQuery: query)))
            }
        }
    }

    @MainActor static func run(output: URL? = nil) async throws {
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label) }
        func until(_ condition: () -> Bool) async throws {
            for _ in 0..<300 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw Failure.timedOut
        }
        func cancelled<T>(_ task: Task<T, Error>) async -> Bool {
            do { _ = try await task.value; return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let beforeStart = HealthReadingQuery<Int>(), beforeCounts = Counts()
        beforeStart.cancel()
        do {
            _ = try await beforeStart.value(start: { beforeCounts.add("start") }, stop: { beforeCounts.add("stop") })
            check(false, "cancelled-before-start must throw")
        } catch is CancellationError { check(true, "cancel-before-registration resumes cancellation") }
        check(beforeCounts.get("start") == 0 && beforeCounts.get("stop") == 0, "cancel-before-registration never starts or stops an unexecuted query")

        let synchronous = HealthReadingQuery<Int>(), syncCounts = Counts()
        let syncValue = try await synchronous.value(start: { synchronous.complete(.success(7)) }, stop: { syncCounts.add("stop") })
        synchronous.cancel(); synchronous.complete(.success(99))
        check(syncValue == 7 && syncCounts.get("stop") == 0, "synchronous completion and late callbacks finish once without stopping a completed query")

        let duringStart = HealthReadingQuery<Int>(), duringCounts = Counts()
        do {
            _ = try await duringStart.value(start: {
                duringCounts.add("start"); duringStart.cancel(); duringCounts.add("registered")
            }, stop: {
                precondition(duringCounts.get("registered") == 1)
                duringCounts.add("stop"); duringStart.complete(.success(99))
            })
            check(false, "registration cancellation must throw")
        } catch is CancellationError { check(true, "cancellation during registration resumes only after start returns and stop finishes") }
        check(duringCounts.get("start") == 1 && duringCounts.get("stop") == 1, "registration race stops exactly once and ignores a reentrant stop callback")

        let expired = HealthReadingQuery<Int>(), expiryCounts = Counts()
        do {
            _ = try await expired.value(timeout: 0.01, start: { expiryCounts.add("start") }, stop: { expiryCounts.add("stop") })
            check(false, "query timeout must throw")
        } catch HealthReadingQueryFailure.timeout { check(true, "actual query deadline resumes the waiting continuation") }
        expired.complete(.success(99)); expired.cancel()
        check(expiryCounts.get("start") == 1 && expiryCounts.get("stop") == 1, "deadline stops its query once before returning and ignores late completion")

        for _ in 0..<100 {
            let gate = HealthReadingQuery<Int>(), counts = Counts()
            let task = Task {
                try await gate.value(start: {
                    counts.add("starts")
                    DispatchQueue.global().async { gate.complete(.success(1)) }
                }, stop: { counts.add("stops") })
            }
            task.cancel()
            do { _ = try await task.value } catch is CancellationError { }
            precondition(counts.get("stops") <= counts.get("starts") && counts.get("stops") <= 1)
            gate.complete(.success(2)); gate.cancel()
        }
        check(true, "100 concurrent callback/cancellation races finish without duplicate continuation or stop")

        let detachedGroup = HealthReadingQueryGroup(), detachedCounts = Counts()
        let detachedToken = detachedGroup.register { detachedCounts.add("cancel") }
        detachedGroup.detach(detachedToken); detachedGroup.cancel()
        let lateToken = detachedGroup.register { detachedCounts.add("late") }; detachedGroup.detach(lateToken)
        check(detachedCounts.get("cancel") == 0 && detachedCounts.get("late") == 1, "completed registrations detach; registration after group cancellation cancels immediately")

        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        let selections = HealthTodayReadCoordinator()
        let disconnectedClear = selections.captureSelection(available: false, now: now, calendar: calendar)
        check(selections.isCurrent(disconnectedClear, available: false, now: now, calendar: calendar),
              "explicit clear can bind a disconnected source without pretending it returned readings")
        check(!selections.isCurrent(disconnectedClear, available: true, now: now, calendar: calendar),
              "availability change invalidates the clear review")
        check(!selections.isCurrent(disconnectedClear, available: false, now: now.addingTimeInterval(86400), calendar: calendar)
              && !selections.isCurrent(disconnectedClear, available: false, now: now.addingTimeInterval(-1), calendar: calendar),
              "clear review rejects a different day or a clock moved before selection")
        var sameOffsetZone = calendar; sameOffsetZone.timeZone = TimeZone(identifier: "Etc/UTC")!
        check(!disconnectedClear.matchesSourceAndDay(selections.captureSelection(available: false, now: now, calendar: sameOffsetZone)),
              "equal-offset time-zone identity changes cannot silently replace the initial review window")
        let clearBeforeNewQuery = selections.captureSelection(available: true, now: now, calendar: calendar)
        _ = try await selections.read(available: true, now: now, calendar: calendar) { _, start, end, _ in
            .init(healthQuery: .init(start: start, end: end, checkedAt: end, outcome: .noData))
        }
        check(!selections.isCurrent(clearBeforeNewQuery, available: true, now: now, calendar: calendar),
              "a newer query selection invalidates an earlier clear review even without a file write")
        let afterNewQuery = selections.captureSelection(available: true, now: now, calendar: calendar)
        check(clearBeforeNewQuery.matchesSourceAndDay(afterNewQuery) && selections.isCurrent(afterNewQuery, available: true, now: now, calendar: calendar),
              "rebuild may bind its own new request while keeping the original source and day")
        selections.invalidate()
        check(!afterNewQuery.matchesSourceAndDay(selections.captureSelection(available: true, now: now, calendar: calendar)),
              "source invalidation during query cannot be adopted as the original review source")
        let coordinator = HealthTodayReadCoordinator(), first = HeldQueries(), second = HeldQueries()
        let a = Task { try await coordinator.read(available: true, now: now, calendar: calendar) { try await first.query($0, $1, $2, $3) } }
        try await until { first.started == 18 }
        let b = Task { try await coordinator.read(available: true, now: now.addingTimeInterval(1), calendar: calendar) { try await second.query($0, $1, $2, $3) } }
        try await until { second.started == 18 }
        second.release(water: 246)
        let secondRead = try await b.value
        first.release(water: 137)
        let firstRead = try await a.value
        check(firstRead.raw.metrics.reading("water").value == 137 && secondRead.raw.metrics.reading("water").value == 246,
              "overlapping requests completed in reverse order each return their own raw observations")
        check(!coordinator.isCurrent(firstRead, available: true, now: now.addingTimeInterval(2), calendar: calendar)
              && coordinator.isCurrent(secondRead, available: true, now: now.addingTimeInterval(2), calendar: calendar),
              "older completion cannot publish or install over the newer request")
        check(first.counts.get("stops") == 0 && second.counts.get("stops") == 0, "normally completed query sets need no cancellation stops")
        check(!coordinator.isCurrent(secondRead, available: false, now: now.addingTimeInterval(2), calendar: calendar), "unavailable source cannot publish a prior successful result")
        check(!coordinator.isCurrent(secondRead, available: true, now: now.addingTimeInterval(86400), calendar: calendar), "day rollover rejects a completed earlier-day result")
        var otherZone = calendar; otherZone.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        check(!coordinator.isCurrent(secondRead, available: true, now: now.addingTimeInterval(2), calendar: otherZone), "time-zone change rejects the captured query window")
        coordinator.invalidate()
        check(!coordinator.isCurrent(secondRead, available: true, now: now.addingTimeInterval(2), calendar: calendar), "source generation invalidation cannot revive an earlier result after reconnect")

        let notAvailable = Counts()
        do {
            _ = try await coordinator.read(available: false, now: now, calendar: calendar) { _, _, _, _ in
                notAvailable.add("query"); return .unknown
            }
            check(false, "unavailable read must throw")
        } catch HealthTodayReadCoordinator.Failure.unavailable { check(true, "unavailable read returns an explicit error rather than shared prior data") }
        check(notAvailable.get("query") == 0, "unavailable read starts no queries")

        for mode in ["owner-task-cancel", "source-invalidate"] {
            let held = HeldQueries()
            let task = Task { try await coordinator.read(available: true, now: now, calendar: calendar) { try await held.query($0, $1, $2, $3) } }
            try await until { held.started == 18 }
            if mode == "owner-task-cancel" { task.cancel() } else { coordinator.invalidate() }
            check(await cancelled(task), "\(mode) propagates cancellation through the actual eighteen waiting continuations")
            check(held.counts.get("stops") == 18, "\(mode) stops all eighteen query handles before returning")
            held.release(water: 999); task.cancel(); coordinator.invalidate()
            check(held.counts.get("stops") == 18, "\(mode) ignores all late query successes and repeated cancellation")
        }
        let fresh = HeldQueries()
        let freshTask = Task { try await coordinator.read(available: true, now: now, calendar: calendar) { try await fresh.query($0, $1, $2, $3) } }
        try await until { fresh.started == 18 }; fresh.release(water: 500)
        let freshRead = try await freshTask.value
        check(freshRead.raw.metrics.reading("water").value == 500 && coordinator.isCurrent(freshRead, available: true, now: now, calendar: calendar),
              "fresh request after invalidation succeeds with distinct observations")

        let failed = HeldQueries()
        let failedTask = Task { try await coordinator.read(available: true, now: now, calendar: calendar) { try await failed.query($0, $1, $2, $3) } }
        try await until { failed.started == 18 }; failed.release(water: nil, failed: true)
        do { _ = try await failedTask.value; check(false, "all-failed request must reject") }
        catch { check(true, "all-query failure produces no replacement readings") }
        check(!coordinator.isCurrent(freshRead, available: true, now: now, calendar: calendar), "failed newer request cannot fall back to the earlier successful result")

        let empty = HeldQueries()
        let emptyTask = Task { try await coordinator.read(available: true, now: now, calendar: calendar) { try await empty.query($0, $1, $2, $3) } }
        try await until { empty.started == 18 }; empty.release(water: nil)
        let emptyRead = try await emptyTask.value
        check(emptyRead.raw.metrics.readings?.count == 18 && emptyRead.raw.metrics.readings?.values.allSatisfy { $0.value == nil && $0.healthQuery?.outcome == .noData } == true,
              "successful empty queries return eighteen explicit unknown/no-data outcomes")
        let cancelledAfterRead = Task {
            let value = try await coordinator.read(available: true, now: now, calendar: calendar) { _, start, end, _ in
                .init(healthQuery: .init(start: start, end: end, checkedAt: end, outcome: .noData))
            }
            withUnsafeCurrentTask { $0?.cancel() }
            return coordinator.isCurrent(value, available: true, now: now, calendar: calendar)
        }
        check(try await !cancelledAfterRead.value, "cancellation after query completion still rejects publication in the owning task")
        if let output {
            let report: [String: Any] = ["status": "passed", "count": checks.count, "checks": checks,
                "scope": "Production query continuation/group/coordinator with real concurrent Tasks, held synthetic callbacks and actual deadline. No Apple Health samples/permissions/daemon or native UI/device acceptance."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
        print("Health today queries: \(checks.count) checks passed")
    }
}
