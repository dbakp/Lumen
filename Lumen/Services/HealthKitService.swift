import Foundation
import HealthKit

// MARK: - Apple Health bridge
// Single owner of HKHealthStore: permissions, today snapshot, sleep with stages,
// workouts, day-by-day history for Trends, body characteristics for onboarding,
// and write-back of meals / water / weight.

public enum TrendMetric: String, CaseIterable, Identifiable, Sendable {
    case sleep, steps, activeEnergy, exercise, restingHR, hrv, weight
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .sleep: return "Sleep"; case .steps: return "Steps"; case .activeEnergy: return "Active energy"
        case .exercise: return "Exercise"; case .restingHR: return "Resting heart rate"; case .hrv: return "Heart rate variability"; case .weight: return "Weight"
        }
    }
    /// One plain-language paragraph shown on the detail screen.
    public var explainer: String {
        switch self {
        case .sleep: return "Time actually asleep each night. Most adults need 7–9 hours; Lumen learns your personal need from your history."
        case .steps: return "Every step counts — walking is one of the simplest ways to improve energy, mood and sleep."
        case .activeEnergy: return "Calories burned by moving, on top of what your body uses at rest."
        case .exercise: return "Minutes of brisk activity. About 30 minutes a day is a great target for most people."
        case .restingHR: return "Your heart rate when fully at rest. It usually drops as fitness improves, and rises with stress, illness, alcohol or poor sleep."
        case .hrv: return "The tiny variation between heartbeats. Higher than your own normal usually means you're well recovered. Compare with yourself, not others."
        case .weight: return "Day-to-day changes are mostly water. Look at the trend over weeks rather than any single day."
        }
    }
    public var icon: String {
        switch self {
        case .sleep: return "moon.fill"; case .steps: return "shoeprints.fill"; case .activeEnergy: return "flame.fill"
        case .exercise: return "figure.run"; case .restingHR: return "heart.fill"; case .hrv: return "waveform.path.ecg"; case .weight: return "scalemass.fill"
        }
    }
    public var unit: String {
        switch self {
        case .sleep: return "h"; case .steps: return "steps"; case .activeEnergy: return "kcal"
        case .exercise: return "min"; case .restingHR: return "bpm"; case .hrv: return "ms"; case .weight: return "kg"
        }
    }
    /// Lower is better (for delta colouring).
    public var lowerIsBetter: Bool { self == .restingHR }
    /// Cumulative metrics sum per day; the rest average.
    var cumulative: Bool { self == .steps || self == .activeEnergy || self == .exercise }
    var hkIdentifier: HKQuantityTypeIdentifier? {
        switch self {
        case .sleep: return nil; case .steps: return .stepCount; case .activeEnergy: return .activeEnergyBurned
        case .exercise: return .appleExerciseTime; case .restingHR: return .restingHeartRate
        case .hrv: return .heartRateVariabilitySDNN; case .weight: return .bodyMass
        }
    }
    var hkUnit: HKUnit {
        switch self {
        case .sleep: return .hour(); case .steps: return .count(); case .activeEnergy: return .kilocalorie()
        case .exercise: return .minute(); case .restingHR: return HKUnit(from: "count/min")
        case .hrv: return HKUnit(from: "ms"); case .weight: return .gramUnit(with: .kilo)
        }
    }
}

public struct DailyValue: Identifiable, Sendable, Hashable {
    public var id: Date { date }
    public var date: Date
    public var value: Double
}

public struct BodyCharacteristics: Sendable {
    public var birthYear: Int?
    public var sex: HealthGoals.Sex?
    public var heightCm: Double?
    public var weightKg: Double?
}

@MainActor
public final class HealthKitService: ObservableObject {
    public static let shared = HealthKitService()

    @Published public private(set) var isAuthorized: Bool
    @Published public var status: String
    @Published public var today = DayMetrics.empty

