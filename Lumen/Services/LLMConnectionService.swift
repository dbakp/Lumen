import Foundation
import AuthenticationServices
import CryptoKit
import SwiftUI

// MARK: - LLMConnectionService: bring-your-own-AI, all from the phone.
// Two real paths, tokens/keys stay on-device:
//  1. API key → any OpenAI-compatible chat-completions endpoint
//     (presets: OpenAI, Google AI Studio's OpenAI-compat endpoint, Custom).
//  2. OAuth 2.0 Authorization Code + PKCE → Bearer token against a
//     compatible endpoint (e.g. a Vertex-style OpenAI-compat gateway).
//     Whole flow runs on-device via ASWebAuthenticationSession.
// Without either, the coach runs fully on-device with your real health data.

@MainActor
public final class LLMConnectionService: ObservableObject {
    public static let shared = LLMConnectionService()

    public enum Mode: String, CaseIterable {
        case onDevice, key, oauth
        public var label: String {
            switch self { case .onDevice: return "Apple or built-in"; case .key: return "API key"; case .oauth: return "Google OAuth" }
        }
    }

    public var mode: Mode { Mode(rawValue: (try? ProviderConnectionStore.preview())?.mode ?? "") ?? .onDevice }
    @Published public var status = "External AI connection off"
    @Published public var isBusy = false
    @Published public var lastTestResult: String?
    @Published public private(set) var credentialProblem: String?

    private init() { refreshStatus() }

    // MARK: key mode (OpenAI-compatible)

    public enum Preset: String, CaseIterable {
        case openAI, aiStudio, custom
        public var label: String {
            switch self { case .openAI: return "OpenAI"; case .aiStudio: return "Google AI Studio"; case .custom: return "Custom" }
        }
        public var endpoint: String {
            switch self {
            case .openAI: return "https://api.openai.com/v1/chat/completions"
            case .aiStudio: return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            case .custom: return ""
            }
        }
        public var defaultModel: String {
            switch self { case .openAI, .custom: return ""; case .aiStudio: return "gemini-3.8-flash" }
        }
    }

    public var apiKey: String {
        get { (try? ProviderConnectionStore.preview())?.apiKey ?? "" }
        set {
            do { try saveAPIKeyChecked(newValue) }
            catch { credentialProblem = error.localizedDescription; status = error.localizedDescription }
        }
    }
    public func saveAPIKeyChecked(_ value: String) throws {
        try updateConnectionChecked { $0.apiKey = value.isEmpty ? nil : value }
    }
    public var endpoint: String {
        get { (try? ProviderConnectionStore.preview())?.endpoint ?? "" }
        set { updateConnection { $0.endpoint = newValue } }
    }
    public var model: String {
        get { (try? ProviderConnectionStore.preview())?.model ?? "" }
        set { updateConnection { $0.model = newValue } }
    }

    public func applyPreset(_ preset: Preset) {
        updateConnection {
            $0.preset = preset.rawValue
            if preset != .custom { $0.endpoint = preset.endpoint; $0.model = preset.defaultModel }
        }
    }

    public var currentPreset: Preset {
        Preset(rawValue: (try? ProviderConnectionStore.preview())?.preset ?? "") ?? .custom
    }

    // MARK: OAuth mode (PKCE, on-device)

    /// Live sign-in requires a provider-supported native client and callback
    /// configuration for this build. Synthetic lifecycle checks do not prove it.
    public var googleClientID: String {
        get { (try? ProviderConnectionStore.preview())?.clientID ?? "" }
        set { updateConnection { $0.clientID = newValue } }
    }
    public var oauthScope: String {
        get { (try? ProviderConnectionStore.preview())?.scope ?? "" }
        set { updateConnection { $0.scope = newValue } }
    }
    /// Bearer endpoint for OAuth mode (OpenAI-compatible request shape).
    public var oauthEndpoint: String {
        get { (try? ProviderConnectionStore.preview())?.oauthEndpoint ?? "" }
        set { updateConnection { $0.oauthEndpoint = newValue } }
    }
    public var oauthModel: String {
        get { (try? ProviderConnectionStore.preview())?.oauthModel ?? "" }
        set { updateConnection { $0.oauthModel = newValue } }
    }

