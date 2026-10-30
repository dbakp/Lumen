import Foundation
import HealthKit
import UIKit

/// Installed from didFinishLaunching, before HealthKit can deliver a cold-launch event.
@MainActor
final class HealthBackgroundSync: ObservableObject {
    static let shared = HealthBackgroundSync()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "lumen.health.background")
    @Published private(set) var registration = "Off"
    @Published private(set) var lastEvent = UserDefaults.standard.object(forKey: "lumen.health.lastEvent") as? Date
    @Published private(set) var lastApplied = UserDefaults.standard.object(forKey: "lumen.health.lastApplied") as? Date
    @Published private(set) var issue: String?
    private var observers: [HKObserverQuery] = []
    private var registrationTask: Task<Void, Never>?
    private(set) var generation = UUID()
    private let hk = HealthKitService.shared
    private var registrationRevision = UUID()

    func start() {
        guard hk.isAuthorized, observers.isEmpty else { return }
        let session = generation
        for type in hk.observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                let delivery = HealthDeliveryCompletion(completion)
                Task { @MainActor in
                    let lifetime = HealthDeliveryLifetime(delivery)
                    lifetime.begin()
                    defer { lifetime.finish() }
                    guard self.generation == session, self.hk.isAuthorized, self.enabled || UIApplication.shared.applicationState == .active else { return }
                    guard UIApplication.shared.isProtectedDataAvailable else {
                        self.issue = "Unlock your iPhone and open Lumen to finish the Health update."
                        return
                    }
                    self.lastEvent = Date()
                    UserDefaults.standard.set(self.lastEvent, forKey: "lumen.health.lastEvent")
                    guard error == nil else { self.issue = "Health reported an update error. Open Lumen to retry."; return }
                    await SyncCoordinator.syncEverything(sleep: SleepStore.shared, health: HealthStore.shared, background: true)
                }
            }
            observers.append(query); hk.store.execute(query)
        }
        configureRegistration()
    }

    func retryRegistration() { if hk.isAuthorized { configureRegistration() } }

    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "lumen.health.background")
        start(); configureRegistration()
    }

    private func configureRegistration() {
        // A new request waits for the previous platform operation. Cancellation alone
        // cannot undo a pending HealthKit enable call after a user turns updates off.
        let previous = registrationTask, revision = UUID(); registrationRevision = revision
        let requested = enabled && hk.isAuthorized
        registration = requested ? "Requesting updates…" : "Pausing updates…"
        registrationTask = Task { @MainActor in
            await previous?.value
            guard registrationRevision == revision else { return }
            do {
                if requested {
                    #if targetEnvironment(simulator)
                    registration = "Unavailable on this device"
                    #else
                    var failures = 0
                    for type in hk.observedTypes {
                        guard registrationRevision == revision else { return }
                        do { try await hk.store.enableBackgroundDelivery(for: type, frequency: .hourly) }
                        catch { failures += 1 }
                    }
                    guard registrationRevision == revision else { return }
                    registration = failures == 0 ? "Updates requested" : "Some updates unavailable"
                    if failures > 0 { issue = "Some Health updates couldn't be registered. Open Lumen or review Health access to retry." }
                    #endif
                } else {
                    try await hk.store.disableAllBackgroundDelivery()
                    guard registrationRevision == revision else { return }
                    registration = "Off"
                }
            } catch {
                guard registrationRevision == revision else { return }
                registration = requested ? "Updates unavailable" : "Pause needs a retry"
                issue = "Health couldn't change background delivery. Open Lumen to retry."
            }
        }
    }

    func resetUserState() {
        setEnabled(false)
        lastEvent = nil; lastApplied = nil; issue = nil
        UserDefaults.standard.removeObject(forKey: "lumen.health.lastEvent")
        UserDefaults.standard.removeObject(forKey: "lumen.health.lastApplied")
    }

    func stop() {
        generation = UUID()
        for query in observers { hk.store.stop(query) }; observers = []
        configureRegistration()
    }

    /// Every successful page is durable before its anchor is reused. View stores are
    /// rebuilt from the cache on retry, even if the last process died after that save.
    func synchronize(sleep: SleepStore, health: HealthStore, deadline: Date? = nil) async throws {
        guard hk.isAuthorized else { return }
        guard UIApplication.shared.isProtectedDataAvailable else { throw SyncFailure.locked }
        let session = generation
        let path = LocalStore.directory.appendingPathComponent("healthSync.json")
        var ledger = try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: path.path) else { return HealthSyncLedger() }
            let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 64 * 1024 * 1024 else { throw SyncFailure.capacity }
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let value = try decoder.decode(HealthSyncLedger.self, from: data)
            try value.validate()
            return value
        }.value
        func checkSession() throws {
            guard hk.isAuthorized, generation == session else { throw CancellationError() }
            try Task.checkCancellation()
            if let deadline, Date() >= deadline { throw SyncFailure.moreHistory }
        }
        // A reviewed Health sheet can expand the readable historical range. An
        // old anchor alone would skip already-existing samples newly made readable.
        if let token = UserDefaults.standard.string(forKey: "lumen.health.rescan") {
            try checkSession()
            ledger.rescanPermissions()
            try await save(ledger, session: session)
            if UserDefaults.standard.string(forKey: "lumen.health.rescan") == token {
                UserDefaults.standard.removeObject(forKey: "lumen.health.rescan")
            }
        }
        // Fixed predicates belong to these anchors. Moving a date window would skip
        // old edits/deletions; a reconnect resumes the same stored start and anchors.
        ledger = try await HealthSyncReplay.drain(ledger, check: checkSession, query: { isSleep, start, anchor in
            try await self.hk.changePage(sleep: isSleep, start: start, anchor: anchor)
        }, save: { value in try await self.save(value, session: session) })
        try checkSession()
        let currentSleep = sleep.episodes, currentWorkouts = health.workouts, captured = ledger
        let result = await Task.detached(priority: .utility) {
            (captured.reconciledSleep(currentSleep), captured.reconciledWorkouts(currentWorkouts))
        }.value
        try checkSession()
        // These checked writes precede publication. If either fails the ledger stays
        // pending; the next run derives both stores again without losing any cursor.
        try LocalStore.saveChecked(result.0, as: "sleep")
        try LocalStore.saveChecked(result.1, as: "workouts")
        sleep.installHealthEpisodes(result.0); health.installHealthWorkouts(result.1)
        ledger.markApplied(); try await save(ledger, session: session)
        try checkSession()
        lastApplied = Date(); UserDefaults.standard.set(lastApplied, forKey: "lumen.health.lastApplied")
        issue = nil
    }

    private func save(_ ledger: HealthSyncLedger, session: UUID) async throws {
        let data = try await Task.detached(priority: .utility) {
            try ledger.validate()
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(ledger)
            guard data.count <= 64 * 1024 * 1024 else { throw SyncFailure.capacity }
            return data
        }.value
        guard generation == session, hk.isAuthorized else { throw CancellationError() }
        try LocalStore.saveEncodedChecked(data, as: "healthSync")
    }

    func report(_ error: Error) {
        if error is CancellationError { return }
        switch error {
        case SyncFailure.locked: issue = "Unlock your iPhone and open Lumen to finish the Health update."
        case SyncFailure.moreHistory: issue = "More Health history is waiting. Open Lumen to finish syncing."
        case SyncFailure.capacity, HealthSyncLedger.Failure.capacity: issue = "Health sync reached a storage limit. Open Lumen to review your saved history."
        default: issue = "Health update incomplete. Your saved records are retained; open Lumen to retry."
        }
    }
    enum SyncFailure: Error { case locked, cache, capacity, query, timeout, moreHistory }
}

