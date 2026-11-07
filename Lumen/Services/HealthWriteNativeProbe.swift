#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI

/// Dedicated synthetic simulator integration. Real HealthStore mutations,
/// LocalStore transactions and receipt writes use a controlled external adapter.
/// No real HealthKit, live account or personal history is used by this probe.
@MainActor final class HealthWriteNativeProbe: ObservableObject {
    static let shared = HealthWriteNativeProbe()
    static var requested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetForUITests") && args.contains("-health-write-native-probe")
    }
    @Published private(set) var status = "Checking synthetic Health recovery…"
    private var started = false
    private var denied: HealthWriteJournal.Metric?
    private var holdWater = false
    private var entered = false
    private var release: CheckedContinuation<Void, Never>?
    private var external: [String: Double] = [:]
    private var trace: [String] = []
    static var verificationTrace: [String] { shared.trace }
    static var verificationExternal: [String: Double] { shared.external }
    private struct Failure: Error { let message: String }
    private struct Check: Codable { let name: String; let passed: Bool }

    static func operate(_ claim: HealthWriteJournal.Claim) async throws {
        precondition(requested)
        let fixture = shared
        fixture.trace.append(claim.action.rawValue + ":" + claim.component.metric.rawValue)
        if fixture.holdWater && claim.component.metric == .water && claim.action == .save {
            fixture.entered = true
            await withCheckedContinuation { fixture.release = $0 }
        }
        if fixture.denied == claim.component.metric { throw HealthWriteOperationFailure(issue: .permission) }
        if claim.action == .save { fixture.external[claim.syncIdentifier] = claim.component.value }
        else { fixture.external[claim.syncIdentifier] = nil }
    }

    func run() async {
        guard Self.requested, !started else { return }; started = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-health-photo-binding-checks") {
            status = await BackupPhotoBindingUIFixture.runChecks(); return
        }
        if let index = args.firstIndex(of: "-health-legacy-root-probe"), args.indices.contains(index + 1) {
            status = await HealthLegacyRootAcquisitionNativeProbe.run(args[index + 1]); return
        }
        if let index = args.firstIndex(of: "-health-local-repair"), args.indices.contains(index + 1) {
            status = await HealthLocalDataNativeProbe.run(args[index + 1]); return
        }
        if let index = args.firstIndex(of: "-health-local-baseline"), args.indices.contains(index + 1) {
            await localDataBaseline(args[index + 1]); return
        }
        let health = HealthStore.shared
        var checks: [Check] = []
        var identities: [String] = []
        func check(_ value: Bool, _ name: String) throws {
            checks.append(.init(name: name, passed: value))
            if !value { throw Failure(message: name) }
        }
        func bytes() throws -> [String: Data] {
            let root = try LocalStore.checkedDirectory()
            return try Dictionary(uniqueKeysWithValues: ["water.json", "meals.json", "goals.json", "today.json", HealthWriteFiles.name].map { name in
                let file = root.appendingPathComponent(name)
                return (name, FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : Data())
            })
        }
        do {
            for _ in 0..<300 where !health.conversationReady { try await Task.sleep(for: .milliseconds(25)) }
            try check(health.conversationReady, "actual checked conversation startup is terminal before Health transactions")
            let deviceOwner = try HealthWriteDeviceOwner.current()
            try SecureStore.eraseAllChecked()
            try check(try HealthWriteDeviceOwner.current() == deviceOwner,
                      "validated nonsynchronizing ThisDeviceOnly owner survives provider-credential erasure")
            let existing = try LocalStore.healthWriteJournalChecked()
            try check(existing.owner == deviceOwner, "actual journal owner matches this device's checked Keychain identity")
            try check(existing.pendingEvents.isEmpty, "dedicated synthetic launch has no unrelated pending external intent")
            let before = try bytes()
            let receiptTrial = ProcessInfo.processInfo.arguments.contains("-health-write-receipt-trial")
            if !receiptTrial {
                var failed = false
                do { try health.addWater(ml: 250) } catch { failed = true }
                try check(failed, "actual first water-plus-journal staging I/O failure reaches HealthStore caller")
                try check(try bytes() == before && health.waterLogs.isEmpty && external.isEmpty,
                          "failed combined native commit retains exact files/live records and sends no adapter operation")
            }
            try health.addWater(ml: 250)
            let waterIntent = try LocalStore.healthWriteJournalChecked()
            try check(health.waterLogs.count == 1 && waterIntent.pendingEvents.count == 1 && external.isEmpty,
                      "actual water local record and durable payload exist before worker actor turn")
            identities.append(waterIntent.next()!.syncIdentifier)
            await health.waitForHealthWriteVerification()
            if receiptTrial {
                let afterFailure = try LocalStore.healthWriteJournalChecked()
                try check(afterFailure == waterIntent && external.count == 1,
                          "actual receipt destination I/O failure preserves exact intent after external success")
                try check(health.healthWritePendingCount == 1 && health.healthWriteStatus?.contains("couldn't be saved") == true,
                          "native observable state names unrecorded progress and keeps retry pending")
                health.retryHealthWrites(); await health.waitForHealthWriteVerification()
            }
            try check(try LocalStore.healthWriteJournalChecked().pendingEvents.isEmpty && external.count == 1,
                      "water retry or first acknowledgement completes one external identity")

            let food = FoodItem(name: "Synthetic durable meal", grams: 100, calories: 200, proteinG: 10, carbsG: 20, fatG: 8, fiberG: 3)
            let meal = Meal(id: "synthetic-durable-43-meal", type: .lunch, items: [food])
            denied = .protein
            try health.addMeal(meal)
            await health.waitForHealthWriteVerification()
            let partial = try LocalStore.healthWriteJournalChecked()
            guard let event = partial.events.first(where: { $0.localID == meal.id }) else { throw Failure(message: "meal intent missing") }
            try check(event.acknowledged == [.calories] && event.issue == .permission && external.count == 2,
                      "actual meal saves calories then retains four components after denied protein")
            try check(health.meals.count == 1 && health.healthWriteStatus?.contains("permission") == true,
                      "saved meal remains visible with accurate permission/retry state")
            try await health.logWeight(kg: 75)
            await health.waitForHealthWriteVerification()
            let withWeight = try LocalStore.healthWriteJournalChecked()
            guard let weight = withWeight.events.first(where: { $0.domain == .weight }) else { throw Failure(message: "weight intent missing") }
            try check(weight.complete && health.goals.weightKg == 75 && LocalStore.load(HealthGoals.self, from: "goals")?.weightKg == 75,
                      "actual paired goals/snapshot/weight intent commits and independent weight completes")
            try check(withWeight.events.first(where: { $0.localID == meal.id })?.issue == .permission,
                      "failed meal type remains pending while weight completes")
            denied = nil; health.retryHealthWrites(); await health.waitForHealthWriteVerification()
            try check(try LocalStore.healthWriteJournalChecked().pendingEvents.isEmpty && external.count == 7 && trace.filter { $0 == "save:calories" }.count == 1,
                      "actual retry completes all seven water/meal/weight components without resending acknowledged calories")

            holdWater = true; trace = []
            try health.addWater(ml: 333)
            for _ in 0..<400 where !entered { try await Task.sleep(for: .milliseconds(10)) }
            try check(entered, "actual second water reaches held adapter save")
            let heldID = health.waterLogs.last!.id
            try health.undoLastWater()
            let undo = try LocalStore.healthWriteJournalChecked()
            try check(!health.waterLogs.contains(where: { $0.id == heldID }) && undo.events.first(where: { $0.localID == heldID })?.action == .delete,
                      "actual Undo atomically removes local water and persists original-identity deletion")
            try check(!trace.contains("delete:water"), "native deletion cannot overtake the held save callback")
            holdWater = false; release?.resume(); release = nil
            await health.waitForHealthWriteVerification()
            let afterUndo = try LocalStore.healthWriteJournalChecked()
            try check(trace == ["save:water", "delete:water"] && external.count == 7 && afterUndo.pendingEvents.isEmpty,
                      "actual held save completes before delete, with no final orphaned adapter record")
            try check(health.waterUndoStatus?.contains("No matching Lumen entry remains") == true,
                      "native Undo status follows its own durable deletion acknowledgement")
            identities += afterUndo.events.flatMap { event in event.components.map { component in
                "com.dbakp.lumen.health.v1.\(afterUndo.owner.uuidString).\(event.id.uuidString).\(component.metric.rawValue)"
            } }
            status = "Health recovery checks passed"
        } catch {
            holdWater = false; release?.resume(); release = nil
            status = "Health recovery checks failed: \(error)"
        }
        struct Report: Encodable {
            let status: String; let checks: [Check]; let trace: [String]; let sourceOwnedIdentities: [String]
            let externalComponents: Int; let external: [String: Double]; let persistedFiles: [String: Data]
            let liveWaterIDs: [String]; let liveMealIDs: [String]; let liveWeight: Double?
            let pendingCount: Int; let writeStatus: String?; let undoStatus: String?; let scope: String
        }
        let report = Report(status: status, checks: checks, trace: trace, sourceOwnedIdentities: identities,
                            externalComponents: external.count, external: external, persistedFiles: (try? bytes()) ?? [:],
                            liveWaterIDs: health.waterLogs.map(\.id), liveMealIDs: health.meals.map(\.id), liveWeight: health.goals.weightKg,
                            pendingCount: health.healthWritePendingCount, writeStatus: health.healthWriteStatus, undoStatus: health.waterUndoStatus,
                            scope: "Actual signed-simulator HealthStore/LocalStore transactions and observable state with controlled adapter and real Foundation I/O faults; not HealthKit samples, physical-device, full UI or complete batch acceptance.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try encoder.encode(report).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-durable-health-report.json"), options: .atomic) }
        catch { status = "Health recovery checks failed: report write" }
    }
    /// Measures the current production load/save behavior before repairing it.
    /// Only this dedicated simulator's synthetic current/legacy files are used.
    private func localDataBaseline(_ domain: String) async {
        var checks: [Check] = []
        var before = Data(), after: [String: Data] = [:]
        var loadedWater: [String] = [], loadedMeals: [String] = []
        var loadedWeight: Double?, savedWater: [String] = [], savedMeals: [String] = []
        var savedWeight: Double?, mutationError: String?, readError: String?
        var directoryRetained = false
        func check(_ value: Bool, _ name: String) throws {
            checks.append(.init(name: name, passed: value))
            if !value { throw Failure(message: name) }
        }
        do {
            let shared = HealthStore.shared
            for _ in 0..<300 where !shared.conversationReady { try await Task.sleep(for: .milliseconds(25)) }
            try check(shared.conversationReady, "shared startup completed before synthetic file preparation")
            let root = try LocalStore.checkedDirectory()
            let name = domain == "unreadable-water" ? "water" : domain
            let file = root.appendingPathComponent(name + ".json")
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            if domain == "unreadable-water" {
                try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
                do { _ = try Data(contentsOf: file) } catch { readError = String(describing: error) }
                try check(readError != nil, "actual Foundation read rejects a non-regular current water file")
            } else {
                before = Data("{\"syntheticDamagedHistory\": [".utf8)
                try before.write(to: file, options: .atomic)
                try check((try? JSONSerialization.jsonObject(with: before)) == nil,
                          "existing synthetic current file has invalid JSON bytes")
            }
            let legacyEncoder = JSONEncoder()
            let legacyMeal = Meal(id: "synthetic-stale-legacy-meal", type: .lunch,
                                 items: [FoodItem(name: "Synthetic stale meal", grams: 100, calories: 99, proteinG: 1, carbsG: 2, fatG: 3, fiberG: 4)])
            if domain == "meals" { UserDefaults.standard.set(try legacyEncoder.encode([legacyMeal]), forKey: "lumen.health.meals.v1") }
            if domain == "goals" {
                var old = HealthGoals(); old.weightKg = 61.25
                UserDefaults.standard.set(try legacyEncoder.encode(old), forKey: "lumen.health.goals.v1")
            }
            // Uses the actual constructor after the current file is damaged.
            let health = HealthStore()
            for _ in 0..<300 where !health.conversationReady { try await Task.sleep(for: .milliseconds(25)) }
            try check(health.conversationReady, "new actual HealthStore completes unrelated conversation startup")
            loadedWater = health.waterLogs.map(\.id); loadedMeals = health.meals.map(\.id); loadedWeight = health.goals.weightKg
            if domain == "meals" {
                try check(loadedMeals == [legacyMeal.id], "baseline reads stale legacy meals despite damaged current file")
            } else if domain == "goals" {
                try check(loadedWeight == 61.25, "baseline reads stale legacy goals despite damaged current file")
            } else {
                try check(loadedWater.isEmpty, "baseline publishes empty water history after failed current-file read")
            }
            do {
                switch domain {
                case "meals":
                    try health.addMeal(Meal(id: "synthetic-new-corrupt-baseline-meal", type: .lunch,
                                            items: [FoodItem(name: "Synthetic new meal", grams: 100, calories: 213, proteinG: 11, carbsG: 23, fatG: 9, fiberG: 4)]))
                case "goals": try await health.logWeight(kg: 76.25)
                default: try health.addWater(ml: 137)
                }
            } catch { mutationError = String(describing: error) }
            await health.waitForHealthWriteVerification()
            savedWater = health.waterLogs.map(\.id); savedMeals = health.meals.map(\.id); savedWeight = health.goals.weightKg
            for item in ["water.json", "meals.json", "goals.json", "today.json", HealthWriteFiles.name] {
                if let data = try? Data(contentsOf: root.appendingPathComponent(item)) { after[item] = data }
            }
            if domain == "unreadable-water" {
                var isDirectory: ObjCBool = false
                directoryRetained = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) && isDirectory.boolValue
                try check(mutationError != nil && directoryRetained && trace.isEmpty && external.isEmpty,
                          "non-regular destination naturally rejects mutation and retains directory without external dispatch")
            } else {
                try check(mutationError == nil && after[name + ".json"] != before,
                          "baseline defect reproduced: successful new mutation replaces damaged current-file bytes")
                try check(!external.isEmpty && (try LocalStore.healthWriteJournalChecked()).pendingEvents.isEmpty,
                          "baseline dispatches and acknowledges new external work after replacing damaged domain")
            }
            status = "Local data baseline recorded"
        } catch { status = "Local data baseline failed: \(error)" }
        struct Report: Encodable {
            let status: String; let domain: String; let checks: [Check]; let originalDamagedBytes: Data
            let loadedWaterIDs: [String]; let loadedMealIDs: [String]; let loadedWeight: Double?
            let savedWaterIDs: [String]; let savedMealIDs: [String]; let savedWeight: Double?
            let mutationError: String?; let readError: String?; let directoryRetained: Bool
            let trace: [String]; let external: [String: Double]; let persistedFiles: [String: Data]; let scope: String
        }
        let report = Report(status: status, domain: domain, checks: checks, originalDamagedBytes: before,
                            loadedWaterIDs: loadedWater, loadedMealIDs: loadedMeals, loadedWeight: loadedWeight,
                            savedWaterIDs: savedWater, savedMealIDs: savedMeals, savedWeight: savedWeight,
                            mutationError: mutationError, readError: readError, directoryRetained: directoryRetained,
                            trace: trace, external: external, persistedFiles: after,
                            scope: "Pre-repair actual native HealthStore load/mutation baseline with controlled external adapter. Corrupt water/meals/goals replacement is a reproduced defect, not a repaired pass. Directory input proves a real Foundation read error, not physical-device lock/permission behavior.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try encoder.encode(report).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-local-data-baseline.json"), options: .atomic) }
        catch { status = "Local data baseline failed: report write" }
    }
}
#endif
