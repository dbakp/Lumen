import Foundation
import CryptoKit
import Darwin

/// Immutable evidence of a failed fixed legacy value, not permission inferred
/// from an unavailable UI flag. Callers own write/directory serialization.
/// This primitive never enters LocalStore, creates a file or changes defaults.
struct HealthLegacyRecoveryOrigin: Equatable, Sendable {
    static let rawLimit = 4_194_304
    static let envelopeLimit = 5_600_000
    static let aggregateLimit = 3 * rawLimit
    enum ValueType: String, Sendable { case data, stringUTF16LE }
    enum IneligibleValue: Error { case tooLarge, unrepresentableString }
    struct RootIdentity: Equatable, Sendable {
        let path: String
        let device: UInt64
        let inode: UInt64
    }
    struct Value: Equatable, Sendable {
        let domain: HealthLocalFiles.Domain
        let type: ValueType
        let bytes: Data
        var key: String { domain.legacyKey! }
        private init(domain: HealthLocalFiles.Domain, type: ValueType, bytes: Data) {
            self.domain = domain; self.type = type; self.bytes = bytes
        }

        fileprivate static func capture(_ object: Any?, domain: HealthLocalFiles.Domain,
                                        control: BackupOperationControl) throws -> Value? {
            try control.checkCancellation()
            guard domain.legacyKey != nil, let object else { return nil }
            if let data = object as? Data {
                guard data.count <= rawLimit else { throw IneligibleValue.tooLarge }
                return Value(domain: domain, type: .data, bytes: data)
            }
            guard let string = object as? NSString else { return nil }
            guard string.length <= rawLimit / 2 else { throw IneligibleValue.tooLarge }
            var units = [UInt16](); units.reserveCapacity(string.length)
            var bytes = Data(); bytes.reserveCapacity(string.length * 2)
            for index in 0..<string.length {
                if index.isMultiple(of: 4096) { try control.checkCancellation() }
                let unit = string.character(at: index)
                units.append(unit); bytes.append(UInt8(truncatingIfNeeded: unit)); bytes.append(UInt8(unit >> 8))
            }
            // Refuse a bridge that would repair a malformed surrogate sequence.
            guard String(decoding: units, as: UTF16.self).utf16.elementsEqual(units) else { throw IneligibleValue.unrepresentableString }
            try control.checkCancellation()
            return Value(domain: domain, type: .stringUTF16LE, bytes: bytes)
        }

        fileprivate func isFailed(control: BackupOperationControl) throws -> Bool {
            try control.checkCancellation()
            if type == .stringUTF16LE { return true } // Existing migration accepts Data only.
            do {
                try HealthLocalFiles.validateLegacyData(bytes, domain: domain, control: control)
                return false
            } catch is CancellationError { throw CancellationError() }
            catch is DecodingError { try control.checkCancellation(); return true }
            catch HealthLocalFiles.Failure.invalid { try control.checkCancellation(); return true }
            catch ReadableExport.Failure.format { try control.checkCancellation(); return true }
            catch ReadableExport.Failure.ambiguous { try control.checkCancellation(); return true }
            // Acquisition/operational errors and future error categories propagate.
        }

        /// Captured value provenance, never the original preferences plist bytes.
        func encoded(control: BackupOperationControl = .init()) throws -> Data {
            try control.checkCancellation()
            let envelope: [String: Any] = ["schemaVersion": 1, "domain": domain.rawValue, "key": key,
                                          "type": type.rawValue, "payload": bytes.base64EncodedString(),
                                          "sha256": Self.digest(bytes)]
            let result = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            guard result.count <= envelopeLimit else { throw HealthLocalFiles.Failure.invalid }
            try control.checkCancellation()
            return result
        }