extension HealthKitService {
    var observedTypes: [HKSampleType] {
        let ids: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime, .dietaryWater, .restingHeartRate, .heartRateVariabilitySDNN, .oxygenSaturation, .bodyMass, .respiratoryRate, .vo2Max, .heartRate, .bodyFatPercentage, .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal]
        return ids.map { HKQuantityType($0) } + [HKCategoryType(.appleStandHour), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
    }

    func changePage(sleep: Bool, start: Date, anchor: Data?) async throws -> HealthChangePage {
        let decoded: HKQueryAnchor?
        if let anchor { decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchor); guard decoded != nil else { throw HealthBackgroundSync.SyncFailure.cache } }
        else { decoded = nil }
        let type: HKSampleType = sleep ? HKCategoryType(.sleepAnalysis) : HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        // A platform callback may race a timeout. The gate resumes exactly once.
        return try await withCheckedThrowingContinuation { continuation in
            let gate = HealthQueryGate(continuation)
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: decoded, limit: HealthSyncLedger.pageSize) { _, samples, deleted, next, error in
                do {
                    if let error { throw error }
                    guard let samples, let deleted, let next else { throw HealthBackgroundSync.SyncFailure.query }
                    var page = HealthChangePage(deleted: deleted.map { $0.uuid.uuidString }, anchor: try NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true), more: samples.count + deleted.count >= HealthSyncLedger.pageSize)
                    if sleep {
                        page.sleep = (samples as? [HKCategorySample] ?? []).filter { (1...5).contains($0.value) }.map {
                            HealthSleepSample(id: $0.uuid.uuidString, start: $0.startDate, end: $0.endDate, value: $0.value, source: $0.sourceRevision.source.bundleIdentifier)
                        }
                    } else { page.workouts = (samples as? [HKWorkout] ?? []).map(Self.workout) }
                    gate.finish(.success(page))
                } catch { gate.finish(.failure(error)) }
            }
            store.execute(query)
            let queryStore = store
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
                if gate.finish(.failure(HealthBackgroundSync.SyncFailure.timeout)) { queryStore.stop(query) }
            }
        }
    }
}

private final class HealthQueryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HealthChangePage, Error>?
    init(_ continuation: CheckedContinuation<HealthChangePage, Error>) { self.continuation = continuation }
    @discardableResult func finish(_ result: Result<HealthChangePage, Error>) -> Bool {
        lock.lock(); let value = continuation; continuation = nil; lock.unlock()
        value?.resume(with: result); return value != nil
    }
}

@MainActor
final class LumenAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthBackgroundSync.shared.start()
        return true
    }
}

/// Expiration acknowledges the delivery even if iOS stops the process mid-query.
/// Durable page state is replayed on the next event or foreground refresh.
@MainActor private final class HealthDeliveryLifetime {
    private let completion: HealthDeliveryCompletion
    private var token: UIBackgroundTaskIdentifier = .invalid
    init(_ completion: HealthDeliveryCompletion) { self.completion = completion }
    func begin() {
        token = UIApplication.shared.beginBackgroundTask(withName: "Health update") { [weak self] in
            self?.finish()
        }
    }
    func finish() {
        completion.finish()
        if token != .invalid { let old = token; token = .invalid; UIApplication.shared.endBackgroundTask(old) }
    }
}
