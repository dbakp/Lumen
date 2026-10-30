import Foundation

/// Device-local replay state. Anchors and the records they describe are saved together.
/// Never treat an empty Health read as permission denial or a deletion.
struct HealthSyncLedger: Codable, Sendable {
    static let schema = 1
    static let pageSize = 500
    static let maximumRecords = 200_000
    var version = Self.schema
    var start: Date
    var sleepAnchor: Data?
    var workoutAnchor: Data?
    var sleep: [String: HealthSleepSample] = [:]
    var workouts: [String: Workout] = [:]
    var deletedWorkouts: Set<String> = []
    var managedSleepIDs: Set<UUID> = []
    var pendingApplication = false

    init(now: Date = Date(), calendar: Calendar = .current) {
        start = calendar.date(byAdding: .day, value: -730, to: calendar.startOfDay(for: now)) ?? now
    }

    mutating func rescanPermissions() {
        sleepAnchor = nil; workoutAnchor = nil; pendingApplication = true
    }

    enum Failure: Error { case invalidPage, capacity }
    func validate() throws {
        guard version == Self.schema, start.timeIntervalSince1970.isFinite,
              sleepAnchor.map({ !$0.isEmpty && $0.count <= 1024 * 1024 }) ?? true,
              workoutAnchor.map({ !$0.isEmpty && $0.count <= 1024 * 1024 }) ?? true,
              sleep.allSatisfy({ $0.key == $0.value.id && $0.value.isValid }),
              workouts.allSatisfy({ $0.key == $0.value.id && $0.value.source == .healthKit && UUID(uuidString: $0.key) != nil }),
              deletedWorkouts.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw Failure.invalidPage }
        guard sleep.count <= Self.maximumRecords, workouts.count <= Self.maximumRecords,
              deletedWorkouts.count <= Self.maximumRecords, managedSleepIDs.count <= Self.maximumRecords else { throw Failure.capacity }
    }
    mutating func applySleep(_ incoming: [HealthSleepSample], deleted: [String], anchor: Data) throws {
        guard incoming.count + deleted.count <= Self.pageSize, !anchor.isEmpty,
              incoming.allSatisfy({ $0.isValid && $0.end >= start }) else { throw Failure.invalidPage }
        var next = self
        for item in incoming { next.sleep[item.id] = item }
        for id in deleted { next.sleep.removeValue(forKey: id) }
        guard next.sleep.count <= Self.maximumRecords else { throw Failure.capacity }
        next.sleepAnchor = anchor; next.pendingApplication = true; self = next
    }
    mutating func applyWorkouts(_ incoming: [Workout], deleted: [String], anchor: Data) throws {
        guard incoming.count + deleted.count <= Self.pageSize, !anchor.isEmpty,
              incoming.allSatisfy({ $0.source == .healthKit && UUID(uuidString: $0.id) != nil && $0.start >= start && $0.duration.isFinite && $0.duration >= 0 }) else { throw Failure.invalidPage }
        var next = self
        for item in incoming { next.workouts[item.id] = item; next.deletedWorkouts.remove(item.id) }
        for id in deleted { next.workouts.removeValue(forKey: id); next.deletedWorkouts.insert(id) }
        guard next.workouts.count <= Self.maximumRecords, next.deletedWorkouts.count <= Self.maximumRecords else { throw Failure.capacity }
        next.workoutAnchor = anchor; next.pendingApplication = true; self = next
    }
    func reconciledWorkouts(_ current: [Workout]) -> [Workout] {
        let kept = current.filter { !($0.source == .healthKit && $0.importOrigin == nil && deletedWorkouts.contains($0.id)) }
        let localIDs = Set(kept.filter { $0.source == .manual }.map(\.id))
        return WorkoutReconciliation.merge(workouts.values.filter { !localIDs.contains($0.id) }, into: kept)
    }
    func reconciledSleep(_ current: [SleepEpisode]) -> [SleepEpisode] {
        let incoming = HealthSleepSample.episodes(Array(sleep.values))
        let kept = current.filter { episode in
            guard episode.source == .wearable else { return true }
            if managedSleepIDs.contains(episode.id) { return false }
            // Migrate old synthesized Health nights only when a real replacement exists.
            return !incoming.contains { abs($0.midSleep.timeIntervalSince(episode.midSleep)) < 5 * 3600 }
        }
        return (kept + incoming).sorted { $0.bedtime < $1.bedtime }
    }
    mutating func markApplied() {
        managedSleepIDs.formUnion(HealthSleepSample.episodes(Array(sleep.values)).map(\.id))
        pendingApplication = false
    }
}

