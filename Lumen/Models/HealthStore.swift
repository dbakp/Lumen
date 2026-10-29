import Foundation
import SwiftUI

// MARK: - Health store: activity, nutrition, hydration, coaching (local-first)
// Real data only. Apple Health is read on launch / foreground; everything the
// user logs lives on-device and is written back to Health when connected.

@MainActor
public final class HealthStore: ObservableObject {
    public static let shared = HealthStore()

    @Published public var goals = HealthGoals()
    /// Today's numbers: Health snapshot + anything logged in Lumen.
    @Published public private(set) var metrics = DayMetrics.empty
    @Published public var workouts: [Workout] = []
    @Published public var meals: [Meal] = []
    @Published public var waterLogs: [HydrationLog] = []
    @Published public var readiness: Readiness?
    @Published public var plan: DayPlan?
    @Published public var insights: [Insight] = []
    @Published public var lastSync: Date?
    @Published public var isSyncing = false
    @Published public var chat: [ChatMessage] = [] { didSet { if conversationReady { saveActiveConversation() } } }
    @Published public private(set) var conversations: [HealthConversation] = []
    @Published public private(set) var activeConversationID: String?
    private var conversationReady = false

    /// Last Health snapshot for today (persisted so launch is instant).
    private var healthSnapshot = DayMetrics.empty
    private var hrvBaseline: Double?
    private var restingHRBaseline: Double?
    private var sleepDebt: TimeInterval = 0
    private var sleepNeed: TimeInterval = 8 * 3600 + 10 * 60
    private var lastSleepSeconds: Double?

    public var healthConnected: Bool { HealthKitService.shared.isAuthorized }
    /// True when numbers come from a connected source rather than manual logs only.
    public var usingLiveData: Bool { healthConnected || StravaService.shared.isConnected }

    public init() {
        goals = LocalStore.load(HealthGoals.self, from: "goals", legacyKey: "lumen.health.goals.v1") ?? HealthGoals()
        meals = (LocalStore.load([Meal].self, from: "meals", legacyKey: "lumen.health.meals.v1") ?? [])
            .filter { $0.source != .sample }
        workouts = (LocalStore.load([Workout].self, from: "workouts", legacyKey: "lumen.health.workouts.v1") ?? [])
            .filter { $0.source != .sample }
        waterLogs = (LocalStore.load([HydrationLog].self, from: "water") ?? [])
        chat = LocalStore.load([ChatMessage].self, from: "chat", legacyKey: "lumen.health.chat.v1") ?? []
        conversations = ConversationArchive.migrate(legacy: chat, existing: LocalStore.load([HealthConversation].self, from: "conversations") ?? [])
        let rememberedID = UserDefaults.standard.string(forKey: "lumen.conversation.active")
        let selected = conversations.first { $0.id == rememberedID } ?? conversations.max { $0.updatedAt < $1.updatedAt }
        activeConversationID = selected?.id
        chat = selected?.messages ?? []
        conversationReady = true
        LocalStore.save(conversations, as: "conversations")
        if let snap = LocalStore.load(DayMetrics.self, from: "today"), Calendar.current.isDateInToday(snap.date) {
            healthSnapshot = snap
        }
        lastSync = AppGroup.defaults.object(forKey: "health.lastSync") as? Date
        refresh()
    }

    // MARK: Derived

