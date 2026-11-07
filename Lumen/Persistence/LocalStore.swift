import Foundation
import UIKit

// MARK: - Local-first persistence
// Everything lives on this device, inside the App Group container so the
// widget reads the same truth. One JSON file per domain, written atomically.
// Swapping in a remote backend later means replacing this type only.

public enum AppGroup {
    public static let id = "group.com.dbakp.lumen"
    /// Shared defaults for small values the widget needs.
    public static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

public enum LocalStore {
    private static let removeAbandonedStages: Void = {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let abandoned = ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []).filter {
            $0.lastPathComponent.hasPrefix("LumenData.restore-") || $0.lastPathComponent.hasPrefix("LumenData.retired-") || $0.lastPathComponent.hasPrefix("LumenData.discovery-")
        }
        // Capture only leftovers present at first access, before a new restore can start.
        DispatchQueue.global(qos: .utility).async { for folder in abandoned { try? fm.removeItem(at: folder) } }
    }()
    private static let writes = BackupStorageRevision()
    static var revision: UInt64 { writes.current }
    static func performWrite<T>(_ operation: () throws -> T) rethrows -> T { try writes.write(operation) }
    static func commitRestore(_ transaction: BackupFileTransaction, revision: UInt64) throws {
        try writes.commit(ifUnchanged: revision) { try transaction.commit() }
    }
    static func commitRestore(_ transaction: BackupFileTransaction, revision: UInt64,
                              control: BackupOperationControl) throws {
        try writes.commit(ifUnchanged: revision) { try transaction.commit(control: control) }
    }
    /// Called by detached review work. Deliberately bypasses checkedDirectory:
    /// observing a review must not create/restore a root or clean old stages.
    static func captureLegacyRecoveryReview(_ domains: Set<HealthLocalFiles.Domain>,
                                            control: BackupOperationControl) throws
        -> HealthLegacyRecoveryOrigin.ReviewSnapshot {
        let root = storageRoot
        return try writes.read {
            try HealthRecoveryCopies.serialized {
                try HealthLegacyRecoveryOrigin.captureReview(domains, in: root,
                    legacy: { try strictRecoveryLegacyValue($0, control: control) }, control: control)
            }
        }
    }
    /// No storage/revision/write APIs here: also invoked inside final commit.
    private static func strictRecoveryLegacyValue(_ key: String, control: BackupOperationControl) throws -> Any? {
        try control.checkCancellation()
        guard let domain = [HealthLocalFiles.Domain.meals, .workouts, .goals].first(where: { $0.legacyKey == key }),
              let bundle = Bundle.main.bundleIdentifier else { throw HealthLocalFiles.Failure.invalid }
        // Foundation may allocate the entire domain temporarily. Retain only the
        // fixed requested value; never log or retain unrelated preferences.
        let persisted = UserDefaults.standard.persistentDomain(forName: bundle)?[key]
        return try HealthLegacyRecoveryOrigin.checkedPersistentValue(persisted,
            effective: UserDefaults.standard.object(forKey: key), domain: domain, control: control)
    }
    @MainActor static func recoverHealthChecked(_ payload: HealthRecoverySelection.Payload,
                                                control: BackupOperationControl = .init(),
                                                canCommit: () -> Bool, didCommit: () -> Void) async throws {
        try await withTaskCancellationHandler {
            try control.checkCancellation()
            let root = try checkedDirectory(), captured = revision, owner = try HealthWriteDeviceOwner.current()
            let transaction = try await Task.detached(priority: .userInitiated) {
                try HealthRecoverySelection.prepare(payload, into: root, owner: owner, control: control,
                                                    legacy: { try strictRecoveryLegacyValue($0, control: control) })
            }.value
            try Task.checkCancellation(); try control.checkCancellation()
            guard canCommit() else { throw BackupError.recordsChanged }
            try commitRestore(transaction, revision: captured, control: control)
            // Installation has completed. A later cancellation must not turn
            // the saved outcome into a rollback claim.
            didCommit()
        } onCancel: { control.cancel() }
    }