struct HealthSleepSample: Codable, Sendable {
    var id: String
    var start: Date
    var end: Date
    /// HealthKit sleep values: 1 unspecified asleep, 2 awake, 3 core, 4 deep, 5 REM.
    var value: Int
    var source: String
    var isValid: Bool {
        UUID(uuidString: id) != nil && start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite && end > start && end.timeIntervalSince(start) <= 7 * 86400 && (1...5).contains(value)
    }
    static func episodes(_ samples: [Self]) -> [SleepEpisode] {
        let valid = samples.filter(\.isValid)
        let asleep = valid.filter { $0.value != 2 }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var clusters: [[Self]] = [], lastEnd: Date?
        for item in asleep {
            if let end = lastEnd, item.start.timeIntervalSince(end) < 2 * 3600 { clusters[clusters.count - 1].append(item) }
            else { clusters.append([item]) }
            lastEnd = max(lastEnd ?? item.end, item.end)
        }
        func union(_ items: [Self]) -> Double {
            var result = 0.0, range: (Date, Date)?
            for item in items.sorted(by: { $0.start < $1.start }) {
                if let old = range, item.start <= old.1 { range = (old.0, max(old.1, item.end)) }
                else { if let old = range { result += old.1.timeIntervalSince(old.0) }; range = (item.start, item.end) }
            }
            if let old = range { result += old.1.timeIntervalSince(old.0) }; return result
        }
        return clusters.compactMap { cluster in
            guard let bed = cluster.map(\.start).min(), let wake = cluster.map(\.end).max(), union(cluster) >= 3 * 3600,
                  let identity = cluster.map(\.id).sorted().first.flatMap(UUID.init(uuidString:)) else { return nil }
            var episode = SleepEpisode(id: identity, bedtime: bed, wakeTime: wake, source: .wearable)
            episode.asleepSeconds = union(cluster)
            let sources = Dictionary(grouping: cluster, by: \.source)
            let richest = sources.keys.sorted().max { a, b in sources[a]!.filter { $0.value >= 3 }.count < sources[b]!.filter { $0.value >= 3 }.count }.flatMap { sources[$0] } ?? cluster
            func stage(_ value: Int) -> Double? { let result = union(richest.filter { $0.value == value }); return result > 0 ? result : nil }
            episode.coreSeconds = stage(3); episode.deepSeconds = stage(4); episode.remSeconds = stage(5)
            let awake = union(valid.filter { $0.value == 2 && $0.start >= bed && $0.end <= wake })
            episode.awakeSeconds = awake > 0 ? awake : nil
            return episode
        }
    }
}

/// A Health callback can arrive more than once or after a query was stopped.
/// Invoke the platform completion exactly once, including failures and cancellation.
final class HealthDeliveryCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?
    init(_ action: @escaping () -> Void) { self.action = action }
    func finish() { lock.lock(); let action = action; self.action = nil; lock.unlock(); action?() }
    deinit { finish() }
}

struct HealthChangePage: Sendable {
    var sleep: [HealthSleepSample] = []
    var workouts: [Workout] = []
    var deleted: [String]
    var anchor: Data
    var more: Bool
}

enum HealthSyncReplay {
    /// A failed save leaves the caller's authoritative ledger at the preceding page.
    /// Retry receives that page again; additions and tombstones are idempotent.
    @MainActor static func drain(
        _ initial: HealthSyncLedger,
        check: () throws -> Void,
        query: (Bool, Date, Data?) async throws -> HealthChangePage,
        save: (HealthSyncLedger) async throws -> Void
    ) async throws -> HealthSyncLedger {
        var ledger = initial
        for isSleep in [true, false] {
            var more = true
            while more {
                try check()
                let page = try await query(isSleep, ledger.start, isSleep ? ledger.sleepAnchor : ledger.workoutAnchor)
                try check()
                let previousAnchor = isSleep ? ledger.sleepAnchor : ledger.workoutAnchor
                if page.more && page.anchor == previousAnchor { throw HealthSyncLedger.Failure.invalidPage }
                var next = ledger
                if isSleep { try next.applySleep(page.sleep, deleted: page.deleted, anchor: page.anchor) }
                else { try next.applyWorkouts(page.workouts, deleted: page.deleted, anchor: page.anchor) }
                try await save(next)
                ledger = next; more = page.more
            }
        }
        return ledger
    }
}

/// Coalesce events during an active pass and perform one further pass. Foreground
/// callers also request provider refresh; observer callbacks never start OAuth work.
@MainActor final class HealthSyncQueue {
    private var active: Task<Void, Never>?
    private var requested = false
    private var providers = false
    func run(includeProviders: Bool, operation: @escaping (Bool) async -> Void) async {
        requested = true; providers = providers || includeProviders
        if let active { await active.value; return }
        let task = Task { @MainActor in
            defer { active = nil }
            while requested {
                requested = false
                let include = providers; providers = false
                await operation(include)
            }
        }
        active = task; await task.value
    }
}