    var preferExternal: Bool { (try? ProviderConnectionStore.preview())?.preferExternal ?? false }
    func setPreferExternal(_ value: Bool) { updateConnection { $0.preferExternal = value } }
    func connectionDraft() throws -> ProviderConnectionStore.Record { try ProviderConnectionStore.preview() }
    func saveConnectionChecked(_ draft: ProviderConnectionStore.Record, expected: Configuration) throws {
        guard configuration() == expected else { throw ProviderConnectionStore.Failure.changed }
        try ProviderConnectionStore.validateDraft(draft)
        try updateConnectionChecked { $0 = draft }
    }
    private func updateConnectionChecked(_ update: (inout ProviderConnectionStore.Record) -> Void) throws {
        invalidateAuthorization()
        do {
            var draft = try ProviderConnectionStore.preview(); update(&draft)
            try ProviderConnectionStore.save(draft, expectedRevision: ProviderAuthorizationRevision.current)
            credentialProblem = nil; objectWillChange.send(); refreshStatus()
        } catch {
            credentialProblem = error.localizedDescription; status = error.localizedDescription
            objectWillChange.send(); throw error
        }
    }
    private func updateConnection(_ update: (inout ProviderConnectionStore.Record) -> Void) {
        do { try updateConnectionChecked(update) } catch { /* Published status retains the checked failure. */ }
    }
    func removeAPIKeyChecked() throws {
        invalidateAuthorization()
        do {
            try ProviderConnectionStore.removeAPIKey(expectedRevision: ProviderAuthorizationRevision.current)
            credentialProblem = nil; objectWillChange.send(); refreshStatus()
        } catch { credentialProblem = error.localizedDescription; status = error.localizedDescription; objectWillChange.send(); throw error }
    }
    func removeAICredentialsChecked() throws {
        invalidateAuthorization()
        do {
            if SecureStore.erasurePending { try SecureStore.eraseAllChecked() }
            try OAuthCredentialStore.disconnect()
            try ProviderConnectionStore.removeAPIKey(expectedRevision: ProviderAuthorizationRevision.current, useOnDevice: true)
            credentialProblem = nil; objectWillChange.send(); refreshStatus()
        } catch { credentialProblem = error.localizedDescription; status = error.localizedDescription; objectWillChange.send(); throw error }
    }

    public var isOAuthConnected: Bool {
        (try? OAuthCredentialStore.hasCredentials(clientID: googleClientID, scope: oauthScope)) ?? false
    }

    struct Configuration: Equatable {
        let connectionID: UUID?
        let revision: UUID
        let mode: Mode
        let endpoint: String
        let model: String
        let oauthEndpoint: String
        let oauthModel: String
        let clientID: String
        let scope: String
        let preferExternal: Bool
    }
    func configuration() -> Configuration {
        let value = try? ProviderConnectionStore.preview()
        return .init(connectionID: value?.id, revision: ProviderAuthorizationRevision.current,
              mode: Mode(rawValue: value?.mode ?? "") ?? .onDevice, endpoint: value?.endpoint ?? "", model: value?.model ?? "",
              oauthEndpoint: value?.oauthEndpoint ?? "", oauthModel: value?.oauthModel ?? "", clientID: value?.clientID ?? "", scope: value?.scope ?? "",
              preferExternal: value?.preferExternal ?? false)
    }
    func isCurrent(_ expected: Configuration) -> Bool {
        ProviderConnectionStore.routingReady() && credentialProblem == nil && configuration() == expected
    }
    private struct SignInAttempt {
        let id: UUID
        let state: String
        let verifier: String
        let configuration: Configuration
        let redirectURI: URL
    }
    private var pendingSignIn: SignInAttempt?
    private var exchangingSignIn: UUID?
    private var authenticationSession: ASWebAuthenticationSession?
    private var testID: UUID?
    private struct RefreshJob {
        let id: UUID
        let configuration: Configuration
        let account: OAuthCredentialStore.Account
        let task: Task<OAuthCredentialStore.Account?, Never>
    }
    private var refreshJob: RefreshJob?
    var isAuthorizing: Bool { pendingSignIn != nil }

    private func invalidateAuthorization() {
        ProviderAuthorizationRevision.invalidate()
        pendingSignIn = nil
        exchangingSignIn = nil; testID = nil
        authenticationSession?.cancel(); authenticationSession = nil
        credentialProblem = nil; lastTestResult = nil; isBusy = false
    }

