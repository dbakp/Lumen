#if !targetEnvironment(simulator)
#error("The Health source fixture may run only in the iOS simulator")
#endif
import SwiftUI
import HealthKit

/// A separate source identity for actual SDK inclusion/exclusion checks.
/// No Lumen app group, product data or untagged Health samples are accessed.
@main
struct HealthSourceFixtureApp: App {
    @StateObject private var model = FixtureModel()
    var body: some Scene {
        WindowGroup {
            ScrollView { Text(model.status).padding().textSelection(.enabled) }
                .task { await model.run() }
        }
    }
}

@MainActor
private final class FixtureModel: ObservableObject {
    @Published var status = "Waiting for an explicit fixture operation."
    private let store = HKHealthStore()
    private var started = false
    private let source = "com.dbakp.lumen.fixture.health-source"
    private enum Dataset: String, Codable { case nutrition, measured }
    private func metadataKey(_ dataset: Dataset) -> String {
        dataset == .nutrition ? "LumenForeignSourceFixtureV1" : "LumenMeasuredSourceFixtureV2"
    }
    private struct Definition {
        let type: HKQuantityTypeIdentifier
        let unit: HKUnit
        let values: [Double]
    }
    private func definitions(_ dataset: Dataset) -> [Definition] {
        if dataset == .measured { return [
            .init(type: .stepCount, unit: .count(), values: [0, 240]),
            .init(type: .activeEnergyBurned, unit: .kilocalorie(), values: [20, 30]),
            .init(type: .basalEnergyBurned, unit: .kilocalorie(), values: [60, 90]),
            .init(type: .restingHeartRate, unit: HKUnit(from: "count/min"), values: [55, 61]),
            .init(type: .heartRateVariabilitySDNN, unit: HKUnit(from: "ms"), values: [28, 42]),
            .init(type: .oxygenSaturation, unit: .percent(), values: [0.95, 0.98]),
            .init(type: .bodyMass, unit: .gramUnit(with: .kilo), values: [70, 71.25]),
            .init(type: .respiratoryRate, unit: HKUnit(from: "count/min"), values: [14, 17]),
            .init(type: .vo2Max, unit: HKUnit(from: "ml/(kg*min)"), values: [38, 44]),
            .init(type: .heartRate, unit: HKUnit(from: "count/min"), values: [64, 80]),
            .init(type: .bodyFatPercentage, unit: .percent(), values: [0.19, 0.23])
        ] }
        return [
        .init(type: .dietaryWater, unit: .literUnit(with: .milli), values: [150, 250]),
        .init(type: .dietaryEnergyConsumed, unit: .kilocalorie(), values: [125, 225]),
        .init(type: .dietaryProtein, unit: .gram(), values: [8, 12]),
        .init(type: .dietaryCarbohydrates, unit: .gram(), values: [15, 25]),
        .init(type: .dietaryFatTotal, unit: .gram(), values: [5, 7])
    ] }
    private struct Row: Codable {
        let identifier: String
        let unit: String
        let value: Double
        let uuid: UUID
        let start: Date
        let end: Date
    }
    private struct Ledger: Codable {
        let version: Int
        let run: UUID
        let source: String
        let dataset: Dataset?
        var status: String
        var rows: [Row]
        var observed: [UUID]
        var error: String?
    }
    private enum Failure: Error { case arguments, identity, ledger, permission, mismatch }

    func run() async {
        guard !started else { return }; started = true
        do {
            let args = ProcessInfo.processInfo.arguments
            guard args.count == 3, ["seed", "seed-measured", "inspect", "cleanup", "inspect-lumen"].contains(args[1]),
                  let run = UUID(uuidString: args[2]) else { throw Failure.arguments }
            guard Bundle.main.bundleIdentifier == source, HKHealthStore.isHealthDataAvailable() else { throw Failure.identity }
            if args[1] == "inspect-lumen" {
                status = try await LumenOwnedInspection.run(run, store: store)
                return
            }
            let url = try ledgerURL(run)
            switch args[1] {
            case "seed", "seed-measured": try await seed(run, dataset: args[1] == "seed-measured" ? .measured : .nutrition, url: url)
            default: try await inspect(run, url: url, cleanup: args[1] == "cleanup")
            }
        } catch { status = "Fixture stopped: \(error). No untagged samples were changed." }
    }

