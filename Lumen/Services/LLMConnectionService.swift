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
            switch self { case .onDevice: return "On-device"; case .key: return "API key"; case .oauth: return "Google OAuth" }
        }
    }

    @Published public var mode: Mode = .onDevice
    @Published public var status = "On-device brain active"
    @Published public var isBusy = false
    @Published public var lastTestResult: String?

    private let modeKey = "lumen.llm.mode"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: modeKey), let m = Mode(rawValue: raw) {
            mode = m
        } else if !(UserDefaults.standard.string(forKey: "lumen.llm.key") ?? "").isEmpty {
            mode = .key // migrated from earlier key-only versions
        }
        refreshStatus()
    }

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
            case .custom: return UserDefaults.standard.string(forKey: "lumen.llm.endpoint") ?? "https://api.openai.com/v1/chat/completions"
            }
        }
        public var defaultModel: String {
            switch self { case .openAI: return "gpt-4o-mini"; case .aiStudio: return "gemini-2.0-flash"; case .custom: return "gpt-4o-mini" }
        }
    }

    public var apiKey: String {
        get { UserDefaults.standard.string(forKey: "lumen.llm.key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.llm.key"); refreshStatus() }
    }
    public var endpoint: String {
        get { UserDefaults.standard.string(forKey: "lumen.llm.endpoint") ?? Preset.openAI.endpoint }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.llm.endpoint"); refreshStatus() }
    }
    public var model: String {
        get { UserDefaults.standard.string(forKey: "lumen.llm.model") ?? "gpt-4o-mini" }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.llm.model") }
    }

    public func applyPreset(_ preset: Preset) {
        if preset != .custom {
            endpoint = preset.endpoint
            model = preset.defaultModel
        }
        UserDefaults.standard.set(preset.rawValue, forKey: "lumen.llm.preset")
    }

    public var currentPreset: Preset {
        Preset(rawValue: UserDefaults.standard.string(forKey: "lumen.llm.preset") ?? "openAI") ?? .openAI
    }

    // MARK: OAuth mode (PKCE, on-device)

    /// Google Cloud → Credentials → OAuth client. Any client type works as long
    /// as `lumen://oauth-callback` is a registered redirect URI.
    public var googleClientID: String {
        get { UserDefaults.standard.string(forKey: "lumen.llm.google.clientid") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.llm.google.clientid"); refreshStatus() }
    }
    public var oauthScope: String {
        get { UserDefaults.standard.string(forKey: "lumen.llm.google.scope") ?? "openid email profile" }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.llm.google.scope") }
    }
    /// Bearer endpoint for OAuth mode (OpenAI-compatible request shape).
    public var oauthEndpoint: String {
        get { UserDefaults.standard.string(forKey: "lumen.llm.oauth.endpoint") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.llm.oauth.endpoint"); refreshStatus() }
    }
    public var oauthModel: String {
        get { UserDefaults.standard.string(forKey: "lumen.llm.oauth.model") ?? "gemini-2.0-flash" }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.llm.oauth.model") }
    }

    private var oauthAccess: String? { UserDefaults.standard.string(forKey: "lumen.llm.oauth.token") }
    private var oauthRefresh: String? { UserDefaults.standard.string(forKey: "lumen.llm.oauth.refresh") }
    private var oauthExpiry: Date? { UserDefaults.standard.object(forKey: "lumen.llm.oauth.expires") as? Date }
    private var pendingVerifier: String?

    public var isOAuthConnected: Bool { oauthAccess != nil }

    public func setMode(_ m: Mode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: modeKey)
        refreshStatus()
    }

    public func refreshStatus() {
        switch mode {
        case .onDevice:
            status = "On-device brain active"
        case .key:
            status = apiKey.isEmpty ? "Add an API key to enable AI vision + chat" : "AI active · \(currentPreset.label) · \(model)"
        case .oauth:
            if isOAuthConnected {
                status = "AI active · OAuth connected"
            } else {
                status = googleClientID.isEmpty ? "Add your Google Client ID, then connect" : "Tap Connect to sign in with Google"
            }
        }
    }

    public func connectGoogle() {
        guard !googleClientID.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = "Paste your Google Client ID first (Google Cloud → Credentials)"; return
        }
        let verifier = Self.randomString(length: 64)
        pendingVerifier = verifier
        let challenge = Self.pkceChallenge(verifier: verifier)
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: googleClientID),
            .init(name: "redirect_uri", value: "lumen://oauth-callback"),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: oauthScope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        guard let url = c.url else { status = "Could not build auth URL"; return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lumen") { callback, error in
            if error != nil { Task { @MainActor in self.status = "Sign-in cancelled" }; return }
            guard let callback,
                  let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else {
                Task { @MainActor in self.status = "No auth code returned" }; return
            }
            Task { await self.exchangeOAuth(code: code) }
        }
        session.presentationContextProvider = AuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        _ = session.start()
    }

    private func exchangeOAuth(code: String) async {
        guard let verifier = pendingVerifier else { status = "Session expired — try again"; return }
        pendingVerifier = nil
        isBusy = true; defer { isBusy = false }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        let fields = [
            "client_id": googleClientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": "lumen://oauth-callback",
        ]
        req.httpBody = fields.map { "\($0.key)=\($0.value.urlEncoded)" }.joined(separator: "&").data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let tok = try JSONDecoder().decode(OAuthToken.self, from: data)
            UserDefaults.standard.set(tok.access_token, forKey: "lumen.llm.oauth.token")
            if let r = tok.refresh_token { UserDefaults.standard.set(r, forKey: "lumen.llm.oauth.refresh") }
            UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(tok.expires_in)), forKey: "lumen.llm.oauth.expires")
            status = "Connected — Bearer token stored on this phone"
        } catch {
            status = "Token exchange failed: \(error.localizedDescription)"
        }
    }

    public func validOAuthToken() async -> String? {
        if let exp = oauthExpiry, exp > Date().addingTimeInterval(60), let t = oauthAccess { return t }
        guard let refresh = oauthRefresh else { return oauthAccess }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        let fields = ["client_id": googleClientID, "refresh_token": refresh, "grant_type": "refresh_token"]
        req.httpBody = fields.map { "\($0.key)=\($0.value.urlEncoded)" }.joined(separator: "&").data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let tok = try JSONDecoder().decode(OAuthToken.self, from: data)
            UserDefaults.standard.set(tok.access_token, forKey: "lumen.llm.oauth.token")
            UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(tok.expires_in)), forKey: "lumen.llm.oauth.expires")
            return tok.access_token
        } catch { return oauthAccess }
    }

    public func disconnectOAuth() {
        UserDefaults.standard.removeObject(forKey: "lumen.llm.oauth.token")
        UserDefaults.standard.removeObject(forKey: "lumen.llm.oauth.refresh")
        UserDefaults.standard.removeObject(forKey: "lumen.llm.oauth.expires")
        if mode == .oauth { setMode(.onDevice) } else { refreshStatus() }
    }

    public func runTest() async {
        isBusy = true; defer { isBusy = false }
        if let out = await LLMClient.simplePrompt("Reply with exactly: Lumen AI link OK") {
            lastTestResult = out
        } else {
            lastTestResult = "No response — check mode, key/connection, and endpoint."
        }
    }

    struct OAuthToken: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int
    }

    // MARK: PKCE helpers

    static func randomString(length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
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
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
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
        switch svc.mode {
        case .onDevice: return false
        case .key: return !svc.apiKey.isEmpty
        case .oauth: return svc.isOAuthConnected && !svc.oauthEndpoint.isEmpty
        }
    }

    /// OpenAI-compatible chat completions. Returns assistant text or nil.
    public static func complete(endpoint: URL, bearer: String, model: String, turns: [ChatTurn], maxTokens: Int = 400, temperature: Double = 0.7, imageData: Data? = nil) async -> String? {
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
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]] else {
                // Some gateways nest differently; try `output` shape.
                return nil
            }
            if let msg = choices.first?["message"] as? [String: Any], let content = msg["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        } catch { return nil }
    }

    @MainActor
    private static func route() async -> (endpoint: URL, bearer: String, model: String)? {
        let svc = LLMConnectionService.shared
        switch svc.mode {
        case .onDevice:
            return nil
        case .key:
            guard !svc.apiKey.isEmpty, let url = URL(string: svc.endpoint) else { return nil }
            return (url, svc.apiKey, svc.model)
        case .oauth:
            guard let token = await svc.validOAuthToken(), !svc.oauthEndpoint.isEmpty, let url = URL(string: svc.oauthEndpoint) else { return nil }
            return (url, token, svc.oauthModel)
        }
    }

    /// Coach chat with full conversation history.
    @MainActor
    public static func coachChat(system: String, history: [(role: String, text: String)], userText: String) async -> String? {
        guard let r = await route() else { return nil }
        var turns = [ChatTurn(role: "system", text: system)]
        turns += history.map { ChatTurn(role: $0.role, text: $0.text) }
        turns.append(ChatTurn(role: "user", text: userText))
        return await complete(endpoint: r.endpoint, bearer: r.bearer, model: r.model, turns: turns, maxTokens: 400)
    }

    /// Meal photo → raw JSON string (caller parses MealAnalysis).
    @MainActor
    public static func visionMealJSON(imageData: Data) async -> String? {
        guard let r = await route() else { return nil }
        let prompt = "You are a nutrition vision model. Look at this meal photo and return JSON: {\"items\":[{\"name\":string,\"grams\":number,\"calories\":number,\"proteinG\":number,\"carbsG\":number,\"fatG\":number,\"fiberG\":number}],\"headline\":string,\"coachingNote\":string}. Be realistic, generous with protein detection, one-line kind coachingNote. No markdown, JSON only."
        return await complete(endpoint: r.endpoint, bearer: r.bearer, model: r.model, turns: [ChatTurn(role: "user", text: prompt)], maxTokens: 700, temperature: 0.4, imageData: imageData)
    }

    /// Connectivity check used by the in-app Test button.
    @MainActor
    public static func simplePrompt(_ text: String) async -> String? {
        guard let r = await route() else { return nil }
        return await complete(endpoint: r.endpoint, bearer: r.bearer, model: r.model, turns: [ChatTurn(role: "user", text: text)], maxTokens: 60)
    }
}