    public func setMode(_ m: Mode) {
        updateConnection { $0.mode = m.rawValue }
    }

    public func refreshStatus() {
        if SecureStore.erasurePending || OAuthCredentialStore.removalPending || ProviderConnectionStore.removalPending {
            status = OAuthCredentialStore.Failure.removalPending.localizedDescription; return
        }
        if let credentialProblem { status = credentialProblem; return }
        do {
            if try ProviderConnectionStore.preview().legacyCleanupPending {
                status = "Old credential cleanup hasn't finished. Save the connection again before sending."; return
            }
        } catch { credentialProblem = error.localizedDescription; status = error.localizedDescription; return }
        switch mode {
        case .onDevice:
            status = "External AI connection off"
        case .key:
            do {
                let key = try ProviderConnectionStore.preview().apiKey ?? ""
                status = key.isEmpty ? "Add an API key to use this connection" : "AI credentials saved · \(model)"
            } catch { credentialProblem = error.localizedDescription; status = error.localizedDescription }
        case .oauth:
            if isOAuthConnected {
                status = "OAuth credentials saved on this device"
            } else {
                status = googleClientID.isEmpty ? "Add an iOS client ID to set up Google sign-in" : "Google sign-in required"
            }
        }
    }

    static func googleRedirectURI(clientID: String) -> URL? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let identifier = String(clientID.dropLast(suffix.count))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        guard !identifier.isEmpty, identifier.utf8.count <= 256, identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return URL(string: "com.googleusercontent.apps." + identifier + ":/oauth2redirect/google")
    }

    private func prepareSignIn() -> (attempt: SignInAttempt, url: URL)? {
        guard let redirect = Self.googleRedirectURI(clientID: googleClientID) else {
            status = "Add a Google iOS client ID configured for this app's bundle ID."; return nil
        }
        guard !SecureStore.erasurePending, !OAuthCredentialStore.removalPending else { refreshStatus(); return nil }
        setMode(.oauth)
        invalidateAuthorization()
        let state = Self.randomString(length: 32), verifier = Self.randomString(length: 64)
        guard state.count == 32, verifier.count == 64 else { status = "Secure sign-in couldn't start. Try again."; return nil }
        let attempt = SignInAttempt(id: UUID(), state: state, verifier: verifier, configuration: configuration(), redirectURI: redirect)
        pendingSignIn = attempt
        let challenge = Self.pkceChallenge(verifier: attempt.verifier)
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: attempt.configuration.clientID),
            .init(name: "redirect_uri", value: attempt.redirectURI.absoluteString),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: attempt.configuration.scope),
            .init(name: "state", value: attempt.state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        guard let url = c.url else { pendingSignIn = nil; status = "Could not build auth URL"; return nil }
        return (attempt, url)
    }

    public func connectGoogle() {
        guard let prepared = prepareSignIn(), let scheme = prepared.attempt.redirectURI.scheme else { return }
        let attempt = prepared.attempt
        let session = ASWebAuthenticationSession(url: prepared.url, callback: .customScheme(scheme)) { [weak self] callback, error in
            Task { @MainActor in await self?.receiveOAuthCallback(callback, failed: error != nil, attemptID: attempt.id) }
        }
        session.presentationContextProvider = AuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        authenticationSession = session
        status = "Complete sign-in in the browser"
        if !session.start() { authenticationSession = nil; pendingSignIn = nil; status = "Sign-in couldn't start. Try again." }
    }

    private func receiveOAuthCallback(_ callback: URL?, failed: Bool, attemptID: UUID) async {
        guard let attempt = pendingSignIn, attempt.id == attemptID, exchangingSignIn == nil, isCurrent(attempt.configuration) else { return }
        authenticationSession = nil
        guard !failed else { pendingSignIn = nil; status = "Sign-in cancelled"; return }
        let expected = URLComponents(url: attempt.redirectURI, resolvingAgainstBaseURL: false)!
        guard let callback, let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == expected.scheme?.lowercased(), components.host == expected.host, components.path == expected.path,
              components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
              let items = components.queryItems, !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "state" }).count == 1, items.filter({ $0.name == "code" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == attempt.state,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            pendingSignIn = nil; status = "Sign-in response didn't match this attempt. Try again."; return
        }
        exchangingSignIn = attempt.id; isBusy = true
        defer { if pendingSignIn?.id == attempt.id { pendingSignIn = nil; exchangingSignIn = nil; isBusy = false } }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        let fields = [
            "client_id": attempt.configuration.clientID,
            "code": code,
            "code_verifier": attempt.verifier,
            "grant_type": "authorization_code",
            "redirect_uri": attempt.redirectURI.absoluteString,
        ]
        req.httpBody = fields.map { "\($0.key)=\($0.value.urlEncoded)" }.joined(separator: "&").data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await tokenResponse(for: req, authorizing: { self.pendingSignIn?.id == attempt.id && self.isCurrent(attempt.configuration) })
            let tok = try Self.decodeToken(data)
            guard !Task.isCancelled, pendingSignIn?.id == attempt.id, isCurrent(attempt.configuration) else { return }
            let account = OAuthCredentialStore.Account(clientID: attempt.configuration.clientID, scope: attempt.configuration.scope,
                accessToken: tok.access_token, refreshToken: tok.refresh_token, expiresAt: Date().addingTimeInterval(TimeInterval(tok.expires_in)))
            try OAuthCredentialStore.save(account, expectedRevision: attempt.configuration.revision)
            _ = try OAuthCredentialStore.load(clientID: account.clientID, scope: account.scope, expectedRevision: attempt.configuration.revision)
            status = "OAuth credentials saved on this device"
        } catch {
            if pendingSignIn?.id == attempt.id, isCurrent(attempt.configuration) {
                credentialProblem = "Sign-in credentials couldn't be saved. Try again."; status = credentialProblem!
            }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    struct SyntheticSignIn {
        let id: UUID
        let state: String
        let redirectURI: URL
        let authorizationURL: URL
        let pkceMatches: Bool
    }
    func beginSyntheticSignIn() -> SyntheticSignIn? {
        precondition(ProviderAuthorizationNativeProbe.requested && googleClientID == ProviderAuthorizationNativeProbe.syntheticClientID)
        guard let prepared = prepareSignIn() else { return nil }
        let items = URLComponents(url: prepared.url, resolvingAgainstBaseURL: false)!.queryItems!
        return .init(id: prepared.attempt.id, state: prepared.attempt.state, redirectURI: prepared.attempt.redirectURI,
            authorizationURL: prepared.url,
            pkceMatches: items.first(where: { $0.name == "code_challenge" })?.value == Self.pkceChallenge(verifier: prepared.attempt.verifier))
    }
    func finishSyntheticSignIn(_ callback: URL?, failed: Bool = false, id: UUID) async {
        precondition(ProviderAuthorizationNativeProbe.requested)
        await receiveOAuthCallback(callback, failed: failed, attemptID: id)
    }
    #endif

    public func validOAuthToken() async -> String? {
        await validOAuthAccount(expected: configuration())?.accessToken
    }

    private func accountIsCurrent(_ account: OAuthCredentialStore.Account, configuration expected: Configuration) -> Bool {
        isCurrent(expected) && (try? OAuthCredentialStore.read()) == account
    }

    func validOAuthAccount(expected: Configuration) async -> OAuthCredentialStore.Account? {
        guard !Task.isCancelled, expected.mode == .oauth, isCurrent(expected), pendingSignIn == nil else { return nil }
        do {
            guard let account = try OAuthCredentialStore.load(clientID: expected.clientID, scope: expected.scope, expectedRevision: expected.revision),
                  accountIsCurrent(account, configuration: expected) else { return nil }
            if account.accessToken != nil, account.expiresAt > Date(), (account.expiresAt > Date().addingTimeInterval(60) || account.refreshToken == nil) { return account }
            guard let refresh = account.refreshToken else { return nil }
            let job: RefreshJob
            if let existing = refreshJob, existing.configuration == expected, existing.account == account {
                job = existing
            } else {
                let task = Task { @MainActor [weak self] () -> OAuthCredentialStore.Account? in
                    guard let self, self.accountIsCurrent(account, configuration: expected) else { return nil }
                    var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
                    req.httpMethod = "POST"
                    let fields = ["client_id": expected.clientID, "refresh_token": refresh, "grant_type": "refresh_token"]
                    req.httpBody = fields.map { "\($0.key)=\($0.value.urlEncoded)" }.joined(separator: "&").data(using: .utf8)
                    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    do {
                        let (data, _) = try await self.tokenResponse(for: req, authorizing: { self.accountIsCurrent(account, configuration: expected) })
                        let tok = try Self.decodeToken(data)
                        guard !Task.isCancelled, self.accountIsCurrent(account, configuration: expected) else { return nil }
                        var updated = account
                        updated.accessToken = tok.access_token; updated.expiresAt = Date().addingTimeInterval(TimeInterval(tok.expires_in))
                        if let rotated = tok.refresh_token { updated.refreshToken = rotated }
                        try OAuthCredentialStore.save(updated, expectedRevision: expected.revision)
                        return updated
                    } catch {
                        if self.isCurrent(expected) { self.credentialProblem = "AI credentials couldn't refresh. Reconnect or try again."; self.status = self.credentialProblem! }
                        return nil
                    }
                }
                job = RefreshJob(id: UUID(), configuration: expected, account: account, task: task)
                refreshJob = job
            }
            let updated = await job.task.value
            if refreshJob?.id == job.id { refreshJob = nil }
            guard !Task.isCancelled, let updated, accountIsCurrent(updated, configuration: expected), updated.expiresAt > Date() else { return nil }
            return updated
        } catch {
            if isCurrent(expected) { credentialProblem = "AI credentials couldn't be read or saved. Try again."; status = credentialProblem! }
            return nil
        }
    }

    public func disconnectOAuth() {
        do { try disconnectOAuthChecked() }
        catch { credentialProblem = error.localizedDescription; status = error.localizedDescription }
    }
    public func disconnectOAuthChecked() throws {
        invalidateAuthorization()
        let wasOAuth = mode == .oauth
        do {
            try OAuthCredentialStore.disconnect()
            if wasOAuth { try updateConnectionChecked { $0.mode = "onDevice" } }
            credentialProblem = nil; refreshStatus()
        }
        catch { credentialProblem = error.localizedDescription; status = error.localizedDescription; throw error }
    }

    private func tokenResponse(for request: URLRequest, authorizing: @MainActor () -> Bool) async throws -> (Data, URLResponse) {
        var request = request
        #if DEBUG && targetEnvironment(simulator)
        if ProviderAuthorizationNativeProbe.requested {
            request = try ProviderAuthorizationNativeProbe.tokenRequest(for: request)
        }
        #endif
        return try await OAuthTokenTransport.data(for: request, authorizing: authorizing)
    }

    struct PreparedAuthorization {
        let configuration: Configuration
        let endpoint: URL
        let bearer: String
        let model: String
        let label: String
        let account: OAuthCredentialStore.Account?
    }

    var providerLabel: String { Self.providerLabel(configuration()) ?? "Configured AI provider" }
    private static func providerLabel(_ configuration: Configuration) -> String? {
        let text = configuration.mode == .oauth ? configuration.oauthEndpoint : configuration.endpoint
        guard let url = URLComponents(string: text), let host = url.host, !host.isEmpty else { return nil }
        let origin = (url.scheme ?? "https") + "://" + host + (url.port.map { ":\($0)" } ?? "")
        return (configuration.mode == .oauth ? "OAuth · " : "API key · ") + origin
    }

    func prepareAuthorization(expectedRevision: UUID? = nil) async -> PreparedAuthorization? {
        let captured = configuration()
        guard !Task.isCancelled, expectedRevision.map({ $0 == captured.revision }) ?? true,
              isCurrent(captured), pendingSignIn == nil, captured.mode != .onDevice else { return nil }
        let endpoint = captured.mode == .oauth ? captured.oauthEndpoint : captured.endpoint
        let model = captured.mode == .oauth ? captured.oauthModel : captured.model
        guard let parts = URLComponents(string: endpoint), let url = parts.url,
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let label = Self.providerLabel(captured) else { return nil }
        do {
            let connection = try ProviderConnectionStore.loadForRouting(expectedRevision: captured.revision)
            guard connection.id == captured.connectionID, isCurrent(captured) else { return nil }
            let account: OAuthCredentialStore.Account?
            let bearer: String
            if captured.mode == .oauth {
                guard let result = await validOAuthAccount(expected: captured), let access = result.accessToken else { return nil }
                account = result; bearer = access
            } else {
                let savedKey = connection.apiKey
                guard let key = savedKey, !key.isEmpty,
                      !key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else { return nil }
                account = nil; bearer = key
            }
            let prepared = PreparedAuthorization(configuration: captured, endpoint: url, bearer: bearer, model: model, label: label, account: account)
            return isCurrent(prepared) ? prepared : nil
        } catch {
            if isCurrent(captured) { credentialProblem = "AI credentials couldn't be read. Unlock this device and try again."; status = credentialProblem! }
            return nil
        }
    }

    func isCurrent(_ prepared: PreparedAuthorization) -> Bool {
        guard isCurrent(prepared.configuration), pendingSignIn == nil else { return false }
        if let account = prepared.account {
            return account.expiresAt > Date() && account.accessToken == prepared.bearer && (try? OAuthCredentialStore.read()) == account
        }
        return (try? ProviderConnectionStore.read())?.apiKey == prepared.bearer
    }

    public func runTest() async {
        await runTest(expectedConfiguration: configuration())
    }

    func runTest(expectedConfiguration captured: Configuration) async {
        guard !Task.isCancelled, configuration() == captured else { return }
        credentialProblem = nil
        let id = UUID(); testID = id; lastTestResult = nil
        isBusy = true; defer { if testID == id { testID = nil; isBusy = false } }
        let out = await LLMClient.simplePrompt("Reply with exactly: Lumen AI link OK", expectedProviderRevision: captured.revision)
        guard !Task.isCancelled, testID == id, isCurrent(captured) else { return }
        if let out {
            lastTestResult = out
        } else {
            lastTestResult = "No response. Check the saved model, credentials and endpoint."
        }
    }

    struct OAuthToken: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int
        var token_type: String
        var error: String?
    }

    /// Decode unambiguous JSON before credential construction. JSONDecoder alone
    /// can accept repeated fields, including escaped spellings of the same key.
    static func decodeToken(_ data: Data) throws -> OAuthToken {
        guard data.count <= 128_000 else { throw URLError(.dataLengthExceedsMaximum) }
        let document = try LiteralJSON.parse(data)
        guard document.root.members != nil, document.root["error"] == nil else { throw URLError(.cannotParseResponse) }
        let token = try JSONDecoder().decode(OAuthToken.self, from: data)
        guard token.token_type.lowercased() == "bearer", token.expires_in > 0 else { throw URLError(.cannotParseResponse) }
        return token
    }

    // MARK: PKCE helpers

    static func randomString(length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else { return "" }
        return bytes.map { String(chars[Int($0) % chars.count]) }.joined()
    }

    static func pkceChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? ""
    }
}

