import Foundation
import HealthKit

@MainActor
public final class HealthKitExtended: ObservableObject {
    public static let shared = HealthKitExtended()
    @Published public var isAuthorized = false
    @Published public var status = "Not connected"
    @Published public var today = DayMetrics.empty

    private let store = HKHealthStore()
    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {}

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        let quantities: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime, .appleStandTime, .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate, .oxygenSaturation, .vo2Max, .bodyMass, .bodyFatPercentage, .leanBodyMass, .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber, .dietarySugar, .dietaryWater, .dietaryCaffeine]
        for id in quantities { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { s.insert(mindful) }
        s.insert(HKObjectType.workoutType())
        return s
    }

    private var shareTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>()
        let quantities: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber, .dietarySugar, .dietaryWater, .dietaryCaffeine, .bodyMass]
        for id in quantities { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let m = HKObjectType.categoryType(forIdentifier: .mindfulSession) { s.insert(m) }
        s.insert(HKObjectType.workoutType())
        return s
    }

    public func requestAuthorization() async {
        guard isAvailable else { status = "HealthKit unavailable (Simulator?) — demo data on"; return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
            status = "Connected"
            await refreshToday()
        } catch {
            status = "Denied — manual + demo still work"
        }
    }

    public func refreshToday() async {
        guard isAvailable, isAuthorized else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
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
        let (s, a, b, e, st, w, rh, hv, ox, wt) = await (steps, active, basal, exercise, stand, water, rhr, hrv, spo2, weight)
        today.date = start
        today.steps = s ?? 0; today.activeCalories = a ?? 0; today.restingCalories = b ?? 0
        today.exerciseMin = e ?? 0; today.standHours = Int((st ?? 0).rounded())
        today.restingHR = rh; today.hrvMS = hv
        if let ox { today.spo2 = ox * 100 }
        today.weightKg = wt; today.waterML = w ?? 0
        today.avgHR = await average(.heartRate, unit: HKUnit(from: "count/min"), start: start, end: end)
        status = "Synced \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            self.store.execute(q)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            self.store.execute(q)
        }
    }

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            self.store.execute(q)
        }
    }

    public func fetchWorkouts(days: Int = 30) async -> [Workout] {
        guard isAvailable, isAuthorized else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 200, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKWorkout] else { cont.resume(returning: []); return }
                let out: [Workout] = samples.map { w in
                    let kind = Self.mapWorkoutType(w.workoutActivityType)
                    let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? kind.met * (w.duration / 3600) * 75
                    let dist = w.totalDistance?.doubleValue(for: .meter())
                    return Workout(kind: kind, title: Self.workoutName(w.workoutActivityType), start: w.startDate, duration: w.duration, activeCalories: kcal, distanceM: dist, source: .healthKit)
                }
                cont.resume(returning: out)
            }
            self.store.execute(q)
        }
    }

    public static func mapWorkoutType(_ t: HKWorkoutActivityType) -> WorkoutKind {
        switch t {
        case .running: return .run; case .cycling: return .ride; case .swimming: return .swim
        case .walking: return .walk; case .hiking: return .hike
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
        case .highIntensityIntervalTraining: return .hiit; case .yoga: return .yoga
        case .rowing: return .row; default: return .other
        }
    }

    static func workoutName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Run"; case .cycling: return "Ride"; case .swimming: return "Swim"
        case .walking: return "Walk"; case .hiking: return "Hike"
        case .traditionalStrengthTraining: return "Strength"; case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"; case .rowing: return "Row"; default: return "Workout"
        }
    }

    public func saveMeal(_ meal: Meal) async {
        guard isAvailable, isAuthorized else { return }
        let now = meal.date
        func qty(_ id: HKQuantityTypeIdentifier, _ value: Double, _ unit: HKUnit) -> HKQuantitySample? {
            guard let t = HKQuantityType.quantityType(forIdentifier: id), value > 0 else { return nil }
            return HKQuantitySample(type: t, quantity: HKQuantity(unit: unit, doubleValue: value), start: now, end: now)
        }
        var samples: [HKQuantitySample] = []
        if let s = qty(.dietaryEnergyConsumed, meal.calories, .kilocalorie()) { samples.append(s) }
        if let s = qty(.dietaryProtein, meal.protein, .gram()) { samples.append(s) }
        if let s = qty(.dietaryCarbohydrates, meal.carbs, .gram()) { samples.append(s) }
        if let s = qty(.dietaryFatTotal, meal.fat, .gram()) { samples.append(s) }
        if let s = qty(.dietaryFiber, meal.fiber, .gram()) { samples.append(s) }
        guard !samples.isEmpty else { return }
        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.save(samples) { _, err in err == nil ? cont.resume() : cont.resume(throwing: err!) }
        }
    }

    public func saveWater(ml: Double) async {
        guard isAvailable, isAuthorized, let t = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let s = HKQuantitySample(type: t, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml), start: Date(), end: Date())
        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.save(s) { _, err in err == nil ? cont.resume() : cont.resume(throwing: err!) }
        }
    }
}
