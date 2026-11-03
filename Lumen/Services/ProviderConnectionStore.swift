import Foundation

/// One checked item owns the complete recipient configuration and API key.
/// OAuth account tokens remain separately bound to their client and scope.
enum ProviderConnectionStore {
    static let key = "lumen.llm.connection.v3"
    private static let removalKey = "lumen.llm.keyRemovalPending"
    private static let legacyID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static var removalPending: Bool { UserDefaults.standard.bool(forKey: removalKey) }

    struct Record: Codable, Equatable, Sendable {
        var version = 3
        var id = UUID()
        var mode = "onDevice"
        var preset = "openAI"
        var endpoint = "https://api.openai.com/v1/chat/completions"
        var model = ""
        var apiKey: String?
        var clientID = ""
        var scope = "openid email profile"
        var oauthEndpoint = ""
        var oauthModel = ""
        var preferExternal = false
        var legacyCleanupPending = false

        var isValid: Bool {
            version == 3 && ["onDevice", "key", "oauth"].contains(mode) && ["openAI", "aiStudio", "custom"].contains(preset) &&
            [endpoint, oauthEndpoint, clientID, scope].allSatisfy { $0.utf8.count <= 8192 } &&
            [model, oauthModel].allSatisfy { $0.utf8.count <= 1024 } &&
            (apiKey.map { !$0.isEmpty && $0.utf8.count <= 64_000 && $0.utf8.allSatisfy { (33...126).contains($0) } } ?? true)
        }
    }
    enum Failure: LocalizedError {
        case corrupt, pending, invalidDraft, changed
        var errorDescription: String? {
            switch self {
            case .corrupt: return "The saved AI connection couldn't be read. Remove it before connecting again."
            case .pending: return "Credential removal hasn't finished. Retry removal before connecting."
            case .invalidDraft: return "Check the endpoint, model and credentials before saving."
            case .changed: return "The saved connection changed. Reload it before saving your edits."
            }
        }
    }
    private static func checkIntent(allowKeyRemoval: Bool = false) throws {
        guard !SecureStore.erasurePending, !OAuthCredentialStore.removalPending,
              allowKeyRemoval || !removalPending else { throw Failure.pending }
    }
    private static func raw() throws -> Record? {
        guard let bytes = try SecureStore.dataChecked(key) else { return nil }
        guard bytes.count <= 128_000, let value = try? JSONDecoder().decode(Record.self, from: bytes),
              value.isValid else { throw Failure.corrupt }
        return value
    }
    static func read() throws -> Record? {
        try checkIntent()
        return try raw()
    }
    /// Preview does not migrate a secret or rewrite any setting. A malformed or
    /// unavailable present record never falls back to an old credential.
    static func preview() throws -> Record {
        try checkIntent()
        if let value = try raw() { return value }
        let defaults = UserDefaults.standard
        let key = try SecureStore.stringChecked("lumen.llm.key", migrateLegacy: false).flatMap { $0.isEmpty ? nil : $0 }
        var value = Record(); value.id = legacyID
        value.mode = defaults.string(forKey: "lumen.llm.mode") ?? (key == nil ? "onDevice" : "key")
        value.preset = defaults.string(forKey: "lumen.llm.preset") ?? "openAI"
        value.endpoint = defaults.string(forKey: "lumen.llm.endpoint") ?? value.endpoint
        // Preserve old installed choices; new drafts have no guessed model ID.
        value.model = defaults.string(forKey: "lumen.llm.model") ?? (key == nil ? "" : "gpt-4o-mini")
        value.apiKey = key
        value.clientID = defaults.string(forKey: "lumen.llm.google.clientid") ?? ""
        value.scope = defaults.string(forKey: "lumen.llm.google.scope") ?? value.scope
        value.oauthEndpoint = defaults.string(forKey: "lumen.llm.oauth.endpoint") ?? ""
        value.oauthModel = defaults.string(forKey: "lumen.llm.oauth.model") ?? (value.clientID.isEmpty ? "" : "gemini-2.0-flash")
        value.preferExternal = defaults.bool(forKey: "lumen.ai.preferOpenAI")
        guard value.isValid else { throw Failure.corrupt }
        return value
    }
    static func routingReady() -> Bool {
        guard let value = try? preview() else { return false }
        return !value.legacyCleanupPending
    }
    static func validateDraft(_ value: Record) throws {
        guard value.isValid else { throw Failure.invalidDraft }
        func endpoint(_ string: String) -> Bool {
            guard let parts = URLComponents(string: string), let url = parts.url,
                  ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
                  parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
            return true
        }
        if value.mode == "key" {
            guard value.apiKey != nil, endpoint(value.endpoint), !value.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidDraft }
        }
        if value.mode == "oauth" {
            guard !value.clientID.isEmpty, !value.scope.isEmpty, endpoint(value.oauthEndpoint), !value.oauthModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidDraft }
        }
    }
    private static func write(_ value: Record) throws {
        guard value.isValid else { throw Failure.invalidDraft }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= 128_000 else { throw Failure.invalidDraft }
        try SecureStore.setDataChecked(bytes, for: key)
    }
    private static func finishLegacyCleanup(_ value: inout Record) throws {
        guard value.legacyCleanupPending else { return }
        try SecureStore.removeChecked("lumen.llm.key")
        // Metadata was committed with the secret first. A surviving legacy item
        // is shadowed, and the durable marker prevents routing until retry.
        for name in ["lumen.llm.mode", "lumen.llm.preset", "lumen.llm.endpoint", "lumen.llm.model",
                     "lumen.llm.google.clientid", "lumen.llm.google.scope", "lumen.llm.oauth.endpoint",
                     "lumen.llm.oauth.model", "lumen.ai.preferOpenAI"] { UserDefaults.standard.removeObject(forKey: name) }
        value.legacyCleanupPending = false
        try write(value)
    }
    @discardableResult static func save(_ draft: Record, expectedRevision: UUID) throws -> Record {
        try ProviderAuthorizationRevision.commit(expected: expectedRevision) {
            try checkIntent()
            var value = draft; value.id = UUID()
            value.legacyCleanupPending = true
            try write(value)
            try finishLegacyCleanup(&value)
            return value
        }
    }
    /// First real use migrates the whole legacy tuple, retaining its captured
    /// identity. Explicit later saves always get a new identity.
    static func loadForRouting(expectedRevision: UUID) throws -> Record {
        try ProviderAuthorizationRevision.commit(expected: expectedRevision) {
            try checkIntent()
            var value: Record
            if let saved = try raw() { value = saved }
            else {
                value = try preview(); value.legacyCleanupPending = true
                try write(value)
            }
            try finishLegacyCleanup(&value)
            return value
        }
    }
    /// Repeated removal can recover a malformed record without reading its key.
    /// The intent survives a failed write/delete and blocks both route methods.
    static func removeAPIKey(expectedRevision: UUID, useOnDevice: Bool = false) throws {
        try ProviderAuthorizationRevision.commit(expected: expectedRevision) {
            UserDefaults.standard.set(true, forKey: removalKey)
            try checkIntent(allowKeyRemoval: true)
            var value: Record
            do { value = try raw() ?? Record() }
            catch Failure.corrupt { value = Record() }
            value.id = UUID(); value.apiKey = nil
            if value.mode == "key" || useOnDevice { value.mode = "onDevice" }
            if useOnDevice { value.preferExternal = false }
            value.legacyCleanupPending = true
            try write(value)
            try finishLegacyCleanup(&value)
            UserDefaults.standard.removeObject(forKey: removalKey)
        }
    }
}