// MARK: - LLMClient: one routing layer for chat + vision.

public enum LLMClient {
    public struct ChatTurn: Sendable {
        public var role: String // system | user | assistant
        public var text: String
        public init(role: String, text: String) { self.role = role; self.text = text }
    }

    @MainActor
    public static func isConfigured() -> Bool {
        let svc = LLMConnectionService.shared
        guard ProviderConnectionStore.routingReady(), svc.credentialProblem == nil, !svc.isAuthorizing else { return false }
        switch svc.mode {
        case .onDevice: return false
        case .key: return !svc.apiKey.isEmpty
        case .oauth: return svc.isOAuthConnected && !svc.oauthEndpoint.isEmpty
        }
    }

    /// OpenAI-compatible chat completions. Returns assistant text or nil.
    public static func complete(endpoint: URL, bearer: String, model: String, turns: [ChatTurn], maxTokens: Int = 400, temperature: Double = 0.7, imageData: Data? = nil, submissionAllowed: @MainActor () -> Bool = { true }) async -> String? {
        guard !Task.isCancelled, (imageData?.count ?? 0) <= 8_000_000,
              turns.reduce(0, { $0 + $1.text.utf8.count }) <= ProviderReplyTransport.maxRequestBytes else { return nil }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var messages: [[String: Any]] = []
        for t in turns {
            if t.role == "user", let img = imageData {
                messages.append(["role": "user", "content": [
                    ["type": "text", "text": t.text],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(img.base64EncodedString())"]],
                ]])
            } else {
                messages.append(["role": t.role, "content": t.text])
            }
        }
        let payload: [String: Any] = ["model": model, "messages": messages, "max_tokens": maxTokens, "temperature": temperature]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        #if DEBUG && targetEnvironment(simulator)
        await PersonalContextSubmissionFixture.waitIfArmed()
        #endif
        return try? await ProviderReplyTransport.send(req, authorizing: submissionAllowed)
    }

