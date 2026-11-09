#if DEBUG && targetEnvironment(simulator)
import Foundation
import Darwin

/// Dedicated synthetic confirmation-window protocol. A gate is not permission
/// to recover; the unchanged product transaction must reject the old token.
@MainActor
final class HealthConfirmationTargetChangeGate {
    static let flag = "-health-legacy-confirmation-window-ui"
    static var requested: Bool {
        HealthLegacyTargetChangeUIFixture.requested && ProcessInfo.processInfo.arguments.filter { $0 == flag }.count == 1
    }
    let nonce = UUID()
    let appearance: UUID
    let sessionID: UUID
    let binding: [String: String]
    let lifecycle: HealthConfirmationLifecycleTrace.Metadata?
    private let ack: URL
    private let control = BackupOperationControl()
    private var closed = false
    private var consumed = false
    private var expiryElapsed: (seconds: Int64, attoseconds: Int64)?
    var accessibilityValue: String {
        let record = binding.merging(["nonce": nonce.uuidString, "appearanceID": appearance.uuidString,
            "domains": "meals", "legacyDomains": "meals", "omitPhotos": "false", "phase": consumed ? "mutated" : "armed",
            "targetPhase": HealthLegacyTargetChangeUIFixture.phase]) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "invalid" }
        return value
    }
    init(session: BackupRecoveryReviewSession, appearance: UUID, domains: Set<HealthLocalFiles.Domain>,
         legacyDomains: Set<HealthLocalFiles.Domain>, omitPhotos: Bool) throws {
        guard Self.requested, domains == [.meals], legacyDomains == [.meals], !omitPhotos,
              Bundle.main.bundleIdentifier == "com.dbakp.lumen",
              let parent = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else {
            throw HealthLegacyTargetChangeUIFixture.Failure.invalidContext
        }
        self.appearance = appearance; sessionID = session.id
        binding = try HealthLegacyTargetChangeUIFixture.confirmationBinding(session.id)
        let stem = "Lumen-confirmation-window-" + binding["runID"]!.lowercased() + "-" + nonce.uuidString.lowercased()
        let gate = parent.appendingPathComponent(stem + ".json")
        ack = parent.appendingPathComponent(stem + "-ack.json")
        var record = binding; record["nonce"] = nonce.uuidString
        record["appearanceID"] = appearance.uuidString
        record["domains"] = "meals"; record["legacyDomains"] = "meals"; record["omitPhotos"] = "false"
        let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        let temporary = gate.appendingPathExtension("tmp")
        try bytes.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.moveItem(at: temporary, to: gate)
        lifecycle = try HealthConfirmationLifecycleTrace.register(binding: record,
            acknowledgement: parent.appendingPathComponent(stem + "-ack.json"))
    }
    func close(reason: String = "unspecified") {
        guard !closed else { return }
        closed = true; control.cancel()
        HealthConfirmationLifecycleTrace.note(lifecycle, event: "closed", fields: ["reason": reason,
            "closed": closed, "consumed": consumed, "controlCancelled": control.verificationCancelled])
    }
    func noteWaiterStarted() {
        HealthConfirmationLifecycleTrace.note(lifecycle, event: "wait-started", fields: [
            "taskCancelled": Task.isCancelled, "closed": closed, "consumed": consumed,
            "controlCancelled": control.verificationCancelled])
    }
    func noteWaiterExit(errorType: String) {
        var fields: [String: Any] = [
            "errorType": errorType, "taskCancelled": Task.isCancelled, "closed": closed,
            "consumed": consumed, "controlCancelled": control.verificationCancelled]
        if let expiryElapsed {
            fields["expiryClock"] = "ContinuousClock"
            fields["expiryLimitSeconds"] = 90
            fields["expiryElapsedSeconds"] = expiryElapsed.seconds
            fields["expiryElapsedAttoseconds"] = expiryElapsed.attoseconds
        }
        HealthConfirmationLifecycleTrace.note(lifecycle, event: "wait-exit", fields: fields)
    }
    func waitAndChange(_ session: BackupRecoveryReviewSession, stillPresented: () -> Bool) async throws {
        let began = ContinuousClock.now
        let deadline = began.advanced(by: .seconds(90))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation(); try control.checkCancellation()
            guard !closed, !consumed, session.id == sessionID, stillPresented(),
                  try HealthLegacyTargetChangeUIFixture.confirmationBinding(session.id) == binding else {
                throw CancellationError()
            }
            if let bytes = try readAcknowledgement() {
                let expected = binding.merging(["nonce": nonce.uuidString, "phase": "ui-observed"]) { _, new in new }
                guard let row = try JSONSerialization.jsonObject(with: bytes) as? [String: String], row == expected else {
                    throw HealthLegacyTargetChangeUIFixture.Failure.invalidObservation
                }
                // All guards and the existing serialized known write run on the
                // MainActor without another suspension. Dismiss/Recover closes
                // this owner synchronously before any product recovery begins.
                try Task.checkCancellation(); try control.checkCancellation()
                guard !closed, stillPresented(), try HealthLegacyTargetChangeUIFixture.confirmationBinding(session.id) == binding else {
                    throw CancellationError()
                }
                HealthLegacyTargetChangeUIFixture.change(session)
                guard ["mutated", "host-target-changed"].contains(HealthLegacyTargetChangeUIFixture.phase) else {
                    throw HealthLegacyTargetChangeUIFixture.Failure.invalidObservation
                }
                consumed = true
                while ContinuousClock.now < deadline {
                    try Task.checkCancellation(); try control.checkCancellation()
                    guard !closed, stillPresented() else { throw CancellationError() }
                    if HealthLegacyTargetChangeUIFixture.phase == "host-target-changed" { return }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw HealthLegacyTargetChangeUIFixture.Failure.invalidObservation
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        if HealthConfirmationLifecycleTrace.expiryRequested {
            expiryElapsed = began.duration(to: ContinuousClock.now).components
            close(reason: "deadline")
        }
        throw HealthLegacyTargetChangeUIFixture.Failure.invalidObservation
    }
    private func readAcknowledgement() throws -> Data? {
        let descriptor = open(ack.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor == -1 {
            if errno == ENOENT { return nil }
            throw HealthLegacyTargetChangeUIFixture.Failure.invalidObservation
        }
        defer { Darwin.close(descriptor) }
        var facts = stat()
        guard fstat(descriptor, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              facts.st_nlink == 1, facts.st_size > 0, facts.st_size <= 4096 else {
            throw HealthLegacyTargetChangeUIFixture.Failure.invalidObservation
        }
        var buffer = [UInt8](repeating: 0, count: 4097)
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        guard count == Int(facts.st_size) else { throw HealthLegacyTargetChangeUIFixture.Failure.invalidObservation }
        return Data(buffer.prefix(count))
    }
}
#endif
