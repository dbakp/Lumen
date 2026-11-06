#if !targetEnvironment(simulator)
#error("Synthetic Health inspection must never run on a physical device")
#endif
import Foundation
import HealthKit

/// Read-only, exact-identity observation of records written through Lumen's
/// production adapter. This helper cannot create, acknowledge or delete them.
@MainActor enum LumenOwnedInspection {
    private struct Row: Codable {
        let event: UUID
        let localID: UUID
        let domain: String
        let metric: String
        let value: Double
        let date: Date
    }
    private struct Manifest: Codable {
        let version: Int
        let run: UUID
        let owner: UUID
        let source: String
        let rows: [Row]
    }
    private struct Observation: Codable {
        let metric: String
        let uuid: UUID
        let source: String
        let value: Double
        let start: Date
        let end: Date
        let syncIdentifier: String
        let syncVersion: Int
    }
    private struct Report: Codable {
        let version: Int
        let run: UUID
        let manifest: Manifest
        let inspectedAt: Date
        let observations: [Observation]
        let status: String
        let permissionInferred: Bool
        let mutatesHealth: Bool
    }
    private enum Failure: Error { case manifest, identity }

    static func run(_ run: UUID, store: HKHealthStore) async throws -> String {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        let input = root.appendingPathComponent("lumen-owned-\(run.uuidString).json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) < 16_384 else { throw Failure.manifest }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: input))
        let definitions: [String: (HKQuantityTypeIdentifier, HKUnit)] = [
            "water": (.dietaryWater, .literUnit(with: .milli)),
            "calories": (.dietaryEnergyConsumed, .kilocalorie()),
            "protein": (.dietaryProtein, .gram()), "carbs": (.dietaryCarbohydrates, .gram()),
            "fat": (.dietaryFatTotal, .gram()), "fiber": (.dietaryFiber, .gram())]
        guard manifest.version == 1, manifest.run == run, manifest.source == "com.dbakp.lumen",
              manifest.rows.count == 6, Set(manifest.rows.map(\.metric)) == Set(definitions.keys),
              Set(manifest.rows.map(\.event)).count == 2,
              Set(manifest.rows.map(\.localID)).count == 2 else { throw Failure.manifest }
        let now = Date()
        for row in manifest.rows {
            guard row.domain == (row.metric == "water" ? "water" : "meal"),
                  row.value.isFinite, row.value >= 0, row.value <= 10_000,
                  row.date.timeIntervalSince1970.isFinite,
                  Calendar.current.isDate(row.date, inSameDayAs: now), row.date <= now else { throw Failure.manifest }
        }
        let meals = manifest.rows.filter { $0.domain == "meal" }
        guard Set(meals.map(\.event)).count == 1, Set(meals.map(\.localID)).count == 1,
              Set(meals.map(\.date)).count == 1 else { throw Failure.manifest }
        // Read authorization is requested only after the exact manifest passes
        // validation. Completion never proves that any read category is granted.
        let readTypes = Set(definitions.values.map { HKQuantityType($0.0) as HKObjectType })
        try await store.requestAuthorization(toShare: [], read: readTypes)
        var observed: [Observation] = []
        for row in manifest.rows {
            guard let (identifier, unit) = definitions[row.metric] else { throw Failure.manifest }
            let sync = "com.dbakp.lumen.health.v1.\(manifest.owner.uuidString).\(row.event.uuidString).\(row.metric)"
            let predicates = [
                HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [sync]),
                HKQuery.predicateForObjects(withMetadataKey: "LumenHealthOwner", allowedValues: [manifest.owner.uuidString]),
                HKQuery.predicateForObjects(withMetadataKey: "LumenHealthEvent", allowedValues: [row.event.uuidString]),
                HKQuery.predicateForObjects(withMetadataKey: row.domain == "water" ? "LumenWaterID" : "LumenMealID",
                                            allowedValues: [row.localID.uuidString])]
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                store.execute(HKSampleQuery(sampleType: HKQuantityType(identifier),
                    predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
                    limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: (samples as? [HKQuantitySample]) ?? []) }
                })
            }
            guard samples.count <= 1 else { throw Failure.identity }
            for sample in samples {
                let value = sample.quantity.doubleValue(for: unit)
                guard sample.sourceRevision.source.bundleIdentifier == manifest.source,
                      abs(value - row.value) <= max(1e-9, abs(row.value) * 1e-9),
                      abs(sample.startDate.timeIntervalSince(row.date)) <= 0.001,
                      abs(sample.endDate.timeIntervalSince(row.date)) <= 0.001,
                      (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue == 1 else { throw Failure.identity }
                observed.append(.init(metric: row.metric, uuid: sample.uuid, source: manifest.source,
                    value: value, start: sample.startDate, end: sample.endDate,
                    syncIdentifier: sync, syncVersion: 1))
            }
        }
        let status = observed.count == 6 ? "observed-complete" : observed.isEmpty ? "observed-empty" : "observed-partial"
        let report = Report(version: 1, run: run, manifest: manifest, inspectedAt: Date(),
                            observations: observed, status: status, permissionInferred: false, mutatesHealth: false)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: root.appendingPathComponent("lumen-owned-\(run.uuidString)-report.json"), options: .atomic)
        return "\(status) · \(observed.count)/6 exact Lumen records · read-only\nRun \(run.uuidString)"
    }
}
