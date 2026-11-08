#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import CryptoKit
import Darwin

/// One known preference mutation in the explicitly guarded synthetic fixture.
/// No host preferences write, replacement authority or forced product error.
enum HealthLegacyTargetChangeUIFixture {
    enum Failure: Error { case invalidContext, invalidObservation, duplicateMutation }
    struct Context: Equatable { let runID: UUID; let kind: String }
    static let flag = "-health-legacy-target-change-ui"
    static let runFlag = "-health-legacy-target-change-run"
    static let verificationProtocol = "Lumen-legacy-target-change-verification-v1"
    static let newerMeals = Data("{synthetic newer persisted meals damaged".utf8)
    static let newerMealsString = "Synthetic newer saved value e\u{301} 🫖"
    private static let bridge = Bridge()

    static func context(_ args: [String]) throws -> Context? {
        guard args.contains(flag) || args.contains(runFlag) else { return nil }
        func one(_ flag: String) throws -> String {
            let positions = args.indices.filter { args[$0] == flag }
            guard positions.count == 1, let index = positions.first, args.indices.contains(index + 1),
                  !args[index + 1].hasPrefix("-") else { throw Failure.invalidContext }
            return args[index + 1]
        }
        guard try one(flag) == "ready", let run = UUID(uuidString: try one(runFlag)),
              let reset = UUID(uuidString: try one("-health-legacy-reset-run")), run == reset,
              ["data", "string"].contains(try one("-health-legacy-origin-ui")), try one("-health-backup-case") == "legacy"
        else { throw Failure.invalidContext }
        for required in ["-resetForUITests", "-health-backup-ui-fixture", "-health-backup-empty-ui",
                         "-health-backup-healthy-merge-ui", "-health-legacy-reset-ui"] {
            guard args.filter({ $0 == required }).count == 1 else { throw Failure.invalidContext }
        }
        for forbidden in ["-health-legacy-reset-observer", "-health-legacy-reset-diagnostic-only",
                          "-health-legacy-origin-mixed-ui", "-health-legacy-capture-ui"] {
            guard !args.contains(forbidden) else { throw Failure.invalidContext }
        }
        return Context(runID: run, kind: try one("-health-legacy-origin-ui"))
    }
    static var requested: Bool { (try? context(ProcessInfo.processInfo.arguments)) != nil }
    static func preflightIfRequested() throws {
        guard let context = try context(ProcessInfo.processInfo.arguments) else { return }
        guard let parent = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else { throw Failure.invalidContext }
        var facts = stat()
        guard lstat(parent.path, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.invalidContext }
        let prefix = "Lumen-legacy-target-change-" + context.runID.uuidString.lowercased()
        guard try FileManager.default.contentsOfDirectory(atPath: parent.path).allSatisfy({ !$0.hasPrefix(prefix) }) else {
            throw Failure.invalidContext
        }
    }
    static func prepare(in root: URL) throws {
        guard let context = try context(ProcessInfo.processInfo.arguments) else { return }
        try bridge.prepare(context, root: root)
    }
    static func opened(_ session: UUID) { guard requested else { return }; bridge.opened(session) }
    static func began(_ session: UUID, control: BackupOperationControl) {
        guard requested else { return }; bridge.began(session, control: control)
    }
    static func ready(_ session: UUID, control: BackupOperationControl, domains: Set<HealthLocalFiles.Domain>) {
        guard requested else { return }; bridge.ready(session, control: control, domains: domains)
    }
    static func closed(_ session: UUID) { guard requested else { return }; bridge.closed(session) }
    static func rejected(_ session: UUID, changed: Bool, message: String, error: Error, control: BackupOperationControl) {
        guard requested else { return }
        bridge.rejected(session, changed: changed, message: message,
                        errorType: String(reflecting: type(of: error)), control: String(describing: ObjectIdentifier(control)))
    }
    static func succeeded(_ session: UUID) { guard requested else { return }; bridge.succeeded(session) }
    static var canStart: Bool { bridge.canStart }
    @MainActor static func start() {
        do {
            guard let context = try context(ProcessInfo.processInfo.arguments),
                  Bundle.main.bundleIdentifier == "com.dbakp.lumen" else { throw Failure.invalidContext }
            let root = try bridge.root(for: context)
            func missing(_ name: String) -> [String: Any] {
                var facts = stat()
                let result = lstat(root.appendingPathComponent(name).path, &facts)
                let failure = result == -1 ? errno : 0
                return ["missing": result == -1 && failure == ENOENT,
                        "exists": result == 0, "errno": Int(failure), "mode": Int(facts.st_mode)]
            }
            let meals = missing("meals.json"), workouts = missing("workouts.json")
            let health = UserDefaults.standard.bool(forKey: "lumen.health.connected")
            let observation: [String: Any] = ["runID": context.runID.uuidString, "pid": Int(getpid()),
                "at": Date().timeIntervalSince1970, "fixed": fixedFacts(), "healthConnected": health,
                "mealsLeaf": meals, "workoutsLeaf": workouts]
            // Persist the actual bounded observation before its value assertions.
            // This is metadata only: no LocalStore write/revision/defaults API.
            try bridge.observeBootstrap(context, facts: observation)
            guard !health, meals["missing"] as? Bool == true, workouts["missing"] as? Bool == true else {
                throw Failure.invalidObservation
            }
            try missingMeals(in: root)
            try requireOriginalFixedValues()
            try bridge.finishBootstrap(context)
        } catch { bridge.failed(error, facts: fixedFacts()) }
    }
    static var phase: String { bridge.phase }
    static func canChange(_ session: UUID) -> Bool { bridge.canChange(session) }
    static func expectedMeals() -> Data { bridge.didWrite ? newerMeals : HealthLegacyOriginUIFixture.data }
    static func expectedMealsString() -> String { bridge.didWrite ? newerMealsString : HealthLegacyOriginUIFixture.string }

