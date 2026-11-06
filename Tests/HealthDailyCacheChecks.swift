import Foundation
import Darwin

enum HealthDailyCacheChecks {
    static func run(output: URL? = nil) throws {
        let fm = FileManager.default
        let outer = fm.temporaryDirectory.appendingPathComponent("Lumen-daily-cache-" + UUID().uuidString)
        try fm.createDirectory(at: outer, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: outer) }
        let day = Date(timeIntervalSince1970: 1_793_491_200), end = day.addingTimeInterval(3600)
        let owner = UUID()
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label) }
        func rejects(_ label: String, _ operation: () throws -> Void) {
            var rejected = false
            do { try operation() } catch { rejected = true }
            check(rejected, label)
        }
        var journal = HealthWriteJournal(owner: owner)
        try journal.append(domain: .water, localID: "in-flight", components: [.init(metric: .water, value: 246, date: day)])
        let inFlight = journal.next()!
        try journal.append(domain: .meal, localID: "partial", components: [
            .init(metric: .calories, value: 400, date: day), .init(metric: .protein, value: 24, date: day)])
        let partial = journal.next(excluding: [inFlight.event])!
        try journal.acknowledge(partial)
        try journal.requestDeletion(domain: .water, localID: "pending-removal")
        let originalJournal = journal, journalBytes = try journal.encoded()
        func seed(_ name: String, state: String) throws -> URL {
            let root = outer.appendingPathComponent(name)
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            var files = try ConversationFiles.encoded([], activeID: nil)
            files[HealthWriteFiles.name] = journalBytes
            files["profile.json"] = Data("private profile sentinel".utf8)
            files["water.json"] = Data("[]".utf8)
            files["goals.json"] = try BackupArchive.encoder().encode(HealthGoals())
            for (name, data) in files { try data.write(to: root.appendingPathComponent(name)) }
            try fm.createDirectory(at: root.appendingPathComponent("photos"), withIntermediateDirectories: false)
            try Data([0, 1, 2, 3, 4]).write(to: root.appendingPathComponent("photos/existing.jpg"))
            switch state {
            case "healthy": try BackupArchive.encoder().encode(HealthDailyCache.unknown(day: day)).write(to: root.appendingPathComponent("today.json"))
            case "corrupt": try Data("{invalid saved cache".utf8).write(to: root.appendingPathComponent("today.json"))
            case "directory":
                try fm.createDirectory(at: root.appendingPathComponent("today.json/nested"), withIntermediateDirectories: true)
                try Data("failed directory bytes".utf8).write(to: root.appendingPathComponent("today.json/nested/raw.bin"))
            default: break
            }
            return root
        }
        func tree(_ root: URL) throws -> [String: Data] {
            var result: [String: Data] = [:]
            guard let physical = realpath(root.path, nil) else { throw HealthLocalFiles.Failure.invalid }
            let canonical = URL(fileURLWithPath: String(cString: physical)); free(physical)
            guard let entries = fm.enumerator(at: canonical, includingPropertiesForKeys: nil) else { return result }
            for case let file as URL in entries {
                let facts = try fm.attributesOfItem(atPath: file.path)
                if facts[.type] as? FileAttributeType == .typeRegular {
                    result[String(file.path.dropFirst(canonical.path.count + 1))] = try Data(contentsOf: file)
                }
            }
            return result
        }
        func readings() -> [String: HealthMetricReading] {
            Dictionary(uniqueKeysWithValues: HealthDailyCache.queryKeys.map { key in
                (key, .init(healthQuery: .init(start: day, end: end, checkedAt: end, outcome: .noData)))
            })
        }
        var queried = readings()
        queried["steps"] = .init(components: [.init(value: 0, origin: .healthKit, source: "Apple Health", start: day, end: end, checkedAt: end, aggregation: .total)], healthQuery: .init(start: day, end: end, checkedAt: end, outcome: .recorded))
        queried["water"] = .init(components: [.init(value: 137, origin: .healthKit, source: "Apple Health", start: day, end: end, checkedAt: end, aggregation: .total)], healthQuery: .init(start: day, end: end, checkedAt: end, outcome: .recorded))
        queried["hrv"] = .init(healthQuery: .init(start: day, end: end, checkedAt: end, outcome: .failed))
        let raw = try HealthDailyCache.rawReadings(queried, start: day, end: end)
        var failedQueries = readings()
        for key in failedQueries.keys { failedQueries[key]?.healthQuery?.outcome = .failed }
        rejects("a completely failed rebuild cannot become implicit clearing") {
            _ = try HealthDailyCache.rawReadings(failedQueries, start: day, end: end)
        }
        let noData = try HealthDailyCache.rawReadings(readings(), start: day, end: end)
        check(noData.metrics.readings?.count == 18 && noData.metrics.recordedTotalKeys?.isEmpty == true
              && noData.metrics.readings?.values.allSatisfy { $0.value == nil && $0.healthQuery?.outcome == .noData } == true,
              "successful empty queries retain explicit no-data provenance without invented values")
        check(raw.metrics.reading("steps").value == 0 && raw.metrics.recordedTotalKeys?.contains("steps") == true,
              "recorded zero remains an actual returned reading")
        check(raw.metrics.reading("calories").value == nil && raw.metrics.reading("calories").healthQuery?.outcome == .noData,
              "no-data query remains unknown with its query provenance")
        check(raw.metrics.reading("hrv").value == nil && raw.metrics.reading("hrv").healthQuery?.outcome == .failed,
              "failed query remains distinct from empty data")
        for invalid in ["missing-key", "mixed-window", "local-total", "false-no-data", "early-check"] {
            var candidate = queried
            switch invalid {
            case "missing-key": candidate.removeValue(forKey: "fat")
            case "mixed-window": candidate["hrv"]?.healthQuery?.start = day.addingTimeInterval(-86400)
            case "local-total": candidate["water"]?.components[0].origin = .localLog
            case "false-no-data": candidate["water"]?.healthQuery?.outcome = .noData
            default: candidate["steps"]?.healthQuery?.checkedAt = day
            }
            rejects("raw cache rejects \(invalid)") { _ = try HealthDailyCache.rawReadings(candidate, start: day, end: end) }
        }
        let cleared = HealthDailyCache.unknown(day: day)
        check(cleared.readings?.isEmpty == true && cleared.recordedTotalKeys?.isEmpty == true && cleared.reading("steps").value == nil,
              "explicit clear has unknown readings, not measured zero")
        for state in ["missing", "healthy", "corrupt", "directory"] {
            for action in ["clear", "rebuild"] {
                let root = try seed(state + "-" + action, state: state)
                let previous = root.appendingPathExtension("previous")
                try fm.copyItem(at: root, to: previous)
                try Data("prior unique sentinel".utf8).write(to: previous.appendingPathComponent("prior-only.bin"))
                let before = try tree(root), old = try tree(previous)
                let selected = try HealthDailyCache.capture(in: root)
                check(selected.state.rawValue == (state == "corrupt" || state == "directory" ? "unavailable" : state),
                      "\(state)/\(action) distinguishes actual cache availability")
                let replacement: HealthDailyCache.Replacement = action == "clear" ? .clear(day: day) : .rebuild(raw)
                let transaction = try HealthDailyCache.prepare(replacement, replacing: selected, in: root, owner: owner)
                check(try tree(root) == before && tree(previous) == old, "\(state)/\(action) preparation changes no live or previous bytes")
                try transaction.commit()
                let installed = try HealthLocalFiles.read(DayMetrics.self, domain: .today, from: root).value!
                check(installed.reading("water").value == (action == "clear" ? nil : 137), "\(state)/\(action) installs only the chosen raw snapshot")
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let water = [HydrationLog(id: "local", date: day.addingTimeInterval(120), ml: 246)]
                let imported = ImportedHealthDay(date: day, values: ["steps": 42], sources: ["steps": "Portable import"])
                let sleep = SleepEpisode(bedtime: day.addingTimeInterval(-7 * 3600), wakeTime: day.addingTimeInterval(1800))
                func resolved(_ snapshot: DayMetrics) -> DayMetrics {
                    CurrentHealthEvidence.resolve(snapshot: snapshot, imported: imported, meals: [], water: water,
                                                  workouts: [], sleep: sleep, now: end, calendar: calendar)
                }
                let shown = resolved(installed)
                check(shown.reading("water").value == (action == "clear" ? 246 : 383)
                      && shown.reading("steps").value == (action == "clear" ? 42 : 0),
                      "\(state)/\(action) combines local/imported readings once with recorded-zero precedence")
                check(shown.reading("sleep").value == 7.5 && installed.reading("sleep").value == nil,
                      "\(state)/\(action) derives sleep once without persisting it as raw Health data")
                let reopened = try HealthLocalFiles.read(DayMetrics.self, domain: .today, from: root).value!
                check(resolved(reopened).readings == shown.readings && reopened.reading("water").value == installed.reading("water").value,
                      "\(state)/\(action) actual file reopen recomputes totals without double counting")
                let after = try tree(root)
                check(try before.filter { !$0.key.hasPrefix("today.json") }.allSatisfy { after[$0.key] == $0.value } && tree(previous) == old,
                      "\(state)/\(action) retains exact unrelated files and entire previous root")
                let saved = try HealthWriteFiles.read(from: root, owner: owner)
                check(saved == originalJournal && saved.lifecycle == originalJournal.lifecycle && saved.contains(inFlight)
                      && saved.next() == originalJournal.next() && saved.pendingEvents == originalJournal.pendingEvents
                      && after[HealthWriteFiles.name] == journalBytes,
                      "\(state)/\(action) preserves exact journal, partial acknowledgement, in-flight save and deletion eligibility")
                let retained = after.filter { $0.key.hasPrefix(HealthRecoveryCopies.name + "/") }
                if state != "missing" {
                    check(before.filter { $0.key.hasPrefix("today.json") }.allSatisfy { original in
                        retained.contains { $0.key.hasSuffix("/" + original.key) && $0.value == original.value }
                    }, "\(state)/\(action) retains exact replaced raw file or nested directory")
                }
                check(after.keys.filter { $0.hasPrefix(".health-cache-history/") }.count == 1,
                      "\(state)/\(action) records cache provenance without a Health delivery acknowledgement")
            }
        }
        for fault in ["cancel", "current-change", "previous-change", "selection-change", "install-permission"] {
            let root = try seed("reject-" + fault, state: "corrupt"), previous = root.appendingPathExtension("previous")
            try fm.copyItem(at: root, to: previous)
            let selected = try HealthDailyCache.capture(in: root), operation = BackupOperationControl()
            if fault == "selection-change" {
                try Data("new selected cache".utf8).write(to: root.appendingPathComponent("today.json"), options: .atomic)
                let before = try tree(root), prior = try tree(previous)
                rejects("changed reviewed cache cannot begin preparation") { _ = try HealthDailyCache.prepare(.clear(day: day), replacing: selected, in: root, owner: owner) }
                check(try tree(root) == before && tree(previous) == prior, "changed selection rejection preserves current and previous")
                continue
            }
            let transaction = try HealthDailyCache.prepare(.clear(day: day), replacing: selected, in: root, owner: owner, control: operation)
            if fault == "cancel" { operation.cancel() }
            if fault == "current-change" { try Data("new local write".utf8).write(to: root.appendingPathComponent("profile.json"), options: .atomic) }
            if fault == "previous-change" { try Data("new prior bytes".utf8).write(to: previous.appendingPathComponent("profile.json"), options: .atomic) }
            let before = try tree(root), prior = try tree(previous)
            if fault == "install-permission" {
                guard chmod(outer.path, 0o500) == 0 else { throw HealthLocalFiles.Failure.invalid }
            }
            rejects("\(fault) rejects installation") { try transaction.commit(control: operation) }
            if fault == "install-permission" {
                guard chmod(outer.path, 0o700) == 0 else { throw HealthLocalFiles.Failure.invalid }
            }
            check(try tree(root) == before && tree(previous) == prior, "\(fault) rejection preserves all live and previous bytes")
            transaction.discard()
        }
        let unreadable = try seed("unreadable", state: "corrupt"), blocked = unreadable.appendingPathComponent("today.json")
        let failedBytes = try Data(contentsOf: blocked)
        guard chmod(blocked.path, 0) == 0 else { throw HealthLocalFiles.Failure.invalid }
        let unreadableBoundary = try HealthDailyCache.capture(in: unreadable)
        check(unreadableBoundary.state == .unavailable, "actual EACCES is unavailable, not an absent cache")
        let unreadableTransaction = try HealthDailyCache.prepare(.clear(day: day), replacing: unreadableBoundary, in: unreadable, owner: owner)
        try unreadableTransaction.commit()
        let privateBase = unreadable.appendingPathComponent(HealthRecoveryCopies.name)
        let privateEntries = fm.enumerator(at: privateBase, includingPropertiesForKeys: nil)!
        var preservedFailure = false
        for case let file as URL in privateEntries where file.lastPathComponent == "today.json" {
            let facts = try fm.attributesOfItem(atPath: file.path)
            check((facts[.posixPermissions] as? NSNumber)?.intValue == 0, "unreadable raw copy retains its original permissions")
            guard chmod(file.path, 0o600) == 0 else { throw HealthLocalFiles.Failure.invalid }
            preservedFailure = try Data(contentsOf: file) == failedBytes
        }
        check(preservedFailure, "actual unreadable original bytes survive clear in the private copy")
        let linked = try seed("symlink", state: "missing"), target = outer.appendingPathComponent("personal-target")
        let targetBytes = Data("do not read or replace".utf8); try targetBytes.write(to: target)
        try fm.createSymbolicLink(at: linked.appendingPathComponent("today.json"), withDestinationURL: target)
        rejects("symlink cache rejects without choosing its target") { _ = try HealthDailyCache.capture(in: linked) }
        check(try Data(contentsOf: target) == targetBytes, "symlink target remains exact")
        let repeated = try seed("repeated-clear", state: "healthy")
        try fm.copyItem(at: repeated, to: repeated.appendingPathExtension("previous"))
        var incidentCounts: [Int] = []
        for _ in 0..<3 {
            let observed = try HealthDailyCache.capture(in: repeated)
            let prepared = try HealthDailyCache.prepare(.clear(day: day), replacing: observed, in: repeated, owner: owner)
            try prepared.commit()
            incidentCounts.append(try fm.contentsOfDirectory(at: repeated.appendingPathComponent(HealthRecoveryCopies.name), includingPropertiesForKeys: nil).count)
        }
        check(incidentCounts == [1, 1, 1], "repeated identical clears reuse actual retained cache bytes rather than growing duplicate private copies")
        let unrelated = try seed("unrelated-prior-copy", state: "healthy")
        try fm.copyItem(at: unrelated, to: unrelated.appendingPathExtension("previous"))
        try Data("{broken water".utf8).write(to: unrelated.appendingPathComponent("water.json"), options: .atomic)
        _ = try HealthRecoveryCopies.discover(in: unrelated)
        var unrelatedCounts: [Int] = []
        for _ in 0..<2 {
            let observed = try HealthDailyCache.capture(in: unrelated)
            let prepared = try HealthDailyCache.prepare(.clear(day: day), replacing: observed, in: unrelated, owner: owner)
            try prepared.commit()
            unrelatedCounts.append(try fm.contentsOfDirectory(at: unrelated.appendingPathComponent(HealthRecoveryCopies.name), includingPropertiesForKeys: nil).count)
        }
        check(unrelatedCounts == [2, 2], "cache replacement preserves known prior incidents without duplicating unrelated failed-domain copies")
        for scenario in ["matching", "changed-payload", "changed-intent", "missing-payload", "matching-directory", "changed-directory"] {
            let root = try seed("subset-" + scenario, state: "healthy")
            let prior = root.appendingPathExtension("previous")
            try fm.copyItem(at: root, to: prior)
            if scenario.contains("directory") {
                try fm.removeItem(at: prior.appendingPathComponent("water.json"))
                try fm.createDirectory(at: prior.appendingPathComponent("water.json/nested"), withIntermediateDirectories: true)
                try Data("prior nested raw bytes".utf8).write(to: prior.appendingPathComponent("water.json/nested/raw.bin"))
            }
            try Data("{broken water".utf8).write(to: root.appendingPathComponent("water.json"), options: .atomic)
            try Data("{broken today".utf8).write(to: root.appendingPathComponent("today.json"), options: .atomic)
            let initial = try HealthRecoveryCopies.discover(in: root)
            check(initial.count == 1, "\(scenario): initial discovery retains compound prior water and today")
            if scenario == "changed-payload" {
                try Data("[ ]".utf8).write(to: prior.appendingPathComponent("water.json"), options: .atomic)
            } else if scenario == "changed-intent" {
                var changed = journal
                try changed.append(domain: .water, localID: "new-provenance", components: [.init(metric: .water, value: 137, date: day)])
                try changed.encoded().write(to: prior.appendingPathComponent(HealthWriteFiles.name), options: .atomic)
            } else if scenario == "missing-payload" {
                try fm.removeItem(at: root.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(initial[0].id).appendingPathComponent("water.json"))
            } else if scenario == "changed-directory" {
                try Data("changed nested raw bytes".utf8).write(to: prior.appendingPathComponent("water.json/nested/raw.bin"), options: .atomic)
            }
            let privateBefore = try tree(root.appendingPathComponent(HealthRecoveryCopies.name))
            let priorBefore = try tree(prior)
            let observed = try HealthDailyCache.capture(in: root)
            try HealthDailyCache.prepare(.clear(day: day), replacing: observed, in: root, owner: owner).commit()
            let copies = try HealthRecoveryCopies.discover(in: root)
            let expected = scenario.hasPrefix("matching") ? 2 : 3
            check(copies.count == expected, "\(scenario): subset discovery reuses only an intact byte-and-intent covering copy")
            let privateAfter = try tree(root.appendingPathComponent(HealthRecoveryCopies.name))
            check(privateBefore.allSatisfy { privateAfter[$0.key] == $0.value }, "\(scenario): every existing private file remains exact")
            check(try tree(prior) == priorBefore && Data(contentsOf: root.appendingPathComponent(HealthWriteFiles.name)) == journalBytes,
                  "\(scenario): complete previous tree and current pending Health intent stay exact")
            let again = try HealthRecoveryCopies.discover(in: root)
            check(again.count == expected, "\(scenario): repeated discovery adds no redundant subset copy")
        }
        let healthy = try seed("ordinary-guard", state: "healthy")
        rejects("generic unavailable-domain route still rejects healthy cache") {
            _ = try BackupFileTransaction.prepare(["today.json": BackupArchive.encoder().encode(cleared)], photoFiles: [:], into: healthy, recoveringHealthDomains: [.today])
        }
        if let output {
            let report: [String: Any] = ["status": "passed", "count": checks.count, "checks": checks,
                "scope": "Actual production cache raw builder and real-file preparation/atomic exchange, source changes, cancellation, exact current/previous preservation and unchanged pending Health semantics. No UI/query cancellation/HealthKit/device/full cache acceptance."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
        print("Health daily cache: \(checks.count) checks passed")
    }
}
