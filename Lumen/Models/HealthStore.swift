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
    @Published public private(set) var waterUndoStatus: String?
    @Published var watchWaterSaveFailure: String?
    private var waterUndoOperation = UUID()
    private let healthWrites = OrderedHealthWrites()
    @Published public var readiness: Readiness?
    @Published public var plan: DayPlan?
    @Published public var insights: [Insight] = []
    @Published public var lastSync: Date?
    @Published public var isSyncing = false
    @Published public private(set) var chat: [ChatMessage] = []
    @Published public private(set) var conversations: [HealthConversation] = []
    @Published public private(set) var activeConversationID: String?
    @Published public private(set) var conversationReady = false
    @Published public private(set) var isConversationSaving = false
    @Published public private(set) var conversationStorageIssue: String?
    @Published private(set) var pendingConversationReplies: [PendingConversationReply] = []
    private var conversationOperation = UUID()
    private var conversationGeneration = UUID()
    private var conversationLifetimes: [String: UUID] = [:]
    private var conversationReplyCancellations: [String: (owner: ConversationReplyOwner, cancel: () -> Void)] = [:]

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
        if let snap = LocalStore.load(DayMetrics.self, from: "today"), Calendar.current.isDateInToday(snap.date) {
            healthSnapshot = snap
        }
        lastSync = AppGroup.defaults.object(forKey: "health.lastSync") as? Date
        refresh()
        let operation = conversationOperation
        Task { if self.conversationOperation == operation { await self.openConversationsChecked() } }
    }

    // MARK: Derived

    private func today<T>(_ items: [T], _ date: (T) -> Date) -> [T] {
        let now = Date(), calendar = Calendar.current
        return items.filter { date($0) <= now && calendar.isDate(date($0), inSameDayAs: now) }
    }
    public var displayEvidence: DisplayEvidence {
        var values: [String: Double] = [:], estimates: Set<String> = []
        for key in HealthMetricCatalog.keys {
            let reading = metrics.reading(key)
            if let value = reading.value { values[key] = value; if reading.isEstimate { estimates.insert(key) } }
        }
        if let readiness { values["readiness"] = Double(readiness.score); estimates.insert("readiness") }
        if let debt = assistantSleepDebt { values["sleepDebt"] = debt / 3600; estimates.insert("sleepDebt") }
        return .init(day: metrics.date, capturedAt: Date(), values: values, estimates: estimates)
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

    public func addMeal(_ meal: Meal, photo: UIImage? = nil) throws {
        guard !meals.contains(where: { $0.id == meal.id }) else { throw BackupError.invalid }
        var saved = meal
        var ownedPhoto: String?
        if let photo {
            let id = UUID().uuidString
            try PhotoStore.saveNewChecked(photo, id: id)
            ownedPhoto = id; saved.photoID = id
        }
        let records = meals + [saved]
        do { try LocalStore.saveChecked(records, as: "meals") }
        catch { PhotoStore.delete(ownedPhoto); throw error }
        meals = records
        healthWrites.enqueueSave(.meal(meal.id), isCurrent: { [weak self] in
            self?.meals.contains(where: { $0.id == meal.id }) == true
        }) {
            await HealthKitService.shared.saveMeal(meal)
        }
        refresh()
    }

    public func deleteMeal(_ id: String) throws {
        let photoIDs = Set(meals.filter { $0.id == id }.compactMap(\.photoID))
        let remaining = meals.filter { $0.id != id }
        guard remaining.count != meals.count else { return }
        try LocalStore.saveChecked(remaining, as: "meals")
        meals = remaining
        for photoID in photoIDs where !remaining.contains(where: { $0.photoID == photoID }) { PhotoStore.delete(photoID) }
        healthWrites.enqueue(.meal(id)) { await HealthKitService.shared.deleteMeal(id: id) }
        refresh()
    }

    public func addWater(ml: Double) throws {
        guard ml.isFinite, ml > 0, ml <= 10000 else { throw BackupError.invalid }
        let log = HydrationLog(ml: ml)
        let records = waterLogs + [log]
        try LocalStore.saveChecked(records, as: "water")
        waterUndoOperation = UUID(); waterUndoStatus = nil
        waterLogs = records
        healthWrites.enqueueSave(.water(log.id), isCurrent: { [weak self] in
            self?.waterLogs.contains(where: { $0.id == log.id && $0.logOrigin == nil }) == true
        }) {
            await HealthKitService.shared.saveWater(ml: ml, id: log.id, at: log.date)
        }
        refresh()
    }

    public var canUndoQuickWater: Bool { LocalHealthCorrection.latestQuickWater(waterLogs) != nil }
    public func undoLastWater() throws {
        guard let last = LocalHealthCorrection.latestQuickWater(waterLogs) else { return }
        let remaining = waterLogs.filter { $0.id != last.id }
        try LocalStore.saveChecked(remaining, as: "water")
        waterLogs = remaining; refresh()
        let operation = UUID(); waterUndoOperation = operation
        waterUndoStatus = "Removed from Lumen. Checking Apple Health…"
        healthWrites.enqueue(.water(last.id)) { [weak self] in
            let status: String
            do {
                if let count = try await HealthKitService.shared.deleteWater(id: last.id) {
                    status = count > 0 ? "Removed from Lumen and Apple Health." : "Removed from Lumen. No matching Apple Health entry was removed."
                } else { status = "Removed from Lumen. No Apple Health removal was attempted." }
            } catch { status = "Removed from Lumen. Apple Health removal failed; check the entry in Health." }
            guard let self, self.waterUndoOperation == operation else { return }
            self.waterUndoStatus = status
        }
    }

    public func addManualWorkout(kind: WorkoutKind, minutes: Double, kcal: Double? = nil, start: Date = Date()) throws {
        guard minutes.isFinite, minutes > 0, minutes <= 1440,
              start.timeIntervalSince1970.isFinite, start <= Date(),
              kcal.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw BackupError.invalid }
        let w = Workout(kind: kind, title: kind.label, start: start, duration: minutes * 60,
                        activeCalories: kcal ?? kind.met * (minutes / 60) * (goals.weightKg ?? 75), source: .manual)
        let records = (workouts + [w]).sorted { $0.start < $1.start }
        try LocalStore.saveChecked(records, as: "workouts")
        workouts = records; refresh()
    }

    public func deleteWorkout(_ id: String) throws {
        if workouts.first(where: { $0.id == id }).map(LocalHealthCorrection.canEdit) == true {
            try correctConfirmedWorkout(id, draft: nil)
            return
        }
        let records = workouts.filter { !($0.id == id && $0.source == .manual && $0.importOrigin == nil) }
        guard records.count != workouts.count else { return }
        try LocalStore.saveChecked(records, as: "workouts")
        workouts = records; refresh()
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

    public func logWeight(kg: Double) async throws {
        guard kg.isFinite, kg > 0, kg <= 1000 else { throw BackupError.invalid }
        // A refresh can change the in-memory snapshot before its final disk
        // write. The storage revision alone cannot detect that suspended state.
        if isSyncing {
            #if DEBUG && targetEnvironment(simulator)
            QuickWeightSyncFixture.release()
            #endif
            throw BackupError.busy
        }
        var savedGoals = goals, snapshot = healthSnapshot
        savedGoals.weightKg = kg
        if !Calendar.current.isDateInToday(snapshot.date) { snapshot = .empty }
        if snapshot.readings == nil { snapshot = CurrentHealthEvidence.resolve(snapshot: snapshot, imported: nil, meals: [], water: [], workouts: [], sleep: nil) }
        let now = Date()
        snapshot.setReading(.init(components: [.init(value: kg, origin: .localLog, source: "Lumen weight log", start: now, end: now, lastSampleAt: now, aggregation: .latest)]), for: "weight")
        try await LocalStore.saveWeightChecked(goals: savedGoals, snapshot: snapshot, canCommit: { !self.isSyncing }) {
            goals = savedGoals; healthSnapshot = snapshot
            Task { await HealthKitService.shared.saveWeight(kg: kg, at: now) }
            refresh()
        }
    }

    /// Settings change one field against the latest live goals. Do not publish
    /// a new target or overwrite other record domains when storage rejects it.
    func updateGoalsChecked(_ change: (inout HealthGoals) -> Void) throws {
        var saved = goals; change(&saved)
        try LocalStore.saveChecked(saved, as: "goals")
        installCheckedGoals(saved)
    }

    func installCheckedGoals(_ saved: HealthGoals) { goals = saved; refresh() }

    public func persist() {
        LocalStore.save(meals, as: "meals")
        LocalStore.save(workouts, as: "workouts")
        LocalStore.save(goals, as: "goals")
        LocalStore.save(waterLogs, as: "water")
        LocalStore.save(healthSnapshot, as: "today")
    }

    func reloadAfterRestore() {
        watchWaterSaveFailure = nil
        // A restore must not start an old queued write using restored content.
        // Already-started Health callbacks cannot be recalled; their record's
        // requested deletion still waits for completion through the same queue.
        healthWrites.invalidatePendingSaves(); waterUndoOperation = UUID(); waterUndoStatus = nil
        goals = LocalStore.load(HealthGoals.self, from: "goals") ?? goals
        meals = LocalStore.load([Meal].self, from: "meals") ?? meals
        workouts = LocalStore.load([Workout].self, from: "workouts") ?? workouts
        waterLogs = LocalStore.load([HydrationLog].self, from: "water") ?? waterLogs
        invalidateConversationWork()
        do {
            let loaded = try LocalStore.loadConversationsChecked()
            guard !loaded.needsMigration else { throw BackupError.currentDataInvalid }
            installConversations(loaded.conversations, activeID: loaded.selection?.activeID)
            conversationReady = true; conversationStorageIssue = nil
        } catch { conversationStorageIssue = Self.conversationOpenFailure }
        refresh()
    }

    // MARK: Conversations

    private static let conversationOpenFailure = "Saved conversations couldn't be opened. Retry before sending or changing history. Your saved history hasn't been replaced."

    func openConversationsChecked() async {
        guard !isConversationSaving else { return }
        let operation = UUID(); conversationOperation = operation
        isConversationSaving = true; conversationReady = false; conversationStorageIssue = nil
        cancelObsoleteConversationReplies()
        defer { if conversationOperation == operation { isConversationSaving = false } }
        for attempt in 0..<5 {
            guard conversationOperation == operation else { return }
            do {
                let loaded = try LocalStore.loadConversationsChecked()
                let selected: String?
                if let selection = loaded.selection { selected = selection.activeID }
                else {
                    let remembered = UserDefaults.standard.string(forKey: "lumen.conversation.active")
                    selected = loaded.conversations.first(where: { $0.id == remembered })?.id
                        ?? loaded.conversations.max(by: { $0.updatedAt < $1.updatedAt })?.id
                }
                if loaded.needsMigration || loaded.selection == nil {
                    try await LocalStore.saveConversationsChecked(loaded.conversations, activeID: selected,
                        canCommit: { self.conversationOperation == operation }, didCommit: {
                            self.installConversations(loaded.conversations, activeID: selected)
                            self.conversationReady = true
                        })
                } else {
                    guard conversationOperation == operation else { return }
                    installConversations(loaded.conversations, activeID: selected); conversationReady = true
                }
                return
            } catch BackupError.recordsChanged where attempt < 4 {
                // Startup and Health refresh can write other domains together.
                // Discard the obsolete stage and re-read current files; never
                // retry decoding or I/O failures as if history were absent.
                guard conversationOperation == operation else { return }
                do { try await Task.sleep(for: .milliseconds(25 * (attempt + 1))) }
                catch { return }
            } catch {
                if conversationOperation == operation { conversationStorageIssue = Self.conversationOpenFailure }
                return
            }
        }
    }

    private func installConversations(_ saved: [HealthConversation], activeID: String?) {
        conversations = saved; activeConversationID = activeID
        chat = saved.first(where: { $0.id == activeID })?.messages ?? []
        conversationLifetimes = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, conversationLifetimes[$0.id] ?? UUID()) })
        UserDefaults.standard.set(activeID, forKey: "lumen.conversation.active")
        cancelObsoleteConversationReplies()
    }

    private func invalidateConversationWork() {
        conversationOperation = UUID(); conversationGeneration = UUID(); conversationLifetimes = [:]
        conversationReady = false; isConversationSaving = false; pendingConversationReplies = []
        cancelObsoleteConversationReplies()
    }

    private func commitConversations(_ saved: [HealthConversation], activeID: String?, didCommit: () -> Void = {}) async throws {
        guard conversationReady, !isConversationSaving else { throw ConversationSaveError.notReady }
        let operation = UUID(); conversationOperation = operation; isConversationSaving = true
        defer { if conversationOperation == operation { isConversationSaving = false } }
        try await LocalStore.saveConversationsChecked(saved, activeID: activeID,
            canCommit: { self.conversationOperation == operation && self.conversationReady }, didCommit: {
                self.installConversations(saved, activeID: activeID); didCommit()
            })
    }

    public func newConversation() async throws { try await selectConversation(nil) }

    public func selectConversation(_ id: String?) async throws {
        guard id == nil || conversations.contains(where: { $0.id == id }) else { throw ConversationSaveError.changed }
        try await commitConversations(conversations, activeID: id)
    }

    public func renameConversation(_ id: String, title: String, expectedTitle: String? = nil) async throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = conversations.firstIndex(where: { $0.id == id }) else { throw ConversationSaveError.changed }
        if let expectedTitle, conversations[index].title != expectedTitle { throw ConversationSaveError.changed }
        var saved = conversations; saved[index].title = String(title.prefix(100))
        try await commitConversations(saved, activeID: activeConversationID)
    }

    public func deleteConversation(_ id: String) async throws {
        guard conversations.contains(where: { $0.id == id }) else { throw ConversationSaveError.changed }
        try await commitConversations(conversations.filter { $0.id != id }, activeID: activeConversationID == id ? nil : activeConversationID) {
            self.pendingConversationReplies.removeAll { $0.owner.conversationID == id }
        }
    }

    public func clearConversationChecked() async throws {
        guard let id = activeConversationID, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        var saved = conversations; saved[index].messages = []; saved[index].updatedAt = Date()
        try await commitConversations(saved, activeID: id) {
            self.conversationLifetimes[id] = UUID()
            self.pendingConversationReplies.removeAll { $0.owner.conversationID == id }
        }
    }

    func sendUserMessageChecked(_ message: ChatMessage, expectedConversationID: String?) async throws -> ConversationSend {
        guard activeConversationID == expectedConversationID, message.role == .user,
              pendingConversationReplies.isEmpty else { throw ConversationSaveError.changed }
        let history = chat
        var saved = conversations
        let id: String
        if let activeConversationID {
            id = activeConversationID; saved = ConversationArchive.appending(message, to: id, in: saved)
        } else {
            let conversation = HealthConversation(title: ConversationArchive.suggestedTitle([message]), messages: [message])
            id = conversation.id; saved.insert(conversation, at: 0)
        }
        var owner: ConversationReplyOwner?
        try await commitConversations(saved, activeID: id) {
            if let lifetime = self.conversationLifetimes[id] {
                owner = .init(conversationID: id, lifetime: lifetime, generation: self.conversationGeneration, questionID: message.id)
            }
        }
        guard let owner else { throw ConversationSaveError.changed }
        return ConversationSend(owner: owner, history: history)
    }

    func ownsReply(_ owner: ConversationReplyOwner) -> Bool {
        conversationReady && owner.generation == conversationGeneration && conversationLifetimes[owner.conversationID] == owner.lifetime
            && conversations.first(where: { $0.id == owner.conversationID })?.messages.last(where: { $0.role == .user })?.id == owner.questionID
    }

    /// The store owns invalidation even if reset removes the Assistant view.
    /// Navigation and rename preserve a request to its still-intact origin.
    func registerConversationReplyCancellation(_ owner: ConversationReplyOwner, cancel: @escaping () -> Void) -> Bool {
        guard ownsReply(owner) else { cancel(); return false }
        conversationReplyCancellations[owner.questionID] = (owner, cancel)
        return true
    }

    func finishConversationReply(_ owner: ConversationReplyOwner) {
        if conversationReplyCancellations[owner.questionID]?.owner == owner {
            conversationReplyCancellations.removeValue(forKey: owner.questionID)
        }
    }

    private func cancelObsoleteConversationReplies() {
        let obsolete = conversationReplyCancellations.filter { !ownsReply($0.value.owner) }
        for key in obsolete.keys { conversationReplyCancellations.removeValue(forKey: key) }
        for entry in obsolete.values { entry.cancel() }
    }

    func retainConversationReply(_ message: ChatMessage, owner: ConversationReplyOwner, savePlan: Bool) -> String? {
        guard ownsReply(owner), message.role == .coach else { return nil }
        let pending = PendingConversationReply(message: message, owner: owner, savePlan: savePlan)
        pendingConversationReplies.append(pending); return pending.id
    }

    func discardConversationReply(_ id: String) { pendingConversationReplies.removeAll { $0.id == id } }

    func savePendingConversationReply(_ id: String) async throws -> PendingConversationReply {
        guard let pending = pendingConversationReplies.first(where: { $0.id == id }), ownsReply(pending.owner) else { throw ConversationSaveError.changed }
        let saved = ConversationArchive.appending(pending.message, to: pending.owner.conversationID, in: conversations)
        try await commitConversations(saved, activeID: activeConversationID) {
            self.pendingConversationReplies.removeAll { $0.id == id }
        }
        return pending
    }

    // MARK: Sync

    func installHealthWorkouts(_ values: [Workout]) { workouts = values }

    public func syncAll() async {
        await SyncCoordinator.syncEverything(sleep: SleepStore.shared, health: self)
    }

    func refreshSources(includeProviders: Bool) async {
        let session = HealthBackgroundSync.shared.generation
        let hk = HealthKitService.shared
        if hk.isAuthorized {
            await hk.refreshToday()
            guard hk.isAuthorized, HealthBackgroundSync.shared.generation == session else { return }
            healthSnapshot = CurrentHealthEvidence.merging(hk.today, into: healthSnapshot)
            if let w = healthSnapshot.weightKg { goals.weightKg = (w * 10).rounded() / 10 }
            // Workouts are applied by the durable anchored pipeline.
            let hrvDays = await hk.dailySeries(.hrv, days: 30).filter { !Calendar.current.isDateInToday($0.date) }
            let hrDays = await hk.dailySeries(.restingHR, days: 30).filter { !Calendar.current.isDateInToday($0.date) }
            guard hk.isAuthorized, HealthBackgroundSync.shared.generation == session else { return }
            hrvBaseline = hrvDays.count >= 7 ? hrvDays.map(\.value).reduce(0, +) / Double(hrvDays.count) : nil
            restingHRBaseline = hrDays.count >= 7 ? hrDays.map(\.value).reduce(0, +) / Double(hrDays.count) : nil
        }
        if includeProviders, StravaService.shared.isConnected {
            await StravaService.shared.sync()
            guard HealthBackgroundSync.shared.generation == session else { return }
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
    public func recompute(sleepDebt: TimeInterval, sleepNeed: TimeInterval, sleepEpisodes: [SleepEpisode], birthYear: Int? = nil) {
        let currentGoals = ProfileSettings.refreshedAge(goals: goals, birthYear: birthYear)
        if currentGoals.age != goals.age { goals = currentGoals }
        self.sleepDebt = sleepDebt
        self.sleepNeed = sleepNeed
        self.sleepEpisodes = sleepEpisodes
        refresh()
    }

    public func refresh() {
        let m = CurrentHealthEvidence.resolve(snapshot: healthSnapshot, imported: CompanionStore.shared.todayImport, meals: meals, water: waterLogs, workouts: workouts, sleep: SleepEvidence.today(sleepEpisodes))
        metrics = m

        readiness = CoachingEngine.readinessIfAvailable(metrics: m, sleepDebt: assistantSleepDebt, workoutsToday: workoutsToday, goals: goals, hrvBaseline: hrvBaseline, restingHRBaseline: restingHRBaseline)
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
        d.set(displayEvidence.encoded(), forKey: DisplayEvidence.widgetKey)
        WidgetBridge.reload()
        WatchSync.shared.scheduleSend()
        NotificationManager.shared.refreshContext(health: self)
    }

    /// Start over: clears every log (Health data itself is untouched).
    public func resetAll() {
        watchWaterSaveFailure = nil
        healthWrites.invalidatePendingSaves(); waterUndoOperation = UUID(); waterUndoStatus = nil
        invalidateConversationWork()
        goals = HealthGoals(); meals = []; workouts = []; waterLogs = []; chat = []
        conversations = []; activeConversationID = nil
        UserDefaults.standard.removeObject(forKey: "lumen.conversation.active")
        conversationReady = true; conversationStorageIssue = nil
        CompanionStore.shared.reset()
        healthSnapshot = .empty; lastSync = nil; hrvBaseline = nil; restingHRBaseline = nil; sleepEpisodes = []; sleepDebt = 0
        refresh()
    }
}
