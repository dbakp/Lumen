import Foundation
import SwiftUI

@MainActor
public final class HealthStore: ObservableObject {
    public static let shared = HealthStore()

    @Published public var goals = HealthGoals()
    @Published public var metrics = DayMetrics.empty
    @Published public var workouts: [Workout] = []
    @Published public var meals: [Meal] = []
    @Published public var waterLogs: [HydrationLog] = []
    @Published public var readiness: Readiness?
    @Published public var plan: DayPlan?
    @Published public var insights: [Insight] = []
    @Published public var lastSync: Date?
    @Published public var isSyncing = false
    @Published public var chat: [ChatMessage] = []
    /// True once real HealthKit data has replaced the first-run demo samples.
    @Published public var usingLiveData = false

    private let mealsKey = "lumen.health.meals.v1"
    private let workoutsKey = "lumen.health.workouts.v1"
    private let goalsKey = "lumen.health.goals.v1"
    private let chatKey = "lumen.health.chat.v1"
    private let liveKey = "lumen.health.live.v1"

    public init() {
        if let d = UserDefaults.standard.data(forKey: goalsKey),
           let g = try? JSONDecoder().decode(HealthGoals.self, from: d) { goals = g }
        if let d = UserDefaults.standard.data(forKey: mealsKey),
           let m = try? JSONDecoder().decode([Meal].self, from: d),
           Calendar.current.isDateInToday(m.last?.date ?? .distantPast) { meals = m }
        else { meals = Self.sampleMeals() }
        if !workoutsSeeded() { workouts = Self.sampleWorkouts() }
        metrics = Self.sampleMetrics()
        usingLiveData = UserDefaults.standard.bool(forKey: liveKey)
        if usingLiveData {
            // Don't resurrect demo samples across launches once live.
            workouts.removeAll { $0.source == .sample }
            meals.removeAll { $0.source == .sample }
        }
        if let d = UserDefaults.standard.data(forKey: chatKey),
           let c = try? JSONDecoder().decode([ChatMessage].self, from: d) { chat = c }
        recompute(sleepDebt: 0, sleepNeed: 8*3600+10*60)
    }

    private func workoutsSeeded() -> Bool {
        if let d = UserDefaults.standard.data(forKey: workoutsKey),
           let w = try? JSONDecoder().decode([Workout].self, from: d), !w.isEmpty {
            workouts = w; return true
        }
        return false
    }