    private func today<T>(_ items: [T], _ date: (T) -> Date) -> [T] { items.filter { Calendar.current.isDateInToday(date($0)) } }
    public var mealsToday: [Meal] { today(meals, \.date).sorted { $0.date < $1.date } }
    public var caloriesEaten: Double { HealthTotals.nutrient(local: mealsToday.reduce(0) { $0 + $1.calories }, external: metrics.dietaryCalories, imported: CompanionStore.shared.todayImport?.values["calories"], excludesLumen: metrics.excludesLumenNutrition == true) }
    public var proteinEaten: Double { HealthTotals.nutrient(local: mealsToday.reduce(0) { $0 + $1.protein }, external: metrics.dietaryProtein, imported: CompanionStore.shared.todayImport?.values["protein"], excludesLumen: metrics.excludesLumenNutrition == true) }
    public var carbsEaten: Double { HealthTotals.nutrient(local: mealsToday.reduce(0) { $0 + $1.carbs }, external: metrics.dietaryCarbs, imported: CompanionStore.shared.todayImport?.values["carbs"], excludesLumen: metrics.excludesLumenNutrition == true) }
    public var fatEaten: Double { HealthTotals.nutrient(local: mealsToday.reduce(0) { $0 + $1.fat }, external: metrics.dietaryFat, imported: CompanionStore.shared.todayImport?.values["fat"], excludesLumen: metrics.excludesLumenNutrition == true) }
    public var waterTodayML: Double { metrics.waterML }
    public var workoutsToday: [Workout] { today(workouts, \.start) }
    public var caloriesRemaining: Int { max(0, goals.calorieTarget() - Int(caloriesEaten)) }
    public var moveProgress: Double { min(1, metrics.activeCalories / max(1, goals.activeCalGoal)) }
    public var isCalibrating: Bool { readiness == nil }
    public var hasActivityToday: Bool { metrics.steps > 0 || metrics.activeCalories > 0 || !workoutsToday.isEmpty }

    /// Meals grouped by day, newest first (for the nutrition journal).
    public func meals(on day: Date) -> [Meal] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    // MARK: Mutations

    public func addMeal(_ meal: Meal) {
        meals.append(meal)
        Task { await HealthKitService.shared.saveMeal(meal) }
        persist(); refresh()
    }

    public func deleteMeal(_ id: String) {
        PhotoStore.delete(meals.first { $0.id == id }?.photoID)
        meals.removeAll { $0.id == id }
        Task { await HealthKitService.shared.deleteMeal(id: id) }
        persist(); refresh()
    }

    public func addWater(ml: Double) {
        guard ml.isFinite, ml > 0, ml <= 10000 else { return }
        let log = HydrationLog(ml: ml)
        waterLogs.append(log)
        Task { await HealthKitService.shared.saveWater(ml: ml, id: log.id) }
        persist(); refresh()
    }

    public func undoLastWater() {
        guard let last = today(waterLogs, \.date).max(by: { $0.date < $1.date }) else { return }
        waterLogs.removeAll { $0.id == last.id }
        Task { await HealthKitService.shared.deleteWater(id: last.id) }
        persist(); refresh()
    }

    public func addManualWorkout(kind: WorkoutKind, minutes: Double, kcal: Double? = nil, start: Date = Date()) {
        let w = Workout(kind: kind, title: kind.label, start: start, duration: minutes * 60,
                        activeCalories: kcal ?? kind.met * (minutes / 60) * (goals.weightKg ?? 75), source: .manual)
        workouts.append(w)
        workouts.sort { $0.start < $1.start }
        persist(); refresh()
    }

    public func deleteWorkout(_ id: String) {
        workouts.removeAll { $0.id == id && $0.source == .manual }
        persist(); refresh()
    }

    public func logWeight(kg: Double) {
        goals.weightKg = kg
        healthSnapshot.weightKg = kg
        Task { await HealthKitService.shared.saveWeight(kg: kg) }
        persist(); refresh()
    }

    public func updateGoals(_ g: HealthGoals) {
        goals = g
        persist(); refresh()
    }

    public func persist() {
        LocalStore.save(meals, as: "meals")
        LocalStore.save(workouts, as: "workouts")
        LocalStore.save(goals, as: "goals")
        LocalStore.save(conversations, as: "conversations")
        LocalStore.save(chat, as: "chat")
        LocalStore.save(waterLogs, as: "water")
        LocalStore.save(healthSnapshot, as: "today")
    }

    // MARK: Conversations

    private func saveActiveConversation() {
        guard conversationReady else { return }
        if activeConversationID == nil {
            guard !chat.isEmpty else { return }
            let conversation = HealthConversation(title: ConversationArchive.suggestedTitle(chat), messages: chat)
            conversations.insert(conversation, at: 0); activeConversationID = conversation.id
        } else if let index = conversations.firstIndex(where: { $0.id == activeConversationID }) {
            conversations[index].messages = chat
            conversations[index].updatedAt = Date()
            if conversations[index].title == "New conversation" { conversations[index].title = ConversationArchive.suggestedTitle(chat) }
        }
        UserDefaults.standard.set(activeConversationID, forKey: "lumen.conversation.active")
        LocalStore.save(conversations, as: "conversations"); LocalStore.save(chat, as: "chat")
    }