        static func decode(_ data: Data, control: BackupOperationControl = .init()) throws -> Value {
            try control.checkCancellation()
            guard data.count <= envelopeLimit else { throw HealthLocalFiles.Failure.invalid }
            try JSONFieldAudit.check(data, control: control)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["schemaVersion", "domain", "key", "type", "payload", "sha256"] else { throw HealthLocalFiles.Failure.invalid }
            struct Envelope: Decodable {
                let schemaVersion: Int; let domain: String; let key: String
                let type: String; let payload: String; let sha256: String
            }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == 1, let domain = HealthLocalFiles.Domain(rawValue: envelope.domain),
                  let key = domain.legacyKey, envelope.key == key,
                  let type = ValueType(rawValue: envelope.type), envelope.payload.utf8.count <= 5_592_408,
                  let bytes = Data(base64Encoded: envelope.payload), bytes.count <= rawLimit,
                  bytes.base64EncodedString() == envelope.payload, Self.digest(bytes) == envelope.sha256 else { throw HealthLocalFiles.Failure.invalid }
            if type == .stringUTF16LE {
                guard bytes.count.isMultiple(of: 2) else { throw HealthLocalFiles.Failure.invalid }
                var units = [UInt16](); units.reserveCapacity(bytes.count / 2)
                for index in stride(from: 0, to: bytes.count, by: 2) {
                    if index.isMultiple(of: 4096) { try control.checkCancellation() }
                    units.append(UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
                }
                guard String(decoding: units, as: UTF16.self).utf16.elementsEqual(units) else { throw HealthLocalFiles.Failure.invalid }
            }
            let value = Value(domain: domain, type: type, bytes: bytes)
            guard try value.isFailed(control: control) else { throw HealthLocalFiles.Failure.invalid }
            try control.checkCancellation()
            return value
        }
        private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    }

    let root: RootIdentity
    let value: Value
    private init(root: RootIdentity, value: Value) { self.root = root; self.value = value }

    /// nil distinguishes an ineligible target from an acquisition failure.
    static func capture(_ domain: HealthLocalFiles.Domain, in directory: URL,
                        legacy: (String) throws -> Any?, control: BackupOperationControl = .init()) throws -> Self? {
        try control.checkCancellation()
        guard domain.legacyKey != nil else { return nil }
        let root = try rootIdentity(directory)
        guard try currentAbsent(domain, in: directory),
              let value = try Value.capture(legacy(domain.legacyKey!), domain: domain, control: control),
              try value.isFailed(control: control) else { return nil }
        let result = Self(root: root, value: value)
        try result.verify(in: directory, legacy: legacy, control: control)
        return result
    }

    func verify(in directory: URL, legacy: (String) throws -> Any?, control: BackupOperationControl = .init()) throws {
        try control.checkCancellation()
        guard try Self.rootIdentity(directory) == root, try Self.currentAbsent(value.domain, in: directory),
              let current = try Value.capture(legacy(value.key), domain: value.domain, control: control),
              current == value, try current.isFailed(control: control) else { throw HealthLocalFiles.Failure.changed }
        try control.checkCancellation()
    }

    /// Projects only a fixed persisted key. Registration/argument fallbacks alone
    /// cannot authorize replacement. The caller must not retain the whole domain.
    static func checkedPersistentValue(_ persisted: Any?, effective: Any?,
                                       domain: HealthLocalFiles.Domain,
                                       control: BackupOperationControl) throws -> Any? {
        try control.checkCancellation()
        guard domain.legacyKey != nil, let persisted else { return nil }
        guard let value = try Value.capture(persisted, domain: domain, control: control) else { return persisted }
        let observed: Value?
        do { observed = try Value.capture(effective, domain: domain, control: control) }
        catch is IneligibleValue { throw HealthLocalFiles.Failure.changed }
        guard observed == value else { throw HealthLocalFiles.Failure.changed }
        return persisted
    }

    struct ReviewMetadata: Equatable, Sendable {
        let fileDomains: Set<HealthLocalFiles.Domain>
        let legacyDomains: Set<HealthLocalFiles.Domain>
        let ineligibleDomains: Set<HealthLocalFiles.Domain>