    public var caloriesEaten: Double { meals.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    public var proteinEaten: Double { meals.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.protein } }
    public var carbsEaten: Double { meals.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.carbs } }
    public var fatEaten: Double { meals.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.fat } }
    public var waterTodayML: Double {
        let logged = waterLogs.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.ml }
        return max(metrics.waterML, logged)
    }
    public var workoutsToday: [Workout] { workouts.filter { Calendar.current.isDateInToday($0.start) } }
    public var caloriesRemaining: Int { max(0, goals.calorieTarget() - Int(caloriesEaten)) }
    public var moveProgress: Double { min(1, metrics.activeCalories / max(1, goals.activeCalGoal)) }

    public func addMeal(_ meal: Meal) {
        meals.append(meal)
        if meal.source != .sample { goLive() }
        Task { await HealthKitExtended.shared.saveMeal(meal) }
        persist()
        recompute(sleepDebt: 0, sleepNeed: 8*3600)
    }
    public func deleteMeal(_ id: String) {
        meals.removeAll { $0.id == id }; persist()
        recompute(sleepDebt: 0, sleepNeed: 8*3600)
    }
    public func addWater(ml: Double) {
        waterLogs.append(HydrationLog(ml: ml))
        metrics.waterML += ml
        Task { await HealthKitExtended.shared.saveWater(ml: ml) }
        persist()
    }
    public func addManualWorkout(kind: WorkoutKind, minutes: Double, kcal: Double? = nil) {
        let w = Workout(kind: kind, title: "Manual \(kind.label)", start: Date(), duration: minutes*60, activeCalories: kcal ?? kind.met * (minutes/60) * (goals.weightKg ?? 75), source: .manual)
        workouts.append(w); metrics.activeCalories += w.activeCalories; metrics.exerciseMin += minutes
        goLive()
        persist()
        recompute(sleepDebt: 0, sleepNeed: 8*3600)
    }

    public func persist() {
        if let d = try? JSONEncoder().encode(meals) { UserDefaults.standard.set(d, forKey: mealsKey) }
        if let d = try? JSONEncoder().encode(workouts) { UserDefaults.standard.set(d, forKey: workoutsKey) }
        if let d = try? JSONEncoder().encode(goals) { UserDefaults.standard.set(d, forKey: goalsKey) }
        if let d = try? JSONEncoder().encode(chat) { UserDefaults.standard.set(d, forKey: chatKey) }
    }

    public func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }
        await HealthKitExtended.shared.refreshToday()
        let hk = HealthKitExtended.shared
        if hk.isAuthorized {
            metrics.steps = hk.today.steps
            metrics.activeCalories = max(metrics.activeCalories, hk.today.activeCalories)
            metrics.restingCalories = hk.today.restingCalories
            metrics.exerciseMin = max(metrics.exerciseMin, hk.today.exerciseMin)
            metrics.standHours = hk.today.standHours
            metrics.restingHR = hk.today.restingHR
            metrics.hrvMS = hk.today.hrvMS
            metrics.avgHR = hk.today.avgHR ?? metrics.avgHR
            metrics.spo2 = hk.today.spo2 ?? metrics.spo2
            metrics.weightKg = hk.today.weightKg ?? metrics.weightKg
            if hk.today.waterML > 0 { metrics.waterML = max(metrics.waterML, hk.today.waterML) }
            let hkWorkouts = await hk.fetchWorkouts(days: 14)
            mergeWorkouts(hkWorkouts)
            // Real data is in: retire every demo sample so the app never
            // mixes demo numbers with your body. Empty states guide from here.
            goLive()
        }
        if StravaService.shared.isConnected {
            await StravaService.shared.sync()
            mergeWorkouts(StravaService.shared.activities)
            if !StravaService.shared.activities.isEmpty { goLive() }
        }
        lastSync = Date()
        persist()
        recompute(sleepDebt: 0, sleepNeed: 8*3600)
    }

    private func mergeWorkouts(_ incoming: [Workout]) {
        for w in incoming {
            if let sid = w.stravaID, workouts.contains(where: { $0.stravaID == sid }) { continue }
            if workouts.contains(where: { $0.overlaps(w) && $0.source != .manual }) { continue }
            workouts.append(w)
        }
        workouts.sort { $0.start < $1.start }
        if workouts.count > 300 { workouts.removeFirst(workouts.count - 300) }
    }

    /// Drop all `.sample` content and mark this device as live-data mode.
    public func goLive() {
        let hadSamples = workouts.contains(where: { $0.source == .sample }) || meals.contains(where: { $0.source == .sample })
        workouts.removeAll { $0.source == .sample }
        meals.removeAll { $0.source == .sample }
        if !usingLiveData || hadSamples {
            usingLiveData = true
            UserDefaults.standard.set(true, forKey: liveKey)
            persist()
        }
    }

    public func recompute(sleepDebt: TimeInterval, sleepNeed: TimeInterval, lastSleepSeconds: Double? = nil) {
        if let s = lastSleepSeconds { metrics.sleepSeconds = s }
        readiness = CoachingEngine.readiness(metrics: metrics, sleepDebt: sleepDebt, workoutsToday: workoutsToday, goals: goals)
        plan = CoachingEngine.dayPlan(metrics: metrics, readiness: readiness, goals: goals, sleepDebt: sleepDebt, eaten: caloriesEaten, protein: proteinEaten, waterML: waterTodayML)
        insights = CoachingEngine.insights(metrics: metrics, readiness: readiness, goals: goals, mealsToday: meals.filter { Calendar.current.isDateInToday($0.date) }, workoutsToday: workoutsToday, sleepDebt: sleepDebt)
        UserDefaults.standard.set(sleepDebt/3600, forKey: "lumen.widget.debt")
        UserDefaults.standard.set(readiness?.score ?? 70, forKey: "lumen.widget.energy")
    }

    static func sampleMetrics() -> DayMetrics {
        var m = DayMetrics.empty
        m.steps = 7642; m.activeCalories = 486; m.restingCalories = 1650
        m.exerciseMin = 32; m.standHours = 9; m.avgHR = 72; m.restingHR = 58
        m.hrvMS = 62; m.weightKg = 75; m.sleepSeconds = 6.8*3600; m.waterML = 900
        return m
    }
    static func sampleWorkouts() -> [Workout] {
        let now = Date(); let cal = Calendar.current
        func at(dayOffset: Int, hour: Int) -> Date {
            let d = cal.date(byAdding: .day, value: dayOffset, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d) ?? d
        }
        return [
            Workout(kind: .run, title: "Morning Run", start: at(dayOffset: 0, hour: 7), duration: 32*60, activeCalories: 342, distanceM: 5200, avgHR: 148, source: .sample),
            Workout(kind: .strength, title: "Upper Strength", start: at(dayOffset: -1, hour: 18), duration: 45*60, activeCalories: 280, avgHR: 118, source: .sample),
            Workout(kind: .walk, title: "Evening Walk", start: at(dayOffset: -1, hour: 20), duration: 25*60, activeCalories: 110, distanceM: 1800, source: .sample),
            Workout(kind: .ride, title: "Weekend Ride", start: at(dayOffset: -2, hour: 9), duration: 68*60, activeCalories: 640, distanceM: 24500, avgHR: 132, source: .sample),
        ]
    }
    static func sampleMeals() -> [Meal] {
        let cal = Calendar.current; let now = Date()
        func at(hour: Int) -> Date { cal.date(bySettingHour: hour, minute: 15, second: 0, of: now) ?? now }
        return [
            Meal(date: at(hour: 8), type: .breakfast, items: [
                FoodItem(name: "Greek yogurt + berries + honey", grams: 280, calories: 340, proteinG: 28, carbsG: 42, fatG: 6, fiberG: 5, confidence: 0.9),
                FoodItem(name: "Espresso", grams: 60, calories: 5, proteinG: 0, carbsG: 1, fatG: 0, confidence: 0.99),
            ], source: .sample),
            Meal(date: at(hour: 13), type: .lunch, items: [
                FoodItem(name: "Chicken burrito bowl", grams: 450, calories: 640, proteinG: 45, carbsG: 62, fatG: 20, fiberG: 9, confidence: 0.85),
            ], source: .sample),
        ]
    }
}
