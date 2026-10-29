import Foundation

/// Shared only between the parser and its screen. Cancellation never commits partial data.
public final class HealthImportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var processed = 0
    private var stage = HealthImportProgress.Stage.reading
    private var extractedBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    public var progress: HealthImportProgress {
        lock.lock(); defer { lock.unlock() }
        return HealthImportProgress(stage: stage, records: processed, extractedBytes: extractedBytes, totalBytes: totalBytes)
    }
    func copyingArchive(bytes: Int64, total: Int64) {
        lock.lock(); stage = .copyingArchive; extractedBytes = bytes; totalBytes = total; lock.unlock()
    }
    func checkingArchive() { lock.lock(); stage = .checkingArchive; lock.unlock() }
    func extractingArchive(bytes: Int64, total: Int64) {
        lock.lock(); stage = .extracting; extractedBytes = bytes; totalBytes = total; lock.unlock()
    }
    func readingRecords() { lock.lock(); stage = .reading; lock.unlock() }
    public init() {}
    public var recordsProcessed: Int { lock.lock(); defer { lock.unlock() }; return processed }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func checkCancellation() throws {
        lock.lock(); let stop = cancelled; lock.unlock()
        if stop { throw CancellationError() }
    }
    func record(_ progress: @Sendable (Int) -> Void) throws {
        try checkCancellation()
        lock.lock(); processed += 1; let count = processed; lock.unlock()
        if count.isMultiple(of: 512) { progress(count) }
        try checkCancellation()
    }
}

public struct HealthImportProgress: Sendable {
    public enum Stage: Sendable { case copyingArchive, checkingArchive, extracting, reading }
    public var stage: Stage
    public var records: Int
    public var extractedBytes: Int64
    public var totalBytes: Int64
    public var title: String {
        switch stage {
        case .copyingArchive: return "Opening health export"
        case .checkingArchive: return "Checking health export"
        case .extracting: return "Preparing health history"
        case .reading: return "Reading your file"
        }
    }
    public var detail: String {
        switch stage {
        case .checkingArchive: return "No records added yet"
        case .copyingArchive, .extracting: return ByteCountFormatter.string(fromByteCount: extractedBytes, countStyle: .file) + " of " + ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        case .reading: return "\(records.formatted()) records reviewed"
        }
    }
}
