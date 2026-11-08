#if DEBUG && targetEnvironment(simulator)
import Foundation
import UIKit
import CryptoKit
import Darwin

/// Dedicated synthetic native integration. The host must read the actual
/// rejected files before this probe is allowed to recover any of them.
@MainActor enum HealthLocalDataNativeProbe {
    struct SemanticFixture: Codable { let label: String; let domain: String; let afterOpen: Bool; let bytes: Data }
    struct Check: Codable { let name: String; let passed: Bool }
    struct Checkpoint: Codable {
        let nonce: UUID; let domain: String; let afterOpen: Bool; let inputCase: String?; let checks: [Check]
        let files: [String: Data]; let missing: [String]; let directory: String?
        let liveWaterIDs: [String]; let liveMealIDs: [String]; let liveWorkoutIDs: [String]
        let liveWeight: Double?; let issue: String?; let trace: [String]
    }
    struct Report: Codable {
        let status: String; let checkpoint: Checkpoint?; let checks: [Check]
        let persistedFiles: [String: Data]; let trace: [String]; let external: [String: Double]
        let liveWaterIDs: [String]; let liveMealIDs: [String]; let liveWorkoutIDs: [String]
        let liveWeight: Double?; let issue: String?; let scope: String
    }
    enum Failure: Error { case check(String), hostTimeout }
    static func run(_ requested: String) async -> String {
        var checks: [Check] = [], checkpoint: Checkpoint?
        var status = "Saved-data checks failed: not started"
        var health: HealthStore?
        let args = ProcessInfo.processInfo.arguments
        let fixture: SemanticFixture?
        if requested == "semantic-fixture" {
            do {
                let file = try LocalStore.checkedDirectory().deletingLastPathComponent().appendingPathComponent("Lumen-local-semantic-fixture.json")
                fixture = try JSONDecoder().decode(SemanticFixture.self, from: Data(contentsOf: file))
            } catch { return "Saved-data checks failed: semantic fixture couldn't be opened" }
        } else { fixture = nil }
        let previousTrial = requested == "previous-copy"
        let requestedDomain = previousTrial ? "water" : fixture?.domain ?? requested
        let afterOpen = fixture?.afterOpen ?? args.contains("-health-local-after-open")
        let isDirectory = requestedDomain == "unreadable-water"
        let domain = HealthLocalFiles.Domain(rawValue: isDirectory ? "water" : requestedDomain)!
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func check(_ value: Bool, _ name: String) throws {
            checks.append(.init(name: name, passed: value)); if !value { throw Failure.check(name) }
        }
        func rejects(_ label: String, _ operation: () async throws -> Void) async throws {
            var failed = false
            do { try await operation() } catch { failed = true }
            try check(failed, label)
        }
        func files(_ root: URL) throws -> [String: Data] {
            var saved: [String: Data] = [:]
            for name in HealthLocalFiles.Domain.allCases.map({ $0.rawValue + ".json" }) + [HealthWriteFiles.name, "profile.json"] {
                let url = root.appendingPathComponent(name)
                if (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular {
                    saved[name] = try Data(contentsOf: url)
                }
            }
            let copies = root.appendingPathComponent(HealthRecoveryCopies.name)
            if FileManager.default.fileExists(atPath: copies.path) {
                guard let entries = FileManager.default.enumerator(at: copies, includingPropertiesForKeys: nil) else { throw Failure.check("private copies enumeration") }
                for case let file as URL in entries {
                    let facts = try FileManager.default.attributesOfItem(atPath: file.path)
                    guard let kind = facts[.type] as? FileAttributeType, kind == .typeDirectory || kind == .typeRegular else { throw Failure.check("unsafe private-copy path") }
                    if kind == .typeRegular { saved[String(file.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: file) }
                }
            }
            return saved
        }
        do {
            let shared = HealthStore.shared
            for _ in 0..<300 where !shared.conversationReady { try await Task.sleep(for: .milliseconds(25)) }
            try check(shared.conversationReady, "shared startup completes before synthetic domain setup")
            let root = try LocalStore.checkedDirectory(), file = root.appendingPathComponent(domain.rawValue + ".json")
            let now = Date()
            let water = [HydrationLog(id: "synthetic-retained-water", date: now, ml: 100)]
            let meal = Meal(id: "synthetic-retained-meal", type: .lunch, items: [FoodItem(name: "Synthetic", grams: 100, calories: 100, proteinG: 10, carbsG: 20, fatG: 3, fiberG: 2)])
            let workout = Workout(id: "synthetic-retained-workout", kind: .walk, title: "Synthetic", start: now, duration: 600, activeCalories: 20, source: .manual)
            var goals = HealthGoals(); goals.weightKg = 70
            let originals = ["water.json": try encoder.encode(water), "meals.json": try encoder.encode([meal]),
                             "workouts.json": try encoder.encode([workout]), "goals.json": try encoder.encode(goals), "today.json": try encoder.encode(DayMetrics.empty)]
            for (name, data) in originals { try data.write(to: root.appendingPathComponent(name), options: .atomic) }
            if domain == .meals { UserDefaults.standard.set(try JSONEncoder().encode([Meal(id: "synthetic-stale-legacy", type: .lunch, items: [])]), forKey: domain.legacyKey!) }
            if domain == .goals { var old = HealthGoals(); old.weightKg = 61.25; UserDefaults.standard.set(try JSONEncoder().encode(old), forKey: domain.legacyKey!) }
            if afterOpen { health = HealthStore() }
            if isDirectory {
                try FileManager.default.removeItem(at: file)
                try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            } else { try (fixture?.bytes ?? Data("{\"syntheticDamagedHistory\": [".utf8)).write(to: file, options: .atomic) }
            if health == nil { health = HealthStore() }
            let store = health!
            for _ in 0..<300 where !store.conversationReady { try await Task.sleep(for: .milliseconds(25)) }
            try check(store.conversationReady, "actual test store completes checked conversation startup")
            if previousTrial {
                let previous = root.appendingPathExtension("previous")
                try FileManager.default.copyItem(at: root, to: previous)
                try originals["water.json"]!.write(to: previous.appendingPathComponent("water.json"), options: .atomic)
                try await ProfileSettingsCommit.birthYear(1990, sleep: .shared, health: store)
                let base = root.appendingPathComponent(HealthRecoveryCopies.name)
                let copies = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix("pending-") }
                try check(copies.count == 1 && (try? Data(contentsOf: copies[0].appendingPathComponent("water.json"))) == originals["water.json"],
                          "actual native paired profile/goals change preserves the exact good prior water privately")
                try check((try? Data(contentsOf: file)) == Data("{\"syntheticDamagedHistory\": [".utf8) && !store.localHealthAvailable(.water),
                          "unrelated native paired commit leaves damaged water unchanged and unavailable")
                try await ProfileSettingsCommit.birthYear(1991, sleep: .shared, health: store)
                try check((try? Data(contentsOf: copies[0].appendingPathComponent("water.json"))) == originals["water.json"] && SleepStore.shared.profile.birthYear == 1991,
                          "later native paired change retains the original private copy and publishes the valid profile")
                try check(!FileManager.default.fileExists(atPath: copies[0].appendingPathComponent(HealthWriteFiles.name).path),
                          "private provenance cannot become a live native Health operation journal")
                let recoveryPreviews = try HealthRecoveryCopies.previews(in: root)
                try check(recoveryPreviews.count == 1 && recoveryPreviews[0].complete,
                          "actual native retained incident is a complete checked recovery preview")
                let recoveredWater = recoveryPreviews[0].domains.first { $0.domain == .water }
                try check(recoveredWater?.state == .readable && recoveredWater?.recordCount == 1 && recoveredWater?.digest != nil,
                          "actual native preview reads one retained water record with exact-source fingerprint")
                try check(recoveryPreviews[0].hasIntentProvenance && recoveryPreviews[0].domains.allSatisfy { $0.domain == .water || $0.state == .notIncluded },
                          "actual native preview keeps private intent separate from selected history")
                try HealthRecoveryCopies.verify(recoveryPreviews[0], in: root)
                try check((try? Data(contentsOf: file)) == Data("{\"syntheticDamagedHistory\": [".utf8) && !store.localHealthAvailable(.water),
                          "actual native preview leaves the damaged live domain unavailable and unchanged")
            }
            let before = try files(root), waterIDs = store.waterLogs.map(\.id), mealIDs = store.meals.map(\.id), workoutIDs = store.workouts.map(\.id), weight = store.goals.weightKg
            let freshMeal = Meal(id: "synthetic-new-recovered-meal", type: .lunch, items: [FoodItem(name: "Synthetic new", grams: 100, calories: 213, proteinG: 11, carbsG: 23, fatG: 9, fiberG: 4)])
            func mutate() async throws {
                switch domain {
                case .water: try store.addWater(ml: 137)
                case .meals: try store.addMeal(freshMeal)
                case .workouts: try store.addManualWorkout(kind: .walk, minutes: 12, kcal: 50)
                case .goals, .today: try await store.logWeight(kg: 76.25)
                }
            }
            try await rejects("actual affected-domain mutation rejects damaged or unreadable source", mutate)
            try check(store.localHealthStorageIssue != nil && !store.localHealthAvailable(domain), "native model exposes unavailable domain and saved-data issue")
            if !afterOpen && domain == .meals { try check(!store.meals.contains { $0.id == "synthetic-stale-legacy" }, "damaged current meals never resurrect stale legacy meal") }
            if !afterOpen && domain == .goals { try check(store.goals.weightKg != 61.25, "damaged current goals never resurrect stale legacy weight") }
            switch domain {
            case .water:
                try await rejects("Undo cannot turn unreadable history into an empty rewrite") { try store.undoLastWater() }
                try await rejects("local-only correction cannot overwrite unreadable water") { try store.correctConfirmedWater("synthetic-retained-water", draft: nil) }
                try check(store.metrics.reading("water").value == nil, "unavailable water history is unknown, not a recorded zero")
            case .meals:
                let photos = root.appendingPathComponent("photos")
                let oldPhotos = (try? FileManager.default.contentsOfDirectory(atPath: photos.path)) ?? []
                let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
                try await rejects("meal rejection precedes owned photo creation") { try store.addMeal(freshMeal, photo: image) }
                try check(((try? FileManager.default.contentsOfDirectory(atPath: photos.path)) ?? []) == oldPhotos, "failed meal adds no orphaned photo")
                try await rejects("meal deletion rejects unavailable history") { try store.deleteMeal(meal.id) }
                try check(store.metrics.reading("calories").value == nil, "unavailable meal history is unknown, not a recorded zero")
            case .workouts:
                try await rejects("workout deletion rejects unavailable history") { try store.deleteWorkout(workout.id) }
                try await rejects("import merge rejects unavailable workout history") { try store.importWorkouts([workout], filename: "synthetic.xml") }
                try await rejects("import removal rejects unavailable workout history") { try store.clearImportedWorkouts() }
                try await rejects("local-only workout correction rejects unavailable history") { try store.correctConfirmedWorkout(workout.id, draft: nil) }
                try check(store.metrics.reading("exercise").value == nil, "unavailable workout history does not claim a complete exercise total")
            case .goals:
                try await rejects("goal settings reject unavailable source") { try store.updateGoalsChecked { $0.stepGoal = 9000 } }
                try await rejects("profile/goals paired change rejects unavailable goals") { try await ProfileSettingsCommit.birthYear(1990, sleep: .shared, health: store) }
            case .today: break
            }
            try await rejects("backup cannot export an unavailable domain as empty history") { _ = try BackupService.snapshot(sleep: .shared, health: store) }
            let reply = await ChatCoachService.shared.replyOutcome(to: "What should I plan today?", health: store, sleepDebt: 0)
            try check(reply.source == "Lumen notice" && !reply.canBecomePlan && reply.text.contains("couldn't be opened"), "assistant declines history/target-based planning before model or provider work")
            try check(store.plan == nil && store.readiness == nil, "failed source cannot produce default-goal coaching")
            try check(try files(root) == before && store.waterLogs.map(\.id) == waterIDs && store.meals.map(\.id) == mealIDs && store.workouts.map(\.id) == workoutIDs && store.goals.weightKg == weight,
                      "all rejected actions preserve exact domain/journal/profile files and original live values")
            try check(HealthWriteNativeProbe.verificationTrace.isEmpty && HealthWriteNativeProbe.verificationExternal.isEmpty,
                      "rejected actions dispatch no new external Health operation")
            let allNames = HealthLocalFiles.Domain.allCases.map { $0.rawValue + ".json" } + [HealthWriteFiles.name, "profile.json"]
            checkpoint = Checkpoint(nonce: UUID(), domain: requestedDomain, afterOpen: afterOpen, inputCase: fixture?.label, checks: checks, files: before,
                                    missing: allNames.filter { before[$0] == nil && !(isDirectory && $0 == "water.json") }, directory: isDirectory ? "water.json" : nil,
                                    liveWaterIDs: waterIDs, liveMealIDs: mealIDs, liveWorkoutIDs: workoutIDs, liveWeight: weight,
                                    issue: store.localHealthStorageIssue, trace: HealthWriteNativeProbe.verificationTrace)
            let base = root.deletingLastPathComponent()
            try encoder.encode(checkpoint!).write(to: base.appendingPathComponent("Lumen-local-data-checkpoint.json"), options: .atomic)
            let approval = base.appendingPathComponent("Lumen-local-data-readback.json")
            var approved = false
            for _ in 0..<3000 {
                if let data = try? Data(contentsOf: approval), let nonce = try? JSONDecoder().decode(UUID.self, from: data), nonce == checkpoint!.nonce { approved = true; break }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard approved else { throw Failure.hostTimeout }
            try check(true, "independent host matched all rejected current files before recovery was allowed")
            // An unaffected valid domain remains usable while the failed one is paused.
            if domain == .water { try store.addMeal(freshMeal) } else { try store.addWater(ml: 137) }
            await store.waitForHealthWriteVerification()
            try check(!HealthWriteNativeProbe.verificationExternal.isEmpty && !store.localHealthAvailable(domain), "unrelated healthy domain commits while damaged source remains paused")
            if previousTrial {
                let observed = try HealthRecoveryCopies.previews(in: root).first!
                let selected = try await Task.detached {
                    try HealthRecoverySelection.retained(observed, in: root, domains: [.water], validPhoto: { _ in false })
                }.value
                let externalBeforeRecovery = HealthWriteNativeProbe.verificationExternal
                if args.contains("-health-recovery-task-cancel-probe") {
                    let originalFiles = try files(root)
                    let arrived = DispatchSemaphore(value: 0), released = DispatchSemaphore(value: 0)
                    let cancellation = BackupOperationControl { progress in
                        if case .restoring = progress.stage, progress.completed == 0 {
                            arrived.signal(); released.wait()
                        }
                    }
                    cancellation.setCancellationHandler { released.signal() }
                    let pending = Task { @MainActor in
                        try await store.recoverUnavailableHealth(selected, control: cancellation)
                    }
                    let reached = await Task.detached { arrived.wait(timeout: .now() + 5) == .success }.value
                    if !reached {
                        pending.cancel(); cancellation.cancel(); released.signal()
                        _ = try? await pending.value
                    }
                    try check(reached, "caller-task cancellation reaches actual detached transaction preparation")
                    pending.cancel()
                    var forwarded = false
                    do { try cancellation.checkCancellation() } catch is CancellationError { forwarded = true }
                    released.signal() // Safety release; cancellation itself must have reached the token already.
                    var cancelled = false
                    do { try await pending.value } catch is CancellationError { cancelled = true }
                    try check(forwarded, "cancelling only the caller Task cancels the actual shared worker control")
                    try check(cancelled, "cancelled native recovery returns CancellationError before installation")
                    try check(try files(root) == originalFiles, "caller-task cancellation preserves exact current/private bytes and pending intent")
                    let stages = try FileManager.default.contentsOfDirectory(at: root.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                    try check(!stages.contains { $0.lastPathComponent.hasPrefix(root.lastPathComponent + ".restore-") }, "cancelled native preparation removes its abandoned stage")
                    try check(!store.localHealthAvailable(.water) && HealthWriteNativeProbe.verificationExternal == externalBeforeRecovery,
                              "cancelled native recovery leaves water paused and dispatches no new external work")
                    let committedControl = BackupOperationControl()
                    var committedTask: Task<Void, Error>?
                    var committedCallback = false
                    committedTask = Task { @MainActor in
                        try await LocalStore.recoverHealthChecked(selected, control: committedControl,
                            canCommit: { !store.localHealthAvailable(.water) }, didCommit: {
                                committedCallback = true
                                committedTask?.cancel()
                            })
                    }
                    try await committedTask!.value
                    try check(committedCallback && committedTask!.isCancelled,
                              "caller Task cancelled inside actual didCommit still returns its saved outcome")
                    var committedCancellation = false
                    do { try committedControl.checkCancellation() } catch is CancellationError { committedCancellation = true }
                    try check(committedCancellation && (try? Data(contentsOf: file)) == originals["water.json"],
                              "post-commit Task cancellation reaches its control without undoing exact installed data")
                    committedTask = nil
                    try store.retryLocalHealthDataChecked()
                } else {
                    try await store.recoverUnavailableHealth(selected)
                }
                await store.waitForHealthWriteVerification()
                try check(store.localHealthAvailable(.water) && (try? Data(contentsOf: file)) == originals["water.json"],
                          "actual native explicit replacement installs the exact reviewed water and its live boundary")
                let recoveryCopies = try HealthRecoveryCopies.previews(in: root)
                try check(recoveryCopies.contains { $0.domains.contains { $0.domain == .water && $0.state == .unavailable } },
                          "actual native explicit replacement keeps the damaged original privately")
                try check(HealthWriteNativeProbe.verificationExternal == externalBeforeRecovery,
                          "native recovery imports no old Health work and dispatches no recovered record")
            } else {
                if isDirectory { try FileManager.default.removeItem(at: file) }
                try originals[domain.rawValue + ".json"]!.write(to: file, options: .atomic)
                try await rejects("healthy replacement file alone cannot bless the old unavailable live model", mutate)
            }
            try store.retryLocalHealthDataChecked()
            try check(store.localHealthStorageIssue == nil && store.localHealthAvailable(domain), "explicit checked retry installs recovered data and clears its issue")
            try check(store.waterLogs.contains { $0.id == water[0].id } && store.meals.contains { $0.id == meal.id } && store.workouts.contains { $0.id == workout.id } && store.goals.weightKg == 70,
                      "checked retry retains original healthy histories and original target weight")
            try await mutate(); await store.waitForHealthWriteVerification()
            try check(try LocalStore.healthWriteJournalChecked().pendingEvents.isEmpty, "new mutation after checked recovery completes its durable external work")
            try store.requireAllLocalHealthData()
            try check(true, "all domain source boundaries match after healthy recovery and mutation")
            // A healthy old source is not permission to commit an invalid new
            // payload. Exercise the actual native writer, including goal values
            // that would otherwise be unsafe to convert for display.
            let validFiles = try files(root), trace = HealthWriteNativeProbe.verificationTrace
            switch domain {
            case .water:
                try await rejects("native writer rejects new negative water before commit") {
                    try LocalStore.saveChecked([HydrationLog(id: "synthetic-invalid-new-water", ml: -1)], as: "water", healthBoundary: store.requireLocalHealthBoundary(.water))
                }
            case .meals:
                var invalid = freshMeal; invalid.id = "synthetic-invalid-new-meal"; invalid.items[0].confidence = 2
                try await rejects("native meal writer rejects new invalid confidence before commit") { try store.addMeal(invalid) }
            case .workouts:
                var invalid = workout; invalid.duration = -1
                try await rejects("native writer rejects new invalid workout before commit") {
                    try LocalStore.saveChecked([invalid], as: "workouts", healthBoundary: store.requireLocalHealthBoundary(.workouts))
                }
            case .goals:
                try await rejects("native goal writer rejects unsafe new numeric value before live installation") { try store.updateGoalsChecked { $0.stepGoal = 1e300 } }
            case .today:
                var invalid = DayMetrics.empty; invalid.steps = -1
                try await rejects("native writer rejects new invalid cache before commit") {
                    try LocalStore.saveChecked(invalid, as: "today", healthBoundary: store.requireLocalHealthBoundary(.today))
                }
            }
            try check(try files(root) == validFiles && HealthWriteNativeProbe.verificationTrace == trace,
                      "invalid new payload retains all healthy files and queues no new external work")
            status = "Saved-data checks passed"
        } catch { status = "Saved-data checks failed: \(error)" }
        let finalFiles = (try? files(LocalStore.checkedDirectory())) ?? [:]
        let report = Report(status: status, checkpoint: checkpoint, checks: checks, persistedFiles: finalFiles,
                            trace: HealthWriteNativeProbe.verificationTrace, external: HealthWriteNativeProbe.verificationExternal,
                            liveWaterIDs: health?.waterLogs.map(\.id) ?? [], liveMealIDs: health?.meals.map(\.id) ?? [], liveWorkoutIDs: health?.workouts.map(\.id) ?? [],
                            liveWeight: health?.goals.weightKg, issue: health?.localHealthStorageIssue,
                            scope: "Actual signed-simulator HealthStore/LocalStore rejection and checked reload with real damaged/non-regular files, host readback barrier, controlled external adapter. Not HealthKit, UI/critic, locked-device or complete Batch43 acceptance.")
        do { try encoder.encode(report).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-local-data-repair-report.json"), options: .atomic) }
        catch { return "Saved-data checks failed: report write" }
        return status
    }
}
/// Observation-only wrapper probe. This does not authorize a UI recovery and
/// never treats an observed unsafe baseline as product acceptance.
@MainActor enum HealthLegacyRootAcquisitionNativeProbe {
    enum Mode: String { case noPrior = "legacy-root-missing-no-prior", withPrior = "legacy-root-missing-with-prior", ordinary = "ordinary-root-missing-pending-removal-control" }
    enum Failure: Error { case invalid(String), timeout }
    private static var observedRoot: URL?
    private static var notes: [[String: Any]] = []
    static func observe(_ phase: String) {
        guard let root = observedRoot else { return }
        do { notes.append(["phase": phase, "root": try tree(root), "previous": try tree(root.appendingPathExtension("previous"))]) }
        catch { notes.append(["phase": phase, "observationError": String(describing: error)]) }
    }
    private static func facts(_ url: URL) throws -> [String: Any] {
        var st = stat()
        if lstat(url.path, &st) != 0 {
            if errno == ENOENT { return ["exists": false] }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return ["exists": true, "device": Int64(st.st_dev), "inode": UInt64(st.st_ino), "mode": UInt32(st.st_mode), "size": st.st_size,
                "mtimeSeconds": st.st_mtimespec.tv_sec, "mtimeNanos": st.st_mtimespec.tv_nsec]
    }
    private static func tree(_ root: URL) throws -> [String: Any] {
        let rootFacts = try facts(root)
        guard rootFacts["exists"] as? Bool == true else { return ["root": rootFacts, "entries": [:]] }
        var entries: [String: Any] = [:], total = 0
        func visit(_ directory: URL, prefix: String) throws {
            for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = prefix + child.lastPathComponent
                var row = try facts(child)
                let mode = (row["mode"] as! UInt32) & UInt32(S_IFMT)
                guard mode == UInt32(S_IFREG) || mode == UInt32(S_IFDIR) else { throw Failure.invalid("nonregular synthetic tree") }
                if mode == UInt32(S_IFREG) {
                    guard (row["size"] as! Int64) <= 262144 else { throw Failure.invalid("file bound") }
                    let data = try Data(contentsOf: child); total += data.count
                    guard total <= 2097152 else { throw Failure.invalid("tree bound") }
                    row["base64"] = data.base64EncodedString(); row["bytes"] = data.count
                    row["sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                }
                entries[name] = row
                if mode == UInt32(S_IFDIR) { try visit(child, prefix: name + "/") }
            }
        }
        try visit(root, prefix: "")
        return ["root": rootFacts, "entries": entries]
    }
    private static func fixedValues() throws -> [String: Any] {
        guard let bundle = Bundle.main.bundleIdentifier else { throw Failure.invalid("bundle") }
        var result: [String: Any] = [:]
        for key in ["lumen.health.meals.v1", "lumen.health.workouts.v1"] {
            guard let persisted = UserDefaults.standard.persistentDomain(forName: bundle)?[key] as? Data,
                  let effective = UserDefaults.standard.object(forKey: key) as? Data, persisted == effective,
                  persisted == Data("{synthetic persisted legacy origin damaged".utf8) else { throw Failure.invalid("actual fixed Data") }
            result[key] = ["type": "data", "base64": persisted.base64EncodedString(), "bytes": persisted.count,
                           "sha256": SHA256.hash(data: persisted).map { String(format: "%02x", $0) }.joined()]
        }
        return result
    }
    static func run(_ requested: String) async -> String {
        let fm = FileManager.default
        guard HealthWriteNativeProbe.requested, let mode = Mode(rawValue: requested),
              ProcessInfo.processInfo.arguments.contains("-health-backup-empty-ui"),
              ProcessInfo.processInfo.arguments.contains("-health-legacy-origin-ui") else { return "Legacy root probe failed: flags" }
        let reportURL = fm.temporaryDirectory.appendingPathComponent("Lumen-legacy-root-probe-report.json")
        let ackURL = fm.temporaryDirectory.appendingPathComponent("Lumen-legacy-root-probe-ack.json")
        let runID = UUID().uuidString
        var report: [String: Any] = ["runID": runID, "mode": mode.rawValue, "scope": "Actual LocalStore API boundary only. Constant canCommit; no UI authority, HealthStore permission or external-delivery acceptance."]
        func emit(_ phase: String) throws {
            report["phase"] = phase; report["notes"] = notes
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
        }
        func waitAck(_ phase: String) async throws {
            for _ in 0..<1200 {
                if let data = try? Data(contentsOf: ackURL), let ack = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   ack["runID"] == runID, ack["phase"] == phase { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw Failure.timeout
        }
        do {
            let shared = HealthStore.shared
            for _ in 0..<1200 where !shared.conversationReady || shared.isSyncing { try await Task.sleep(for: .milliseconds(25)) }
            guard shared.conversationReady, !shared.isSyncing else { throw Failure.invalid("startup") }
            let root = try LocalStore.checkedDirectory(), previous = root.appendingPathExtension("previous")
            let moved = root.deletingLastPathComponent().appendingPathComponent("LumenData.legacy-root-probe-" + runID)
            let movedPrevious = root.deletingLastPathComponent().appendingPathComponent("LumenData.legacy-prior-probe-" + runID)
            guard (try facts(previous))["exists"] as? Bool == true else { throw Failure.invalid("prior fixture absent") }
            let owner = try HealthWriteDeviceOwner.current()
            var journal = HealthWriteJournal(owner: owner)
            if mode == .ordinary { try journal.requestDeletion(domain: .water, localID: "synthetic-legacy-root-removal") }
            let journalData = try journal.encoded()
            for directory in [root, previous] {
                try journalData.write(to: directory.appendingPathComponent(HealthWriteFiles.name), options: .atomic)
                if mode == .ordinary { try Data("{synthetic regular workout damage".utf8).write(to: directory.appendingPathComponent("workouts.json"), options: .atomic) }
            }
            let control = BackupOperationControl(), lease = HealthRecoveryOriginReviewLease()
            defer { lease.close(); observedRoot = nil }
            let snapshot = BackupSnapshot(profile: .default, goals: HealthGoals(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
            var payload = try HealthRecoverySelection.backup(snapshot, photos: [:], domains: [.workouts], control: control, validPhoto: { _ in false })
            if mode != .ordinary {
                try lease.begin(control)
                try await Task.detached {
                    let captured = try LocalStore.captureLegacyRecoveryReview([.workouts], control: control)
                    try lease.finish(captured, control: control)
                }.value
                guard lease.state == .ready, lease.metadata?.legacyDomains == [.workouts] else { throw Failure.invalid("ready origin") }
                payload = try HealthRecoverySelection.bindingLegacyOrigins(lease.acquire([.workouts], control: control), to: payload)
            }
            report["paths"] = ["root": root.path, "previous": previous.path, "moved": moved.path, "movedPrevious": movedPrevious.path]
            report["initialRoot"] = try tree(root); report["initialPrevious"] = try tree(previous)
            report["initialFixed"] = try fixedValues(); report["journalBeforeBase64"] = journalData.base64EncodedString()
            report["traceBefore"] = HealthWriteNativeProbe.verificationTrace
            report["externalBefore"] = HealthWriteNativeProbe.verificationExternal
            report["leaseReady"] = lease.state == .ready
            try emit("prepared"); try await waitAck("prepared")
            try fm.moveItem(at: root, to: moved)
            if mode == .noPrior { try fm.moveItem(at: previous, to: movedPrevious) }
            // No actor yield between relocation and actual wrapper entry. The
            // notes surround its existing production acquisition unchanged.
            observedRoot = root; notes = []
            var didCommit = false, rejected = false, actualError: String?
            do { try await LocalStore.recoverHealthChecked(payload, control: control, canCommit: { true }, didCommit: { didCommit = true }) }
            catch { rejected = true; actualError = String(describing: error) }
            observedRoot = nil
            // Allow the actual commit retirement worker to finish before the
            // observed host boundary; do not erase or conceal any residue.
            for _ in 0..<200 {
                let siblings = try fm.contentsOfDirectory(atPath: root.deletingLastPathComponent().path)
                if !siblings.contains(where: { $0.hasPrefix("LumenData.restore-") || $0.hasPrefix("LumenData.retired-") || $0.hasPrefix("LumenData.discovery-") }) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            report["didCommit"] = didCommit; report["rejected"] = rejected; report["error"] = actualError ?? NSNull()
            report["finalRoot"] = try tree(root); report["finalPrevious"] = try tree(previous)
            report["movedRoot"] = try tree(moved); report["movedPrevious"] = try tree(movedPrevious)
            report["finalFixed"] = try fixedValues()
            report["traceAfter"] = HealthWriteNativeProbe.verificationTrace
            report["externalAfter"] = HealthWriteNativeProbe.verificationExternal
            report["siblingNamesAfter"] = try fm.contentsOfDirectory(atPath: root.deletingLastPathComponent().path).sorted()
            try emit("observed"); try await waitAck("observed")
            try emit("host-audited")
            return "Legacy root probe observed: " + mode.rawValue
        } catch {
            report["probeError"] = String(describing: error); try? emit("failed")
            return "Legacy root probe failed: " + String(describing: error)
        }
    }
}
#endif
