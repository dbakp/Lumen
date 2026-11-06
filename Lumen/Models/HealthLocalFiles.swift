import Foundation
import CryptoKit
import Darwin

/// A failed current read is never a missing-file migration. The boundary is
/// retained with the loaded model so an old live array cannot replace a file
/// that changed or became unreadable since it was opened.
enum HealthLocalFiles {
    enum Domain: String, CaseIterable, Sendable {
        case water, meals, workouts, goals, today
        var legacyKey: String? {
            switch self {
            case .meals, .workouts, .goals: return "lumen.health.\(rawValue).v1"
            default: return nil
            }
        }
        var label: String {
            switch self {
            case .water: return "water history"
            case .meals: return "meal history"
            case .workouts: return "workout history"
            case .goals: return "targets"
            case .today: return "daily readings"
            }
        }
    }
    enum Boundary: Equatable, Sendable {
        case current(String)
        case missing(legacy: String?)
    }
    struct Loaded<Value> { let value: Value?; let boundary: Boundary }
    enum Failure: Error, LocalizedError {
        case invalid, changed, unavailable
        var errorDescription: String? {
            switch self {
            case .changed: return "Saved health data changed. Retry opening saved data before making this change."
            case .invalid, .unavailable: return "Saved health data couldn't be opened. Retry opening saved data before making this change. The saved files haven't been replaced."
            }
        }
    }
    static let limit = 100_000_000

    /// Check the opened descriptor before allocating data, then read in bounded
    /// chunks. A file growing after stat cannot turn this into an unbounded
    /// allocation. Nonblocking open also rejects a raced-in FIFO without waiting.
    static func readRegularData(_ file: URL, limit: Int, control: BackupOperationControl? = nil) throws -> Data {
        try control?.checkCancellation()
        guard limit >= 0, limit < Int.max else { throw Failure.invalid }
        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            #if DEBUG && targetEnvironment(simulator)
            var closed = false
            do { try input.close(); closed = true } catch { }
            if let control { HealthReadUIFixture.didClose(control: control, descriptor: descriptor, succeeded: closed) }
            #else
            try? input.close()
            #endif
        }
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), before.st_size >= 0,
              before.st_size <= off_t(limit) else { throw Failure.invalid }
        var data = Data()
        while true {
            try control?.checkCancellation()
            let block = try input.read(upToCount: min(64 * 1024, limit - data.count + 1)) ?? Data()
            try control?.checkCancellation()
            if block.isEmpty { break }
            guard block.count <= limit - data.count else { throw Failure.invalid }
            data.append(block)
            if let control {
                let progress = control.progress
                switch progress.stage {
                case .preparing, .reading:
                    control.update(.reading, completed: progress.completed, total: progress.total, bytes: Int64(data.count))
                default: break // The caller owns photo-check/restore/unlock progress.
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            if let control { try HealthReadUIFixture.pause(control: control, file: file, descriptor: descriptor, bytesRead: data.count) }
            #endif
            try control?.checkCancellation()
        }
        var after = stat(), path = stat()
        guard fstat(descriptor, &after) == 0, lstat(file.path, &path) == 0,
              before.st_size == after.st_size, data.count == Int(after.st_size),
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              path.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              path.st_dev == after.st_dev, path.st_ino == after.st_ino else { throw Failure.changed }
        try control?.checkCancellation()
        return data
    }

    static func read<Value: Decodable>(_ type: Value.Type, domain: Domain, from root: URL,
                                      legacy: () throws -> Data? = { nil }) throws -> Loaded<Value> {
        if let data = try currentData(domain, from: root) {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return Loaded(value: try decode(type, domain: domain, data: data, decoder: decoder), boundary: .current(hash(data)))
        }
        let old = try legacy()
        return Loaded(value: try old.map { try decode(type, domain: domain, data: $0, decoder: JSONDecoder()) },
                      boundary: .missing(legacy: old.map(hash)))
    }

    static func boundary(_ domain: Domain, from root: URL, legacy: () throws -> Data? = { nil }) throws -> Boundary {
        if let data = try currentData(domain, from: root) { return .current(hash(data)) }
        return .missing(legacy: try legacy().map(hash))
    }

    static func verify(_ expected: Boundary, domain: Domain, from root: URL,
                       legacy: () throws -> Data? = { nil }) throws {
        guard try boundary(domain, from: root, legacy: legacy) == expected else { throw Failure.changed }
    }

    static func validateCurrentData(_ data: Data, domain: Domain, control: BackupOperationControl? = nil) throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        switch domain {
        case .water: _ = try decode([HydrationLog].self, domain: domain, data: data, decoder: decoder, control: control)
        case .meals: _ = try decode([Meal].self, domain: domain, data: data, decoder: decoder, control: control)
        case .workouts: _ = try decode([Workout].self, domain: domain, data: data, decoder: decoder, control: control)
        case .goals: _ = try decode(HealthGoals.self, domain: domain, data: data, decoder: decoder, control: control)
        case .today: _ = try decode(DayMetrics.self, domain: domain, data: data, decoder: decoder, control: control)
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, domain: Domain, data: Data, decoder: JSONDecoder,
                                                 control: BackupOperationControl? = nil) throws -> Value {
        try control?.checkCancellation()
        guard data.count <= limit else { throw Failure.invalid }
        try JSONFieldAudit.check(data, control: control ?? .init())
        let value = try decoder.decode(type, from: data)
        try control?.checkCancellation()
        guard HealthRecordValidation.accepts(value, domain: domain) else { throw Failure.invalid }
        try control?.checkCancellation()
        return value
    }

    private static func currentData(_ domain: Domain, from root: URL) throws -> Data? {
        try BackupFiles.openDirectory(root, createIfMissing: false)
        let file = root.appendingPathComponent(domain.rawValue + ".json")
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: file.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value <= limit else { throw Failure.invalid }
        return try readRegularData(file, limit: limit)
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
