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
        case .exercise: return "Exercise"; case .restingHR: return "Resting HR"; case .hrv: return "HRV"; case .weight: return "Weight"
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

    private let store = HKHealthStore()
    private let connectedKey = "lumen.health.connected"
    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {
        // HealthKit never reveals read permission, so we remember that the user
        // went through the sheet and simply query — denied types come back empty.
        let connected = UserDefaults.standard.bool(forKey: connectedKey) && HKHealthStore.isHealthDataAvailable()
        isAuthorized = connected
        status = connected ? "Connected" : "Not connected"
    }

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        let quantities: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime, .appleStandTime, .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate, .oxygenSaturation, .vo2Max, .bodyMass, .height, .bodyFatPercentage, .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber, .dietaryWater, .dietaryCaffeine]
        for id in quantities { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(t) }
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
            status = "Connected"
            return true
        } catch {
            status = "Couldn't connect — try again from Settings"
            return false
        }
    }

    public func disconnectLocally() {
        UserDefaults.standard.set(false, forKey: connectedKey)
        sleepBackfilled = false
        isAuthorized = false
        status = "Paused — manage access in the Health app"
    }

    // MARK: Today

    public func refreshToday() async {
        guard isAvailable, isAuthorized else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        async let steps = sum(.stepCount, unit: .count(), start: start, end: end)
        async let active = sum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let basal = sum(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let exercise = sum(.appleExerciseTime, unit: .minute(), start: start, end: end)
        async let stand = sum(.appleStandTime, unit: .hour(), start: start, end: end)
        async let water = sum(.dietaryWater, unit: .literUnit(with: .milli), start: start, end: end)
        async let rhr = latest(.restingHeartRate, unit: HKUnit(from: "count/min"))
        async let hrv = latest(.heartRateVariabilitySDNN, unit: HKUnit(from: "ms"))
        async let spo2 = latest(.oxygenSaturation, unit: .percent())
        async let weight = latest(.bodyMass, unit: .gramUnit(with: .kilo))
        async let resp = latest(.respiratoryRate, unit: HKUnit(from: "count/min"))
        async let vo2 = latest(.vo2Max, unit: HKUnit(from: "ml/kg*min"))
        async let avgHR = average(.heartRate, unit: HKUnit(from: "count/min"), start: start, end: end)
        let (s, a, b, e, st, w) = await (steps, active, basal, exercise, stand, water)
        let (rh, hv, ox, wt, rr, v2, ah) = await (rhr, hrv, spo2, weight, resp, vo2, avgHR)
        var m = DayMetrics.empty
        m.date = start
        m.steps = s ?? 0; m.activeCalories = a ?? 0; m.restingCalories = b ?? 0
        m.exerciseMin = e ?? 0; m.standHours = Int((st ?? 0).rounded())
        m.restingHR = rh; m.hrvMS = hv; m.respiratoryRate = rr; m.vo2max = v2; m.avgHR = ah
        if let ox { m.spo2 = ox * 100 }
        m.weightKg = wt; m.waterML = w ?? 0
        today = m
        status = "Synced \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
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

    // MARK: Sleep (with stages)

    /// Nightly sleep from Health, one episode per night. Overlapping samples from
    /// several sources (phone + watch) are unioned so nothing is double-counted.
    /// Full history on first connect, then a short rolling window.
    public static let historyDays = 730
    public var sleepBackfilled: Bool {
        get { UserDefaults.standard.bool(forKey: "lumen.health.sleepBackfilled") }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.health.sleepBackfilled") }
    }

    public func fetchSleep(days: Int = 30) async -> [SleepEpisode] {
        guard isAvailable, isAuthorized,
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        // Years of Watch nights can be tens of thousands of samples — cluster off the main thread.
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: Self.episodes(from: (s as? [HKCategorySample]) ?? []))
            }
            self.store.execute(q)
        }
    }

    nonisolated static func episodes(from samples: [HKCategorySample]) -> [SleepEpisode] {
        typealias V = HKCategoryValueSleepAnalysis
        let asleepValues: Set<Int> = [V.asleepUnspecified.rawValue, V.asleepCore.rawValue, V.asleepDeep.rawValue, V.asleepREM.rawValue]
        let asleep = samples.filter { asleepValues.contains($0.value) }.sorted { $0.startDate < $1.startDate }

        // Cluster into nights: gaps under 2h stay in the same night.
        var clusters: [[HKCategorySample]] = []
        var lastEnd: Date?
        for s in asleep {
            if let e = lastEnd, s.startDate.timeIntervalSince(e) < 2 * 3600 {
                clusters[clusters.count - 1].append(s)
            } else {
                clusters.append([s])
            }
            lastEnd = max(lastEnd ?? s.endDate, s.endDate)
        }

        func unionSeconds(_ items: [HKCategorySample]) -> Double {
            var total = 0.0; var curS: Date?; var curE: Date?
            for s in items.sorted(by: { $0.startDate < $1.startDate }) {
                if let cs = curS, let ce = curE, s.startDate <= ce {
                    curE = max(ce, s.endDate); _ = cs
                } else {
                    if let cs = curS, let ce = curE { total += ce.timeIntervalSince(cs) }
                    curS = s.startDate; curE = s.endDate
                }
            }
            if let cs = curS, let ce = curE { total += ce.timeIntervalSince(cs) }
            return total
        }

        var out: [SleepEpisode] = []
        for c in clusters {
            guard let bed = c.map(\.startDate).min(), let wake = c.map(\.endDate).max() else { continue }
            let asleepSecs = unionSeconds(c)
            guard asleepSecs >= 3 * 3600 else { continue } // naps are not nights
            // Stage totals from the richest source (usually the watch).
            let bySource = Dictionary(grouping: c) { $0.sourceRevision.source.bundleIdentifier }
            let staged = bySource.values.max { a, b in
                a.filter { $0.value != V.asleepUnspecified.rawValue }.count < b.filter { $0.value != V.asleepUnspecified.rawValue }.count
            } ?? c
            func stage(_ v: V) -> Double? {
                let secs = staged.filter { $0.value == v.rawValue }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                return secs > 0 ? secs : nil
            }
            let awakeInside = samples.filter { $0.value == V.awake.rawValue && $0.startDate >= bed && $0.endDate <= wake }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            var ep = SleepEpisode(bedtime: bed, wakeTime: wake, source: .wearable)
            ep.asleepSeconds = asleepSecs
            ep.deepSeconds = stage(.asleepDeep)
            ep.remSeconds = stage(.asleepREM)
            ep.coreSeconds = stage(.asleepCore)
            ep.awakeSeconds = awakeInside > 0 ? awakeInside : nil
            out.append(ep)
        }
        return out
    }

    // MARK: Workouts

    public func fetchWorkouts(days: Int = 30) async -> [Workout] {
        guard isAvailable, isAuthorized else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 300, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKWorkout] else { cont.resume(returning: []); return }
                let out: [Workout] = samples.map { w in
                    let kind = Self.mapWorkoutType(w.workoutActivityType)
                    let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                    let kcal = energy ?? kind.met * (w.duration / 3600) * 75
                    let dist = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                        ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
                        ?? w.statistics(for: HKQuantityType(.distanceSwimming))?.sumQuantity()?.doubleValue(for: .meter())
                    let hr = w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                    return Workout(id: w.uuid.uuidString, kind: kind, title: Self.workoutName(w.workoutActivityType), start: w.startDate,
                                   duration: w.duration, activeCalories: kcal, distanceM: dist, avgHR: hr, source: .healthKit)
                }
                cont.resume(returning: out)
            }
            self.store.execute(q)
        }
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

    public func saveWater(ml: Double) async {
        guard isAvailable, isAuthorized else { return }
        let s = HKQuantitySample(type: HKQuantityType(.dietaryWater), quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml), start: Date(), end: Date())
        try? await store.save(s)
    }

    public func saveWeight(kg: Double) async {
        guard isAvailable, isAuthorized else { return }
        let s = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: Date(), end: Date())
        try? await store.save(s)
    }

    // MARK: Query helpers

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            self.store.execute(q)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKQuantityType(id), predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
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
