#if DEBUG && targetEnvironment(simulator)
import Foundation
import CryptoKit
import Darwin

/// Bounded evidence for one explicitly requested synthetic cancellation case.
/// This registry owns metadata, never a task, gate, session or origin lease.
@MainActor
enum HealthConfirmationLifecycleTrace {
    struct Metadata: Sendable, Equatable {
        let binding: [String: String]
        let taskGeneration: UUID
        let trace: URL
        let acknowledgement: URL
    }
    enum Failure: Error { case invalidContext, invalidRecord, unsafeFile, tooManyEvents }
    static let verificationProtocol = "Lumen-confirmation-lifecycle-verification-v1"
    static let expiryVerificationProtocol = "Lumen-confirmation-expiry-verification-v1"
    private static var activeVerificationProtocol: String {
        expiryRequested ? expiryVerificationProtocol : verificationProtocol
    }
    private static var records: [String: [String: Any]] = [:]
    private static var metadata: [String: Metadata] = [:]
    private static var published: [String: (bytes: Int, sha256: String)] = [:]
    private static var publishedChecks: [String: (bytes: Int, sha256: String)] = [:]
    static var requested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.filter { $0 == HealthLegacyTargetChangeUIFixture.lifecycleFlag }.count == 1
            && (try? HealthLegacyTargetChangeUIFixture.context(args))?.kind == "data"
    }
    static var expiryRequested: Bool {
        requested && ProcessInfo.processInfo.arguments.filter {
            $0 == HealthLegacyTargetChangeUIFixture.expiryFlag
        }.count == 1
    }

    static func register(binding: [String: String], acknowledgement: URL) throws -> Metadata? {
        guard requested else { return nil }
        guard Bundle.main.bundleIdentifier == "com.dbakp.lumen",
              Set(binding.keys) == ["runID", "pid", "sessionID", "captureID", "nonce", "appearanceID", "domains", "legacyDomains", "omitPhotos"],
              ["runID", "sessionID", "captureID", "nonce", "appearanceID"].allSatisfy({ UUID(uuidString: binding[$0] ?? "")?.uuidString == binding[$0] }),
              let nonce = binding["nonce"], UUID(uuidString: nonce) != nil,
              let run = binding["runID"], let session = binding["sessionID"],
              let sessionID = UUID(uuidString: session),
              binding["pid"] == String(getpid()), binding["domains"] == "meals",
              binding["legacyDomains"] == "meals", binding["omitPhotos"] == "false",
              try HealthLegacyTargetChangeUIFixture.confirmationBinding(sessionID)
                == binding.filter({ !["nonce", "appearanceID", "domains", "legacyDomains", "omitPhotos"].contains($0.key) }),
              let parent = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id),
              acknowledgement.deletingLastPathComponent() == parent,
              acknowledgement.lastPathComponent == "Lumen-confirmation-window-" + run.lowercased() + "-" + nonce.lowercased() + "-ack.json",
              metadata[nonce] == nil else { throw Failure.invalidContext }
        let file = parent.appendingPathComponent("Lumen-confirmation-lifecycle-" + run.lowercased() + "-" + nonce.lowercased() + ".json")
        guard !FileManager.default.fileExists(atPath: file.path) else { throw Failure.invalidRecord }
        let value = Metadata(binding: binding, taskGeneration: UUID(), trace: file, acknowledgement: acknowledgement)
        metadata[nonce] = value
        records[nonce] = ["verificationProtocol": activeVerificationProtocol, "binding": binding,
            "taskGeneration": value.taskGeneration.uuidString, "events": [[String: Any]](),
            "checks": [[String: Any]](), "problems": [String]()]
        try append(value, event: "created", fields: [:])
        return value
    }

    static func note(_ value: Metadata?, event: String, fields: [String: Any]) {
        guard let value else { return }
        do { try append(value, event: event, fields: fields) }
        catch { problem(value, String(reflecting: error)) }
    }

    /// Called only by an outside observer after awaiting the exact waiter value.
    static func noteTaskCompleted(_ value: Metadata) {
        do {
            let row = try current(value)
            guard let events = row["events"] as? [[String: Any]],
                  events.filter({ $0["event"] as? String == "closed" }).count == 1,
                  events.last?["event"] as? String == "wait-exit",
                  !events.contains(where: { $0["event"] as? String == "task-value-completed" }) else {
                throw Failure.invalidRecord
            }
            try append(value, event: "task-value-completed", fields: [:])
        } catch { problem(value, String(reflecting: error)) }
    }

    static func observeCompletion(of task: Task<Void, Never>, metadata value: Metadata) {
        Task { @MainActor in
            await task.value
            noteTaskCompleted(value)
        }
    }

    /// A real diagnostic button invokes this function; neither cached rows nor
    /// the host's relay can manufacture a new touch/request or preference read.
    static func check(session: UUID, request: UUID) -> String {
        let matches = metadata.values.filter { $0.binding["sessionID"] == session.uuidString }
        guard requested, matches.count == 1, let value = matches.first else { return "check-failed-context" }
        do {
            var row = try current(value)
            guard let events = row["events"] as? [[String: Any]],
                  let closed = events.first(where: { $0["event"] as? String == "closed" }),
                  closed["reason"] as? String == (expiryRequested ? "deadline" : "not-now"),
                  closed["consumed"] as? Bool == false,
                  events.last?["event"] as? String == "task-value-completed",
                  let checks = row["checks"] as? [[String: Any]], checks.isEmpty else { throw Failure.invalidRecord }
            if expiryRequested {
                guard closed["closed"] as? Bool == true,
                      closed["controlCancelled"] as? Bool == true,
                      let exit = events.first(where: { $0["event"] as? String == "wait-exit" }),
                      exit["expiryClock"] as? String == "ContinuousClock",
                      exit["expiryLimitSeconds"] as? Int == 90,
                      let seconds = exit["expiryElapsedSeconds"] as? Int64, seconds >= 90,
                      let attoseconds = exit["expiryElapsedAttoseconds"] as? Int64,
                      attoseconds >= 0, attoseconds < 1_000_000_000_000_000_000,
                      exit["closed"] as? Bool == true, exit["consumed"] as? Bool == false,
                      exit["controlCancelled"] as? Bool == true,
                      exit["taskCancelled"] as? Bool == false else { throw Failure.invalidRecord }
            }
            let touchAt = Date().timeIntervalSince1970
            var check: [String: Any] = ["ordinal": checks.count + 1, "requestID": request.uuidString,
                                       "touchAt": touchAt, "status": "reading-acknowledgement"]
            try saveCheck(value, check, record: &row)
            let began = Date().timeIntervalSince1970
            let bytes = try regular(value.acknowledgement, limit: 4096)
            check["ackReadStartedAt"] = began
            check["ackReadFinishedAt"] = Date().timeIntervalSince1970
            check["acknowledgement"] = ["bytes": bytes.count, "sha256": digest(bytes), "base64": bytes.base64EncodedString()]
            check["status"] = "acknowledgement-raw-retained"
            try saveCheck(value, check, record: &row)
            let expected = value.binding.filter { ["runID", "pid", "sessionID", "captureID", "nonce"].contains($0.key) }
                .merging(["phase": "ui-observed"]) { _, new in new }
            guard let ack = try JSONSerialization.jsonObject(with: bytes) as? [String: String], ack == expected,
                  let capture = value.binding["captureID"] else { throw Failure.invalidRecord }
            let facts = try HealthLegacyTargetChangeUIFixture.confirmationLifecycleFacts(session: session, capture: capture)
            check["nativeFacts"] = facts
            check["status"] = "native-facts-retained"
            try saveCheck(value, check, record: &row)
            guard facts["healthConnected"] as? Bool == false,
                  facts["knownKeyWritten"] as? Bool == false,
                  facts["fixtureFlags"] as? [String: Bool] == ["singleUseConsumed": false, "knownKeyWritten": false, "failed": false],
                  facts["originalValuesVerified"] as? Bool == true else { throw Failure.invalidRecord }
            check["status"] = "checked"; check["finishedAt"] = Date().timeIntervalSince1970
            try saveCheck(value, check, record: &row)
            return "checked-1"
        } catch {
            problem(value, String(reflecting: error))
            return "check-failed"
        }
    }

    private static func append(_ value: Metadata, event: String, fields: [String: Any]) throws {
        var row = try current(value)
        guard var events = row["events"] as? [[String: Any]], events.count < 16,
              ["created", "wait-started", "closed", "wait-exit", "task-value-completed"].contains(event),
              fields["event"] == nil, fields["at"] == nil else { throw Failure.tooManyEvents }
        if event == "closed" {
            guard !events.contains(where: { $0["event"] as? String == "closed" }) else { throw Failure.invalidRecord }
        }
        events.append(fields.merging(["event": event, "at": Date().timeIntervalSince1970]) { _, new in new })
        row["events"] = events; try save(value, row)
    }

    private static func current(_ value: Metadata) throws -> [String: Any] {
        guard requested, let nonce = value.binding["nonce"], metadata[nonce] == value,
              let row = records[nonce], row["binding"] as? [String: String] == value.binding,
              row["taskGeneration"] as? String == value.taskGeneration.uuidString else { throw Failure.invalidContext }
        return row
    }

    private static func save(_ value: Metadata, _ row: [String: Any]) throws {
        guard let nonce = value.binding["nonce"], metadata[nonce] == value else { throw Failure.invalidContext }
        let bytes = try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys])
        guard bytes.count <= 16384 else { throw Failure.tooManyEvents }
        records[nonce] = row
        try publish(bytes, to: value.trace, previous: published[nonce])
        published[nonce] = (bytes.count, digest(bytes))
    }

    private static func saveCheck(_ value: Metadata, _ check: [String: Any], record: inout [String: Any]) throws {
        guard let nonce = value.binding["nonce"], metadata[nonce] == value else { throw Failure.invalidContext }
        let file = value.trace.deletingPathExtension().appendingPathExtension("check-1.json")
        let full: [String: Any] = ["verificationProtocol": activeVerificationProtocol,
            "binding": value.binding, "taskGeneration": value.taskGeneration.uuidString, "check": check]
        let bytes = try JSONSerialization.data(withJSONObject: full, options: [.prettyPrinted, .sortedKeys])
        guard bytes.count <= 16384 else { throw Failure.tooManyEvents }
        try publish(bytes, to: file, previous: publishedChecks[nonce])
        let hash = digest(bytes); publishedChecks[nonce] = (bytes.count, hash)
        // Only the bounded observation file owns diagnostic fixed-value facts.
        // This registry keeps its identity/digest and touch metadata, no payload.
        record["checks"] = [["ordinal": check["ordinal"]!, "requestID": check["requestID"]!,
            "touchAt": check["touchAt"]!, "status": check["status"]!,
            "file": file.path, "bytes": bytes.count, "sha256": hash]]
        try save(value, record)
    }

    private static func publish(_ bytes: Data, to file: URL, previous: (bytes: Int, sha256: String)?) throws {
        if let previous {
            let current = try regular(file, limit: 16384)
            guard current.count == previous.bytes, digest(current) == previous.sha256 else { throw Failure.invalidRecord }
        } else {
            var facts = stat()
            guard lstat(file.path, &facts) == -1, errno == ENOENT else { throw Failure.unsafeFile }
        }
        // Atomic replacement uses a new sibling, never follows an existing leaf.
        let temporary = file.appendingPathExtension(UUID().uuidString + ".tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.unsafeFile }
        var installed = false
        defer { Darwin.close(fd); if !installed { try? FileManager.default.removeItem(at: temporary) } }
        let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard written == bytes.count, fsync(fd) == 0 else { throw Failure.unsafeFile }
        guard rename(temporary.path, file.path) == 0 else { throw Failure.unsafeFile }
        installed = true
    }

    private static func problem(_ value: Metadata, _ message: String) {
        guard let nonce = value.binding["nonce"], var row = records[nonce] else { return }
        var problems = row["problems"] as? [String] ?? []
        if problems.count < 4 { problems.append(String(message.prefix(1000))) }
        row["problems"] = problems; records[nonce] = row
        try? save(value, row)
    }

    private static func regular(_ file: URL, limit: Int) throws -> Data {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unsafeFile }
        defer { Darwin.close(fd) }
        var facts = stat()
        guard fstat(fd, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              facts.st_nlink == 1, facts.st_size > 0, facts.st_size <= Int64(limit) else { throw Failure.unsafeFile }
        var buffer = [UInt8](repeating: 0, count: limit + 1)
        let count = Darwin.read(fd, &buffer, buffer.count)
        guard count == Int(facts.st_size) else { throw Failure.unsafeFile }
        return Data(buffer.prefix(count))
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
