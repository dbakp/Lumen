import Foundation
import CryptoKit
import Darwin

/// Explicit replacement of today's raw readings, never a record restore or a
/// resolved display total. This path must not rotate or rewrite Health intent.
enum HealthDailyCache {
    static let queryKeys: Set<String> = ["steps", "activeEnergy", "restingEnergy", "exercise", "stand", "water",
        "restingHR", "hrv", "spo2", "weight", "respiratoryRate", "vo2max", "heartRate", "bodyFat",
        "calories", "protein", "carbs", "fat"]

    struct RawReadings: Sendable {
        let metrics: DayMetrics
        let start: Date
        let end: Date
        fileprivate init(metrics: DayMetrics, start: Date, end: Date) {
            self.metrics = metrics; self.start = start; self.end = end
        }
    }
    enum Replacement: Sendable {
        case clear(day: Date)
        case rebuild(RawReadings)
        var metrics: DayMetrics {
            switch self {
            case .clear(let day): return HealthDailyCache.unknown(day: day)
            case .rebuild(let raw): return raw.metrics
            }
        }
    }
    struct Boundary: Equatable, Codable, Sendable {
        enum State: String, Codable, Sendable { case missing, healthy, unavailable }
        let state: State
        fileprivate let entries: [String: Entry]
    }
    fileprivate struct Entry: Equatable, Codable, Sendable {
        let mode: UInt16
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanos: Int64
        let digest: String?
    }

    static func unknown(day: Date) -> DayMetrics {
        var value = DayMetrics.empty
        value.date = day; value.readings = [:]; value.recordedTotalKeys = []
        value.excludesLumenNutrition = true
        return value
    }

    /// All queried keys and outcomes belong to one captured query window.
    /// Empty/failed results retain their query evidence, never measured zero.
    static func rawReadings(_ readings: [String: HealthMetricReading], start: Date, end: Date) throws -> RawReadings {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              start <= end, Set(readings.keys) == queryKeys,
              readings.values.contains(where: { $0.healthQuery?.outcome != .failed && $0.healthQuery != nil }) else { throw HealthLocalFiles.Failure.invalid }
        var value = unknown(day: start)
        for key in queryKeys.sorted() {
            let reading = readings[key]!
            guard let query = reading.healthQuery, query.start == start, query.end == end,
                  query.checkedAt.timeIntervalSinceReferenceDate.isFinite, query.checkedAt >= end,
                  !reading.overlapKeptSeparate else { throw HealthLocalFiles.Failure.invalid }
            if query.outcome == .recorded {
                guard reading.components.count == 1, reading.value != nil,
                      reading.components.allSatisfy({ $0.origin == .healthKit && !$0.isEstimate }) else { throw HealthLocalFiles.Failure.invalid }
            } else { guard reading.components.isEmpty else { throw HealthLocalFiles.Failure.invalid } }
            value.setReading(reading, for: key)
        }
        try HealthLocalFiles.validateCurrentData(BackupArchive.encoder().encode(value), domain: .today)
        return RawReadings(metrics: value, start: start, end: end)
    }

    /// Observe the actual raw path, including malformed files and directory
    /// trees. No legacy today key exists. Reject links without reading targets.
    static func capture(in root: URL, control: BackupOperationControl = .init()) throws -> Boundary {
        try BackupFiles.openDirectory(root, createIfMissing: false)
        var entries: [String: Entry] = [:]
        let file = root.appendingPathComponent("today.json")
        func visit(_ url: URL, relative: String, depth: Int) throws {
            try control.checkCancellation()
            guard depth <= 8, entries.count < 200_000 else { throw HealthLocalFiles.Failure.invalid }
            var before = stat()
            guard lstat(url.path, &before) == 0 else {
                if errno == ENOENT && relative.isEmpty { return }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            let kind = before.st_mode & mode_t(S_IFMT)
            guard kind == mode_t(S_IFREG) || kind == mode_t(S_IFDIR) else { throw HealthLocalFiles.Failure.invalid }
            var hash: String?
            if kind == mode_t(S_IFREG) {
                do { hash = digest(try HealthLocalFiles.readRegularData(url, limit: HealthLocalFiles.limit, control: control)) }
                catch let error as NSError where error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code) {
                    // The transaction retains this same regular-file inode.
                    // Permission failure remains unavailable, never missing.
                }
            }
            entries[relative] = Entry(mode: before.st_mode, device: before.st_dev, inode: before.st_ino,
                size: before.st_size, modifiedSeconds: Int64(before.st_mtimespec.tv_sec),
                modifiedNanos: Int64(before.st_mtimespec.tv_nsec), digest: hash)
            if kind == mode_t(S_IFDIR) {
                let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                guard children.count <= 200_000 else { throw HealthLocalFiles.Failure.invalid }
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, relative: relative + "/" + child.lastPathComponent, depth: depth + 1)
                }
            }
            var after = stat()
            guard lstat(url.path, &after) == 0, before.st_mode == after.st_mode,
                  before.st_dev == after.st_dev, before.st_ino == after.st_ino, before.st_size == after.st_size,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw HealthLocalFiles.Failure.changed }
        }
        try visit(file, relative: "", depth: 0)
        let state: Boundary.State
        if entries.isEmpty { state = .missing }
        else {
            do { _ = try HealthLocalFiles.read(DayMetrics.self, domain: .today, from: root); state = .healthy }
            catch is CancellationError { throw CancellationError() }
            catch { state = .unavailable }
        }
        try control.checkCancellation()
        return Boundary(state: state, entries: entries)
    }

    static func verify(_ boundary: Boundary, in root: URL, control: BackupOperationControl = .init()) throws {
        guard try capture(in: root, control: control) == boundary else { throw HealthLocalFiles.Failure.changed }
    }

    static func prepare(_ replacement: Replacement, replacing boundary: Boundary, in root: URL, owner: UUID,
                        control: BackupOperationControl = .init()) throws -> BackupFileTransaction {
        try verify(boundary, in: root, control: control)
        let bytes = try BackupArchive.encoder().encode(replacement.metrics)
        try HealthLocalFiles.validateCurrentData(bytes, domain: .today, control: control)
        let kind: String
        switch replacement { case .clear: kind = "clear"; case .rebuild: kind = "rebuild" }
        struct Receipt: Encodable {
            let action: String; let owner: UUID; let prior: Boundary
            let rawDigest: String; let replacedAt: Date
        }
        let receipt = try BackupArchive.encoder().encode(Receipt(action: kind, owner: owner, prior: boundary,
                                                                  rawDigest: digest(bytes), replacedAt: Date()))
        let files = ["today.json": bytes, ".health-cache-history/" + UUID().uuidString + ".json": receipt]
        let transaction = try ConversationFiles.prepareDailyCache(files, into: root, control: control)
        try verify(boundary, in: root, control: control)
        return transaction
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