    let store = HKHealthStore()
    private let connectedKey = "lumen.health.connected"
    private let todayReads = HealthTodayReadCoordinator()
    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {
        // HealthKit never reveals read permission, so we remember that the user
        // went through the sheet and simply query — denied types come back empty.
        let connected = UserDefaults.standard.bool(forKey: connectedKey) && HKHealthStore.isHealthDataAvailable()
        isAuthorized = connected
        status = connected ? "Access requested" : "Not connected"
    }

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        let quantities: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime, .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate, .oxygenSaturation, .vo2Max, .bodyMass, .height, .bodyFatPercentage, .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber, .dietaryWater, .dietaryCaffeine]
        for id in quantities { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .appleStandHour) { s.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .mindfulSession) { s.insert(t) }
        if let t = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { s.insert(t) }
        if let t = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { s.insert(t) }
        s.insert(HKObjectType.workoutType())
        return s
    }

    private var shareTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>()
        let quantities: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber, .dietaryWater, .bodyMass]
        for id in quantities { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        #if DEBUG && targetEnvironment(simulator)
        if HealthDailyCacheRecordedFixture.requested {
            s.insert(HKQuantityType(.stepCount)); s.insert(HKQuantityType(.heartRate))
        }
        #endif
        return s
    }

    /// Presents the Health permission sheet. Returns true if the user went through it.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard isAvailable else { status = "Health isn't available on this device"; return false }
        invalidateTodayQueries()
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            UserDefaults.standard.set(true, forKey: connectedKey)
            isAuthorized = true
            UserDefaults.standard.set(UUID().uuidString, forKey: "lumen.health.rescan")
            status = "Access requested"
            #if DEBUG && targetEnvironment(simulator)
            // The actual HealthKit probe isolates sample replay from observer
            // refreshes. Permission and HealthKit operations remain real.
            if HealthWriteHealthKitProbe.requested || HealthWriteLifecycleProbe.requested || HealthRecoveryUIFixture.dailyRebuildRequested { return true }
            #endif
            HealthBackgroundSync.shared.start()
            return true
        } catch {
            status = "Couldn't connect — try again from Settings"
            return false
        }
    }

    public func disconnectLocally() {
        UserDefaults.standard.set(false, forKey: connectedKey)
        isAuthorized = false
        HealthBackgroundSync.shared.stop()
        status = "Paused — manage access in the Health app"
    }

    // MARK: Today

    public func refreshToday() async {
        do { publishToday(try await queryTodayReadings()) }
        catch { /* Keep the last actual check; never publish a stale fallback. */ }
    }

    func invalidateTodayQueries() { todayReads.invalidate() }

    struct DailySourceBoundary: Sendable {
        let selection: HealthTodayReadCoordinator.Selection
        let hardwareAvailable: Bool
        let connected: Bool
    }

    func captureDailySource() -> DailySourceBoundary {
        DailySourceBoundary(selection: todayReads.captureSelection(available: isAvailable && isAuthorized),
                            hardwareAvailable: isAvailable, connected: isAuthorized)
    }

    func dailySourceIsCurrent(_ boundary: DailySourceBoundary) -> Bool {
        boundary.hardwareAvailable == isAvailable && boundary.connected == isAuthorized
            && todayReads.isCurrent(boundary.selection, available: isAvailable && isAuthorized)
    }

    func queryTodayReadings() async throws -> HealthTodayReadCoordinator.Readings {
        let result = try await todayReads.read(available: isAvailable && isAuthorized) { [self] key, start, end, operation in
            try await todayReading(key, start: start, end: end, operation: operation)
        }
        try Task.checkCancellation()
        guard readingsAreCurrent(result) else { throw HealthTodayReadCoordinator.Failure.changed }
        #if DEBUG && targetEnvironment(simulator)
        if HealthRecoveryUIFixture.dailyRebuildRequested { try HealthDailyCacheHealthUIFixture.record(result) }
        #endif
        return result
    }

    func readingsAreCurrent(_ result: HealthTodayReadCoordinator.Readings) -> Bool {
        todayReads.isCurrent(result, available: isAvailable && isAuthorized)
    }

    func publishToday(_ result: HealthTodayReadCoordinator.Readings) {
        guard readingsAreCurrent(result) else { return }
        today = result.raw.metrics
        let available = today.readings?.values.filter { $0.value != nil }.count ?? 0
        status = "Checked \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)) · \(available) metrics returned"
    }

    private func todayReading(_ key: String, start: Date, end: Date, operation: HealthReadingQueryGroup) async throws -> HealthMetricReading {
        if key == "stand" { return try await standHoursReading(start: start, end: end, operation: operation) }
        let identifier: HKQuantityTypeIdentifier, unit: HKUnit, aggregation: HealthMetricComponent.Aggregation
        var excludingLumen = false, multiplier = 1.0
        switch key {
        case "steps": identifier = .stepCount; unit = .count(); aggregation = .total
        case "activeEnergy": identifier = .activeEnergyBurned; unit = .kilocalorie(); aggregation = .total
        case "restingEnergy": identifier = .basalEnergyBurned; unit = .kilocalorie(); aggregation = .total
        case "exercise": identifier = .appleExerciseTime; unit = .minute(); aggregation = .total
        case "water": identifier = .dietaryWater; unit = .literUnit(with: .milli); aggregation = .total; excludingLumen = true
        case "restingHR": identifier = .restingHeartRate; unit = HKUnit(from: "count/min"); aggregation = .latest
        case "hrv": identifier = .heartRateVariabilitySDNN; unit = HKUnit(from: "ms"); aggregation = .latest
        case "spo2": identifier = .oxygenSaturation; unit = .percent(); aggregation = .latest; multiplier = 100
        case "weight": identifier = .bodyMass; unit = .gramUnit(with: .kilo); aggregation = .latest
        case "respiratoryRate": identifier = .respiratoryRate; unit = HKUnit(from: "count/min"); aggregation = .latest
        case "vo2max": identifier = .vo2Max; unit = HKUnit(from: "ml/(kg*min)"); aggregation = .latest
        case "heartRate": identifier = .heartRate; unit = HKUnit(from: "count/min"); aggregation = .average
        case "bodyFat": identifier = .bodyFatPercentage; unit = .percent(); aggregation = .latest; multiplier = 100
        case "calories": identifier = .dietaryEnergyConsumed; unit = .kilocalorie(); aggregation = .total; excludingLumen = true
        case "protein": identifier = .dietaryProtein; unit = .gram(); aggregation = .total; excludingLumen = true
        case "carbs": identifier = .dietaryCarbohydrates; unit = .gram(); aggregation = .total; excludingLumen = true
        case "fat": identifier = .dietaryFatTotal; unit = .gram(); aggregation = .total; excludingLumen = true
        default: throw HealthLocalFiles.Failure.invalid
        }
        return try await quantityReading(identifier, unit: unit, aggregation: aggregation, start: start, end: end,
                                         excludingLumen: excludingLumen, multiplier: multiplier, operation: operation)
    }

    // MARK: History (Trends)

    public func dailySeries(_ metric: TrendMetric, days: Int) async -> [DailyValue] {
        guard isAvailable, isAuthorized, let id = metric.hkIdentifier,
              let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: end)) ?? end
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let options: HKStatisticsOptions = metric.cumulative ? .cumulativeSum : .discreteAverage
        let unit = metric.hkUnit
        let cumulative = metric.cumulative
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: pred, options: options,
                                                anchorDate: start, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var out: [DailyValue] = []
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let q = cumulative ? stats.sumQuantity() : stats.averageQuantity()
                    if let v = q?.doubleValue(for: unit) { out.append(DailyValue(date: stats.startDate, value: v)) }
                }
                cont.resume(returning: out)
            }
            self.store.execute(q)
        }
    }

    // MARK: Body characteristics (onboarding prefill)

    public func characteristics() async -> BodyCharacteristics {
        var c = BodyCharacteristics()
        guard isAvailable, isAuthorized else { return c }
        if let dob = try? store.dateOfBirthComponents(), let y = dob.year { c.birthYear = y }
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex { case .female: c.sex = .female; case .male: c.sex = .male; default: c.sex = nil }
        }
        if let h = await latest(.height, unit: .meterUnit(with: .centi)) { c.heightCm = h }
        if let w = await latest(.bodyMass, unit: .gramUnit(with: .kilo)) { c.weightKg = w }
        return c
    }

    // MARK: Workouts (used by the anchored synchronization pipeline)

    nonisolated static func workout(_ w: HKWorkout) -> Workout {
        let kind = Self.mapWorkoutType(w.workoutActivityType)
        let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let kcal = energy ?? 0
        let dist = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
            ?? w.statistics(for: HKQuantityType(.distanceSwimming))?.sumQuantity()?.doubleValue(for: .meter())
        let hr = w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
        var workout = Workout(id: w.uuid.uuidString, kind: kind, title: Self.workoutName(w.workoutActivityType), start: w.startDate,
                       duration: w.duration, activeCalories: kcal, distanceM: dist, avgHR: hr, source: .healthKit)
        workout.energyKnown = energy != nil; workout.energyIsEstimate = false
        return workout
    }

    nonisolated public static func mapWorkoutType(_ t: HKWorkoutActivityType) -> WorkoutKind {
        switch t {
        case .running: return .run; case .cycling: return .ride; case .swimming: return .swim
        case .walking: return .walk; case .hiking: return .hike
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: return .strength
        case .highIntensityIntervalTraining, .crossTraining: return .hiit; case .yoga, .pilates, .mindAndBody: return .yoga
        case .rowing: return .row; default: return .other
        }
    }

    nonisolated static func workoutName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Run"; case .cycling: return "Ride"; case .swimming: return "Swim"
        case .walking: return "Walk"; case .hiking: return "Hike"
        case .traditionalStrengthTraining: return "Strength"; case .functionalStrengthTraining: return "Functional strength"
        case .coreTraining: return "Core"; case .highIntensityIntervalTraining: return "HIIT"; case .crossTraining: return "Cross training"
        case .yoga: return "Yoga"; case .pilates: return "Pilates"; case .rowing: return "Row"; case .tennis: return "Tennis"
        case .soccer: return "Football"; case .basketball: return "Basketball"; case .dance, .socialDance, .cardioDance: return "Dance"
        case .elliptical: return "Elliptical"; case .stairClimbing: return "Stairs"; case .climbing: return "Climbing"
        default: return "Workout"
        }
    }

    // Checked write-back and source-owned verification live in
    // HealthWriteHealthAdapter; only durable journal claims reach HealthKit.

    // MARK: Query helpers

    private func standHoursReading(start: Date, end: Date, operation: HealthReadingQueryGroup) async throws -> HealthMetricReading {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            return .init(healthQuery: .init(start: start, end: end, checkedAt: Date(), outcome: .failed))
        }
        let gate = HealthReadingQuery<HealthMetricReading>()
        let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak gate] query, samples, error in
            #if DEBUG && targetEnvironment(simulator)
            HealthDailyCacheSDKCallbackObservation.record(identifier: "stand", kind: "sample", error: error)
            #endif
            let samples = ((samples as? [HKCategorySample]) ?? []).filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue || $0.value == HKCategoryValueAppleStandHour.idle.rawValue }
            let events = samples.map { CurrentHealthEvidence.StandHourEvent(start: $0.startDate, stood: $0.value == HKCategoryValueAppleStandHour.stood.rawValue) }
            let count = CurrentHealthEvidence.standHours(events, start: start, end: end)
            let checkedAt = Date()
            let check = HealthMetricQuery(start: start, end: end, checkedAt: checkedAt, outcome: Self.queryFailed(error) ? .failed : error != nil || count == nil ? .noData : .recorded)
            guard error == nil, let count else { Self.deliverReading(gate, query: query, reading: .init(healthQuery: check)); return }
            let names = Set(samples.map { $0.sourceRevision.source.name }).sorted().joined(separator: ", ")
            let component = HealthMetricComponent(value: count, origin: .healthKit, source: names.isEmpty ? "Apple Health" : "Apple Health · " + names, start: start, end: end, checkedAt: checkedAt, aggregation: .total)
            Self.deliverReading(gate, query: query, reading: .init(components: [component], healthQuery: check))
        }
        return try await reading(query, gate: gate, operation: operation, start: start, end: end)
    }

    /// Query time and aggregation window are separate from a latest sample's actual date.
    /// Empty reads never establish denied or granted read authorization.
    private func quantityReading(_ id: HKQuantityTypeIdentifier, unit: HKUnit, aggregation: HealthMetricComponent.Aggregation, start: Date, end: Date, excludingLumen: Bool, multiplier: Double, operation: HealthReadingQueryGroup) async throws -> HealthMetricReading {
        let dates = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = excludingLumen ? NSCompoundPredicate(andPredicateWithSubpredicates: [dates, NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))]) : dates
        let gate = HealthReadingQuery<HealthMetricReading>()
        let query: HKQuery
        if aggregation == .latest {
            query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { [weak gate] query, samples, error in
                #if DEBUG && targetEnvironment(simulator)
                HealthDailyCacheSDKCallbackObservation.record(identifier: id.rawValue, kind: "sample", error: error)
                #endif
                let sample = samples?.first as? HKQuantitySample
                Self.deliverReading(gate, query: query, reading: Self.quantityResult(sample?.quantity.doubleValue(for: unit), source: sample.map { "Apple Health · " + $0.sourceRevision.source.name } ?? "Apple Health", sampleStart: sample?.startDate, sampleEnd: sample?.endDate, error: error, multiplier: multiplier, aggregation: aggregation, start: start, end: end))
            }
        } else {
            let options: HKStatisticsOptions = aggregation == .total ? .cumulativeSum : .discreteAverage
            query = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: options) { [weak gate] query, statistics, error in
                #if DEBUG && targetEnvironment(simulator)
                HealthDailyCacheSDKCallbackObservation.record(identifier: id.rawValue, kind: "statistics", error: error)
                #endif
                let quantity = aggregation == .total ? statistics?.sumQuantity() : statistics?.averageQuantity()
                let names = statistics?.sources?.map(\.name).sorted().joined(separator: ", ") ?? ""
                Self.deliverReading(gate, query: query, reading: Self.quantityResult(quantity?.doubleValue(for: unit), source: names.isEmpty ? "Apple Health" : "Apple Health · " + names, error: error, multiplier: multiplier, aggregation: aggregation, start: start, end: end))
            }
        }
        return try await reading(query, gate: gate, operation: operation, start: start, end: end)
    }

    /// Statistics queries report an empty predicate with HKError.errorNoData.
    /// That is unknown data, not a failed check or proof of read permission.
    nonisolated private static func queryFailed(_ error: Error?) -> Bool {
        guard let error else { return false }
        let platformError = error as NSError
        return platformError.domain != HKErrorDomain || platformError.code != HKError.Code.errorNoData.rawValue
    }

    nonisolated static func quantityResult(_ value: Double?, source: String, sampleStart: Date? = nil,
                                                   sampleEnd: Date? = nil, error: Error?, multiplier: Double,
                                                   aggregation: HealthMetricComponent.Aggregation, start: Date, end: Date) -> HealthMetricReading {
        let checkedAt = Date()
        let failed = queryFailed(error)
        // Ignore any accompanying quantity on an error, including no-data.
        let usable = error == nil ? value.flatMap { $0.isFinite && $0 >= 0 ? $0 * multiplier : nil } : nil
        let outcome: HealthMetricQuery.Outcome = failed ? .failed : usable == nil ? .noData : .recorded
        let query = HealthMetricQuery(start: start, end: end, checkedAt: checkedAt, outcome: outcome)
        guard let usable, !failed else { return .init(healthQuery: query) }
        let component = HealthMetricComponent(value: usable, origin: .healthKit, source: source, start: sampleStart ?? start, end: sampleEnd ?? end, lastSampleAt: sampleEnd, checkedAt: checkedAt, aggregation: aggregation)
        return .init(components: [component], healthQuery: query)
    }

    nonisolated private static func deliverReading(_ gate: HealthReadingQuery<HealthMetricReading>?, query: HKQuery, reading: HealthMetricReading) {
        #if DEBUG && targetEnvironment(simulator)
        if HealthDailyCacheSDKInterruptionFixture.hold(query: query, delivery: { [weak gate] in gate?.complete(.success(reading)) }) { return }
        #endif
        gate?.complete(.success(reading))
    }

    private func reading(_ query: HKQuery, gate: HealthReadingQuery<HealthMetricReading>,
                         operation: HealthReadingQueryGroup, start: Date, end: Date) async throws -> HealthMetricReading {
        let cancellation = operation.register { gate.cancel() }
        defer { operation.detach(cancellation) }
        let store = self.store
        do {
            return try await gate.value(start: {
                #if DEBUG && targetEnvironment(simulator)
                HealthDailyCacheSDKInterruptionFixture.executed(query)
                #endif
                store.execute(query)
            }, stop: {
                store.stop(query)
                #if DEBUG && targetEnvironment(simulator)
                HealthDailyCacheSDKInterruptionFixture.stopped(query)
                #endif
            })
        } catch is CancellationError { throw CancellationError() }
        catch {
            try operation.checkCancellation()
            return .init(healthQuery: .init(start: start, end: end, checkedAt: Date(), outcome: .failed))
        }
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date, excludingLumen: Bool = false) async -> Double? {
        let dates = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let pred = excludingLumen ? NSCompoundPredicate(andPredicateWithSubpredicates: [dates, NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))]) : dates
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            self.store.execute(q)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit, todayOnly: Bool = false) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let freshness: NSPredicate? = (todayOnly || id == .restingHeartRate || id == .heartRateVariabilitySDNN || id == .oxygenSaturation || id == .respiratoryRate)
                ? HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate) : nil
            let q = HKSampleQuery(sampleType: HKQuantityType(id), predicate: freshness, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            self.store.execute(q)
        }
    }

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            self.store.execute(q)
        }
    }
}
