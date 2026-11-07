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
    @Published public private(set) var healthWriteStatus: String?
    @Published public private(set) var healthWritePendingCount = 0
    @Published public private(set) var healthWriteNeedsDeviceSetup = false
    @Published public private(set) var localHealthStorageIssue: String?
    @Published public private(set) var healthRefreshIssue: String?
    private var localHealthBoundaries: [HealthLocalFiles.Domain: HealthLocalFiles.Boundary] = [:]
    private var unavailableLocalHealth: Set<HealthLocalFiles.Domain> = []
    @Published var watchWaterSaveFailure: String?
    private lazy var healthWrites = HealthWriteRecovery(
        read: { try LocalStore.healthWriteJournalChecked() },
        commit: { try LocalStore.saveHealthReceiptChecked($0, replacing: $1) },
        operate: {
            #if DEBUG && targetEnvironment(simulator)
            if HealthWriteNativeProbe.requested { try await HealthWriteNativeProbe.operate($0); return }
            #endif
            try await HealthKitService.shared.performDurableWrite($0)
            #if DEBUG && targetEnvironment(simulator)
            HealthWriteLifecycleProbe.recordVerified($0)
            #endif
        },
        changed: { [weak self] in self?.refreshHealthWriteStatus() })
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
    private var healthSourceRefresh = UUID()
    private var dailyCacheOperation = UUID()
    private var dailyCacheControl: BackupOperationControl?
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
        openLocalHealthDomains()
        lastSync = AppGroup.defaults.object(forKey: "health.lastSync") as? Date
        refresh()
        let operation = conversationOperation
        Task { if self.conversationOperation == operation { await self.openConversationsChecked() } }
        refreshHealthWriteStatus()
    }

    private func openLocalHealthDomains() {
        for domain in HealthLocalFiles.Domain.allCases {
            do {
                let boundary: HealthLocalFiles.Boundary
                switch domain {
                case .water:
                    let loaded = try LocalStore.loadHealthDomainChecked([HydrationLog].self, domain: domain)
                    waterLogs = loaded.value ?? []; boundary = loaded.boundary
                case .meals:
                    let loaded = try LocalStore.loadHealthDomainChecked([Meal].self, domain: domain)
                    meals = (loaded.value ?? []).filter { $0.source != .sample }; boundary = loaded.boundary
                case .workouts:
                    let loaded = try LocalStore.loadHealthDomainChecked([Workout].self, domain: domain)
                    workouts = (loaded.value ?? []).filter { $0.source != .sample }; boundary = loaded.boundary
                case .goals:
                    let loaded = try LocalStore.loadHealthDomainChecked(HealthGoals.self, domain: domain)
                    goals = loaded.value ?? HealthGoals(); boundary = loaded.boundary
                case .today:
                    let loaded = try LocalStore.loadHealthDomainChecked(DayMetrics.self, domain: domain)
                    healthSnapshot = loaded.value.flatMap { Calendar.current.isDateInToday($0.date) ? $0 : nil } ?? .empty
                    boundary = loaded.boundary
                }
                localHealthBoundaries[domain] = boundary; unavailableLocalHealth.remove(domain)
            } catch { unavailableLocalHealth.insert(domain) }
        }
        updateLocalHealthIssue()
    }

    private func updateLocalHealthIssue() {
        let names = unavailableLocalHealth.map(\.label).sorted().joined(separator: ", ")
        let subject = names.prefix(1).uppercased() + names.dropFirst()
        localHealthStorageIssue = names.isEmpty ? nil : "\(subject) couldn't be opened. Changes to this data are paused. Lumen hasn't replaced the saved data."
    }

    func localHealthAvailable(_ domain: HealthLocalFiles.Domain) -> Bool {
        localHealthBoundaries[domain] != nil && !unavailableLocalHealth.contains(domain)
    }

    /// A failed read stays unavailable until an explicit checked reload installs
    /// the recovered content. Checking the file alone must not bless stale memory.
    func requireLocalHealthBoundary(_ domain: HealthLocalFiles.Domain) throws -> HealthLocalFiles.Boundary {
        guard localHealthAvailable(domain), let boundary = localHealthBoundaries[domain] else { throw HealthLocalFiles.Failure.unavailable }
        do { try LocalStore.verifyHealthBoundary(boundary, domain: domain); return boundary }
        catch {
            unavailableLocalHealth.insert(domain); updateLocalHealthIssue(); refresh()
            throw error
        }
    }

    func requireAllLocalHealthData() throws {
        for domain in HealthLocalFiles.Domain.allCases { _ = try requireLocalHealthBoundary(domain) }
    }

    func retryLocalHealthDataChecked() throws {
        openLocalHealthDomains(); refresh()
        guard unavailableLocalHealth.isEmpty else { throw HealthLocalFiles.Failure.unavailable }
    }

    func recoverUnavailableHealth(_ payload: HealthRecoverySelection.Payload,
                                  control: BackupOperationControl = .init()) async throws {
        try control.checkCancellation()
        func canCommit() -> Bool {
            conversationReady && !isSyncing && !payload.domains.isEmpty
                && payload.domains.allSatisfy { !localHealthAvailable($0) }
        }
        guard canCommit() else { throw BackupError.recordsChanged }
        try await LocalStore.recoverHealthChecked(payload, control: control, canCommit: canCommit) {
            openLocalHealthDomains()
            refresh()
            retryHealthWrites()
        }
    }

    enum DailyCacheAction { case clear, rebuild }
    enum DailyCacheFailure: Error { case opening, busy, changed }
    struct DailyCachePreview {
        let boundary: HealthDailyCache.Boundary
        let replacement: HealthDailyCache.Replacement
        let readings: HealthTodayReadCoordinator.Readings?
        fileprivate let operation: UUID
        fileprivate let revision: UInt64
        fileprivate let owner: UUID
        fileprivate let source: HealthKitService.DailySourceBoundary
    }

    func inspectDailyCache(control: BackupOperationControl) async throws -> HealthDailyCache.Boundary.State {
        let root = try LocalStore.checkedDirectory(), revision = LocalStore.revision
        let boundary = try await Task.detached(priority: .userInitiated) {
            try HealthDailyCache.capture(in: root, control: control)
        }.value
        try Task.checkCancellation(); try control.checkCancellation()
        guard LocalStore.revision == revision else { throw DailyCacheFailure.changed }
        return boundary.state
    }

    func cancelDailyCacheReview(control: BackupOperationControl) {
        control.cancel()
        guard dailyCacheControl === control else { return }
        dailyCacheControl = nil; dailyCacheOperation = UUID()
    }

    func reviewDailyCache(_ action: DailyCacheAction, control: BackupOperationControl) async throws -> DailyCachePreview {
        try Task.checkCancellation(); try control.checkCancellation()
        guard conversationReady else { throw DailyCacheFailure.opening }
        guard !isSyncing else { throw DailyCacheFailure.busy }
        dailyCacheControl?.cancel()
        let operation = UUID(); dailyCacheOperation = operation; dailyCacheControl = control
        healthSourceRefresh = UUID()
        let hk = HealthKitService.shared
        hk.invalidateTodayQueries()
        do {
            return try await withTaskCancellationHandler {
                let root = try LocalStore.checkedDirectory(), revision = LocalStore.revision
                let owner = try HealthWriteDeviceOwner.current(), initialSource = hk.captureDailySource()
                let boundary = try await Task.detached(priority: .userInitiated) {
                    try HealthDailyCache.capture(in: root, control: control)
                }.value
                try Task.checkCancellation(); try control.checkCancellation()
                guard dailyCacheOperation == operation, LocalStore.revision == revision,
                      hk.dailySourceIsCurrent(initialSource) else { throw DailyCacheFailure.changed }
                let readings: HealthTodayReadCoordinator.Readings?
                let replacement: HealthDailyCache.Replacement
                switch action {
                case .clear:
                    readings = nil; replacement = .clear(day: initialSource.selection.day)
                case .rebuild:
                    let query = Task { try await hk.queryTodayReadings() }
                    control.setCancellationHandler { query.cancel() }
                    do { readings = try await query.value }
                    catch { control.setCancellationHandler(nil); throw error }
                    control.setCancellationHandler(nil)
                    replacement = .rebuild(readings!.raw)
                }
                let source = hk.captureDailySource()
                try await Task.detached(priority: .userInitiated) {
                    try HealthDailyCache.verify(boundary, in: root, control: control)
                }.value
                try Task.checkCancellation(); try control.checkCancellation()
                guard dailyCacheOperation == operation, LocalStore.revision == revision, !isSyncing,
                      try HealthWriteDeviceOwner.current() == owner, hk.dailySourceIsCurrent(source),
                      initialSource.selection.matchesSourceAndDay(source.selection),
                      initialSource.hardwareAvailable == source.hardwareAvailable, initialSource.connected == source.connected,
                      readings.map(hk.readingsAreCurrent) ?? true else { throw DailyCacheFailure.changed }
                return DailyCachePreview(boundary: boundary, replacement: replacement, readings: readings,
                                         operation: operation, revision: revision, owner: owner, source: source)
            } onCancel: { control.cancel() }
        } catch {
            cancelDailyCacheReview(control: control)
            throw error
        }
    }

    func installDailyCache(_ preview: DailyCachePreview, control: BackupOperationControl,
                           didCommit: () -> Void) async throws {
        let hk = HealthKitService.shared
        func canCommit() -> Bool {
            dailyCacheOperation == preview.operation && dailyCacheControl === control && !Task.isCancelled
                && conversationReady && !isSyncing && hk.dailySourceIsCurrent(preview.source)
                && (preview.readings.map(hk.readingsAreCurrent) ?? true)
        }
        guard canCommit() else { throw DailyCacheFailure.changed }
        try await LocalStore.replaceDailyCacheChecked(preview.replacement, replacing: preview.boundary,
            expectedRevision: preview.revision, expectedOwner: preview.owner, control: control, canCommit: canCommit) {
                // This callback runs in the commit's actor turn. A later Cancel
                // cannot relabel the already installed snapshot as unsaved.
                healthSnapshot = preview.replacement.metrics
                acceptLocalHealthCommit([.today]); healthRefreshIssue = nil; refresh()
                if let readings = preview.readings { hk.publishToday(readings) }
                dailyCacheControl = nil; dailyCacheOperation = UUID()
                didCommit()
            }
    }

    func acceptLocalHealthCommit(_ domains: [HealthLocalFiles.Domain]) {
        // The commit has succeeded; a later read error reports unavailable state
        // rather than falsely telling the caller the committed change rolled back.
        for domain in domains {
            do { localHealthBoundaries[domain] = try LocalStore.healthBoundaryChecked(domain); unavailableLocalHealth.remove(domain) }
            catch { unavailableLocalHealth.insert(domain) }
        }
        updateLocalHealthIssue()
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
    public var mealsToday: [Meal] { localHealthAvailable(.meals) ? today(meals.filter { $0.source != .sample }, \.date).sorted { $0.date < $1.date } : [] }
    public var caloriesEaten: Double { metrics.reading("calories").value ?? 0 }
    public var proteinEaten: Double { metrics.reading("protein").value ?? 0 }
    public var carbsEaten: Double { metrics.reading("carbs").value ?? 0 }
    public var fatEaten: Double { metrics.reading("fat").value ?? 0 }
    public var waterTodayML: Double { metrics.waterML }
    public var workoutsToday: [Workout] { localHealthAvailable(.workouts) ? today(workouts.filter { $0.source != .sample }, \.start) : [] }
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

    func retryHealthWrites() {
        #if DEBUG && targetEnvironment(simulator)
        if HealthWriteLifecycleProbe.shouldHoldDispatch { refreshHealthWriteStatus(); return }
        #endif
        healthWrites.kick()
    }

    func startHealthWritesOnThisDeviceChecked() throws {
        try LocalStore.startHealthWritesOnThisDeviceChecked()
        retryHealthWrites()
    }

    private var queuesOptionalHealthWrites: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if HealthWriteNativeProbe.requested { return true }
        #endif
        return HealthKitService.shared.isAuthorized
    }
    #if DEBUG && targetEnvironment(simulator)
    func waitForHealthWriteVerification() async {
        precondition(HealthWriteNativeProbe.requested || HealthWriteLifecycleProbe.requested)
        await healthWrites.waitForCurrentWork()
    }
    #endif

    private func refreshHealthWriteStatus() {
        do {
            let journal = try LocalStore.healthWriteJournalChecked()
            healthWriteNeedsDeviceSetup = false
            let pending = journal.pendingEvents
            healthWritePendingCount = pending.count
            if healthWrites.storageIssue {
                healthWriteStatus = "Apple Health progress couldn't be saved. Your local entries are saved; retry to check the pending updates."
            } else if pending.isEmpty { healthWriteStatus = nil }
            else if !queuesOptionalHealthWrites {
                healthWriteStatus = "Apple Health updates are pending. Connect to finish them; your local changes are saved."
            } else if pending.contains(where: { $0.issue == .permission }) {
                healthWriteStatus = "Apple Health updates need permission. Allow Lumen to write these types in Health, then retry. Your local changes are saved."
            } else if pending.contains(where: { $0.issue != nil }) {
                healthWriteStatus = "Apple Health updates need retry. Your local changes are saved."
            } else { healthWriteStatus = "Your local changes are saved. Updating Apple Health…" }
            if let last = journal.events.filter({ $0.domain == .water && $0.action == .delete }).max(by: { $0.requestedAt < $1.requestedAt }) {
                waterUndoStatus = last.complete
                    ? "Removed from Lumen. No matching Lumen entry remains in Apple Health."
                    : "Removed from Lumen. Apple Health removal is pending; retry from Settings."
            }
        } catch HealthWriteJournal.Failure.foreignOwner {
            healthWriteNeedsDeviceSetup = true
            healthWriteStatus = "These pending Apple Health updates aren't linked to this iPhone. Your local entries are saved."
        } catch {
            healthWriteNeedsDeviceSetup = false
            healthWriteStatus = "Pending Apple Health updates couldn't be opened. Their saved record hasn't been replaced."
        }
    }

    public func addMeal(_ meal: Meal, photo: UIImage? = nil) throws {
        let boundary = try requireLocalHealthBoundary(.meals)
        guard !meals.contains(where: { $0.id == meal.id }) else { throw BackupError.invalid }
        var saved = meal
        var ownedPhoto: String?
        if let photo {
            let id = UUID().uuidString
            try PhotoStore.saveNewChecked(photo, id: id)
            ownedPhoto = id; saved.photoID = id
        }
        let records = meals + [saved]
        do {
            if queuesOptionalHealthWrites {
                let values: [(HealthWriteJournal.Metric, Double)] = [(.calories, meal.calories), (.protein, meal.protein), (.carbs, meal.carbs), (.fat, meal.fat), (.fiber, meal.fiber)]
                guard values.allSatisfy({ $0.1.isFinite && $0.1 >= 0 }) else { throw BackupError.invalid }
                let components = values.filter { $0.1 > 0 }.map { HealthWriteJournal.Component(metric: $0.0, value: $0.1, date: meal.date) }
                if components.isEmpty { try LocalStore.saveChecked(records, as: "meals", healthBoundary: boundary) }
                else { try LocalStore.saveHealthChangeChecked(records, as: "meals", boundary: boundary) { try $0.append(domain: .meal, localID: meal.id, components: components) } }
            } else { try LocalStore.saveChecked(records, as: "meals", healthBoundary: boundary) }
        }
        catch { PhotoStore.delete(ownedPhoto); throw error }
        meals = records
        acceptLocalHealthCommit([.meals])
        retryHealthWrites()
        refresh()
    }

    public func deleteMeal(_ id: String) throws {
        let boundary = try requireLocalHealthBoundary(.meals)
        let photoIDs = Set(meals.filter { $0.id == id }.compactMap(\.photoID))
        let remaining = meals.filter { $0.id != id }
        guard remaining.count != meals.count else { return }
        try LocalStore.saveHealthChangeChecked(remaining, as: "meals", boundary: boundary) { try $0.requestDeletion(domain: .meal, localID: id) }
        meals = remaining
        acceptLocalHealthCommit([.meals])
        for photoID in photoIDs where !remaining.contains(where: { $0.photoID == photoID }) { PhotoStore.delete(photoID) }
        retryHealthWrites()
        refresh()
    }

    public func addWater(ml: Double) throws {
        let boundary = try requireLocalHealthBoundary(.water)
        guard ml.isFinite, ml > 0, ml <= 10000 else { throw BackupError.invalid }
        let log = HydrationLog(ml: ml)
        let records = waterLogs + [log]
        if queuesOptionalHealthWrites {
            try LocalStore.saveHealthChangeChecked(records, as: "water", boundary: boundary) {
                try $0.append(domain: .water, localID: log.id, components: [.init(metric: .water, value: ml, date: log.date)])
            }
        } else { try LocalStore.saveChecked(records, as: "water", healthBoundary: boundary) }
        waterUndoStatus = nil
        waterLogs = records
        acceptLocalHealthCommit([.water])
        retryHealthWrites()
        refresh()
    }

    public var canUndoQuickWater: Bool { localHealthAvailable(.water) && LocalHealthCorrection.latestQuickWater(waterLogs) != nil }
    public func undoLastWater() throws {
        let boundary = try requireLocalHealthBoundary(.water)
        guard let last = LocalHealthCorrection.latestQuickWater(waterLogs) else { return }
        let remaining = waterLogs.filter { $0.id != last.id }
        try LocalStore.saveHealthChangeChecked(remaining, as: "water", boundary: boundary) { try $0.requestDeletion(domain: .water, localID: last.id) }
        waterLogs = remaining; acceptLocalHealthCommit([.water]); refresh()
        retryHealthWrites()
    }

    public func addManualWorkout(kind: WorkoutKind, minutes: Double, kcal: Double? = nil, start: Date = Date()) throws {
        let boundary = try requireLocalHealthBoundary(.workouts)
        if kcal == nil { _ = try requireLocalHealthBoundary(.goals) }
        guard minutes.isFinite, minutes > 0, minutes <= 1440,
              start.timeIntervalSince1970.isFinite, start <= Date(),
              kcal.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw BackupError.invalid }
        let w = Workout(kind: kind, title: kind.label, start: start, duration: minutes * 60,
                        activeCalories: kcal ?? kind.met * (minutes / 60) * (goals.weightKg ?? 75), source: .manual)
        let records = (workouts + [w]).sorted { $0.start < $1.start }
        try LocalStore.saveChecked(records, as: "workouts", healthBoundary: boundary)
        workouts = records; acceptLocalHealthCommit([.workouts]); refresh()
    }

    public func deleteWorkout(_ id: String) throws {
        let boundary = try requireLocalHealthBoundary(.workouts)
        if workouts.first(where: { $0.id == id }).map(LocalHealthCorrection.canEdit) == true {
            try correctConfirmedWorkout(id, draft: nil)
            return
        }
        let records = workouts.filter { !($0.id == id && $0.source == .manual && $0.importOrigin == nil) }
        guard records.count != workouts.count else { return }
        try LocalStore.saveChecked(records, as: "workouts", healthBoundary: boundary)
        workouts = records; acceptLocalHealthCommit([.workouts]); refresh()
    }

    /// Confirmed conversational entries are local-only. Corrections never call HealthKit.
    func correctConfirmedWater(_ id: String, draft: HealthLogDraft?) throws {
        let boundary = try requireLocalHealthBoundary(.water)
        let records = try LocalHealthCorrection.water(id: id, draft: draft, records: waterLogs)
        try LocalStore.saveChecked(records, as: "water", healthBoundary: boundary)
        waterLogs = records; acceptLocalHealthCommit([.water]); refresh()
    }

    func correctConfirmedWorkout(_ id: String, draft: HealthLogDraft?) throws {
        let boundary = try requireLocalHealthBoundary(.workouts)
        let records = try LocalHealthCorrection.workout(id: id, draft: draft, records: workouts)
        try LocalStore.saveChecked(records, as: "workouts", healthBoundary: boundary)
        workouts = records; acceptLocalHealthCommit([.workouts]); refresh()
    }

    public func logWeight(kg: Double) async throws {
        let boundaries: [HealthLocalFiles.Domain: HealthLocalFiles.Boundary] = [.goals: try requireLocalHealthBoundary(.goals), .today: try requireLocalHealthBoundary(.today)]
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
        let event: HealthWriteJournal.Component? = queuesOptionalHealthWrites ? .init(metric: .weight, value: kg, date: now) : nil
        try await LocalStore.saveWeightChecked(goals: savedGoals, snapshot: snapshot, healthEvent: event, healthBoundaries: boundaries, canCommit: { !self.isSyncing }) {
            goals = savedGoals; healthSnapshot = snapshot
            acceptLocalHealthCommit([.goals, .today])
            retryHealthWrites()
            refresh()
        }
    }

    /// Settings change one field against the latest live goals. Do not publish
    /// a new target or overwrite other record domains when storage rejects it.
    func updateGoalsChecked(_ change: (inout HealthGoals) -> Void) throws {
        let boundary = try requireLocalHealthBoundary(.goals)
        var saved = goals; change(&saved)
        try LocalStore.saveChecked(saved, as: "goals", healthBoundary: boundary)
        installCheckedGoals(saved)
    }

    func installCheckedGoals(_ saved: HealthGoals) { goals = saved; acceptLocalHealthCommit([.goals]); refresh() }

    func reloadAfterRestore() {
        watchWaterSaveFailure = nil
        // A restore must not start an old queued write using restored content.
        // Already-started Health callbacks cannot be recalled; their record's
        // requested deletion still waits for completion through the same queue.
        waterUndoStatus = nil
        retryHealthWrites()
        openLocalHealthDomains()
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

    func installHealthWorkouts(_ values: [Workout]) { workouts = values; acceptLocalHealthCommit([.workouts]) }

    public func syncAll() async {
        await SyncCoordinator.syncEverything(sleep: SleepStore.shared, health: self)
    }

    func refreshSources(includeProviders: Bool) async {
        let operation = UUID(); healthSourceRefresh = operation
        healthRefreshIssue = nil
        let session = HealthBackgroundSync.shared.generation
        let hk = HealthKitService.shared
        if hk.isAuthorized {
            let capturedRevision = LocalStore.revision
            do {
                let readings = try await hk.queryTodayReadings()
                try Task.checkCancellation()
                guard healthSourceRefresh == operation, hk.readingsAreCurrent(readings), HealthBackgroundSync.shared.generation == session,
                      LocalStore.revision == capturedRevision else { throw BackupError.recordsChanged }
                let boundary = try requireLocalHealthBoundary(.today)
                let snapshot = CurrentHealthEvidence.merging(readings.raw.metrics, into: healthSnapshot)
                try Task.checkCancellation()
                try LocalStore.saveChecked(snapshot, as: "today", healthBoundary: boundary)
                healthSnapshot = snapshot; acceptLocalHealthCommit([.today])
                hk.publishToday(readings)
                if !Task.isCancelled, readings.raw.metrics.weightKg != nil, localHealthAvailable(.today), let w = healthSnapshot.weightKg {
                    do { try updateGoalsChecked { $0.weightKg = (w * 10).rounded() / 10 } }
                    catch { healthRefreshIssue = "The latest weight couldn't be saved to your targets. Open saved data again, then retry syncing." }
                }
            } catch is CancellationError { return }
            catch HealthTodayReadCoordinator.Failure.changed { return }
            catch {
                guard !Task.isCancelled, healthSourceRefresh == operation, hk.isAuthorized, HealthBackgroundSync.shared.generation == session else { return }
                healthRefreshIssue = "Recent Apple Health readings couldn't be checked or saved. Open saved data again, then retry syncing."
            }
            guard healthSourceRefresh == operation, hk.isAuthorized, HealthBackgroundSync.shared.generation == session else { return }
            // Workouts are applied by the durable anchored pipeline.
            let hrvDays = await hk.dailySeries(.hrv, days: 30).filter { !Calendar.current.isDateInToday($0.date) }
            let hrDays = await hk.dailySeries(.restingHR, days: 30).filter { !Calendar.current.isDateInToday($0.date) }
            guard healthSourceRefresh == operation, hk.isAuthorized, HealthBackgroundSync.shared.generation == session else { return }
            hrvBaseline = hrvDays.count >= 7 ? hrvDays.map(\.value).reduce(0, +) / Double(hrvDays.count) : nil
            restingHRBaseline = hrDays.count >= 7 ? hrDays.map(\.value).reduce(0, +) / Double(hrDays.count) : nil
        }
        if includeProviders, StravaService.shared.isConnected {
            await StravaService.shared.sync()
            guard healthSourceRefresh == operation, HealthBackgroundSync.shared.generation == session else { return }
            do { try mergeWorkoutsChecked(StravaService.shared.activities) }
            catch { healthRefreshIssue = "Recent workouts couldn't be saved. Open saved data again, then retry syncing." }
        }
        guard healthSourceRefresh == operation else { return }
        lastSync = Date()
        AppGroup.defaults.set(lastSync, forKey: "health.lastSync")
        refresh()
    }

    private func mergeWorkoutsChecked(_ incoming: [Workout]) throws {
        let boundary = try requireLocalHealthBoundary(.workouts)
        let records = WorkoutReconciliation.merge(incoming, into: workouts)
        try LocalStore.saveChecked(records, as: "workouts", healthBoundary: boundary)
        workouts = records; acceptLocalHealthCommit([.workouts])
    }

    func importWorkouts(_ incoming: [Workout], filename: String) throws {
        let records = incoming.map { original in
            var workout = original; workout.importOrigin?.filename = filename; return workout
        }
        try mergeWorkoutsChecked(records); refresh()
    }

    func clearImportedWorkouts() throws {
        let boundary = try requireLocalHealthBoundary(.workouts)
        let records = workouts.filter { $0.importOrigin == nil }
        try LocalStore.saveChecked(records, as: "workouts", healthBoundary: boundary)
        workouts = records; acceptLocalHealthCommit([.workouts]); refresh()
    }

    // MARK: Coaching

    /// Called by the sleep side whenever debt / need / last night change.
    public func recompute(sleepDebt: TimeInterval, sleepNeed: TimeInterval, sleepEpisodes: [SleepEpisode], birthYear: Int? = nil) {
        let currentGoals = ProfileSettings.refreshedAge(goals: goals, birthYear: birthYear)
        if localHealthAvailable(.goals), currentGoals.age != goals.age { goals = currentGoals }
        self.sleepDebt = sleepDebt
        self.sleepNeed = sleepNeed
        self.sleepEpisodes = sleepEpisodes
        refresh()
    }

    public func refresh() {
        var m = CurrentHealthEvidence.resolve(snapshot: localHealthAvailable(.today) ? healthSnapshot : .empty,
                                             imported: CompanionStore.shared.todayImport,
                                             meals: localHealthAvailable(.meals) ? meals : [],
                                             water: localHealthAvailable(.water) ? waterLogs : [],
                                             workouts: localHealthAvailable(.workouts) ? workouts : [], sleep: SleepEvidence.today(sleepEpisodes))
        // A known incomplete local history cannot become an apparently complete
        // total just because another source supplies part of today's reading.
        if !localHealthAvailable(.water) { m.setReading(.unknown, for: "water") }
        if !localHealthAvailable(.meals) { for key in ["calories", "protein", "carbs", "fat"] { m.setReading(.unknown, for: key) } }
        if !localHealthAvailable(.workouts) { for key in ["exercise", "activeEnergy"] { m.setReading(.unknown, for: key) } }
        metrics = m

        readiness = unavailableLocalHealth.isEmpty ? CoachingEngine.readinessIfAvailable(metrics: m, sleepDebt: assistantSleepDebt, workoutsToday: workoutsToday, goals: goals, hrvBaseline: hrvBaseline, restingHRBaseline: restingHRBaseline) : nil
        plan = unavailableLocalHealth.isEmpty ? CoachingEngine.dayPlan(metrics: m, readiness: readiness, goals: goals, sleepDebt: assistantSleepDebt, eaten: caloriesEaten, protein: proteinEaten, waterML: waterTodayML) : nil
        let perspective = CompanionStore.shared.perspective(health: self)
        plan?.briefing = perspective.body
        if !CompanionStore.shared.activeSymptoms.isEmpty {
            plan?.bullets = ["Check how you feel before activity; keep your plans flexible.", "Keep notes on symptom timing and changes.", "For symptoms that persist, worsen or concern you, contact a clinician."]
            plan?.workoutSuggestion = "Check symptoms before exercise"
        }
        insights = unavailableLocalHealth.isEmpty ? CoachingEngine.insights(metrics: m, readiness: readiness, goals: goals, mealsToday: mealsToday, workoutsToday: workoutsToday, sleepDebt: assistantSleepDebt) : []

        let d = AppGroup.defaults
        d.set(readiness?.score ?? 0, forKey: "widget.readiness")
        d.set(Int(caloriesEaten), forKey: "widget.eaten")
        d.set(localHealthAvailable(.goals) ? goals.calorieTarget() : 0, forKey: "widget.target")
        d.set(Int(proteinEaten), forKey: "widget.protein")
        d.set(localHealthAvailable(.goals) ? goals.proteinTarget() : 0, forKey: "widget.proteinTarget")
        d.set(m.steps, forKey: "widget.steps")
        d.set(moveProgress, forKey: "widget.move")
        d.set(displayEvidence.encoded(), forKey: DisplayEvidence.widgetKey)
        d.set(localHealthStorageIssue, forKey: "health.localStorageIssue")
        WidgetBridge.reload()
        WatchSync.shared.scheduleSend()
        NotificationManager.shared.refreshContext(health: self)
    }

    /// Start over: clears every log (Health data itself is untouched).
    public func resetAll() {
        watchWaterSaveFailure = nil
        waterUndoStatus = nil
        refreshHealthWriteStatus()
        invalidateConversationWork()
        goals = HealthGoals(); meals = []; workouts = []; waterLogs = []; chat = []
        conversations = []; activeConversationID = nil
        UserDefaults.standard.removeObject(forKey: "lumen.conversation.active")
        conversationReady = true; conversationStorageIssue = nil
        CompanionStore.shared.reset()
        healthSnapshot = .empty; lastSync = nil; hrvBaseline = nil; restingHRBaseline = nil; sleepEpisodes = []; sleepDebt = 0
        openLocalHealthDomains(); healthRefreshIssue = nil
        refresh()
    }
}