    @discardableResult public func ensureConversation() -> String {
        if let activeConversationID { return activeConversationID }
        let conversation = HealthConversation()
        conversations.insert(conversation, at: 0); activeConversationID = conversation.id
        saveActiveConversation(); return conversation.id
    }

    public func newConversation() {
        guard !chat.isEmpty else { return }
        selectConversation(nil)
    }

    public func selectConversation(_ id: String?) {
        guard id == nil || conversations.contains(where: { $0.id == id }) else { return }
        conversationReady = false
        activeConversationID = id
        chat = conversations.first { $0.id == id }?.messages ?? []
        conversationReady = true
        UserDefaults.standard.set(id, forKey: "lumen.conversation.active")
        LocalStore.save(chat, as: "chat")
    }

    public func renameConversation(_ id: String, title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = String(title.prefix(100)); LocalStore.save(conversations, as: "conversations")
    }

    public func deleteConversation(_ id: String) {
        conversations.removeAll { $0.id == id }
        if activeConversationID == id { selectConversation(nil) }
        LocalStore.save(conversations, as: "conversations")
    }

    @discardableResult public func appendMessage(_ message: ChatMessage, to id: String) -> Bool {
        guard conversations.contains(where: { $0.id == id }) else { return false }
        if activeConversationID == id { chat.append(message) }
        else {
            conversations = ConversationArchive.appending(message, to: id, in: conversations)
            LocalStore.save(conversations, as: "conversations")
        }
        return true
    }

    // MARK: Sync

