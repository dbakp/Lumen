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
                guard data.count <= rawLimit else { throw HealthLocalFiles.Failure.invalid }
                return Value(domain: domain, type: .data, bytes: data)
            }
            guard let string = object as? NSString else { return nil }
            guard string.length <= rawLimit / 2 else { throw HealthLocalFiles.Failure.invalid }
            var units = [UInt16](); units.reserveCapacity(string.length)
            var bytes = Data(); bytes.reserveCapacity(string.length * 2)
            for index in 0..<string.length {
                if index.isMultiple(of: 4096) { try control.checkCancellation() }
                let unit = string.character(at: index)
                units.append(unit); bytes.append(UInt8(truncatingIfNeeded: unit)); bytes.append(UInt8(unit >> 8))
            }
            // Refuse a bridge that would repair a malformed surrogate sequence.
            guard String(decoding: units, as: UTF16.self).utf16.elementsEqual(units) else { throw HealthLocalFiles.Failure.invalid }
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