    typealias ChatRoute = (endpoint: URL, bearer: String, model: String)

    @MainActor
    private static func route(expectedRevision: UUID? = nil) async -> LLMConnectionService.PreparedAuthorization? {
        await LLMConnectionService.shared.prepareAuthorization(expectedRevision: expectedRevision)
    }

    /// Coach chat with full conversation history.
    static func coachTurns(system: String, history: [(role: String, text: String)], userText: String) -> [ChatTurn] {
        [ChatTurn(role: "system", text: system)] + history.map { ChatTurn(role: $0.role, text: $0.text) }
            + [ChatTurn(role: "user", text: userText)]
    }

    @MainActor
    public static func coachChat(system: String, history: [(role: String, text: String)], userText: String, maxTokens: Int = 400,
                                 expectedPersonalContextRevision: UUID? = nil, expectedProviderRevision: UUID? = nil,
                                 submissionAllowed: @MainActor () -> Bool = { true }) async -> String? {
        guard let r = await route(expectedRevision: expectedProviderRevision) else { return nil }
        let result = await preparedCoachChat(system: system, history: history, userText: userText, maxTokens: maxTokens,
                                      expectedPersonalContextRevision: expectedPersonalContextRevision,
                                      submissionAllowed: { LLMConnectionService.shared.isCurrent(r) && submissionAllowed() },
                                      resolving: { (r.endpoint, r.bearer, r.model) })
        return LLMConnectionService.shared.isCurrent(r) && personalContextIsCurrent(expectedPersonalContextRevision) && submissionAllowed() ? result : nil
    }