    @MainActor static func change(_ session: BackupRecoveryReviewSession) {
        do {
            guard let context = try context(ProcessInfo.processInfo.arguments),
                  Bundle.main.bundleIdentifier == "com.dbakp.lumen" else { throw Failure.invalidContext }
            let root = try bridge.root(for: context)
            // The complete authority/value/leaf guards and single known write
            // share this nonrecursive serialization. No revision/read API inside.
            try LocalStore.performWrite {
                let captureID = try bridge.authorize(context, session: session.id)
                try bridge.observedGuard(context, session: session.id, captureID: captureID, facts: fixedFacts())
                guard session.originMetadata?.legacyDomains.contains(.meals) == true,
                      !UserDefaults.standard.bool(forKey: "lumen.health.connected") else { throw Failure.invalidObservation }
                try missingMeals(in: root)
                try requireOriginalFixedValues()
                let guardControl = BackupOperationControl()
                let origins = try session.acquireOrigins([.meals], control: guardControl)
                guard origins.count == 1, let origin = origins[.meals] else { throw Failure.invalidObservation }
                // This is a separately labelled fixture guard acquisition of
                // the actual OLD immutable token, never a recapture/replacement.
                try origin.verify(in: root, legacy: { key in
                    guard key == "lumen.health.meals.v1" else { throw Failure.invalidObservation }
                    return try checkedFixedValue(key, mealsChanged: false)
                }, control: guardControl)
                try bridge.beforeWrite(context, session: session.id, captureID: captureID, facts: fixedFacts(),
                                       guardControl: String(describing: ObjectIdentifier(guardControl)))
                UserDefaults.standard.set(context.kind == "data" ? newerMeals as Any : newerMealsString as Any,
                                          forKey: "lumen.health.meals.v1")
                bridge.markWritten()
                try bridge.observedResult(context, session: session.id, captureID: captureID, facts: fixedFacts())
                try requireFixedValues(mealsChanged: true)
                try missingMeals(in: root)
                try bridge.afterWrite(context, session: session.id, captureID: captureID, facts: fixedFacts())
            }
        } catch { bridge.failed(error, facts: fixedFacts()) }
    }