    /// Cache-only replacement preserves all pending external work. Capture
    /// revision/owner before querying, not after the suspended query returns.
    @MainActor static func replaceDailyCacheChecked(_ replacement: HealthDailyCache.Replacement,
                                                    replacing boundary: HealthDailyCache.Boundary,
                                                    expectedRevision: UInt64, expectedOwner: UUID,
                                                    control: BackupOperationControl,
                                                    canCommit: () -> Bool, didCommit: () -> Void) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation(); try control.checkCancellation()
            guard revision == expectedRevision, try HealthWriteDeviceOwner.current() == expectedOwner,
                  canCommit() else { throw BackupError.recordsChanged }
            let root = try checkedDirectory()
            let transaction = try await Task.detached(priority: .userInitiated) {
                try HealthDailyCache.prepare(replacement, replacing: boundary, in: root, owner: expectedOwner, control: control)
            }.value
            try Task.checkCancellation(); try control.checkCancellation()
            try writes.commit(ifUnchanged: expectedRevision) {
                guard try HealthWriteDeviceOwner.current() == expectedOwner, canCommit() else { throw BackupError.recordsChanged }
                try HealthDailyCache.verify(boundary, in: root, control: control)
                try transaction.commit(control: control)
            }
            didCommit()
        } onCancel: { control.cancel() }
    }
    /// Encode on the caller's actor; prepare off-thread, then install only if no
    /// local writer changed the captured state. No partial goals/today save.
    @MainActor static func saveWeightChecked(goals: HealthGoals, snapshot: DayMetrics,
                                           healthEvent: HealthWriteJournal.Component? = nil,
                                           healthBoundaries: [HealthLocalFiles.Domain: HealthLocalFiles.Boundary] = [:],
                                           canCommit: () -> Bool, didCommit: () -> Void) async throws {
        let captured = revision
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var files = ["goals.json": try encoder.encode(goals), "today.json": try encoder.encode(snapshot)]
        if let healthEvent {
            var journal = try healthWriteJournalChecked()
            try journal.append(domain: .weight, localID: UUID().uuidString, components: [healthEvent])
            files[HealthWriteFiles.name] = try journal.encoded()
        }
        try await saveLinkedFilesChecked(files, expectedRevision: captured, healthBoundaries: healthBoundaries, canCommit: canCommit, didCommit: didCommit)
    }

    @MainActor static func healthWriteJournalChecked() throws -> HealthWriteJournal {
        try HealthWriteFiles.read(from: checkedDirectory(), owner: HealthWriteDeviceOwner.current())
    }

    /// Quick logs are synchronous throwing APIs. Stage both files and install
    /// one recoverable directory swap before publishing either live state or
    /// external work. Weight uses the asynchronous linked-file path above.
    @MainActor static func saveHealthChangeChecked<T: Encodable>(_ records: T, as name: String,
                                                               boundary: HealthLocalFiles.Boundary,
                                                               change: (inout HealthWriteJournal) throws -> Void) throws {
        let root = try checkedDirectory(), captured = revision
        _ = try validateHealthSources([name + ".json"], expected: HealthLocalFiles.Domain(rawValue: name).map { [$0: boundary] } ?? [:])
        var journal = try HealthWriteFiles.read(from: root, owner: HealthWriteDeviceOwner.current())
        try change(&journal)
        let data = try encoder.encode(records)
        try validateNewHealthData(data, as: name)
        let transaction = try HealthWriteFiles.prepare([name + ".json": data], journal: journal, into: root)
        try commitRestore(transaction, revision: captured)
    }

    @MainActor static func saveHealthReceiptChecked(_ journal: HealthWriteJournal, replacing expected: HealthWriteJournal) throws {
        try performWrite {
            let root = try checkedDirectory()
            guard try HealthWriteFiles.read(from: root, owner: HealthWriteDeviceOwner.current()) == expected else { throw BackupError.recordsChanged }
            let target = root.appendingPathComponent(HealthWriteFiles.name), data = try journal.encoded()
            #if DEBUG && targetEnvironment(simulator)
            try QuickLogDiskFault.write(domain: "health-receipt", target: target) {
                try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            #else
            try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #endif
        }
    }

    @MainActor static func startHealthWritesOnThisDeviceChecked() throws {
        let root = try checkedDirectory(), captured = revision
        let transaction = try HealthWriteFiles.prepareDeviceSetup(into: root, owner: HealthWriteDeviceOwner.current())
        try commitRestore(transaction, revision: captured)
    }

    @MainActor static func saveProfileGoalsChecked(profile: UserProfile, goals: HealthGoals, healthBoundaries: [HealthLocalFiles.Domain: HealthLocalFiles.Boundary] = [:], canCommit: () -> Bool, didCommit: () -> Void) async throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let files = ["profile.json": try encoder.encode(profile), "goals.json": try encoder.encode(goals)]
        try await saveLinkedFilesChecked(files, healthBoundaries: healthBoundaries, canCommit: canCommit, didCommit: didCommit)
    }

    static func loadConversationsChecked() throws -> ConversationFiles.Loaded {
        try ConversationFiles.load(from: checkedDirectory()) {
            guard let data = UserDefaults.standard.data(forKey: "lumen.health.chat.v1") else { return [] }
            // Pre-file defaults used JSONEncoder's original date representation.
            return try JSONDecoder().decode([ChatMessage].self, from: data)
        }
    }

    @MainActor static func saveConversationsChecked(_ conversations: [HealthConversation], activeID: String?,
                                                    canCommit: () -> Bool, didCommit: () -> Void) async throws {
        let files = try ConversationFiles.encoded(conversations, activeID: activeID)
        try await saveLinkedFilesChecked(files, canCommit: canCommit, didCommit: didCommit)
    }

    @MainActor private static func saveLinkedFilesChecked(_ files: [String: Data], expectedRevision: UInt64? = nil, healthBoundaries: [HealthLocalFiles.Domain: HealthLocalFiles.Boundary] = [:], canCommit: () -> Bool, didCommit: () -> Void) async throws {
        let root = try checkedDirectory(), capturedRevision = expectedRevision ?? revision
        guard revision == capturedRevision else { throw BackupError.recordsChanged }
        let sourceBoundaries = try validateHealthSources(Array(files.keys), expected: healthBoundaries)
        for (name, data) in files where name.hasSuffix(".json") { try validateNewHealthData(data, as: String(name.dropLast(5))) }
        let transaction = try await Task.detached(priority: .userInitiated) {
            try ConversationFiles.prepareLinkedChange(files, into: root)
        }.value
        #if DEBUG && targetEnvironment(simulator)
        if files["conversations.json"] != nil, ConversationPreparedWriteFixture.armed {
            try await ConversationPreparedWriteFixture.pauseIfArmed()
        }
        #endif
        // An uncommitted transaction removes its stage off-thread on release.
        try Task.checkCancellation()
        guard canCommit() else { throw BackupError.busy }
        for (domain, boundary) in sourceBoundaries { try verifyHealthBoundary(boundary, domain: domain) }
        try commitRestore(transaction, revision: capturedRevision)
        // Install the caller's live state in this same actor turn. Returning
        // through an await must not open a gap after disk has committed.
        didCommit()
    }
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    public static var directory: URL {
        // Legacy optional readers still return nil on failure. Do not let their
        // folder lookup discard a previous copy or create over failed recovery.
        // Checked callers use checkedDirectory() and receive the actual error.
        (try? checkedDirectory()) ?? storageRoot
    }

    private static var storageRoot: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LumenData", isDirectory: true)
    }

    static func checkedDirectory() throws -> URL {
        _ = removeAbandonedStages
        let dir = storageRoot
        try BackupFiles.openDirectory(dir, createIfMissing: true)
        return dir
    }

    private static func url(_ name: String) throws -> URL { try checkedDirectory().appendingPathComponent("\(name).json") }

    public static func save<T: Encodable>(_ value: T, as name: String) {
        try? performWrite {
            _ = try validateHealthSources([name + ".json"], expected: [:])
            let data = try encoder.encode(value)
            try validateNewHealthData(data, as: name)
            try data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func saveChecked<T: Encodable>(_ value: T, as name: String, healthBoundary: HealthLocalFiles.Boundary? = nil) throws {
        try performWrite {
            let expected = HealthLocalFiles.Domain(rawValue: name).flatMap { domain in healthBoundary.map { [domain: $0] } } ?? [:]
            _ = try validateHealthSources([name + ".json"], expected: expected)
            let data = try encoder.encode(value)
            try validateNewHealthData(data, as: name)
            #if DEBUG && targetEnvironment(simulator)
            try QuickLogDiskFault.write(domain: name, target: try url(name)) {
                try data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            #else
            try data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #endif
        }
    }

    static func saveEncodedChecked(_ data: Data, as name: String) throws {
        try performWrite {
            _ = try validateHealthSources([name + ".json"], expected: [:])
            try validateNewHealthData(data, as: name)
            try data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    public static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        if let domain = HealthLocalFiles.Domain(rawValue: name) { return try? loadHealthDomainChecked(type, domain: domain).value }
        if let data = try? Data(contentsOf: url(name)), let v = try? decoder.decode(T.self, from: data) { return v }
        return nil
    }

    /// Load from file, falling back to a legacy UserDefaults key (pre-1.1 builds) once.
    public static func load<T: Decodable>(_ type: T.Type, from name: String, legacyKey: String) -> T? {
        if let domain = HealthLocalFiles.Domain(rawValue: name) { return try? loadHealthDomainChecked(type, domain: domain).value }
        // Other legacy consumers also must not fall back after a failed current read.
        do {
            let file = try url(name)
            do { _ = try FileManager.default.attributesOfItem(atPath: file.path) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                return try UserDefaults.standard.data(forKey: legacyKey).map { try JSONDecoder().decode(type, from: $0) }
            }
            return try decoder.decode(type, from: Data(contentsOf: file))
        } catch { return nil }
    }

    private static func healthLegacyData(_ domain: HealthLocalFiles.Domain) throws -> Data? {
        guard let key = domain.legacyKey, let value = UserDefaults.standard.object(forKey: key) else { return nil }
        guard let data = value as? Data else { throw HealthLocalFiles.Failure.invalid }
        return data
    }

    private static func validateNewHealthData(_ data: Data, as name: String) throws {
        if let domain = HealthLocalFiles.Domain(rawValue: name) { try HealthLocalFiles.validateCurrentData(data, domain: domain) }
    }

    static func loadHealthDomainChecked<T: Decodable>(_ type: T.Type, domain: HealthLocalFiles.Domain) throws -> HealthLocalFiles.Loaded<T> {
        try HealthLocalFiles.read(type, domain: domain, from: checkedDirectory()) { try healthLegacyData(domain) }
    }

    static func healthBoundaryChecked(_ domain: HealthLocalFiles.Domain) throws -> HealthLocalFiles.Boundary {
        try HealthLocalFiles.boundary(domain, from: checkedDirectory()) { try healthLegacyData(domain) }
    }

    static func verifyHealthBoundary(_ boundary: HealthLocalFiles.Boundary, domain: HealthLocalFiles.Domain) throws {
        try HealthLocalFiles.verify(boundary, domain: domain, from: checkedDirectory()) { try healthLegacyData(domain) }
    }

    private static func validateHealthSources(_ names: [String], expected: [HealthLocalFiles.Domain: HealthLocalFiles.Boundary]) throws -> [HealthLocalFiles.Domain: HealthLocalFiles.Boundary] {
        var loaded: [HealthLocalFiles.Domain: HealthLocalFiles.Boundary] = [:]
        for domain in HealthLocalFiles.Domain.allCases where names.contains(domain.rawValue + ".json") {
            let boundary: HealthLocalFiles.Boundary
            switch domain {
            case .water: boundary = try loadHealthDomainChecked([HydrationLog].self, domain: domain).boundary
            case .meals: boundary = try loadHealthDomainChecked([Meal].self, domain: domain).boundary
            case .workouts: boundary = try loadHealthDomainChecked([Workout].self, domain: domain).boundary
            case .goals: boundary = try loadHealthDomainChecked(HealthGoals.self, domain: domain).boundary
            case .today: boundary = try loadHealthDomainChecked(DayMetrics.self, domain: domain).boundary
            }
            if let wanted = expected[domain], wanted != boundary { throw HealthLocalFiles.Failure.changed }
            loaded[domain] = boundary
        }
        return loaded
    }

    /// All stored files — used by export.
    public static func allFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    /// Wipe everything Lumen stores locally (account reset).
    public static func eraseAll() {
        // Legacy synthetic callers retain their nonthrowing interface. The
        // actual Settings reset uses eraseAllChecked and surfaces failure.
        try? eraseAllChecked()
    }

    static func eraseAllChecked() throws {
        try ProviderAuthorizationRevision.mutate {
            let root = try checkedDirectory(), captured = revision
            let transaction = try HealthWriteFiles.prepareReset(into: root, owner: HealthWriteDeviceOwner.current())
            try commitRestore(transaction, revision: captured)
            if let bundle = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: bundle) }
            AppGroup.defaults.removePersistentDomain(forName: AppGroup.id)
        }
    }
}

// MARK: - Meal photos (small JPEG thumbnails next to the data files)

public enum PhotoStore {
    private static var dir: URL {
        let d = LocalStore.directory.appendingPathComponent("photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) { try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        return d
    }
    public static func url(_ id: String) -> URL { dir.appendingPathComponent("\(id).jpg") }

    /// A fresh identifier belongs only to this pending meal. Never overwrite an
    /// existing/shared image while preparing a new record.
    static func saveNewChecked(_ image: UIImage, id: String) throws {
        let maxSide: CGFloat = 900
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try LocalStore.performWrite {
            let target = url(id)
            guard !FileManager.default.fileExists(atPath: target.path),
                  let data = resized.jpegData(compressionQuality: 0.75) else { throw BackupError.invalid }
            #if DEBUG && targetEnvironment(simulator)
            try QuickLogDiskFault.write(domain: "photo", target: target) {
                try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            #else
            try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #endif
        }
    }

    public static func load(_ id: String?) -> UIImage? {
        guard let id else { return nil }
        return UIImage(contentsOfFile: url(id).path)
    }

    public static func delete(_ id: String?) {
        guard let id else { return }
        LocalStore.performWrite { try? FileManager.default.removeItem(at: url(id)) }
    }
}
