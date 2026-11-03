import Foundation
import Security

// MARK: - Keychain for secrets (API keys, OAuth tokens). Never UserDefaults.

public enum SecureStore {
    private static let service = "com.dbakp.lumen.secrets"
    private static let erasurePendingKey = "lumen.secrets.erasurePending"
    static var erasurePending: Bool { UserDefaults.standard.bool(forKey: erasurePendingKey) }

    public enum Operation: String { case read, write, delete }
    public struct Failure: Error, Equatable, LocalizedError {
        public let operation: Operation
        public let status: OSStatus
        public var errorDescription: String? {
            switch operation {
            case .read: return "Credentials couldn't be read. Unlock this device and try again."
            case .write: return "Credentials couldn't be saved. Try again."
            case .delete: return "Credentials couldn't be removed. Try again."
            }
        }
    }

    public static func string(_ key: String) -> String? {
        try? stringChecked(key)
    }

    public static func stringChecked(_ key: String, migrateLegacy: Bool = true) throws -> String? {
        if let data = try dataChecked(key) {
            guard let value = String(data: data, encoding: .utf8) else { throw Failure(operation: .read, status: errSecDecode) }
            return value
        }
        // Keep the only legacy copy if checked migration fails. A protected or
        // otherwise unavailable Keychain read is never treated as a missing item.
        if let legacy = UserDefaults.standard.string(forKey: key), !legacy.isEmpty {
            if !migrateLegacy { return legacy }
            try setChecked(legacy, for: key)
            UserDefaults.standard.removeObject(forKey: key)
            return legacy
        }
        return nil
    }

    public static func dataChecked(_ key: String) throws -> Data? {
        #if DEBUG && targetEnvironment(simulator)
        try consumeInjectedFailure(.read, key: key)
        #endif
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(operation: .read, status: status) }
        guard let data = out as? Data else { throw Failure(operation: .read, status: errSecDecode) }
        return data
    }

    public static func set(_ value: String?, for key: String) {
        try? setChecked(value, for: key)
    }

    public static func setChecked(_ value: String?, for key: String) throws {
        guard let value, !value.isEmpty else { try removeChecked(key); return }
        try setDataChecked(Data(value.utf8), for: key)
    }

    public static func setDataChecked(_ data: Data, for key: String) throws {
        #if DEBUG && targetEnvironment(simulator)
        try consumeInjectedFailure(.write, key: key)
        #endif
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        // Update preserves the previous value if replacement fails. Deleting
        // before adding would destroy the only credential on a failed add.
        var status = SecItemUpdate(base(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = base(key)
            attributes.forEach { q[$0.key] = $0.value }
            status = SecItemAdd(q as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(base(key) as CFDictionary, attributes as CFDictionary)
            }
        }
        guard status == errSecSuccess else { throw Failure(operation: .write, status: status) }
        UserDefaults.standard.removeObject(forKey: key)
    }

    public static func removeChecked(_ key: String) throws {
        #if DEBUG && targetEnvironment(simulator)
        try consumeInjectedFailure(.delete, key: key)
        #endif
        let status = SecItemDelete(base(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(operation: .delete, status: status) }
        UserDefaults.standard.removeObject(forKey: key)
    }

    public static func eraseAll() {
        try? eraseAllChecked()
    }

    public static func eraseAllChecked() throws {
        try ProviderAuthorizationRevision.mutate {
            UserDefaults.standard.set(true, forKey: erasurePendingKey)
            #if DEBUG && targetEnvironment(simulator)
            try consumeInjectedFailure(.delete, key: "synthetic.storage.42.service")
            #endif
            let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(operation: .delete, status: status) }
            for key in ["lumen.llm.key", "lumen.llm.oauth.token", "lumen.llm.oauth.refresh", "lumen.llm.oauth.account.v2",
                        "lumen.llm.oauth.expires", "lumen.llm.oauth.removalPending", "lumen.llm.connection.v3", "lumen.llm.keyRemovalPending",
                        "strava.clientID", "strava.clientSecret", "strava.token", "strava.refresh"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.removeObject(forKey: erasurePendingKey)
        }
    }

    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    #if DEBUG && targetEnvironment(simulator)
    private static let injectionLock = NSLock()
    private static var injectedFailure: (operation: Operation, key: String, status: OSStatus, remainingMatches: Int)?
    static func injectFailure(_ operation: Operation, key: String, status: OSStatus, afterSuccessfulMatches: Int = 0) {
        let args = ProcessInfo.processInfo.arguments
        precondition((args.contains("-resetForUITests") && args.contains("-personal-provenance-probe") && (args.contains("-provider-credential-checks") || args.contains("-provider-authorization-checks"))) || ProviderConnectionUIFixture.isAuthorized)
        precondition(key.hasPrefix("synthetic.storage.42.") || ["lumen.llm.oauth.account.v2", "lumen.llm.oauth.token", "lumen.llm.oauth.refresh", "lumen.llm.key", "lumen.llm.connection.v3"].contains(key))
        precondition((0...4).contains(afterSuccessfulMatches))
        injectionLock.lock(); defer { injectionLock.unlock() }
        injectedFailure = (operation, key, status, afterSuccessfulMatches)
    }
    private static func consumeInjectedFailure(_ operation: Operation, key: String) throws {
        injectionLock.lock(); defer { injectionLock.unlock() }
        guard var failure = injectedFailure, failure.operation == operation, failure.key == key else { return }
        if failure.remainingMatches > 0 { failure.remainingMatches -= 1; injectedFailure = failure; return }
        injectedFailure = nil
        throw Failure(operation: operation, status: failure.status)
    }
    #endif
}

/// Shared synchronous boundary for configuration/reset intents and credential
/// commit. Reset may originate outside the service actor. A committed write
/// either precedes reset invalidation or rejects the superseded generation.
enum ProviderAuthorizationRevision {
    private static let lock = NSLock()
    private static var revision = UUID()
    static var current: UUID { lock.lock(); defer { lock.unlock() }; return revision }
    static func invalidate() { lock.lock(); defer { lock.unlock() }; revision = UUID() }
    static func mutate<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        revision = UUID()
        return try operation()
    }
    enum Changed: Error { case configuration }
    static func commit<T>(expected: UUID, _ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard expected == revision else { throw Changed.configuration }
        // The operation must not re-enter this revision's lock.
        return try operation()
    }
}
