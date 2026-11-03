import Foundation
import Security

/// Tokens, their expiry and local account identity are one Keychain item. This
/// identifies the locally authorized connection, not a verified Google subject.
enum OAuthCredentialStore {
    static let key = "lumen.llm.oauth.account.v2"
    private static let removalKey = "lumen.llm.oauth.removalPending"
    static var removalPending: Bool { UserDefaults.standard.bool(forKey: removalKey) }

    struct Account: Codable, Equatable, Sendable {
        var version = 2
        var id = UUID()
        let clientID: String
        let scope: String
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Date
        var migratedLegacy = false

        var isValid: Bool {
            version == 2 && !clientID.isEmpty && clientID.utf8.count <= 4096 && scope.utf8.count <= 8192 &&
            expiresAt.timeIntervalSinceReferenceDate.isFinite &&
            (accessToken != nil || refreshToken != nil) &&
            [accessToken, refreshToken].compactMap { $0 }.allSatisfy { value in
                !value.isEmpty && value.utf8.count <= 64_000 && value.utf8.allSatisfy { (33...126).contains($0) }
            }
        }
    }

    enum Failure: Error, LocalizedError {
        case corrupt, removalPending
        var errorDescription: String? {
            switch self {
            case .corrupt: return "The saved AI connection couldn't be read. Reconnect before sending."
            case .removalPending: return "Credential removal hasn't finished. Retry removal before connecting."
            }
        }
    }

    /// Read-only identity check. Never falls back to a legacy account when a
    /// present record is malformed or belongs to a different configuration.
    static func read() throws -> Account? {
        guard !SecureStore.erasurePending, !removalPending, !ProviderConnectionStore.removalPending else { throw Failure.removalPending }
        guard let data = try SecureStore.dataChecked(key) else { return nil }
        guard data.count <= 160_000, let account = try? JSONDecoder().decode(Account.self, from: data), account.isValid else { throw Failure.corrupt }
        return account
    }

    static func hasCredentials(clientID: String, scope: String) throws -> Bool {
        if let account = try read() {
            guard account.clientID == clientID, account.scope == scope else { return false }
            return account.refreshToken != nil || (account.accessToken != nil && account.expiresAt > Date())
        }
        guard !clientID.isEmpty else { return false }
        if try legacyValue("lumen.llm.oauth.refresh") != nil { return true }
        let expiry = UserDefaults.standard.object(forKey: "lumen.llm.oauth.expires") as? Date ?? .distantPast
        return try legacyValue("lumen.llm.oauth.token") != nil && expiry > Date()
    }

    /// Legacy records have no verified account subject. Bind their migration to
    /// the current client/scope once, marking that limitation in the record.
    /// Persist the complete replacement before removing any old source. If
    /// cleanup fails the next load retries it; no token is returned on failure.
    static func load(clientID: String, scope: String, expectedRevision: UUID) throws -> Account? {
        if let account = try read() {
            guard account.clientID == clientID, account.scope == scope else { return nil }
            try ProviderAuthorizationRevision.commit(expected: expectedRevision) { try removeLegacy() }
            return account
        }
        guard !clientID.isEmpty else { return nil }
        let access = try legacyValue("lumen.llm.oauth.token")
        let refresh = try legacyValue("lumen.llm.oauth.refresh")
        guard access != nil || refresh != nil else { return nil }
        let expiry = UserDefaults.standard.object(forKey: "lumen.llm.oauth.expires") as? Date ?? .distantPast
        let account = Account(clientID: clientID, scope: scope, accessToken: access, refreshToken: refresh, expiresAt: expiry, migratedLegacy: true)
        try save(account, expectedRevision: expectedRevision)
        try ProviderAuthorizationRevision.commit(expected: expectedRevision) { try removeLegacy() }
        return account
    }

    static func save(_ account: Account, expectedRevision: UUID) throws {
        guard account.isValid else { throw Failure.corrupt }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(account)
        guard data.count <= 160_000 else { throw Failure.corrupt }
        try ProviderAuthorizationRevision.commit(expected: expectedRevision) {
            guard !SecureStore.erasurePending, !removalPending, !ProviderConnectionStore.removalPending else { throw Failure.removalPending }
            try SecureStore.setDataChecked(data, for: key)
        }
    }

    /// Persist intent before deletion so a failed disconnect cannot silently
    /// reload old credentials after relaunch. Retrying is idempotent.
    static func disconnect() throws {
        try ProviderAuthorizationRevision.mutate {
            UserDefaults.standard.set(true, forKey: removalKey)
            try SecureStore.removeChecked(key)
            try removeLegacy()
            UserDefaults.standard.removeObject(forKey: removalKey)
        }
    }

    private static func legacyValue(_ key: String) throws -> String? {
        if let data = try SecureStore.dataChecked(key) {
            guard let value = String(data: data, encoding: .utf8) else { throw SecureStore.Failure(operation: .read, status: errSecDecode) }
            return value.isEmpty ? nil : value
        }
        // Read without creating another legacy Keychain item outside the
        // captured revision's commit. The atomic replacement is the only write.
        return UserDefaults.standard.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func removeLegacy() throws {
        try SecureStore.removeChecked("lumen.llm.oauth.token")
        try SecureStore.removeChecked("lumen.llm.oauth.refresh")
        UserDefaults.standard.removeObject(forKey: "lumen.llm.oauth.expires")
    }
}