        var recoverableDomains: Set<HealthLocalFiles.Domain> {
            fileDomains.union(legacyDomains).subtracting(ineligibleDomains)
        }
    }
    struct ReviewSnapshot: Sendable {
        let metadata: ReviewMetadata
        fileprivate let origins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin]
        fileprivate init(metadata: ReviewMetadata, origins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin]) {
            self.metadata = metadata; self.origins = origins
        }
    }

    /// Check current regular files without installing them into HealthStore.
    /// Only classification survives; raw current contents stay in this scope.
    /// Failed files still require the unavailable-domain and transaction checks.
    /// No directory opening, migration or defaults writes.
    static func captureReview(_ domains: Set<HealthLocalFiles.Domain>, in directory: URL,
                              legacy: (String) throws -> Any?,
                              control: BackupOperationControl) throws -> ReviewSnapshot {
        try control.checkCancellation()
        let root = try rootIdentity(directory)
        var files = Set<HealthLocalFiles.Domain>(), ineligible = Set<HealthLocalFiles.Domain>()
        var origins: [HealthLocalFiles.Domain: Self] = [:]
        for domain in domains.sorted(by: { $0.rawValue < $1.rawValue }) {
            try control.checkCancellation()
            var facts = stat()
            let file = directory.appendingPathComponent(domain.rawValue + ".json")
            if lstat(file.path, &facts) == 0 {
                let kind = facts.st_mode & mode_t(S_IFMT)
                if kind == mode_t(S_IFREG) {
                    do {
                        let data = try HealthLocalFiles.readRegularData(file, limit: HealthLocalFiles.limit, control: control)
                        try HealthLocalFiles.validateCurrentData(data, domain: domain, control: control)
                        ineligible.insert(domain)
                    } catch is CancellationError { throw CancellationError() }
                    catch HealthLocalFiles.Failure.changed { throw HealthLocalFiles.Failure.changed }
                    catch {
                        // Preserve the existing failed-file classification. A
                        // read/decode failure grants no new transaction authority.
                        files.insert(domain)
                    }
                }
                else if kind == mode_t(S_IFDIR) { files.insert(domain) }
                else { ineligible.insert(domain) }
                continue
            }
            let code = errno
            guard code == ENOENT else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
            do {
                if let origin = try capture(domain, in: directory, legacy: legacy, control: control) {
                    guard origin.root == root else { throw HealthLocalFiles.Failure.changed }
                    origins[domain] = origin
                } else { ineligible.insert(domain) }
            } catch is IneligibleValue { ineligible.insert(domain) }
        }
        guard origins.values.reduce(0, { $0 + $1.value.bytes.count }) <= aggregateLimit,
              try rootIdentity(directory) == root else { throw HealthLocalFiles.Failure.changed }
        try control.checkCancellation()
        return ReviewSnapshot(metadata: .init(fileDomains: files, legacyDomains: Set(origins.keys),
                                             ineligibleDomains: ineligible), origins: origins)
    }

    private static func rootIdentity(_ directory: URL) throws -> RootIdentity {
        var facts = stat()
        guard lstat(directory.path, &facts) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw HealthLocalFiles.Failure.invalid }
        return RootIdentity(path: directory.standardizedFileURL.path, device: UInt64(truncatingIfNeeded: facts.st_dev), inode: UInt64(facts.st_ino))
    }

    private static func currentAbsent(_ domain: HealthLocalFiles.Domain, in directory: URL) throws -> Bool {
        var facts = stat()
        if lstat(directory.appendingPathComponent(domain.rawValue + ".json").path, &facts) == 0 { return false }
        let code = errno
        if code == ENOENT { return true }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}

/// Raw observations live with the actual review owner, not cached view state.
/// Cancellation callbacks execute outside this nonrecursive holder lock.
final class HealthRecoveryOriginReviewLease: @unchecked Sendable {
    enum Phase: Equatable, Sendable { case initial, capturing, ready, closed }
    private let lock = NSLock()
    private var phase: Phase = .initial
    private var pending: BackupOperationControl?
    private var snapshot: HealthLegacyRecoveryOrigin.ReviewSnapshot?
    var state: Phase { lock.lock(); defer { lock.unlock() }; return phase }
    var metadata: HealthLegacyRecoveryOrigin.ReviewMetadata? {
        lock.lock(); defer { lock.unlock() }; return snapshot?.metadata
    }
    func begin(_ control: BackupOperationControl) throws {
        try control.checkCancellation()
        lock.lock(); defer { lock.unlock() }
        guard phase == .initial else { throw CancellationError() }
        pending = control; phase = .capturing
    }
    func finish(_ value: HealthLegacyRecoveryOrigin.ReviewSnapshot, control: BackupOperationControl) throws {
        try control.checkCancellation()
        lock.lock(); defer { lock.unlock() }
        guard phase == .capturing, pending === control else { throw CancellationError() }
        snapshot = value; pending = nil; phase = .ready
    }
    func suspend(_ control: BackupOperationControl) {
        lock.lock()
        let matched = phase == .capturing && pending === control
        if matched { pending = nil; phase = .initial }
        lock.unlock()
        if matched { control.cancel() }
    }
    func acquire(_ domains: Set<HealthLocalFiles.Domain>, control: BackupOperationControl) throws
        -> [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin] {
        try control.checkCancellation()
        lock.lock()
        guard phase == .ready, let snapshot,
              domains.isSubset(of: snapshot.metadata.legacyDomains) else {
            lock.unlock(); throw CancellationError()
        }
        let selected = snapshot.origins.filter { domains.contains($0.key) }
        lock.unlock()
        try control.checkCancellation()
        return selected
    }
    func close() {
        lock.lock()
        let old = snapshot, control = pending
        snapshot = nil; pending = nil; phase = .closed
        lock.unlock()
        control?.cancel()
        withExtendedLifetime(old) {}
    }
}
