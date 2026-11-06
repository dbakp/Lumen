import Foundation
import HealthKit

extension HealthKitService {
    /// Stable per-component sync metadata makes a success-before-receipt replay
    /// an upsert of the original sample, not a second nutrition/weight event.
    /// A callback alone is insufficient: verify the source-owned result before
    /// allowing the recovery worker to persist its acknowledgement.
    func performDurableWrite(_ claim: HealthWriteJournal.Claim) async throws {
        guard try LocalStore.healthWriteJournalChecked().contains(claim) else { throw HealthWriteJournal.Failure.staleClaim }
        guard isAvailable, isAuthorized else { throw HealthWriteOperationFailure(issue: .unavailable) }
        let type = durableType(claim.component.metric)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            throw HealthWriteOperationFailure(issue: .permission)
        }
        if claim.action == .save {
            guard claim.identity == .sync else { throw HealthWriteJournal.Failure.invalid }
            var metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: claim.syncIdentifier,
                HKMetadataKeySyncVersion: NSNumber(value: claim.syncVersion),
                "LumenHealthOwner": claim.owner.uuidString,
                "LumenHealthEvent": claim.event.uuidString,
            ]
            if claim.domain == .water { metadata["LumenWaterID"] = claim.localID }
            if claim.domain == .meal { metadata["LumenMealID"] = claim.localID }
            let sample = HKQuantitySample(type: type,
                quantity: HKQuantity(unit: durableUnit(claim.component.metric), doubleValue: claim.component.value),
                start: claim.component.date, end: claim.component.date, metadata: metadata)
            try await store.save(sample)
            let existing = try await durableSamples(claim)
            guard existing.count == 1, let actual = existing.first,
                  let version = actual.metadata?[HKMetadataKeySyncVersion] as? NSNumber,
                  version.intValue == claim.syncVersion,
                  abs(actual.quantity.doubleValue(for: durableUnit(claim.component.metric)) - claim.component.value) <= max(1e-9, abs(claim.component.value) * 1e-9),
                  abs(actual.startDate.timeIntervalSince(claim.component.date)) <= 0.001,
                  abs(actual.endDate.timeIntervalSince(claim.component.date)) <= 0.001 else {
                throw HealthWriteOperationFailure(issue: .operation)
            }
        } else {
            // HealthKit only permits deleting our own samples. Also constrain
            // the query explicitly: a matching foreign source/local ID never
            // becomes permission to delete another app's data.
            let existing = try await durableSamples(claim)
            if !existing.isEmpty { try await store.delete(existing) }
            guard try await durableSamples(claim).isEmpty else { throw HealthWriteOperationFailure(issue: .operation) }
        }
    }

    func durableSamples(_ claim: HealthWriteJournal.Claim) async throws -> [HKQuantitySample] {
        guard try HealthWriteDeviceOwner.current() == claim.owner else { throw HealthWriteJournal.Failure.foreignOwner }
        var predicates = [HKQuery.predicateForObjects(from: HKSource.default())]
        if claim.identity == .sync {
            predicates.append(HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [claim.syncIdentifier]))
            predicates.append(HKQuery.predicateForObjects(withMetadataKey: "LumenHealthOwner", allowedValues: [claim.owner.uuidString]))
            predicates.append(HKQuery.predicateForObjects(withMetadataKey: "LumenHealthEvent", allowedValues: [claim.event.uuidString]))
        } else {
            guard claim.action == .delete, claim.domain != .weight else { throw HealthWriteJournal.Failure.invalid }
            predicates.append(HKQuery.predicateForObjects(withMetadataKey: claim.domain == .water ? "LumenWaterID" : "LumenMealID", allowedValues: [claim.localID]))
        }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: durableType(claim.component.metric),
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
                limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples as? [HKQuantitySample]) ?? []) }
            }
            store.execute(query)
        }
    }

    private func durableType(_ metric: HealthWriteJournal.Metric) -> HKQuantityType {
        switch metric {
        case .water: return HKQuantityType(.dietaryWater)
        case .calories: return HKQuantityType(.dietaryEnergyConsumed)
        case .protein: return HKQuantityType(.dietaryProtein)
        case .carbs: return HKQuantityType(.dietaryCarbohydrates)
        case .fat: return HKQuantityType(.dietaryFatTotal)
        case .fiber: return HKQuantityType(.dietaryFiber)
        case .weight: return HKQuantityType(.bodyMass)
        }
    }
    private func durableUnit(_ metric: HealthWriteJournal.Metric) -> HKUnit {
        switch metric {
        case .water: return .literUnit(with: .milli)
        case .calories: return .kilocalorie()
        case .weight: return .gramUnit(with: .kilo)
        default: return .gram()
        }
    }
}