    private static func missingMeals(in root: URL) throws {
        var facts = stat()
        guard lstat(root.path, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.invalidObservation }
        guard lstat(root.appendingPathComponent("meals.json").path, &facts) == -1, errno == ENOENT else { throw Failure.invalidObservation }
    }
    /// Explicit little-endian code units: do not normalize or compare Swift graphemes.
    static func stringBytes(_ string: NSString) -> Data {
        var bytes = Data()
        for index in 0..<string.length {
            let unit = string.character(at: index)
            bytes.append(UInt8(truncatingIfNeeded: unit)); bytes.append(UInt8(unit >> 8))
        }
        return bytes
    }
    private static func checkedFixedValue(_ key: String, mealsChanged: Bool) throws -> Any {
        guard ["lumen.health.meals.v1", "lumen.health.workouts.v1"].contains(key),
              let context = try context(ProcessInfo.processInfo.arguments) else { throw Failure.invalidContext }
        let persisted = UserDefaults.standard.persistentDomain(forName: "com.dbakp.lumen")?[key]
        let effective = UserDefaults.standard.object(forKey: key)
        let changed = key == "lumen.health.meals.v1" && mealsChanged
        if context.kind == "data" {
            let expected = changed ? newerMeals : HealthLegacyOriginUIFixture.data
            guard let raw = persisted as? Data, let active = effective as? Data,
                  raw == expected, active == raw else { throw Failure.invalidObservation }
            return raw
        }
        guard context.kind == "string", let raw = persisted as? NSString, let active = effective as? NSString else {
            throw Failure.invalidObservation
        }
        let expected = changed ? newerMealsString : HealthLegacyOriginUIFixture.string
        guard stringBytes(raw) == stringBytes(expected as NSString), stringBytes(active) == stringBytes(raw) else {
            throw Failure.invalidObservation
        }
        return raw
    }
    private static func requireOriginalFixedValues() throws { try requireFixedValues(mealsChanged: false) }
    private static func requireFixedValues(mealsChanged: Bool) throws {
        for key in ["lumen.health.meals.v1", "lumen.health.workouts.v1"] {
            _ = try checkedFixedValue(key, mealsChanged: mealsChanged)
        }
    }
    private static func fixedFacts() -> [String: Any] {
        let values = UserDefaults.standard.persistentDomain(forName: "com.dbakp.lumen") ?? [:]
        var result: [String: Any] = [:]
        for key in ["lumen.health.meals.v1", "lumen.health.workouts.v1"] {
            var row: [String: Any] = [:]
            for (name, value) in [("persisted", values[key]), ("effective", UserDefaults.standard.object(forKey: key))] {
                var fact: [String: Any] = ["present": value != nil, "type": value.map { String(reflecting: type(of: $0)) } ?? "nil"]
                if let data = value as? Data {
                    fact["bytes"] = data.count
                    if data.count <= 4096 {
                        fact["sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                        if data == HealthLegacyOriginUIFixture.data || data == newerMeals { fact["payload"] = data.base64EncodedString() }
                    } else { fact["oversize"] = true }
                }
                if let string = value as? NSString {
                    fact["utf16Units"] = string.length
                    if string.length <= 2048 {
                        let bytes = stringBytes(string)
                        fact["bytes"] = bytes.count
                        fact["sha256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                        if bytes == stringBytes(HealthLegacyOriginUIFixture.string as NSString)
                            || bytes == stringBytes(newerMealsString as NSString) { fact["payload"] = bytes.base64EncodedString() }
                    } else { fact["oversize"] = true }
                }
                row[name] = fact
            }
            result[key] = row
        }
        return result
    }

    private final class Bridge: @unchecked Sendable {
        private let lock = NSLock()
        private var context: Context?
        private var preparedPID: pid_t?
        private var rootURL: URL?
        private var parent: URL?
        private var active: UUID?
        private weak var pendingControl: BackupOperationControl?
        private var captureID: UUID?
        private var readyID: UUID?
        private var consumed = false
        private var written = false
        private var failedFlag = false
        private var bootstrapNativeChecked = false
        private var bootstrapObservation: [String: Any]?
        private var rows: [[String: Any]] = []
        private var status = "not-prepared"
        var didWrite: Bool { lock.lock(); defer { lock.unlock() }; return written }
        var phase: String {
            lock.lock()
            let status = self.status, parent = self.parent, context = self.context, active = self.active, capture = captureID
            let sequence = rows.count, readyCount = rows.filter { $0["event"] as? String == "capture-ready" }.count
            lock.unlock()
            let expected: String?
            switch status {
            case "before-selection": expected = "host-before-selection"
            case "ready": expected = "host-ready"
            case "mutated": expected = "host-target-changed"
            case "rejected": expected = "host-rejected"
            case "fresh-ready": expected = "host-fresh-ready"
            case "fresh-recovery-committed": expected = "host-fresh-committed"
            case "closed": expected = readyCount >= 2 ? "host-final-closed" : "host-owners-closed"
            default: expected = nil
            }
            guard let expected, let parent, let context else { return status }
            let ack = parent.appendingPathComponent("Lumen-legacy-target-change-" + context.runID.uuidString.lowercased() + "-ack.json")
            var facts = stat()
            guard lstat(ack.path, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  facts.st_size > 0, facts.st_size <= 4096,
                  let data = try? Data(contentsOf: ack), data.count <= 4096,
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  row["runID"] as? String == context.runID.uuidString, row["pid"] as? Int == Int(getpid()),
                  row["sessionID"] as? String == (active?.uuidString ?? ""), row["captureID"] as? String == (capture?.uuidString ?? ""),
                  row["sequence"] as? Int == sequence, row["phase"] as? String == expected else { return status }
            return expected
        }
        var canStart: Bool {
            lock.lock(); defer { lock.unlock() }
            return context != nil && preparedPID == getpid() && active == nil && captureID == nil
                && !bootstrapNativeChecked && bootstrapObservation == nil && !consumed && !failedFlag && status == "prepared"
        }
        func observeBootstrap(_ context: Context, facts: [String: Any]) throws {
            lock.lock(); defer { lock.unlock() }
            guard self.context == context, preparedPID == getpid(), active == nil, captureID == nil,
                  !bootstrapNativeChecked, bootstrapObservation == nil, !consumed, !failedFlag,
                  status == "prepared" else { throw Failure.invalidObservation }
            bootstrapObservation = facts; status = "bootstrap-checking"
            try save()
        }
        func finishBootstrap(_ context: Context) throws {
            lock.lock(); defer { lock.unlock() }
            guard self.context == context, preparedPID == getpid(), active == nil, captureID == nil,
                  !bootstrapNativeChecked, bootstrapObservation != nil, !consumed, !failedFlag,
                  status == "bootstrap-checking" else { throw Failure.invalidObservation }
            bootstrapNativeChecked = true; status = "before-selection"
            try save()
        }
        func canChange(_ session: UUID) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return bootstrapNativeChecked && !consumed && !failedFlag && active == session && readyID != nil && status == "ready"
        }
        func prepare(_ context: Context, root: URL) throws {
            lock.lock(); defer { lock.unlock() }
            guard self.context == nil, root.lastPathComponent == "LumenData" else { throw Failure.invalidContext }
            self.context = context; preparedPID = getpid(); rootURL = root; parent = root.deletingLastPathComponent(); status = "prepared"
            try save(initial: true)
        }
        func root(for context: Context) throws -> URL {
            lock.lock(); defer { lock.unlock() }
            guard self.context == context, preparedPID == getpid(), let rootURL, !failedFlag else { throw Failure.invalidContext }
            return rootURL
        }
        func opened(_ session: UUID) { update {
            guard bootstrapNativeChecked else { throw Failure.invalidObservation }
            active = session; pendingControl = nil; captureID = nil; readyID = nil; status = "opened"
            rows.append(["event": "open", "sessionID": session.uuidString])
        } }
        func began(_ session: UUID, control: BackupOperationControl) { update {
            guard active == session else { throw Failure.invalidObservation }
            pendingControl = control; captureID = UUID(); readyID = nil; status = "capturing"
            rows.append(["event": "capture-began", "sessionID": session.uuidString,
                         "captureID": captureID!.uuidString, "actualControl": String(describing: ObjectIdentifier(control))])
        } }
        func ready(_ session: UUID, control: BackupOperationControl, domains: Set<HealthLocalFiles.Domain>) { update {
            guard active == session, pendingControl === control, let captureID, domains.contains(.meals) else { throw Failure.invalidObservation }
            readyID = captureID; pendingControl = nil; status = consumed ? "fresh-ready" : "ready"
            rows.append(["event": "capture-ready", "sessionID": session.uuidString, "captureID": captureID.uuidString,
                         "actualControl": String(describing: ObjectIdentifier(control)), "domains": domains.map(\.rawValue).sorted()])
        } }
        func closed(_ session: UUID) { update {
            rows.append(["event": "closed", "sessionID": session.uuidString])
            if active == session { readyID = nil; pendingControl = nil; status = "closed" }
        } }
        func rejected(_ session: UUID, changed: Bool, message: String, errorType: String, control: String) { update {
            guard active == session, readyID != nil, consumed, written else { throw Failure.invalidObservation }
            status = "rejected"
            rows.append(["event": "actual-recovery-error", "sessionID": session.uuidString,
                         "changedClassification": changed, "publishedMessage": message,
                         "actualErrorType": errorType, "actualRecoveryControl": control])
        } }
        func succeeded(_ session: UUID) { update {
            guard active == session, bootstrapNativeChecked, consumed, written,
                  status == "fresh-ready", let readyID, readyID == captureID,
                  let original = rows.first?["sessionID"] as? String,
                  original != session.uuidString,
                  rows.filter({ $0["event"] as? String == "actual-recovery-error" }).count == 1,
                  let rejection = rows.first(where: { $0["event"] as? String == "actual-recovery-error" }),
                  rejection["sessionID"] as? String == original,
                  rejection["changedClassification"] as? Bool == true
            else { throw Failure.invalidObservation }
            status = "fresh-recovery-committed"
            rows.append(["event": "actual-recovery-success", "sessionID": session.uuidString,
                         "captureID": readyID.uuidString])
        } }
        func authorize(_ context: Context, session: UUID) throws -> UUID {
            lock.lock(); defer { lock.unlock() }
            guard self.context == context, preparedPID == getpid(), bootstrapNativeChecked, active == session, !failedFlag, !consumed,
                  status == "ready", let readyID else { throw Failure.duplicateMutation }
            return readyID
        }
        func observedGuard(_ context: Context, session: UUID, captureID: UUID, facts: [String: Any]) throws {
            lock.lock(); defer { lock.unlock() }
            guard self.context == context, preparedPID == getpid(), active == session, readyID == captureID,
                  !consumed, !failedFlag else { throw Failure.invalidObservation }
            rows.append(["event": "guard-observation", "sessionID": session.uuidString,
                         "captureID": captureID.uuidString, "fixed": facts])
            try save()
        }
        func beforeWrite(_ context: Context, session: UUID, captureID: UUID, facts: [String: Any], guardControl: String) throws {
            lock.lock(); defer { lock.unlock() }
            guard self.context == context, preparedPID == getpid(), active == session, readyID == captureID, !consumed, !failedFlag else { throw Failure.invalidObservation }
            consumed = true; status = "before-write"
            rows.append(["event": "before-write", "sessionID": session.uuidString, "captureID": captureID.uuidString,
                         "oldTokenVerified": true, "guardAcquisitionControl": guardControl, "fixed": facts])
            try save()
        }
        func markWritten() { lock.lock(); written = true; lock.unlock() }
        func observedResult(_ context: Context, session: UUID, captureID: UUID, facts: [String: Any]) throws {
            lock.lock(); defer { lock.unlock() }
            guard self.context == context, preparedPID == getpid(), active == session, readyID == captureID,
                  consumed, written, !failedFlag else { throw Failure.invalidObservation }
            rows.append(["event": "result-observation", "sessionID": session.uuidString,
                         "captureID": captureID.uuidString, "fixed": facts])
            try save()
        }
        func afterWrite(_ context: Context, session: UUID, captureID: UUID, facts: [String: Any]) throws {
            lock.lock(); defer { lock.unlock() }
            guard self.context == context, preparedPID == getpid(), active == session, readyID == captureID, consumed, written, !failedFlag else { throw Failure.invalidObservation }
            status = "mutated"
            rows.append(["event": "mutated", "sessionID": session.uuidString, "captureID": captureID.uuidString, "fixed": facts])
            try save()
        }
        func failed(_ error: Error, facts: [String: Any]? = nil) {
            lock.lock(); defer { lock.unlock() }
            failedFlag = true; status = "verification-failed"
            var row: [String: Any] = ["event": "failed", "error": String(describing: error)]
            if let facts { row["fixed"] = facts }
            rows.append(row)
            try? save()
        }
        private func update(_ operation: () throws -> Void) {
            lock.lock(); defer { lock.unlock() }
            guard !failedFlag, preparedPID == getpid() else { return }
            do { try operation(); try save() }
            catch { failedFlag = true; status = "verification-failed"; rows.append(["event": "failed", "error": String(describing: error)]); try? save() }
        }
        private func save(initial: Bool = false) throws {
            guard let context, let parent, preparedPID == getpid(), rows.count <= 40 else { throw Failure.invalidObservation }
            let file = parent.appendingPathComponent("Lumen-legacy-target-change-" + context.runID.uuidString.lowercased() + "-" + String(getpid()) + ".json")
            if !initial {
                var facts = stat()
                guard lstat(file.path, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                      facts.st_size > 0, facts.st_size <= 128 * 1024 else { throw Failure.invalidObservation }
            }
            let value: [String: Any] = ["verificationProtocol": verificationProtocol, "originKind": context.kind, "runID": context.runID.uuidString,
                "pid": Int(getpid()), "status": status, "at": Date().timeIntervalSince1970,
                "sequence": rows.count, "sessionID": active?.uuidString ?? "", "captureID": captureID?.uuidString ?? "",
                "singleUseConsumed": consumed, "knownKeyWritten": written, "failed": failedFlag,
                "healthConnected": UserDefaults.standard.bool(forKey: "lumen.health.connected"),
                "bootstrapNativeChecked": bootstrapNativeChecked, "bootstrapObservation": bootstrapObservation ?? [:], "events": rows]
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
            if initial { try data.write(to: file, options: .withoutOverwriting) }
            else { try data.write(to: file, options: .atomic) }
        }
    }
}

@MainActor struct HealthLegacyTargetChangeUIProbe: View {
    let session: BackupRecoveryReviewSession
    var body: some View {
        if HealthLegacyTargetChangeUIFixture.requested {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Button("Change saved data") { HealthLegacyTargetChangeUIFixture.change(session) }
                    .disabled(!HealthLegacyTargetChangeUIFixture.canChange(session.id))
                    .accessibilityIdentifier("changeHealthRecoveryTarget")
                    .accessibilityValue(HealthLegacyTargetChangeUIFixture.phase)
            }
        }
    }
}

@MainActor struct HealthLegacyTargetStartUIProbe: View {
    var body: some View {
        if HealthLegacyTargetChangeUIFixture.requested {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Button("Start check") { HealthLegacyTargetChangeUIFixture.start() }
                    .disabled(!HealthLegacyTargetChangeUIFixture.canStart)
                    .accessibilityIdentifier("startHealthRecoveryCheck")
                    .accessibilityValue(HealthLegacyTargetChangeUIFixture.phase)
            }
        }
    }
}

@MainActor struct HealthLegacyTargetStatusUIProbe: View {
    let location: String
    var body: some View {
        if HealthLegacyTargetChangeUIFixture.requested && location != "parent" {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Text("Target check").accessibilityIdentifier("healthLegacyTargetStatus-" + location)
                    .accessibilityValue(HealthLegacyTargetChangeUIFixture.phase)
            }
        }
    }
}
#endif
