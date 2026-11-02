#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Actual shared credential/route behavior with a fixed, guarded loopback exchange.
@MainActor enum ProviderAuthorizationNativeProbe {
    static var requested: Bool {
        PersonalContextNativeProbe.requested && ProcessInfo.processInfo.arguments.contains("-provider-authorization-checks")
    }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    struct Packet: Codable {
        let route: String
        let model: String
        let credential: String
        let systemCanary: Bool
        let bodySHA256: String
    }
    struct Audit: Codable {
        let tokenRequests: Int
        let tokenResponses: Int
        let holdTimeouts: Int
        let packets: [Packet]
    }
    struct Observation: Encodable {
        let mode: String
        let accessState: String
        let refreshPresent: Bool
        let expiryPresent: Bool
        let selectedMode: String
        let outgoingRequests: Int
        let packet: Packet?
        let replyAccepted: Bool
    }

    static func tokenResponse(for original: URLRequest) async throws -> (Data, URLResponse) {
        guard requested, original.url?.absoluteString == "https://oauth2.googleapis.com/token", original.httpMethod == "POST",
              let data = original.httpBody, let form = String(data: data, encoding: .utf8),
              let items = URLComponents(string: "?" + form)?.queryItems, items.count == 3,
              items.first(where: { $0.name == "client_id" })?.value == "synthetic-client-42",
              items.first(where: { $0.name == "refresh_token" })?.value == "synthetic-refresh-42",
              items.first(where: { $0.name == "grant_type" })?.value == "refresh_token" else {
            throw Failure("Synthetic token request was not the fixed fixture")
        }
        var request = original
        request.url = URL(string: "http://127.0.0.1:48733/token")!
        request.timeoutInterval = 25
        return try await URLSession.shared.data(for: request)
    }

    static func control(_ path: String) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: URL(string: "http://127.0.0.1:48733/" + path)!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 128_000 else { throw Failure("Synthetic control failed") }
        return data
    }
    static func audit() async throws -> Audit { try JSONDecoder().decode(Audit.self, from: await control("audit")) }

    static func seed() throws {
        let service = LLMConnectionService.shared
        service.disconnectOAuth()
        service.googleClientID = "synthetic-client-42"
        service.oauthScope = "synthetic-scope-42"
        service.oauthEndpoint = "http://127.0.0.1:48733/chat-a"
        service.oauthModel = "synthetic-provider-42-a"
        SecureStore.set("synthetic-access-old-42", for: "lumen.llm.oauth.token")
        SecureStore.set("synthetic-refresh-42", for: "lumen.llm.oauth.refresh")
        UserDefaults.standard.set(Date().addingTimeInterval(-120), forKey: "lumen.llm.oauth.expires")
        service.setMode(.oauth)
        guard SecureStore.string("lumen.llm.oauth.token") == "synthetic-access-old-42",
              SecureStore.string("lumen.llm.oauth.refresh") == "synthetic-refresh-42" else { throw Failure("Synthetic credential seed failed") }
    }

    static func runBaseline() async -> String {
        precondition(requested)
        var observations: [Observation] = []
        var task: Task<String?, Never>?
        var status = "Provider baseline failed"
        do {
            for mode in ["unchanged", "disconnect", "mode", "endpoint", "model", "client", "scope", "revert", "reset", "refresh-failure"] {
                try seed()
                let before = try await audit()
                _ = try await control(mode == "refresh-failure" ? "arm-token-failure" : "arm-token")
                task = Task { await LLMClient.coachChat(system: "SYNTHETIC-PROVIDER-CONTEXT-42", history: [], userText: "SYNTHETIC-PROVIDER-QUESTION-42") }
                var holding = false
                for _ in 0..<200 {
                    if try await audit().tokenRequests == before.tokenRequests + 1 { holding = true; break }
                    try await Task.sleep(for: .milliseconds(25))
                }
                guard holding else { throw Failure("Token hold did not arrive: " + mode) }
                let service = LLMConnectionService.shared
                switch mode {
                case "disconnect": service.disconnectOAuth()
                case "mode": service.setMode(.onDevice)
                case "endpoint": service.oauthEndpoint = "http://127.0.0.1:48733/chat-b"
                case "model": service.oauthModel = "synthetic-provider-42-b"
                case "client": service.googleClientID = "synthetic-client-replaced-42"
                case "scope": service.oauthScope = "synthetic-scope-replaced-42"
                case "revert": service.oauthModel = "synthetic-provider-42-b"; service.oauthModel = "synthetic-provider-42-a"
                case "reset": LocalStore.eraseAll(); SecureStore.eraseAll()
                default: break
                }
                _ = try await control("release-token")
                let reply = await task!.value; task = nil
                let after = try await audit()
                let sent = after.packets.count - before.packets.count
                let access = SecureStore.string("lumen.llm.oauth.token")
                let accessState = access == nil ? "missing" : access == "synthetic-access-refreshed-42" ? "refreshed-fixture" : access == "synthetic-access-old-42" ? "expired-fixture" : "unexpected"
                guard accessState != "unexpected" else { throw Failure("Unexpected credential state") }
                let observation = Observation(mode: mode, accessState: accessState,
                    refreshPresent: SecureStore.string("lumen.llm.oauth.refresh") != nil,
                    expiryPresent: UserDefaults.standard.object(forKey: "lumen.llm.oauth.expires") != nil,
                    selectedMode: service.mode.rawValue, outgoingRequests: sent,
                    packet: sent > 0 ? after.packets.last : nil, replyAccepted: reply == "SYNTHETIC-PROVIDER-REPLY-42")
                observations.append(observation)
                guard after.holdTimeouts == 0, sent == (mode == "reset" ? 0 : 1),
                      accessState == (mode == "refresh-failure" ? "expired-fixture" : "refreshed-fixture"),
                      observation.replyAccepted == (sent == 1) else { throw Failure("Baseline behavior differed: " + mode) }
                if mode == "disconnect" { guard !observation.refreshPresent, observation.selectedMode == "onDevice" else { throw Failure("Disconnect mutation did not complete") } }
                if mode == "endpoint" { guard observation.packet?.route == "/chat-b" else { throw Failure("Changed endpoint not observed") } }
                if mode == "model" { guard observation.packet?.model == "synthetic-provider-42-b" else { throw Failure("Changed model not observed") } }
            }
            status = "Provider baseline reproduced"
        } catch { status = "Provider baseline failed: " + error.localizedDescription }
        _ = try? await control("release-token")
        task?.cancel(); if let task { _ = await task.value }
        LLMConnectionService.shared.disconnectOAuth()
        struct Report: Encodable { let status: String; let observations: [Observation]; let host: Audit? }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Report(status: status, observations: observations, host: try? await audit()))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-baseline-report.json"), options: .atomic)
        } catch { status = "Provider baseline failed: report write failed" }
        return status
    }
}
#endif
