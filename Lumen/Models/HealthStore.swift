import Foundation
import SwiftUI

// MARK: - Health store: activity, nutrition, hydration, coaching (local-first)
// Real data only. Apple Health is read on launch / foreground.
// Conversational confirmations and manual workouts stay local; quick water,
// meals and weight use the existing optional HealthKit write paths.

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
    private var sleepEpisodes: [SleepEpisode] = []
    public var assistantSleepDebt: Double? { CurrentHealthEvidence.estimatedSleepDebt(sleepEpisodes, sleepNeed: sleepNeed) }

    public var healthConnected: Bool { HealthKitService.shared.isAuthorized }
    /// Actual returned Health readings, independent of completing an access request.
    public var usingLiveData: Bool { metrics.readings?.values.contains { $0.value != nil && $0.components.contains { $0.origin == .healthKit } } ?? false }

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

    private func today<T>(_ items: [T], _ date: (T) -> Date) -> [T] {
        let now = Date(), calendar = Calendar.current
        return items.filter { date($0) <= now && calendar.isDate(date($0), inSameDayAs: now) }
    }
    public var mealsToday: [Meal] { today(meals.filter { $0.source != .sample }, \.date).sorted { $0.date < $1.date } }
    public var caloriesEaten: Double { metrics.reading("calories").value ?? 0 }
    public var proteinEaten: Double { metrics.reading("protein").value ?? 0 }
    public var carbsEaten: Double { metrics.reading("carbs").value ?? 0 }
    public var fatEaten: Double { metrics.reading("fat").value ?? 0 }
    public var waterTodayML: Double { metrics.waterML }
    public var workoutsToday: [Workout] { today(workouts.filter { $0.source != .sample }, \.start) }
    public var caloriesRemaining: Int { max(0, goals.calorieTarget() - Int(caloriesEaten)) }
    public var moveProgress: Double { min(1, metrics.activeCalories / max(1, goals.activeCalGoal)) }
    public var isCalibrating: Bool { readiness == nil }
    public var hasActivityToday: Bool { ["steps", "exercise", "activeEnergy", "stand"].contains { metrics.reading($0).value != nil } || !workoutsToday.isEmpty }
    public var hasFoodToday: Bool { ["calories", "protein", "carbs", "fat"].contains { metrics.reading($0).value != nil } }
    public var activitySummary: String {
        for key in ["steps", "exercise", "activeEnergy"] { if let value = metrics.reading(key).value { return HealthMetricCatalog.display(value, key: key) } }
        if !workoutsToday.isEmpty { return "\(workoutsToday.count) workout\(workoutsToday.count == 1 ? "" : "s") logged" }
        return "No activity reading"
    }

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
        if last.logOrigin != nil {
            do { try correctConfirmedWater(last.id, draft: nil) }
            catch { AppRouter.shared.confirm("Couldn’t remove water. Try again.") }
            return
        }
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
        if workouts.first(where: { $0.id == id }).map(LocalHealthCorrection.canEdit) == true {
            do { try correctConfirmedWorkout(id, draft: nil) }
            catch { AppRouter.shared.confirm("Couldn’t remove workout. Try again.") }
            return
        }
        workouts.removeAll { $0.id == id && $0.source == .manual && $0.importOrigin == nil }
        persist(); refresh()
    }

    /// Confirmed conversational entries are local-only. Corrections never call HealthKit.
    func correctConfirmedWater(_ id: String, draft: HealthLogDraft?) throws {
        let records = try LocalHealthCorrection.water(id: id, draft: draft, records: waterLogs)
        try LocalStore.saveChecked(records, as: "water")
        waterLogs = records; refresh()
    }

    func correctConfirmedWorkout(_ id: String, draft: HealthLogDraft?) throws {
        let records = try LocalHealthCorrection.workout(id: id, draft: draft, records: workouts)
        try LocalStore.saveChecked(records, as: "workouts")
        workouts = records; refresh()
    }

    public func logWeight(kg: Double) {
        guard kg.isFinite, kg > 0, kg <= 1000 else { return }
        goals.weightKg = kg
        if !Calendar.current.isDateInToday(healthSnapshot.date) { healthSnapshot = .empty }
        if healthSnapshot.readings == nil { healthSnapshot = CurrentHealthEvidence.resolve(snapshot: healthSnapshot, imported: nil, meals: [], water: [], workouts: [], sleep: nil) }
        let now = Date()
        healthSnapshot.setReading(.init(components: [.init(value: kg, origin: .localLog, source: "Lumen weight log", start: now, end: now, lastSampleAt: now, aggregation: .latest)]), for: "weight")
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

    func reloadAfterRestore() {
        goals = LocalStore.load(HealthGoals.self, from: "goals") ?? goals
        meals = LocalStore.load([Meal].self, from: "meals") ?? meals
        workouts = LocalStore.load([Workout].self, from: "workouts") ?? workouts
        waterLogs = LocalStore.load([HydrationLog].self, from: "water") ?? waterLogs
        conversationReady = false
        conversations = LocalStore.load([HealthConversation].self, from: "conversations") ?? conversations
        if !conversations.contains(where: { $0.id == activeConversationID }) { activeConversationID = nil }
        chat = conversations.first { $0.id == activeConversationID }?.messages ?? []
        conversationReady = true
        UserDefaults.standard.set(activeConversationID, forKey: "lumen.conversation.active")
        LocalStore.save(chat, as: "chat")
        refresh()
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
            healthSnapshot = CurrentHealthEvidence.merging(hk.today, into: healthSnapshot)
            if let w = healthSnapshot.weightKg { goals.weightKg = (w * 10).rounded() / 10 }
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
        workouts = WorkoutReconciliation.merge(incoming, into: workouts)
    }

    func importWorkouts(_ incoming: [Workout], filename: String) {
        let records = incoming.map { original in
            var workout = original; workout.importOrigin?.filename = filename; return workout
        }
        mergeWorkouts(records); persist(); refresh()
    }

    func clearImportedWorkouts() {
        workouts.removeAll { $0.importOrigin != nil }; persist(); refresh()
    }

    // MARK: Coaching

    /// Called by the sleep side whenever debt / need / last night change.
    public func recompute(sleepDebt: TimeInterval, sleepNeed: TimeInterval, sleepEpisodes: [SleepEpisode]) {
        self.sleepDebt = sleepDebt
        self.sleepNeed = sleepNeed
        self.sleepEpisodes = sleepEpisodes
        refresh()
    }

    public func refresh() {
        let m = CurrentHealthEvidence.resolve(snapshot: healthSnapshot, imported: CompanionStore.shared.todayImport, meals: meals, water: waterLogs, workouts: workouts, sleep: sleepEpisodes.max { $0.wakeTime < $1.wakeTime })
        metrics = m

        // Readiness needs at least one body signal — no guessing on day one.
        let hasSignal = m.sleepSeconds != nil || m.hrvMS != nil || m.restingHR != nil
        readiness = hasSignal ? CoachingEngine.readiness(metrics: m, sleepDebt: assistantSleepDebt, workoutsToday: workoutsToday, goals: goals, hrvBaseline: hrvBaseline, restingHRBaseline: restingHRBaseline) : nil
        plan = CoachingEngine.dayPlan(metrics: m, readiness: readiness, goals: goals, sleepDebt: assistantSleepDebt, eaten: caloriesEaten, protein: proteinEaten, waterML: waterTodayML)
        let perspective = CompanionStore.shared.perspective(health: self)
        plan?.briefing = perspective.body
        if !CompanionStore.shared.activeSymptoms.isEmpty {
            plan?.bullets = ["Check how you feel before activity; keep your plans flexible.", "Keep notes on symptom timing and changes.", "For symptoms that persist, worsen or concern you, contact a clinician."]
            plan?.workoutSuggestion = "Check symptoms before exercise"
        }
        insights = CoachingEngine.insights(metrics: m, readiness: readiness, goals: goals, mealsToday: mealsToday, workoutsToday: workoutsToday, sleepDebt: assistantSleepDebt)

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
        healthSnapshot = .empty; lastSync = nil; hrvBaseline = nil; restingHRBaseline = nil; sleepEpisodes = []; sleepDebt = 0
        refresh()
    }
}
