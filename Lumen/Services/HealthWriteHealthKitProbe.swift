#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthKit
import SwiftUI

/// Actual HealthKit, only on the dedicated synthetic simulator. Every sample
/// belongs to a newly generated owner/event identity and is queried/deleted by
/// that exact identity. Never bulk-clear Health or use personal samples.
@MainActor final class HealthWriteHealthKitProbe: ObservableObject {
    static let shared = HealthWriteHealthKitProbe()
    static var requested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetForUITests") && args.contains("-health-write-healthkit-probe")
    }
    @Published private(set) var status = "Waiting for Health access…"
    @Published private(set) var accessReturned = false
    private var started = false
    private struct Check: Codable { let name: String; let passed: Bool }
    private struct Sample: Codable {
        let metric: String; let syncIdentifier: String; let beforeUUID: String; let afterReplayUUID: String
        let sourceBundle: String; let value: Double; let date: Date
        let beforeCount: Int; let afterReplayCount: Int; let beforeValue: Double; let beforeDate: Date
    }
    private struct Failure: Error { let name: String }

    func run() async {
        guard Self.requested, !started else { return }; started = true
        var checks: [Check] = [], observations: [Sample] = [], claims: [HealthWriteJournal.Claim] = []
        var afterSaves: HealthWriteJournal?, afterDeletes: HealthWriteJournal?
        var cleaned = false
        var resultStatus = "HealthKit replay checks failed"
        let health = HealthStore.shared, hk = HealthKitService.shared
        func check(_ value: Bool, _ name: String) throws {
            checks.append(.init(name: name, passed: value)); if !value { throw Failure(name: name) }
        }
        do {
            try check(!HealthWriteNativeProbe.requested, "controlled adapter is disabled for actual HealthKit verification")
            try check(hk.isAvailable, "actual simulator HealthKit is available")
            for _ in 0..<300 where !health.conversationReady { try await Task.sleep(for: .milliseconds(25)) }
            try check(health.conversationReady, "checked local startup finishes before HealthKit fixture commits")
            let authorized = await hk.requestAuthorization()
            accessReturned = true
            HealthBackgroundSync.shared.stop()
            try check(authorized, "actual native Health permission request returns without framework error")
            status = "Checking actual HealthKit replay…"
            var journal = try LocalStore.healthWriteJournalChecked()
            try check(journal.pendingEvents.isEmpty, "actual HealthKit fixture starts without unrelated pending intent")
            let tag = "synthetic-healthkit-43-" + UUID().uuidString
            let date = Date(timeIntervalSince1970: 1_790_000_043)
            func component(_ metric: HealthWriteJournal.Metric, _ value: Double) -> HealthWriteJournal.Component {
                .init(metric: metric, value: value, date: date)
            }
            try journal.append(domain: .water, localID: tag + "-water", components: [component(.water, 137)])
            try journal.append(domain: .meal, localID: tag + "-meal", components: [component(.calories, 213), component(.protein, 11), component(.carbs, 23), component(.fat, 9), component(.fiber, 4)])
            try journal.append(domain: .weight, localID: tag + "-weight", components: [component(.weight, 76.25)])
            let empty = try LocalStore.healthWriteJournalChecked()
            try LocalStore.saveHealthReceiptChecked(journal, replacing: empty)
            // Capture every cleanup identity before the first real sample save.
            var enumeration = journal
            while let claim = enumeration.next() { claims.append(claim); try enumeration.acknowledge(claim) }
            try check(claims.count == 7, "seven stable source-owned cleanup identities exist before any actual save")
            for claim in claims {
                try await hk.performDurableWrite(claim)
                let first = try await hk.durableSamples(claim)
                try check(first.count == 1, "actual first \(claim.component.metric.rawValue) save yields one source-owned sample")
                try await hk.performDurableWrite(claim)
                let replay = try await hk.durableSamples(claim)
                guard let sample = replay.first else { throw Failure(name: "sample disappeared") }
                let unit: HKUnit
                switch claim.component.metric {
                case .water: unit = .literUnit(with: .milli)
                case .calories: unit = .kilocalorie()
                case .weight: unit = .gramUnit(with: .kilo)
                default: unit = .gram()
                }
                let value = sample.quantity.doubleValue(for: unit), beforeValue = first[0].quantity.doubleValue(for: unit)
                observations.append(.init(metric: claim.component.metric.rawValue, syncIdentifier: claim.syncIdentifier,
                                          beforeUUID: first[0].uuid.uuidString, afterReplayUUID: sample.uuid.uuidString,
                                          sourceBundle: sample.sourceRevision.source.bundleIdentifier,
                                          value: value, date: sample.startDate, beforeCount: first.count, afterReplayCount: replay.count,
                                          beforeValue: beforeValue, beforeDate: first[0].startDate))
                try check(replay.count == 1 && sample.metadata?[HKMetadataKeySyncIdentifier] as? String == claim.syncIdentifier,
                          "actual equal-version \(claim.component.metric.rawValue) replay keeps one matching logical sync identity")
                try check(abs(value - claim.component.value) <= 1e-7 && value == beforeValue && sample.startDate == first[0].startDate,
                          "actual \(claim.component.metric.rawValue) replay preserves measured quantity and date")
                try check(sample.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier,
                          "actual \(claim.component.metric.rawValue) sample has this app's HealthKit source")
                let previous = journal; try journal.acknowledge(claim)
                try LocalStore.saveHealthReceiptChecked(journal, replacing: previous)
            }
            afterSaves = journal
            try check(journal.pendingEvents.isEmpty, "all seven actual verified saves have durable receipts")
            try journal.requestDeletion(domain: .water, localID: tag + "-water")
            try journal.requestDeletion(domain: .meal, localID: tag + "-meal")
            let previous = try LocalStore.healthWriteJournalChecked()
            try LocalStore.saveHealthReceiptChecked(journal, replacing: previous)
            while let claim = journal.next() {
                try check(claim.action == .delete, "only explicit water/meal deletion intent reaches actual HealthKit")
                try await hk.performDurableWrite(claim)
                try check(try await hk.durableSamples(claim).isEmpty, "actual \(claim.component.metric.rawValue) deletion leaves no matching own-source sample")
                let previous = journal; try journal.acknowledge(claim)
                try LocalStore.saveHealthReceiptChecked(journal, replacing: previous)
            }
            afterDeletes = journal
            resultStatus = "HealthKit replay checks passed"
        } catch {
            accessReturned = true
            resultStatus = "HealthKit replay checks failed: \(error)"
        }
        // Cleanup is limited to exact fixture identities, including a save that
        // succeeded before a later assertion failed. Weight has no deletion UI;
        // its final deletion here is fixture cleanup, not a product capability.
        do {
            for claim in claims {
                let own = try await hk.durableSamples(claim)
                if !own.isEmpty { try await hk.store.delete(own) }
                guard try await hk.durableSamples(claim).isEmpty else { throw Failure(name: "fixture cleanup incomplete") }
            }
            cleaned = true
        } catch { resultStatus = "HealthKit replay checks failed: exact fixture cleanup \(error)" }
        hk.disconnectLocally()
        struct Report: Encodable {
            let status: String; let checks: [Check]; let samples: [Sample]
            let journalAfterSaves: HealthWriteJournal?; let journalAfterDeletes: HealthWriteJournal?
            let exactFixtureCleanupVerified: Bool; let scope: String
        }
        let report = Report(status: resultStatus, checks: checks, samples: observations, journalAfterSaves: afterSaves,
                            journalAfterDeletes: afterDeletes, exactFixtureCleanupVerified: cleaned,
                            scope: "Actual simulator HealthKit permission/save/query/equal-version replay and explicit water/meal deletion through the production adapter; no controlled adapter, foreign-source collision, process termination, signed-iPhone or background/locked acceptance.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(report).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-durable-healthkit-report.json"), options: .atomic)
            status = resultStatus
        }
        catch { status = "HealthKit replay checks failed: report write" }
    }
}
#endif
