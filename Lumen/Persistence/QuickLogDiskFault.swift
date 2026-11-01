#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Dedicated synthetic UI runs only. Cause Foundation's real write to fail by
/// occupying its destination with a directory, then restore the exact old file.
/// No fake success/error return replaces the production write operation.
enum QuickLogDiskFault {
    private static let lock = NSLock()
    private static var calls: [String: Int] = [:]

    static func write<T>(domain: String, target: URL, _ operation: () throws -> T) throws -> T {
        let args = ProcessInfo.processInfo.arguments
        lock.lock()
        calls[domain, default: 0] += 1
        let count = calls[domain]!
        let requested = args.firstIndex(of: "-quick-save-fault").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        let specification = requested?.split(separator: ":", omittingEmptySubsequences: false) ?? []
        let inject = args.contains("-resetForUITests") && specification.count == 2
            && specification[0] == domain && specification[1].split(separator: ",").contains(Substring(String(count)))
        lock.unlock()
        guard inject else { return try operation() }
        let fm = FileManager.default
        let previous = target.appendingPathExtension("quick-log-test-" + UUID().uuidString)
        let existed = fm.fileExists(atPath: target.path)
        let before = existed ? try Data(contentsOf: target) : nil
        if existed { try fm.moveItem(at: target, to: previous) }
        defer {
            try? fm.removeItem(at: target)
            if existed { try? fm.moveItem(at: previous, to: target) }
            precondition((try? Data(contentsOf: target)) == before, "Synthetic disk fault must restore original bytes")
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        do {
            let result = try operation()
            preconditionFailure("Synthetic directory destination unexpectedly accepted a write: \(result)")
        } catch {
            NSLog("Lumen quick-log real I/O fault %@ %ld %@", domain, count, String(describing: error))
            throw error
        }
    }
}

/// Hold the actual sync queue in its busy state until the first attempted
/// weight save observes it. This covers the real guard and retry, not a fake
/// error injected into the view. Dedicated synthetic launches only.
@MainActor enum QuickWeightSyncFixture {
    private static var released = false
    private static var waiter: CheckedContinuation<Void, Never>?
    static func holdIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-resetForUITests"), args.contains("-quick-weight-busy"), !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    static func release() {
        released = true; waiter?.resume(); waiter = nil
    }
}
#endif
