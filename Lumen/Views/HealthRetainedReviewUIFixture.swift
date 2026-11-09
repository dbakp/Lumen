#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Metadata-only evidence for a dedicated synthetic retained-copy launch.
/// This observer never supplies recovery authority or replacement records.
enum HealthRetainedReviewUIFixture {
    static let flag = "-health-retained-review-owner-ui"
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.filter({ $0 == flag }).count == 1,
              args.contains("-resetForUITests"), args.contains("-health-review-records-fixture"),
              let index = args.firstIndex(of: flag), args.indices.contains(index + 1),
              ["children", "pending-back", "sheet-dismiss"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
    }
    private static let bridge = Bridge()
    static func prepare(in root: URL) throws { if mode != nil { try bridge.reset(root) } }
    static func note(_ event: String, session: UUID, root: URL, operation: UUID? = nil,
                     closed: Bool, metadata: Bool) {
        guard mode != nil else { return }
        bridge.note(event, session: session, root: root, operation: operation, closed: closed, metadata: metadata)
    }
    static func afterCapture(session: UUID, root: URL, operation: UUID, control: BackupOperationControl,
                             closed: @Sendable () -> Bool, metadata: @Sendable () -> Bool) throws {
        guard mode == "pending-back", bridge.claimHold() else { return }
        note("capture-held", session: session, root: root, operation: operation, closed: closed(), metadata: metadata())
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var cancelled = false
        while ContinuousClock.now < deadline {
            do { try control.checkCancellation() }
            catch is CancellationError { cancelled = true }
            if cancelled && closed() {
                // Return the actual captured snapshot to the production finish
                // check after observed real cancellation AND actual owner close.
                // Suspension alone must not be reported as closed authority.
                note("capture-hold-cancelled", session: session, root: root, operation: operation, closed: closed(), metadata: metadata())
                return
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        throw BackupError.invalid
    }
    private final class Bridge: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [[String: Any]] = []
        private var held = false
        private var root: URL?
        func reset(_ root: URL) throws {
            lock.lock(); defer { lock.unlock() }
            self.root = root; rows = []; held = false
            try publish(root)
        }
        func claimHold() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !held else { return false }; held = true; return true
        }
        func note(_ event: String, session: UUID, root: URL, operation: UUID?, closed: Bool, metadata: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard self.root == root else { return }
            rows.append(["event": event, "sessionID": session.uuidString,
                         "operationID": operation.map { $0.uuidString } as Any? ?? NSNull(),
                         "closed": closed, "metadata": metadata])
            try? publish(root) // A missing trace fails the independent evidence check.
        }
        private func publish(_ root: URL) throws {
            let bytes = try JSONSerialization.data(withJSONObject: ["schema": "Lumen-retained-review-owner-v1", "events": rows], options: [.sortedKeys])
            try bytes.write(to: root.deletingLastPathComponent().appendingPathComponent("Lumen-retained-review-owner-events.json"), options: .atomic)
        }
    }
}

@MainActor
struct HealthRetainedRecoveryFixtureRoot: View {
    @State private var scope = HealthRetainedRecoveryReviewScope()
    @State private var settingsPresented = true
    var body: some View {
        if HealthRetainedReviewUIFixture.mode == "sheet-dismiss" {
            Button("Open settings") { settingsPresented = true }
                .accessibilityIdentifier("retainedFixtureOpenSettings")
                .sheet(isPresented: $settingsPresented) { SettingsView() }
        } else {
            NavigationStack { HealthRecoveryView(scope: scope) }
                .onDisappear { scope.close() }
        }
    }
}
#endif
