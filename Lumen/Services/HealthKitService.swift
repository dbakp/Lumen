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
        return s
    }

    /// Presents the Health permission sheet. Returns true if the user went through it.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard isAvailable else { status = "Health isn't available on this device"; return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            UserDefaults.standard.set(true, forKey: connectedKey)
            isAuthorized = true
            UserDefaults.standard.set(UUID().uuidString, forKey: "lumen.health.rescan")
            status = "Access requested"
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
        guard isAvailable, isAuthorized else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        async let r0 = quantityReading(.stepCount, unit: .count(), aggregation: .total, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r1 = quantityReading(.activeEnergyBurned, unit: .kilocalorie(), aggregation: .total, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r2 = quantityReading(.basalEnergyBurned, unit: .kilocalorie(), aggregation: .total, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r3 = quantityReading(.appleExerciseTime, unit: .minute(), aggregation: .total, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r4 = standHoursReading(start: start, end: end)
        async let r5 = quantityReading(.dietaryWater, unit: .literUnit(with: .milli), aggregation: .total, start: start, end: end, excludingLumen: true, multiplier: 1)
        async let r6 = quantityReading(.restingHeartRate, unit: HKUnit(from: "count/min"), aggregation: .latest, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r7 = quantityReading(.heartRateVariabilitySDNN, unit: HKUnit(from: "ms"), aggregation: .latest, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r8 = quantityReading(.oxygenSaturation, unit: .percent(), aggregation: .latest, start: start, end: end, excludingLumen: false, multiplier: 100)
        async let r9 = quantityReading(.bodyMass, unit: .gramUnit(with: .kilo), aggregation: .latest, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r10 = quantityReading(.respiratoryRate, unit: HKUnit(from: "count/min"), aggregation: .latest, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r11 = quantityReading(.vo2Max, unit: HKUnit(from: "ml/(kg*min)"), aggregation: .latest, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r12 = quantityReading(.heartRate, unit: HKUnit(from: "count/min"), aggregation: .average, start: start, end: end, excludingLumen: false, multiplier: 1)
        async let r13 = quantityReading(.bodyFatPercentage, unit: .percent(), aggregation: .latest, start: start, end: end, excludingLumen: false, multiplier: 100)
        async let r14 = quantityReading(.dietaryEnergyConsumed, unit: .kilocalorie(), aggregation: .total, start: start, end: end, excludingLumen: true, multiplier: 1)
        async let r15 = quantityReading(.dietaryProtein, unit: .gram(), aggregation: .total, start: start, end: end, excludingLumen: true, multiplier: 1)
        async let r16 = quantityReading(.dietaryCarbohydrates, unit: .gram(), aggregation: .total, start: start, end: end, excludingLumen: true, multiplier: 1)
        async let r17 = quantityReading(.dietaryFatTotal, unit: .gram(), aggregation: .total, start: start, end: end, excludingLumen: true, multiplier: 1)
        var m = DayMetrics.empty; m.date = start; m.readings = [:]; m.recordedTotalKeys = []
        m.setReading(await r0, for: "steps")
        m.setReading(await r1, for: "activeEnergy")
        m.setReading(await r2, for: "restingEnergy")
        m.setReading(await r3, for: "exercise")
        m.setReading(await r4, for: "stand")
        m.setReading(await r5, for: "water")
        m.setReading(await r6, for: "restingHR")
        m.setReading(await r7, for: "hrv")
        m.setReading(await r8, for: "spo2")
        m.setReading(await r9, for: "weight")
        m.setReading(await r10, for: "respiratoryRate")
        m.setReading(await r11, for: "vo2max")
        m.setReading(await r12, for: "heartRate")
        m.setReading(await r13, for: "bodyFat")
        m.setReading(await r14, for: "calories")
        m.setReading(await r15, for: "protein")
        m.setReading(await r16, for: "carbs")
        m.setReading(await r17, for: "fat")
        m.excludesLumenNutrition = true
        today = m
        let available = m.readings?.values.filter { $0.value != nil }.count ?? 0
        status = "Checked \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)) · \(available) metrics returned"
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

    // MARK: Write-back

    public func saveMeal(_ meal: Meal) async {
        guard isAvailable, isAuthorized else { return }
        let t = meal.date
        func qty(_ id: HKQuantityTypeIdentifier, _ value: Double, _ unit: HKUnit) -> HKQuantitySample? {
            guard value > 0 else { return nil }
            return HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value), start: t, end: t,
                                    metadata: ["LumenMealID": meal.id])
        }
        let samples = [qty(.dietaryEnergyConsumed, meal.calories, .kilocalorie()), qty(.dietaryProtein, meal.protein, .gram()),
                       qty(.dietaryCarbohydrates, meal.carbs, .gram()), qty(.dietaryFatTotal, meal.fat, .gram()),
                       qty(.dietaryFiber, meal.fiber, .gram())].compactMap { $0 }
        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    public func deleteMeal(id: String) async {
        guard isAvailable, isAuthorized else { return }
        let pred = HKQuery.predicateForObjects(withMetadataKey: "LumenMealID", allowedValues: [id])
        for t in [HKQuantityTypeIdentifier.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber] {
            _ = try? await store.deleteObjects(of: HKQuantityType(t), predicate: pred)
        }
    }

    public func saveWater(ml: Double, id: String? = nil) async {
        guard isAvailable, isAuthorized else { return }
        let s = HKQuantitySample(type: HKQuantityType(.dietaryWater), quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml), start: Date(), end: Date(), metadata: id.map { ["LumenWaterID": $0] })
        try? await store.save(s)
    }

    public func deleteWater(id: String) async throws -> Int? {
        guard isAvailable, isAuthorized else { return nil }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: "LumenWaterID", allowedValues: [id])
        return try await store.deleteObjects(of: HKQuantityType(.dietaryWater), predicate: predicate)
    }

    public func saveWeight(kg: Double) async {
        guard isAvailable, isAuthorized else { return }
        let s = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: Date(), end: Date())
        try? await store.save(s)
    }

    // MARK: Query helpers

    private func standHoursReading(start: Date, end: Date) async -> HealthMetricReading {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            return .init(healthQuery: .init(start: start, end: end, checkedAt: Date(), outcome: .failed))
        }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                let samples = ((samples as? [HKCategorySample]) ?? []).filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue || $0.value == HKCategoryValueAppleStandHour.idle.rawValue }
                let events = samples.map { CurrentHealthEvidence.StandHourEvent(start: $0.startDate, stood: $0.value == HKCategoryValueAppleStandHour.stood.rawValue) }
                let count = CurrentHealthEvidence.standHours(events, start: start, end: end)
                let checkedAt = Date()
                let check = HealthMetricQuery(start: start, end: end, checkedAt: checkedAt, outcome: error != nil ? .failed : count == nil ? .noData : .recorded)
                guard error == nil, let count else { continuation.resume(returning: .init(healthQuery: check)); return }
                let names = Set(samples.map { $0.sourceRevision.source.name }).sorted().joined(separator: ", ")
                let component = HealthMetricComponent(value: count, origin: .healthKit, source: names.isEmpty ? "Apple Health" : "Apple Health · " + names, start: start, end: end, checkedAt: checkedAt, aggregation: .total)
                continuation.resume(returning: .init(components: [component], healthQuery: check))
            }
            self.store.execute(query)
        }
    }

    /// Query time and aggregation window are separate from a latest sample's actual date.
    /// Empty reads never establish denied or granted read authorization.
    private func quantityReading(_ id: HKQuantityTypeIdentifier, unit: HKUnit, aggregation: HealthMetricComponent.Aggregation, start: Date, end: Date, excludingLumen: Bool, multiplier: Double) async -> HealthMetricReading {
        let dates = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = excludingLumen ? NSCompoundPredicate(andPredicateWithSubpredicates: [dates, NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))]) : dates
        return await withCheckedContinuation { continuation in
            func result(_ value: Double?, source: String, sampleStart: Date? = nil, sampleEnd: Date? = nil, failed: Bool) -> HealthMetricReading {
                let checkedAt = Date()
                let usable = value.flatMap { $0.isFinite && $0 >= 0 ? $0 * multiplier : nil }
                let outcome: HealthMetricQuery.Outcome = failed ? .failed : usable == nil ? .noData : .recorded
                let query = HealthMetricQuery(start: start, end: end, checkedAt: checkedAt, outcome: outcome)
                guard let usable, !failed else { return .init(healthQuery: query) }
                let component = HealthMetricComponent(value: usable, origin: .healthKit, source: source, start: sampleStart ?? start, end: sampleEnd ?? end, lastSampleAt: sampleEnd, checkedAt: checkedAt, aggregation: aggregation)
                return .init(components: [component], healthQuery: query)
            }
            if aggregation == .latest {
                let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                    let sample = samples?.first as? HKQuantitySample
                    continuation.resume(returning: result(sample?.quantity.doubleValue(for: unit), source: sample.map { "Apple Health · " + $0.sourceRevision.source.name } ?? "Apple Health", sampleStart: sample?.startDate, sampleEnd: sample?.endDate, failed: error != nil))
                }
                self.store.execute(query)
            } else {
                let options: HKStatisticsOptions = aggregation == .total ? .cumulativeSum : .discreteAverage
                let query = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: options) { _, statistics, error in
                    let quantity = aggregation == .total ? statistics?.sumQuantity() : statistics?.averageQuantity()
                    let names = statistics?.sources?.map(\.name).sorted().joined(separator: ", ") ?? ""
                    continuation.resume(returning: result(quantity?.doubleValue(for: unit), source: names.isEmpty ? "Apple Health" : "Apple Health · " + names, failed: error != nil))
                }
                self.store.execute(query)
            }
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