    private func ledgerURL(_ run: UUID) throws -> URL {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return root.appendingPathComponent("health-source-\(run.uuidString).json")
    }
    private func write(_ ledger: Ledger, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: url, options: .atomic)
        status = "\(ledger.status) · \(ledger.rows.count) declared samples · \(ledger.observed.count) observed\nRun \(ledger.run.uuidString)"
    }
    private func matches(_ definition: Definition, run: UUID, dataset: Dataset) async throws -> [HKQuantitySample] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: metadataKey(dataset), allowedValues: [run.uuidString])
        ])
        return try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: HKQuantityType(definition.type), predicate: predicate,
                                       limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples as? [HKQuantitySample]) ?? []) }
            })
        }
    }
    private func validate(_ ledger: Ledger, run: UUID) throws {
        let dataset = ledger.dataset ?? .nutrition
        guard ledger.version == (dataset == .nutrition ? 1 : 2), ledger.run == run, ledger.source == source,
              Set(ledger.rows.map(\.uuid)).count == ledger.rows.count else { throw Failure.ledger }
        let expected = definitions(dataset).flatMap { d in d.values.map { (d.type.rawValue, d.unit.unitString, $0) } }
        guard ledger.rows.count <= expected.count else { throw Failure.ledger }
        for (row, fact) in zip(ledger.rows, expected) {
            guard row.identifier == fact.0, row.unit == fact.1, row.value == fact.2,
                  row.start == row.end else { throw Failure.ledger }
        }
    }
    private func observed(_ ledger: Ledger, run: UUID) async throws -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []
        let dataset = ledger.dataset ?? .nutrition
        for definition in definitions(dataset) {
            for sample in try await matches(definition, run: run, dataset: dataset) {
                guard let row = ledger.rows.first(where: { $0.uuid == sample.uuid }),
                      sample.sourceRevision.source.bundleIdentifier == source,
                      row.identifier == definition.type.rawValue,
                      sample.quantity.doubleValue(for: definition.unit) == row.value,
                      sample.startDate == row.start, sample.endDate == row.end else { throw Failure.mismatch }
                samples.append(sample)
            }
        }
        return samples
    }
    private func seed(_ run: UUID, dataset: Dataset, url: URL) async throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.ledger }
        var ledger = Ledger(version: dataset == .nutrition ? 1 : 2, run: run, source: source, dataset: dataset,
                            status: "preparing", rows: [], observed: [])
        try write(ledger, to: url)
        do {
            let definitions = definitions(dataset)
            let types = Set(definitions.map { HKQuantityType($0.type) })
            try await store.requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
            guard types.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else { throw Failure.permission }
            // Existing matching data without this ledger is never adopted or removed.
            for definition in definitions { guard try await matches(definition, run: run, dataset: dataset).isEmpty else { throw Failure.identity } }
            let base = Date().addingTimeInterval(-120)
            for definition in definitions {
                for value in definition.values {
                    let date = base.addingTimeInterval(Double(ledger.rows.count))
                    let sample = HKQuantitySample(type: HKQuantityType(definition.type),
                        quantity: HKQuantity(unit: definition.unit, doubleValue: value), start: date, end: date,
                        metadata: [metadataKey(dataset): run.uuidString])
                    // Persist identity before save; partial failures remain exactly cleanable.
                    ledger.rows.append(Row(identifier: definition.type.rawValue, unit: definition.unit.unitString,
                                           value: value, uuid: sample.uuid, start: date, end: date))
                    ledger.status = "saving"; try write(ledger, to: url)
                    try await store.save(sample)
                }
            }
            let samples = try await observed(ledger, run: run)
            guard Set(samples.map(\.uuid)) == Set(ledger.rows.map(\.uuid)) else { throw Failure.mismatch }
            ledger.observed = samples.map(\.uuid); ledger.status = "seeded"; try write(ledger, to: url)
        } catch {
            ledger.status = "seed-failed"; ledger.error = String(describing: error)
            try write(ledger, to: url); throw error
        }
    }
    private func inspect(_ run: UUID, url: URL, cleanup: Bool) async throws {
        var ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: url))
        try validate(ledger, run: run)
        let samples = try await observed(ledger, run: run)
        ledger.observed = samples.map(\.uuid)
        if cleanup {
            ledger.status = "cleaning"; try write(ledger, to: url)
            if !samples.isEmpty { try await store.delete(samples) }
            guard try await observed(ledger, run: run).isEmpty else { throw Failure.mismatch }
            ledger.observed = []; ledger.status = "cleaned"
        } else {
            let expectedCount = definitions(ledger.dataset ?? .nutrition).reduce(0) { $0 + $1.values.count }
            ledger.status = samples.count == ledger.rows.count && ledger.rows.count == expectedCount ? "inspected-complete" : "inspected-partial"
        }
        try write(ledger, to: url)
    }
}
