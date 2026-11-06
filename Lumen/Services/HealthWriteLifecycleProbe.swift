#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthKit
import SwiftUI
import Darwin

/// Actual HealthStore/HealthKit process pairs on the dedicated simulator.
/// Only dispatch timing and real receipt I/O failure are controlled. A separate
/// host readback runs after prepare terminates and before resume is launched.
@MainActor final class HealthWriteLifecycleProbe: ObservableObject {
    static let shared = HealthWriteLifecycleProbe()
    static let cases = ["before-worker", "before-receipt", "undo-before-receipt"]
    static var phase: String? { argument("-health-write-lifecycle") }
    static var scenario: String? { argument("-health-write-case") }
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("-resetForUITests")
            && ["prepare", "resume"].contains(phase ?? "") && cases.contains(scenario ?? "")
    }
    static var resuming: Bool { requested && phase == "resume" }
    private static func argument(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static var shouldHoldDispatch: Bool { requested && shared.dispatchHeld }
    static func recordVerified(_ claim: HealthWriteJournal.Claim) {
        guard requested else { return }
        shared.verifiedOperations.append(claim.action.rawValue + ":" + claim.component.metric.rawValue + ":" + claim.syncIdentifier)
    }
    @Published private(set) var status = "Preparing actual Health restart checks…"
    @Published private(set) var accessReturned = false
    private var dispatchHeld = true
    private var started = false
    private var verifiedOperations: [String] = []
    private struct Failure: Error { let name: String }
    private struct Check: Codable { let name: String; let passed: Bool }
    private struct Observation: Codable {
        let metric: String; let syncIdentifier: String; let count: Int
        let values: [Double]; let dates: [Date]; let sourceBundles: [String]; let sampleUUIDs: [String]
    }
    private struct Prepared: Codable {
        let scenario: String; let nonce: UUID; let pid: Int32
        let journal: HealthWriteJournal; let files: [String: Data]
        let waterIDs: [String]; let mealIDs: [String]; let weight: Double?
        let samples: [Observation]; let verifiedOperations: [String]; let checks: [Check]
    }
    private struct Report: Encodable {
        let status: String; let pid: Int32; let prepared: Prepared
        let journal: HealthWriteJournal; let files: [String: Data]
        let waterIDs: [String]; let mealIDs: [String]; let weight: Double?
        let samplesBeforeRecovery: [Observation]; let samplesAfterRecovery: [Observation]
        let verifiedOperations: [String]; let checks: [Check]; let exactFixtureCleanupVerified: Bool; let scope: String
    }
    private var checkpoint: URL { LocalStore.directory.appendingPathComponent("health-write-restart-checkpoint.json") }
    private func files() throws -> [String: Data] {
        let root = try LocalStore.checkedDirectory()
        return try Dictionary(uniqueKeysWithValues: ["water.json", "meals.json", "goals.json", "today.json", HealthWriteFiles.name].map {
            ($0, try Data(contentsOf: root.appendingPathComponent($0)))
        })
    }
    private func claims(_ original: HealthWriteJournal) throws -> [HealthWriteJournal.Claim] {
        var journal = original, result: [HealthWriteJournal.Claim] = []
        while let claim = journal.next() { result.append(claim); try journal.acknowledge(claim) }
        return result
    }
    private func observations(_ claims: [HealthWriteJournal.Claim]) async throws -> [Observation] {
        var rows: [Observation] = []
        for claim in claims {
            let samples = try await HealthKitService.shared.durableSamples(claim)
            let unit: HKUnit
            switch claim.component.metric {
            case .water: unit = .literUnit(with: .milli)
            case .calories: unit = .kilocalorie()
            case .weight: unit = .gramUnit(with: .kilo)
            default: unit = .gram()
            }
            rows.append(.init(metric: claim.component.metric.rawValue, syncIdentifier: claim.syncIdentifier,
                              count: samples.count, values: samples.map { $0.quantity.doubleValue(for: unit) },
                              dates: samples.map(\.startDate), sourceBundles: samples.map { $0.sourceRevision.source.bundleIdentifier },
                              sampleUUIDs: samples.map { $0.uuid.uuidString }))
        }
        return rows
    }
    func run() async {
        guard Self.requested, !started else { return }; started = true
        let health = HealthStore.shared, hk = HealthKitService.shared
        var checks: [Check] = []
        func check(_ value: Bool, _ name: String) throws {
            checks.append(.init(name: name, passed: value)); if !value { throw Failure(name: name) }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            for _ in 0..<300 where !health.conversationReady { try await Task.sleep(for: .milliseconds(25)) }
            try check(health.conversationReady, "actual checked native startup finishes before lifecycle verification")
            try check(!HealthWriteNativeProbe.requested && !HealthWriteHealthKitProbe.requested, "other adapter and standalone SDK probes are disabled")
            guard let scenario = Self.scenario else { throw Failure(name: "missing lifecycle case") }
            if Self.phase == "prepare" {
                let authorized = await hk.requestAuthorization(); accessReturned = true
                HealthBackgroundSync.shared.stop()
                try check(authorized && hk.isAuthorized, "actual Health connection is requested before local changes")
                let initial = try LocalStore.healthWriteJournalChecked()
                try check(initial.pendingEvents.isEmpty && health.waterLogs.isEmpty && health.meals.isEmpty, "dedicated preparation has no unrelated local or pending records")
                let nonce = UUID()
                try health.addWater(ml: 137)
                let food = FoodItem(name: "Synthetic restart meal", grams: 100, calories: 213, proteinG: 11, carbsG: 23, fatG: 9, fiberG: 4)
                try health.addMeal(.init(id: "synthetic-restart-43-" + nonce.uuidString, type: .lunch, items: [food]))
                try await health.logWeight(kg: 76.25)
                let seeded = try LocalStore.healthWriteJournalChecked()
                try check(seeded.events.count == 3 && seeded.events.allSatisfy { $0.acknowledged.isEmpty }, "actual local water/meal/weight and seven unacknowledged payloads commit before dispatch")
                try check(verifiedOperations.isEmpty, "no actual adapter operation starts before all local commits")
                if scenario != "before-worker" {
                    dispatchHeld = false; health.retryHealthWrites()
                    await health.waitForHealthWriteVerification()
                    try check(verifiedOperations.count == 3, "actual water/calorie/weight operations finish before injected receipt I/O failures")
                    try check(health.healthWriteStatus?.contains("couldn't be saved") == true, "native state keeps successful external work pending after real receipt I/O failure")
                }
                dispatchHeld = true
                if scenario == "undo-before-receipt" { try health.undoLastWater() }
                let pending = try LocalStore.healthWriteJournalChecked()
                let activeClaims = try claims(pending)
                try check(activeClaims.count == 7 && pending.events.allSatisfy { $0.acknowledged.isEmpty }, "seven exact payload identities remain durable at the termination boundary")
                let samples = try await observations(activeClaims)
                let expectedExisting = scenario == "before-worker" ? Set<String>() : Set(["water", "calories", "weight"])
                try check(samples.allSatisfy { $0.count == (expectedExisting.contains($0.metric) ? 1 : 0) }, "actual pre-termination Health samples match the precise dispatch boundary")
                try check(pending.events.first(where: { $0.domain == .water })?.action == (scenario == "undo-before-receipt" ? .delete : .save), "pending water action matches the actual local Undo decision")
                let prepared = Prepared(scenario: scenario, nonce: nonce, pid: getpid(), journal: pending, files: try files(),
                                        waterIDs: health.waterLogs.map(\.id), mealIDs: health.meals.map(\.id), weight: health.goals.weightKg,
                                        samples: samples, verifiedOperations: verifiedOperations, checks: checks)
                try encoder.encode(prepared).write(to: checkpoint, options: .atomic)
                status = "Health restart ready to stop"
            } else {
                accessReturned = true
                let prepared = try JSONDecoder().decode(Prepared.self, from: Data(contentsOf: checkpoint))
                try check(prepared.scenario == scenario && prepared.pid != getpid(), "resume is a different actual app process for the prepared case")
                try check(try prepared.journal.owner == HealthWriteDeviceOwner.current(), "same checked device owner survives process termination")
                try check(try files() == prepared.files && LocalStore.healthWriteJournalChecked() == prepared.journal, "every prepared local and intent byte survives the app process boundary")
                try check(hk.isAuthorized && health.waterLogs.map(\.id) == prepared.waterIDs && health.meals.map(\.id) == prepared.mealIDs && health.goals.weightKg == prepared.weight, "new native store loads the original live records and requested Health connection")
                let activeClaims = try claims(prepared.journal)
                let before = try await observations(activeClaims)
                try check(before.map(\.count) == prepared.samples.map(\.count), "actual Health sample presence survives before any recovery operation starts")
                dispatchHeld = false; health.retryHealthWrites()
                await health.waitForHealthWriteVerification()
                let recovered = try LocalStore.healthWriteJournalChecked()
                try check(recovered.pendingEvents.isEmpty && recovered.events.allSatisfy(\.complete), "new-process native worker durably acknowledges every recovered component")
                let after = try await observations(activeClaims)
                try check(after.allSatisfy { $0.count == (scenario == "undo-before-receipt" && $0.metric == "water" ? 0 : 1) }, "actual recovery leaves one sample per saved component and none for the pending Undo")
                for (claim, observation) in zip(activeClaims, after) where observation.count == 1 {
                    try check(abs(observation.values[0] - claim.component.value) <= 1e-7
                              && abs(observation.dates[0].timeIntervalSince(claim.component.date)) <= 0.001
                              && observation.sourceBundles == [Bundle.main.bundleIdentifier!],
                              "recovered actual \(claim.component.metric.rawValue) preserves measured payload, date and source")
                }
                try check(verifiedOperations.count == 7, "seven actual production adapter operations complete in the resumed process")
                let savedFiles = try files()
                for claim in activeClaims {
                    let own = try await hk.durableSamples(claim)
                    if !own.isEmpty { try await hk.store.delete(own) }
                    try check(try await hk.durableSamples(claim).isEmpty, "exact synthetic \(claim.component.metric.rawValue) fixture cleanup is queried absent")
                }
                hk.disconnectLocally()
                let report = Report(status: "Health restart checks passed", pid: getpid(), prepared: prepared,
                                    journal: recovered, files: savedFiles, waterIDs: health.waterLogs.map(\.id),
                                    mealIDs: health.meals.map(\.id), weight: health.goals.weightKg,
                                    samplesBeforeRecovery: before, samplesAfterRecovery: after,
                                    verifiedOperations: verifiedOperations, checks: checks, exactFixtureCleanupVerified: true,
                                    scope: "Actual different native app processes, HealthStore/LocalStore/journal/worker and real simulator HealthKit. Dispatch is held during preparation; receipt faults are actual Foundation I/O failures. Observer refresh is isolated. Not OS power loss, in-flight daemon transaction termination, foreign source, signed-iPhone or background/locked acceptance.")
                try encoder.encode(report).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-health-restart-report.json"), options: .atomic)
                status = report.status
            }
        } catch {
            status = "Health restart checks failed: \(error)"
            try? encoder.encode(["status": status, "phase": Self.phase ?? "missing", "scenario": Self.scenario ?? "missing"])
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-health-restart-failure.json"), options: .atomic)
        }
    }
}
#endif