    public func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }
        let hk = HealthKitService.shared
        if hk.isAuthorized {
            await hk.refreshToday()
            healthSnapshot = hk.today
            if let w = hk.today.weightKg { goals.weightKg = (w * 10).rounded() / 10 }
            mergeWorkouts(await hk.fetchWorkouts(days: 60))
            let hrvDays = await hk.dailySeries(.hrv, days: 30).filter { !Calendar.current.isDateInToday($0.date) }
            let hrDays = await hk.dailySeries(.restingHR, days: 30).filter { !Calendar.current.isDateInToday($0.date) }
            hrvBaseline = hrvDays.count >= 7 ? hrvDays.map(\.value).reduce(0, +) / Double(hrvDays.count) : nil
            restingHRBaseline = hrDays.count >= 7 ? hrDays.map(\.value).reduce(0, +) / Double(hrDays.count) : nil
        }
        if StravaService.shared.isConnected {
            await StravaService.shared.sync()
            mergeWorkouts(StravaService.shared.activities)
        }
        lastSync = Date()
        AppGroup.defaults.set(lastSync, forKey: "health.lastSync")
        persist(); refresh()
    }

    private func mergeWorkouts(_ incoming: [Workout]) {
        for w in incoming {
            if let i = workouts.firstIndex(where: { $0.id == w.id }) { workouts[i] = w; continue }
            if let sid = w.stravaID, workouts.contains(where: { $0.stravaID == sid }) { continue }
            // Same session recorded by two sources: keep the first non-manual copy.
            if workouts.contains(where: { $0.overlaps(w) && $0.kind == w.kind && $0.source != .manual }) { continue }
            workouts.append(w)
        }
        workouts.sort { $0.start < $1.start }
    }

    // MARK: Coaching

    /// Called by the sleep side whenever debt / need / last night change.
    public func recompute(sleepDebt: TimeInterval, sleepNeed: TimeInterval, lastSleepSeconds: Double? = nil) {
        self.sleepDebt = sleepDebt
        self.sleepNeed = sleepNeed
        self.lastSleepSeconds = lastSleepSeconds
        refresh()
    }

    public func refresh() {
        var m = Calendar.current.isDateInToday(healthSnapshot.date) ? healthSnapshot : .empty
        if let imported = CompanionStore.shared.todayImport?.values {
            if m.steps == 0 { m.steps = imported["steps"] ?? 0 }
            if m.activeCalories == 0 { m.activeCalories = imported["activeEnergy"] ?? 0 }
            if m.exerciseMin == 0 { m.exerciseMin = imported["exercise"] ?? 0 }
            m.restingHR = m.restingHR ?? imported["restingHR"]
            m.hrvMS = m.hrvMS ?? imported["hrv"]
            m.weightKg = m.weightKg ?? imported["weight"]
        }
        // Manual sessions aren't in Health's activity totals — add them.
        let manual = workoutsToday.filter { $0.source == .manual }
        if CompanionStore.shared.todayImport?.values["activeEnergy"] == nil || healthConnected { m.activeCalories += manual.reduce(0) { $0 + $1.activeCalories } }
        if CompanionStore.shared.todayImport?.values["exercise"] == nil || healthConnected { m.exerciseMin += manual.reduce(0) { $0 + $1.duration / 60 } }
        let logged = today(waterLogs, \.date).reduce(0) { $0 + $1.ml }
        // Health already includes water we wrote back; take the larger to avoid double count.
        m.waterML = HealthTotals.water(local: logged, snapshot: m.waterML, imported: CompanionStore.shared.todayImport?.values["water"], excludesLumen: m.excludesLumenNutrition == true)
        m.sleepSeconds = lastSleepSeconds ?? CompanionStore.shared.todayImport?.values["sleep"].map { $0 * 3600 }
        if m.weightKg == nil { m.weightKg = goals.weightKg }
        metrics = m

        // Readiness needs at least one body signal — no guessing on day one.
        let hasSignal = m.sleepSeconds != nil || m.hrvMS != nil || m.restingHR != nil
        readiness = hasSignal ? CoachingEngine.readiness(metrics: m, sleepDebt: sleepDebt, workoutsToday: workoutsToday, goals: goals, hrvBaseline: hrvBaseline, restingHRBaseline: restingHRBaseline) : nil
        plan = CoachingEngine.dayPlan(metrics: m, readiness: readiness, goals: goals, sleepDebt: sleepDebt, eaten: caloriesEaten, protein: proteinEaten, waterML: waterTodayML)
        let perspective = CompanionStore.shared.perspective(health: self)
        plan?.briefing = perspective.body
        if !CompanionStore.shared.activeSymptoms.isEmpty {
            plan?.bullets = ["Check how you feel before activity; keep your plans flexible.", "Keep notes on symptom timing and changes.", "For symptoms that persist, worsen or concern you, contact a clinician."]
            plan?.workoutSuggestion = "Check symptoms before exercise"
        }
        insights = CoachingEngine.insights(metrics: m, readiness: readiness, goals: goals, mealsToday: mealsToday, workoutsToday: workoutsToday, sleepDebt: sleepDebt)

        let d = AppGroup.defaults
        d.set(readiness?.score ?? 0, forKey: "widget.readiness")
        d.set(Int(caloriesEaten), forKey: "widget.eaten")
        d.set(goals.calorieTarget(), forKey: "widget.target")
        d.set(Int(proteinEaten), forKey: "widget.protein")
        d.set(goals.proteinTarget(), forKey: "widget.proteinTarget")
        d.set(m.steps, forKey: "widget.steps")
        d.set(moveProgress, forKey: "widget.move")
        WidgetBridge.reload()
        WatchSync.shared.scheduleSend()
        NotificationManager.shared.refreshContext(health: self)
    }

    /// Start over: clears every log (Health data itself is untouched).
    public func resetAll() {
        conversationReady = false
        goals = HealthGoals(); meals = []; workouts = []; waterLogs = []; chat = []
        conversations = []; activeConversationID = nil
        UserDefaults.standard.removeObject(forKey: "lumen.conversation.active")
        conversationReady = true
        CompanionStore.shared.reset()
        healthSnapshot = .empty; lastSync = nil; hrvBaseline = nil; restingHRBaseline = nil
        refresh()
    }
}