    @MainActor
    static func personalContextIsCurrent(_ revision: UUID?) -> Bool {
        revision.map { $0 == CompanionStore.shared.personalContextRevision } ?? true
    }

    /// Credential refresh can suspend. Recheck the original authorization after
    /// that wait, before submitting health context to the resolved provider.
    @MainActor
    static func preparedCoachChat(system: String, history: [(role: String, text: String)], userText: String, maxTokens: Int = 400,
                                  expectedPersonalContextRevision: UUID?, submissionAllowed: @MainActor () -> Bool = { true }, resolving resolve: () async -> ChatRoute?) async -> String? {
        guard let r = await resolve(), !Task.isCancelled,
              personalContextIsCurrent(expectedPersonalContextRevision), submissionAllowed() else { return nil }
        let turns = coachTurns(system: system, history: history, userText: userText)
        return await complete(endpoint: r.endpoint, bearer: r.bearer, model: r.model, turns: turns, maxTokens: min(6000, max(400, maxTokens)),
                              submissionAllowed: { personalContextIsCurrent(expectedPersonalContextRevision) && submissionAllowed() })
    }

    /// Meal photo → raw JSON string (caller parses MealAnalysis).
    @MainActor
    public static func visionMealJSON(imageData: Data, expectedProviderRevision: UUID? = nil) async -> String? {
        guard let r = await route(expectedRevision: expectedProviderRevision) else { return nil }
        let prompt = "You are a nutrition vision model. Look at this meal photo and return JSON: {\"items\":[{\"name\":string,\"grams\":number,\"calories\":number,\"proteinG\":number,\"carbsG\":number,\"fatG\":number,\"fiberG\":number}],\"headline\":string,\"coachingNote\":string}. Be realistic, generous with protein detection, one-line kind coachingNote. No markdown, JSON only."
        let result = await complete(endpoint: r.endpoint, bearer: r.bearer, model: r.model, turns: [ChatTurn(role: "user", text: prompt)], maxTokens: 700, temperature: 0.4, imageData: imageData,
                                    submissionAllowed: { LLMConnectionService.shared.isCurrent(r) })
        return LLMConnectionService.shared.isCurrent(r) ? result : nil
    }

    /// Connectivity check used by the in-app Test button.
    @MainActor
    public static func simplePrompt(_ text: String, expectedProviderRevision: UUID? = nil) async -> String? {
        guard let r = await route(expectedRevision: expectedProviderRevision) else { return nil }
        let result = await complete(endpoint: r.endpoint, bearer: r.bearer, model: r.model, turns: [ChatTurn(role: "user", text: text)], maxTokens: 60,
                                    submissionAllowed: { LLMConnectionService.shared.isCurrent(r) })
        return LLMConnectionService.shared.isCurrent(r) ? result : nil
    }
}
