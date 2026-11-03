#if DEBUG && targetEnvironment(simulator)
import Foundation
import Security
import AuthenticationServices
import CryptoKit
import UIKit

/// Actual shared credential/route behavior with a fixed, guarded loopback exchange.
@MainActor enum ProviderAuthorizationNativeProbe {
    static let syntheticClientID = "123456789-synthetic42.apps.googleusercontent.com"
    static let syntheticAuthCode = "SYNTHETIC+AUTH&CODE=42"
    static var requested: Bool {
        PersonalContextNativeProbe.requested && ProcessInfo.processInfo.arguments.contains(where: { ["-provider-authorization-checks", "-provider-credential-checks"].contains($0) })
    }
    /// Only the second half of the dedicated synthetic relaunch test preserves
    /// local state. Ordinary UI tests retain their normal clean-slate launch.
    static var resumesRemovalCheck: Bool {
        let args = ProcessInfo.processInfo.arguments
        return requested && args.contains("-provider-removal-relaunch") && args.contains("-provider-removal-resume") &&
            ["-provider-removal-oauth", "-provider-removal-all", "-provider-removal-key"].filter { args.contains($0) }.count == 1
    }
    static var usesConfiguredCallerTransport: Bool {
        requested && ProcessInfo.processInfo.arguments.contains("-provider-caller-checks")
    }
    static var resumesAccountResetCheck: Bool {
        AccountResetNativeFixture.requested && ProcessInfo.processInfo.arguments.contains("-provider-reset-resume") && AccountResetNativeFixture.hasReceipt
    }
    static func run() async -> String {
        if ProcessInfo.processInfo.arguments.contains("-provider-token-transport-checks") { return await runTokenTransportChecks() }
        if AccountResetNativeFixture.requested { return await runAccountResetChecks() }
        if ProcessInfo.processInfo.arguments.contains("-provider-connection-checks") { return await runConnectionChecks() }
        if usesConfiguredCallerTransport { return await runCallerChecks() }
        if ProcessInfo.processInfo.arguments.contains("-provider-removal-relaunch") { return await runRemovalRelaunchCheck() }
        if ProcessInfo.processInfo.arguments.contains("-provider-signin-checks") { return await runSignInChecks() }
        if ProcessInfo.processInfo.arguments.contains("-provider-credential-checks") { return runStorageChecks() }
        return await runAuthorizationChecks()
    }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    struct Packet: Codable {
        let kind: String?
        let imageSHA256: String?
        let staleConnectivityReply: Bool?
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
        let loginRequests: Int?
        let loginResponses: Int?
        let loginAudit: [LoginPacket]?
        let tokenTransportAudit: [TokenTransportPacket]?
        let tokenTransportResponses: Int?
        let tokenRedirectHits: Int?
    }
    struct TokenTransportPacket: Codable {
        let caseName: String
        let requestKind: String
        let bodySHA256: String
        let formMatches: Bool
        let cookieAbsent: Bool
        let statusCode: Int
        let payloadBytes: Int
        let advertisedBytes: Int
        let streamStarted: Bool
        let pkceMatches: Bool?
    }
    struct LoginPacket: Codable {
        let pkceMatches: Bool
        let redirectMatches: Bool
        let reservedCodeDecoded: Bool
        let bodySHA256: String
    }
    static func tokenRequest(for original: URLRequest) throws -> URLRequest {
        guard requested, original.url?.absoluteString == "https://oauth2.googleapis.com/token", original.httpMethod == "POST",
              let data = original.httpBody, let form = String(data: data, encoding: .utf8),
              let items = URLComponents(string: "?" + form)?.queryItems,
              Set(items.map(\.name)).count == items.count else {
            throw Failure("Synthetic token request was not the fixed fixture")
        }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        let refresh = fields == ["client_id": "synthetic-client-42", "refresh_token": "synthetic-refresh-42", "grant_type": "refresh_token"]
        let login = fields.count == 5 && fields["client_id"] == syntheticClientID && fields["code"] == syntheticAuthCode && fields["grant_type"] == "authorization_code" &&
            fields["redirect_uri"] == LLMConnectionService.googleRedirectURI(clientID: syntheticClientID)?.absoluteString &&
            fields["code_verifier"]?.count == 64 && fields["code_verifier"]!.utf8.allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8.contains($0) }
        guard refresh || login else { throw Failure("Synthetic token request was not the fixed fixture") }
        var request = original
        let adversarial = ProcessInfo.processInfo.arguments.contains("-provider-token-transport-checks")
        request.url = URL(string: "http://127.0.0.1:48733/" + (adversarial ? (login ? "adversarial-login" : "adversarial-refresh") : (login ? "token-login" : "token")))!
        request.timeoutInterval = 25
        return request
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
        try service.disconnectOAuthChecked()
        service.googleClientID = "synthetic-client-42"
        service.oauthScope = "synthetic-scope-42"
        service.oauthEndpoint = "http://127.0.0.1:48733/chat-a"
        service.oauthModel = "synthetic-provider-42-a"
        try SecureStore.setChecked("synthetic-access-old-42", for: "lumen.llm.oauth.token")
        try SecureStore.setChecked("synthetic-refresh-42", for: "lumen.llm.oauth.refresh")
        UserDefaults.standard.set(Date().addingTimeInterval(-120), forKey: "lumen.llm.oauth.expires")
        service.setMode(.oauth)
        guard SecureStore.string("lumen.llm.oauth.token") == "synthetic-access-old-42",
              SecureStore.string("lumen.llm.oauth.refresh") == "synthetic-refresh-42" else { throw Failure("Synthetic credential seed failed") }
    }

    static func cleanupChecked() throws {
        precondition(requested)
        let service = LLMConnectionService.shared
        try service.disconnectOAuthChecked(); try service.saveAPIKeyChecked(""); service.setMode(.onDevice)
        guard !service.isAuthorizing, !SecureStore.erasurePending, !OAuthCredentialStore.removalPending,
              !ProviderConnectionStore.removalPending,
              try ProviderConnectionStore.read()?.apiKey == nil,
              try ProviderConnectionStore.read()?.legacyCleanupPending != true,
              try SecureStore.dataChecked(OAuthCredentialStore.key) == nil,
              try SecureStore.dataChecked("lumen.llm.key") == nil,
              try SecureStore.dataChecked("lumen.llm.oauth.token") == nil,
              try SecureStore.dataChecked("lumen.llm.oauth.refresh") == nil,
              UserDefaults.standard.object(forKey: "lumen.llm.oauth.expires") == nil else { throw Failure("Synthetic credential cleanup not complete") }
    }

    static func runCallerChecks() async -> String {
        precondition(usesConfiguredCallerTransport)
        struct Result {
            let accepted: Bool
            let source: String
            let savedConversation: Bool
            let savedPlans: Int
        }
        struct Observation: Encodable {
            let caller: String
            let mode: String
            let outgoingRequests: Int
            let accepted: Bool
            let source: String
            let savedConversation: Bool
            let savedPlans: Int
        }
        struct Report: Encodable {
            let status: String
            let observations: [Observation]
            let cleanupVerified: Bool
            let host: Audit?
            let scope: String
            let expectedSyntheticImageSHA256: String
        }
        let ai = AIService.shared, service = LLMConnectionService.shared
        let health = HealthStore.shared, companion = CompanionStore.shared
        var observations: [Observation] = [], tasks: [Task<Result, Error>] = []
        var status = "Provider caller checks failed", cleanup = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        let imageDigest = SHA256.hash(data: image.jpegData(compressionQuality: 0.6)!).map { String(format: "%02x", $0) }.joined()
        func waitFor(_ condition: @MainActor () async throws -> Bool) async throws {
            for _ in 0..<300 {
                if try await condition() { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw Failure("Caller hold did not arrive")
        }
        do {
            try await waitFor { health.conversationReady }
            var notes = PersonalHealthContext(); notes.focus = "SYNTHETIC-PROVIDER-NOTE-42"; notes.includeInAssistant = true
            try companion.savePersonalContextChecked(notes, expectedRevision: companion.personalContextRevision)
            _ = try await control("arm-photo?sha256=" + imageDigest)
            for caller in ["coach", "plan", "health", "photo", "description", "connectivity"] {
                let modes = ["unchanged", "stale-before-task", "submission-change", "response-change", "response-revert"] + (caller == "coach" ? ["search-change", "search-revert"] : caller == "connectivity" ? ["overlap"] : [])
                for mode in modes {
                    try cleanupChecked()
                    service.endpoint = "http://127.0.0.1:48733/caller-chat"; service.model = "synthetic-provider-42-a"
                    try service.saveAPIKeyChecked("synthetic-key-42-a"); service.setMode(.key); ai.preferOpenAI = true
                    let provider = ai.captureProvider(), personalRevision = companion.personalContextRevision
                    guard provider.brain == .openAIKey, provider.source == "API key · http://127.0.0.1:48733" else { throw Failure("Configured caller attribution missing") }
                    let before = try await audit()
                    var sent: ConversationSend?
                    if caller == "coach" {
                        try await health.newConversation()
                        sent = try await health.sendUserMessageChecked(.init(role: .user, text: "SYNTHETIC-PROVIDER-COACH-42 make a plan"), expectedConversationID: nil)
                    }
                    if mode == "stale-before-task" { service.model = "synthetic-provider-42-b" }
                    if mode == "submission-change" { PersonalContextSubmissionFixture.arm() }
                    if mode.hasPrefix("response-") { _ = try await control("arm-chat") }
                    if mode.hasPrefix("search-") { PersonalContextSearchFixture.arm() }
                    if mode == "overlap" { _ = try await control("arm-first-chat") }
                    let owner = sent
                    let task = Task<Result, Error> {
                        switch caller {
                        case "coach":
                            guard let owner else { throw Failure("Synthetic conversation owner missing") }
                            let outcome = await ChatCoachService.shared.replyOutcome(to: "SYNTHETIC-PROVIDER-COACH-42 make a plan", health: health, sleepDebt: 0, conversationHistory: owner.history,
                                expectedProviderConfiguration: provider.configuration, usingBrain: provider.brain)
                            let accepted = outcome.source == provider.source
                            guard accepted ? outcome.canBecomePlan && outcome.personalContext == .included(notes) :
                                outcome.source == "Lumen notice" && !outcome.canBecomePlan && outcome.personalContext == .withoutNotes && outcome.text.contains("Your AI connection changed") else { throw Failure("Caller outcome identity or notice invalid") }
                            let reply = ChatMessage(role: .coach, text: outcome.text, provider: outcome.source, recordContext: outcome.recordContext, personalContext: outcome.personalContext)
                            guard let id = health.retainConversationReply(reply, owner: owner.owner, savePlan: outcome.canBecomePlan) else { throw Failure("Caller reply owner lost") }
                            CoachView().saveReplyPlan(try await health.savePendingConversationReply(id))
                            let saved = try LocalStore.loadConversationsChecked().conversations.first { $0.id == owner.owner.conversationID }?.messages.last
                            let plans = (LocalStore.load([HealthDocument].self, from: "documents") ?? []).filter { $0.messageID == reply.id && $0.kind == .plan }
                            guard saved?.id == reply.id, saved?.provider == outcome.source, saved?.text == reply.text,
                                  plans.count == (accepted ? 1 : 0), plans.allSatisfy({ $0.source == "Lumen assistant · " + provider.source && $0.steps.count == 3 }) else { throw Failure("Actual saved conversation/automatic plan attribution mismatch") }
                            return .init(accepted: accepted, source: outcome.source, savedConversation: true, savedPlans: plans.count)
                        case "plan":
                            let request = ScheduledPlanRequest(goal: "SYNTHETIC-PROVIDER-PLAN-42", startDay: "2030-01-01", weeks: 1)
                            guard let response = await ai.scheduledPlan(request: request, context: "SYNTHETIC-PROVIDER-CONTEXT-42", using: provider.brain,
                                expectedPersonalContextRevision: personalRevision, expectedProviderRevision: provider.configuration.revision) else {
                                return .init(accepted: false, source: "", savedConversation: false, savedPlans: 0)
                            }
                            guard ai.isCurrent(provider) else { throw Failure("Stale plan escaped response guard") }
                            let draft = try ScheduledPlanDraft.parse(response, request: request, source: provider.source)
                            let document = try draft.document(acknowledged: true)
                            try companion.saveChecked(document)
                            guard let saved = LocalStore.load([HealthDocument].self, from: "documents")?.first(where: { $0.id == document.id }),
                                  saved.source == provider.source, saved.steps.count == 1 else { throw Failure("Saved scheduled plan attribution mismatch") }
                            return .init(accepted: true, source: saved.source, savedConversation: false, savedPlans: 1)
                        case "health":
                            do {
                                let drafts = try await ai.healthLogSuggestions(message: .init(role: .user, text: "SYNTHETIC-PROVIDER-LOG-42 I drank 250 ml water"), using: provider)
                                guard drafts.count == 1, drafts[0].kind == .water, drafts[0].waterML == 250,
                                      drafts[0].preparedBy == provider.source else { throw Failure("Health suggestion attribution mismatch") }
                                return .init(accepted: true, source: drafts[0].preparedBy, savedConversation: false, savedPlans: 0)
                            } catch AIService.ProviderRequestFailure.changed {
                                return .init(accepted: false, source: "", savedConversation: false, savedPlans: 0)
                            }
                        case "connectivity":
                            await service.runTest(expectedConfiguration: provider.configuration)
                            return .init(accepted: service.lastTestResult == "Lumen AI link OK", source: "", savedConversation: false, savedPlans: 0)
                        default:
                            let analysis = caller == "photo" ? await ai.analyzeMeal(image: image, using: provider) :
                                await ai.estimateMeal(description: "SYNTHETIC-PROVIDER-MEAL-42", using: provider)
                            if let analysis {
                                guard analysis.items.count == 1, analysis.items[0].name == "Synthetic food", analysis.totalCalories == 250,
                                      ai.isCurrent(provider) else { throw Failure("Meal caller accepted stale or malformed result") }
                            }
                            return .init(accepted: analysis != nil, source: "", savedConversation: false, savedPlans: 0)
                        }
                    }
                    tasks.append(task)
                    if mode == "overlap" {
                        try await waitFor { try await audit().packets.count == before.packets.count + 1 }
                        await service.runTest(expectedConfiguration: provider.configuration)
                        guard service.lastTestResult == "Lumen AI link OK", !service.isBusy else { throw Failure("New connectivity result did not finish while older test was held") }
                        _ = try await control("release-first-chat")
                    }
                    if mode == "submission-change" {
                        try await waitFor { PersonalContextSubmissionFixture.holding }
                        service.model = "synthetic-provider-42-b"; PersonalContextSubmissionFixture.release()
                    }
                    if mode.hasPrefix("response-") {
                        try await waitFor { try await audit().packets.count == before.packets.count + 1 }
                        try service.saveAPIKeyChecked("synthetic-key-42-b")
                        if mode == "response-revert" { try service.saveAPIKeyChecked("synthetic-key-42-a") }
                        _ = try await control("release-chat")
                    }
                    if mode.hasPrefix("search-") {
                        try await waitFor { PersonalContextSearchFixture.holding }
                        service.model = "synthetic-provider-42-b"
                        if mode == "search-revert" { service.model = "synthetic-provider-42-a" }
                        PersonalContextSearchFixture.release()
                    }
                    let result = try await task.value, after = try await audit()
                    let packets = Array(after.packets.dropFirst(before.packets.count))
                    guard result.accepted == (["unchanged", "overlap"].contains(mode)), packets.count == (mode == "overlap" ? 2 : mode == "unchanged" || mode.hasPrefix("response-") ? 1 : 0),
                          packets.allSatisfy({ $0.route == "/caller-chat" && $0.kind == caller && $0.model == "synthetic-provider-42-a" && $0.credential == "api-key-fixture" && $0.systemCanary }),
                          packets.allSatisfy({ caller != "photo" || $0.imageSHA256 == imageDigest }),
                          !PersonalContextSubmissionFixture.timedOut, !PersonalContextSearchFixture.timedOut, after.holdTimeouts == 0 else { throw Failure(caller + " " + mode + " packet/acceptance mismatch") }
                    observations.append(.init(caller: caller, mode: mode, outgoingRequests: packets.count, accepted: result.accepted,
                        source: result.source, savedConversation: result.savedConversation, savedPlans: result.savedPlans))
                }
            }
            try cleanupChecked(); cleanup = true
            status = "Provider caller checks passed"
        } catch { status = "Provider caller checks failed: " + error.localizedDescription }
        PersonalContextSearchFixture.release(); PersonalContextSubmissionFixture.release()
        _ = try? await control("release-chat")
        _ = try? await control("release-first-chat")
        for task in tasks { task.cancel(); _ = try? await task.value }
        if !cleanup { try? cleanupChecked() }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Report(status: status, observations: observations, cleanupVerified: cleanup, host: try? await audit(),
                scope: "Synthetic configured API-key route through production coach/search/conversation/automatic-plan, scheduled-plan save, health draft attribution, meal photo/description and connectivity checks. Fixed generated24x24 image digest independently matches transmitted bytes. No real providers, Apple inference, confirmed health/meal writes or UI interaction acceptance.", expectedSyntheticImageSHA256: imageDigest))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-caller-report.json"), options: .atomic)
        } catch { return "Provider caller checks failed: report write failed" }
        return status
    }

    static func runRemovalRelaunchCheck() async -> String {
        precondition(requested)
        struct Marker: Codable {
            let mode: String
            let pid: Int32
            let accountSHA256: String
            let connectionSHA256: String
        }
        struct Report: Encodable {
            let status: String
            let mode: String
            let phase: String
            let pid: Int32
            let originalPID: Int32
            let checks: [String]
            let scope: String
        }
        let args = ProcessInfo.processInfo.arguments, defaults = UserDefaults.standard
        let all = args.contains("-provider-removal-all"), keyOnly = args.contains("-provider-removal-key")
        let mode = all ? "all" : keyOnly ? "key" : "oauth"
        let phase = resumesRemovalCheck ? "resume" : "prepare"
        let markerKey = "synthetic.storage.42.removal-relaunch"
        let service = LLMConnectionService.shared
        var checks: [String] = [], originalPID = getpid()
        var status = "Credential removal relaunch checks failed"
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { throw Failure(name) }
            checks.append(name)
        }
        func digest(_ data: Data?) -> String {
            guard let data else { return "missing" }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        do {
            try check(["-provider-removal-oauth", "-provider-removal-all", "-provider-removal-key"].filter { args.contains($0) }.count == 1, "exactly one dedicated removal mode")
            let marker: Marker
            if resumesRemovalCheck {
                guard let data = defaults.data(forKey: markerKey) else { throw Failure("Original fixture marker missing") }
                marker = try JSONDecoder().decode(Marker.self, from: data)
                originalPID = marker.pid
                try check(marker.mode == mode && marker.pid != getpid(), "new process reads the original fixture marker without reseeding")
            } else {
                try SecureStore.eraseAllChecked(); try cleanupChecked()
                service.googleClientID = syntheticClientID; service.oauthScope = "openid email profile"
                service.oauthEndpoint = "http://127.0.0.1:48733/chat-a"; service.oauthModel = "synthetic-provider-42-a"
                service.endpoint = "http://127.0.0.1:48733/chat-a"; service.model = "synthetic-provider-42-a"
                try service.saveAPIKeyChecked("synthetic-key-42-a")
                try SecureStore.setChecked("synthetic-key-42-a", for: "lumen.llm.key")
                let account = OAuthCredentialStore.Account(clientID: syntheticClientID, scope: service.oauthScope,
                    accessToken: "synthetic-access-old-42", refreshToken: "synthetic-refresh-42", expiresAt: Date().addingTimeInterval(3600))
                try OAuthCredentialStore.save(account, expectedRevision: ProviderAuthorizationRevision.current)
                try SecureStore.setChecked("synthetic-access-old-42", for: "lumen.llm.oauth.token")
                try SecureStore.setChecked("synthetic-refresh-42", for: "lumen.llm.oauth.refresh")
                defaults.set(account.expiresAt, forKey: "lumen.llm.oauth.expires")
                marker = Marker(mode: mode, pid: getpid(), accountSHA256: digest(try SecureStore.dataChecked(OAuthCredentialStore.key)), connectionSHA256: digest(try SecureStore.dataChecked(ProviderConnectionStore.key)))
                SecureStore.injectFailure(keyOnly ? .write : .delete, key: all ? "synthetic.storage.42.service" : keyOnly ? ProviderConnectionStore.key : OAuthCredentialStore.key, status: errSecInteractionNotAllowed)
                var failed = false
                do { if all { try SecureStore.eraseAllChecked() } else if keyOnly { try service.removeAPIKeyChecked() } else { try service.disconnectOAuthChecked() } }
                catch let error as SecureStore.Failure { failed = error.operation == (keyOnly ? .write : .delete) && error.status == errSecInteractionNotAllowed }
                try check(failed, "checked removal surfaces the injected storage failure")
                defaults.set(try JSONEncoder().encode(marker), forKey: markerKey)
            }
            try check(all ? SecureStore.erasurePending : keyOnly ? ProviderConnectionStore.removalPending : OAuthCredentialStore.removalPending, "removal intent remains set")
            try check(digest(SecureStore.dataChecked(OAuthCredentialStore.key)) == marker.accountSHA256, "original account bytes remain physically stored")
            try check(digest(SecureStore.dataChecked(ProviderConnectionStore.key)) == marker.connectionSHA256, "original complete connection bytes remain physically stored")
            try check(SecureStore.stringChecked("lumen.llm.key") == "synthetic-key-42-a" && SecureStore.stringChecked("lumen.llm.oauth.token") == "synthetic-access-old-42" && SecureStore.stringChecked("lumen.llm.oauth.refresh") == "synthetic-refresh-42", "original key and both legacy sources remain physically stored")
            var blocked = false
            do { _ = try OAuthCredentialStore.read() } catch OAuthCredentialStore.Failure.removalPending { blocked = true }
            try check(blocked, "account read refuses pending removal instead of legacy fallback")
            for connectionMode in [LLMConnectionService.Mode.oauth, .key] {
                service.setMode(connectionMode)
                let prepared = await service.prepareAuthorization()
                try check(prepared == nil && !LLMClient.isConfigured(), "pending removal blocks " + connectionMode.rawValue + " route preparation")
            }
            if resumesRemovalCheck {
                if all { try SecureStore.eraseAllChecked() } else if keyOnly { try service.removeAPIKeyChecked() } else { try service.disconnectOAuthChecked() }
                if keyOnly { try service.disconnectOAuthChecked() }
                try check(!SecureStore.erasurePending && !OAuthCredentialStore.removalPending && SecureStore.dataChecked(OAuthCredentialStore.key) == nil && SecureStore.dataChecked("lumen.llm.oauth.token") == nil && SecureStore.dataChecked("lumen.llm.oauth.refresh") == nil, "actual retry clears intent and every account source")
                try cleanupChecked()
                defaults.removeObject(forKey: markerKey)
                try check(defaults.object(forKey: markerKey) == nil, "checked synthetic credential cleanup and marker removal complete")
            }
            status = "Credential removal relaunch checks passed: " + mode + " " + phase
        } catch { status = "Credential removal relaunch checks failed: " + error.localizedDescription }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Report(status: status, mode: mode, phase: phase, pid: getpid(), originalPID: originalPID, checks: checks,
                scope: "Fixed synthetic credentials; actual app terminate/relaunch and checked Keychain retry. Injected deletion or key-removal write failure; no device power-loss or interrupted whole-app-reset proof."))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-removal-" + mode + "-" + phase + ".json"), options: .atomic)
        } catch { return "Credential removal relaunch checks failed: report write failed" }
        return status
    }

    static func runSignInChecks() async -> String {
        precondition(requested)
        struct Observation: Encodable {
            let mode: String
            let loginRequests: Int
            let accountState: String
            let oldAccountPreserved: Bool
            let originalPKCE: Bool
            let sdkCallbackMatches: Bool
            let pendingAttempt: Bool
        }
        var observations: [Observation] = [], tasks: [Task<Void, Never>] = []
        var status = "Provider sign-in checks failed", cleanup = false, invalidClientsRejected = false
        let service = LLMConnectionService.shared
        func callback(_ attempt: LLMConnectionService.SyntheticSignIn) -> URL {
            var c = URLComponents(url: attempt.redirectURI, resolvingAgainstBaseURL: false)!
            c.queryItems = [.init(name: "state", value: attempt.state), .init(name: "code", value: syntheticAuthCode)]
            return c.url!
        }
        func arm(_ attempt: LLMConnectionService.SyntheticSignIn, noRefresh: Bool = false, failure: Bool = false) async throws {
            let items = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
            guard let challenge = items.first(where: { $0.name == "code_challenge" })?.value else { throw Failure("Missing PKCE challenge") }
            _ = try await control("arm-login?challenge=" + challenge + "&refresh=" + (noRefresh ? "0" : "1") + "&failure=" + (failure ? "1" : "0"))
        }
        func start(_ attempt: LLMConnectionService.SyntheticSignIn) -> Task<Void, Never> {
            let url = callback(attempt)
            let task = Task { await service.finishSyntheticSignIn(url, id: attempt.id) }; tasks.append(task); return task
        }
        func waitForLogin(_ count: Int) async throws {
            for _ in 0..<200 {
                if try await audit().loginRequests == count { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw Failure("Held sign-in request did not arrive")
        }
        do {
            guard LLMConnectionService.googleRedirectURI(clientID: "wrong-client") == nil,
                  LLMConnectionService.googleRedirectURI(clientID: "../bad.apps.googleusercontent.com") == nil,
                  LLMConnectionService.googleRedirectURI(clientID: "invalid_scheme.apps.googleusercontent.com") == nil else { throw Failure("Invalid native client accepted") }
            invalidClientsRejected = true
            for mode in ["success", "no-refresh", "cancel", "wrong-state", "duplicate-state", "wrong-scheme", "wrong-path", "stale-attempt", "disconnect-before-callback", "configuration-before-callback", "disconnect-held", "configuration-held", "revert-held", "replacement-held", "write-failure", "error-response"] {
                try cleanupChecked()
                service.googleClientID = syntheticClientID; service.oauthScope = "openid email profile"
                service.oauthEndpoint = "http://127.0.0.1:48733/chat-a"; service.oauthModel = "synthetic-provider-42-a"
                var old: OAuthCredentialStore.Account?
                if ["no-refresh", "write-failure"].contains(mode) {
                    let account = OAuthCredentialStore.Account(clientID: syntheticClientID, scope: service.oauthScope,
                        accessToken: "synthetic-access-old-42", refreshToken: "synthetic-refresh-42", expiresAt: Date().addingTimeInterval(3600))
                    try OAuthCredentialStore.save(account, expectedRevision: ProviderAuthorizationRevision.current); old = account
                }
                let before = try await audit()
                guard var attempt = service.beginSyntheticSignIn(), attempt.pkceMatches,
                      attempt.redirectURI.absoluteString == "com.googleusercontent.apps.123456789-synthetic42:/oauth2redirect/google",
                      let scheme = attempt.redirectURI.scheme else { throw Failure("Native sign-in preparation invalid") }
                let sdkMatches = ASWebAuthenticationSession.Callback.customScheme(scheme).matchesURL(callback(attempt))
                let fields = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
                guard sdkMatches, fields.first(where: { $0.name == "redirect_uri" })?.value == attempt.redirectURI.absoluteString,
                      fields.first(where: { $0.name == "client_id" })?.value == syntheticClientID,
                      fields.first(where: { $0.name == "state" })?.value == attempt.state,
                      fields.first(where: { $0.name == "code_challenge_method" })?.value == "S256" else { throw Failure("Original attempt URL not preserved") }
                if ["cancel", "wrong-state", "duplicate-state", "wrong-scheme", "wrong-path", "disconnect-before-callback", "configuration-before-callback"].contains(mode) {
                    var url = URLComponents(url: callback(attempt), resolvingAgainstBaseURL: false)!
                    switch mode {
                    case "wrong-state": url.queryItems![0].value = "wrong-state"
                    case "duplicate-state": url.queryItems!.append(.init(name: "state", value: attempt.state))
                    case "wrong-scheme": url.scheme = "lumen"
                    case "wrong-path": url.path = "/wrong-path"
                    case "disconnect-before-callback": try service.disconnectOAuthChecked()
                    case "configuration-before-callback": service.oauthModel = "synthetic-provider-42-b"
                    default: break
                    }
                    await service.finishSyntheticSignIn(url.url, failed: mode == "cancel", id: attempt.id)
                } else {
                    if mode == "stale-attempt" {
                        let stale = attempt
                        guard let newer = service.beginSyntheticSignIn() else { throw Failure("Replacement attempt missing") }
                        attempt = newer
                        await service.finishSyntheticSignIn(callback(stale), id: stale.id)
                        guard service.isAuthorizing, try await audit().loginRequests == before.loginRequests else { throw Failure("Stale callback changed new attempt") }
                    }
                    try await arm(attempt, noRefresh: mode == "no-refresh", failure: mode == "error-response")
                    let task = start(attempt)
                    try await waitForLogin((before.loginRequests ?? 0) + 1)
                    var replacement: LLMConnectionService.SyntheticSignIn?
                    switch mode {
                    case "disconnect-held": try service.disconnectOAuthChecked()
                    case "configuration-held": service.oauthModel = "synthetic-provider-42-b"
                    case "revert-held": service.oauthModel = "synthetic-provider-42-b"; service.oauthModel = "synthetic-provider-42-a"
                    case "replacement-held": replacement = service.beginSyntheticSignIn()
                    case "write-failure": SecureStore.injectFailure(.write, key: OAuthCredentialStore.key, status: errSecNotAvailable)
                    default: break
                    }
                    _ = try await control("release-token"); await task.value
                    if mode == "replacement-held" {
                        guard let replacement, service.isAuthorizing, try OAuthCredentialStore.read() == nil else { throw Failure("Old completion overwrote replacement sign-in") }
                        try await arm(replacement); let next = start(replacement)
                        try await waitForLogin((before.loginRequests ?? 0) + 2)
                        _ = try await control("release-token"); await next.value
                    }
                }
                let after = try await audit(), account = try OAuthCredentialStore.read()
                let sent = (after.loginRequests ?? 0) - (before.loginRequests ?? 0)
                let committed = ["success", "no-refresh", "stale-attempt", "replacement-held"].contains(mode)
                let expectedSends = mode == "replacement-held" ? 2 : ["success", "no-refresh", "stale-attempt", "disconnect-held", "configuration-held", "revert-held", "write-failure", "error-response"].contains(mode) ? 1 : 0
                let state = account == nil ? "missing" : account?.accessToken == "synthetic-signin-access-42" ? "new-account" : account == old ? "old-preserved" : "unexpected"
                let identityPreserved = mode != "write-failure" || account == old
                observations.append(.init(mode: mode, loginRequests: sent, accountState: state, oldAccountPreserved: identityPreserved,
                    originalPKCE: attempt.pkceMatches, sdkCallbackMatches: sdkMatches, pendingAttempt: service.isAuthorizing))
                guard sent == expectedSends, after.holdTimeouts == 0, !service.isAuthorizing,
                      identityPreserved, state == (committed ? "new-account" : mode == "write-failure" ? "old-preserved" : "missing") else { throw Failure("Sign-in observation failed: " + mode) }
                if mode == "no-refresh" { guard account?.refreshToken == nil, account?.id != old?.id else { throw Failure("New login inherited old refresh identity") } }
                if mode == "write-failure" { guard !LLMClient.isConfigured(), service.credentialProblem != nil else { throw Failure("Failed login still routed old account") } }
            }
            let final = try await audit()
            guard final.packets.isEmpty, final.tokenRequests == 0, final.loginAudit?.allSatisfy({ $0.pkceMatches && $0.redirectMatches && $0.reservedCodeDecoded }) == true else { throw Failure("Actual sign-in wire audit failed") }
            try cleanupChecked(); cleanup = true
            status = "Provider sign-in checks passed"
        } catch { status = "Provider sign-in checks failed: " + error.localizedDescription }
        _ = try? await control("release-token")
        for task in tasks { task.cancel(); await task.value }
        if !cleanup { try? cleanupChecked() }
        struct Report: Encodable { let status: String; let observations: [Observation]; let cleanupVerified: Bool; let invalidClientsRejected: Bool; let host: Audit?; let scope: String }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Report(status: status, observations: observations, cleanupVerified: cleanup, invalidClientsRejected: invalidClientsRejected, host: try? await audit(),
                scope: "Actual production attempt/URL/callback, SDK callback matching, token transport and Keychain; browser not launched, fixed synthetic client/code only. No live Google/client/App Check or physical-device acceptance."))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-signin-report.json"), options: .atomic)
        } catch { status = "Provider sign-in checks failed: report write failed" }
        return status
    }

    static func runAuthorizationChecks() async -> String {
        precondition(requested)
        struct Observation: Encodable {
            let mode: String
            let accessState: String
            let accountPresent: Bool
            let accountIdentityPreserved: Bool
            let legacySourcesAbsent: Bool
            let authorizationChanged: Bool
            let credentialProblem: Bool
            let outgoingRequests: Int
            let packets: [Packet]
            let replyAccepted: Bool
        }
        var observations: [Observation] = []
        var tasks: [Task<String?, Never>] = []
        var status = "Provider authorization checks failed"
        let service = LLMConnectionService.shared
        func start() -> Task<String?, Never> {
            let task = Task { await LLMClient.coachChat(system: "SYNTHETIC-PROVIDER-CONTEXT-42", history: [], userText: "SYNTHETIC-PROVIDER-QUESTION-42") }
            tasks.append(task); return task
        }
        func physicalAccount() throws -> OAuthCredentialStore.Account? {
            guard let data = try SecureStore.dataChecked(OAuthCredentialStore.key) else { return nil }
            return try JSONDecoder().decode(OAuthCredentialStore.Account.self, from: data)
        }
        func waitForToken(_ expected: Int) async throws {
            for _ in 0..<200 {
                if try await audit().tokenRequests == expected { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw Failure("Token hold did not arrive")
        }
        func waitForSubmission() async throws {
            for _ in 0..<200 {
                if PersonalContextSubmissionFixture.holding { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw Failure("Serialized submission hold did not arrive")
        }
        func observe(_ mode: String, before: Audit, configuration: LLMConnectionService.Configuration,
                     accountID: UUID?, reply: String?, sends: Int, state: String) async throws {
            let after = try await audit(), account = try physicalAccount()
            let access = account?.accessToken
            let actualState = access == nil ? "missing" : access == "synthetic-access-refreshed-42" ? "refreshed-fixture" : access == "synthetic-access-old-42" ? "expired-fixture" : "unexpected"
            let identity = state == "missing" ? account == nil : account?.id == accountID
            let legacyAbsent = try SecureStore.dataChecked("lumen.llm.oauth.token") == nil && SecureStore.dataChecked("lumen.llm.oauth.refresh") == nil && UserDefaults.standard.object(forKey: "lumen.llm.oauth.expires") == nil
            let packets = Array(after.packets.dropFirst(before.packets.count))
            let accepted = reply == "SYNTHETIC-PROVIDER-REPLY-42"
            observations.append(.init(mode: mode, accessState: actualState, accountPresent: account != nil,
                accountIdentityPreserved: identity, legacySourcesAbsent: legacyAbsent,
                authorizationChanged: service.configuration() != configuration, credentialProblem: service.credentialProblem != nil,
                outgoingRequests: packets.count, packets: packets, replyAccepted: accepted))
            guard after.holdTimeouts == 0, !PersonalContextSubmissionFixture.timedOut, packets.count == sends,
                  accepted == (sends > 0), actualState == state, identity, legacyAbsent else { throw Failure("Authorization observation failed: " + mode) }
            let expectedCredential = mode.hasPrefix("key-") ? "api-key-fixture" : "refreshed-fixture"
            guard packets.allSatisfy({ $0.route == "/chat-a" && $0.model == "synthetic-provider-42-a" && $0.credential == expectedCredential && $0.systemCanary }) else { throw Failure("Original route or credential changed: " + mode) }
        }
        do {
            for mode in ["unchanged", "disconnect", "mode", "endpoint", "model", "client", "scope", "revert", "reset", "refresh-failure", "credential-write-failure", "connection-preference", "connection-preset", "connection-api-endpoint", "connection-api-model", "connection-api-key"] {
                try seed()
                let before = try await audit(), configuration = service.configuration()
                _ = try await control(mode == "refresh-failure" ? "arm-token-failure" : "arm-token")
                let task = start()
                try await waitForToken(before.tokenRequests + 1)
                let original = try physicalAccount()
                guard let original else { throw Failure("Actual legacy migration did not precede refresh") }
                switch mode {
                case "disconnect": try service.disconnectOAuthChecked()
                case "mode": service.setMode(.onDevice)
                case "endpoint": service.oauthEndpoint = "http://127.0.0.1:48733/chat-b"
                case "model": service.oauthModel = "synthetic-provider-42-b"
                case "client": service.googleClientID = "synthetic-client-replaced-42"
                case "scope": service.oauthScope = "synthetic-scope-replaced-42"
                case "revert": service.oauthModel = "synthetic-provider-42-b"; service.oauthModel = "synthetic-provider-42-a"
                case "reset": LocalStore.eraseAll(); try SecureStore.eraseAllChecked()
                case "credential-write-failure": SecureStore.injectFailure(.write, key: OAuthCredentialStore.key, status: errSecNotAvailable)
                case let name where name.hasPrefix("connection-"):
                    var draft = try service.connectionDraft()
                    switch name {
                    case "connection-preference": draft.preferExternal.toggle()
                    case "connection-preset": draft.preset = draft.preset == "custom" ? "openAI" : "custom"
                    case "connection-api-endpoint": draft.endpoint = "http://127.0.0.1:48733/chat-b"
                    case "connection-api-model": draft.model = "synthetic-unused-model-42"
                    default: draft.apiKey = "synthetic-key-42-a"
                    }
                    try service.saveConnectionChecked(draft, expected: configuration)
                default: break
                }
                _ = try await control("release-token")
                let reply = await task.value
                try await observe(mode, before: before, configuration: configuration, accountID: original.id, reply: reply,
                                  sends: mode == "unchanged" ? 1 : 0,
                                  state: mode == "unchanged" ? "refreshed-fixture" : ["disconnect", "reset"].contains(mode) ? "missing" : "expired-fixture")
            }
            try seed()
            let before = try await audit(), configuration = service.configuration()
            _ = try await control("arm-token")
            let first = start(); try await waitForToken(before.tokenRequests + 1)
            let original = try physicalAccount()
            let second = start(); try await Task.sleep(for: .milliseconds(100))
            guard try await audit().tokenRequests == before.tokenRequests + 1 else { throw Failure("Same-account refresh was not coalesced") }
            _ = try await control("release-token")
            let firstReply = await first.value, secondReply = await second.value
            guard firstReply == secondReply, secondReply == "SYNTHETIC-PROVIDER-REPLY-42" else { throw Failure("Coalesced callers lost independent replies") }
            try await observe("coalesced", before: before, configuration: configuration, accountID: original?.id, reply: firstReply, sends: 2, state: "refreshed-fixture")

            for mode in ["submission-unchanged", "submission-disconnect", "submission-model", "submission-revert", "submission-read-failure", "key-unchanged", "key-replace", "key-revert", "key-mode", "key-write-failure"] {
                try seed()
                let keyMode = mode.hasPrefix("key-")
                if keyMode {
                    try service.disconnectOAuthChecked()
                    service.endpoint = "http://127.0.0.1:48733/chat-a"; service.model = "synthetic-provider-42-a"
                    try service.saveAPIKeyChecked("synthetic-key-42-a"); service.setMode(.key)
                } else {
                    let account = OAuthCredentialStore.Account(clientID: service.googleClientID, scope: service.oauthScope,
                        accessToken: "synthetic-access-refreshed-42", refreshToken: nil, expiresAt: Date().addingTimeInterval(3600))
                    try OAuthCredentialStore.save(account, expectedRevision: ProviderAuthorizationRevision.current)
                }
                let before = try await audit(), configuration = service.configuration()
                PersonalContextSubmissionFixture.arm()
                let task = start(); try await waitForSubmission()
                let original = try physicalAccount()
                switch mode {
                case "submission-disconnect": try service.disconnectOAuthChecked()
                case "submission-model": service.oauthModel = "synthetic-provider-42-b"
                case "submission-revert": service.oauthModel = "synthetic-provider-42-b"; service.oauthModel = "synthetic-provider-42-a"
                case "submission-read-failure": SecureStore.injectFailure(.read, key: OAuthCredentialStore.key, status: errSecInteractionNotAllowed)
                case "key-replace": try service.saveAPIKeyChecked("synthetic-key-42-b")
                case "key-revert": try service.saveAPIKeyChecked("synthetic-key-42-b"); try service.saveAPIKeyChecked("synthetic-key-42-a")
                case "key-mode": service.setMode(.onDevice)
                case "key-write-failure":
                    SecureStore.injectFailure(.write, key: ProviderConnectionStore.key, status: errSecNotAvailable)
                    var rejected = false
                    do { try service.saveAPIKeyChecked("synthetic-key-42-b") }
                    catch let error as SecureStore.Failure { rejected = error.operation == .write }
                    guard rejected, try ProviderConnectionStore.read()?.apiKey == "synthetic-key-42-a" else { throw Failure("Failed key replacement lost original value") }
                default: break
                }
                PersonalContextSubmissionFixture.release()
                let reply = await task.value
                guard try await audit().tokenRequests == before.tokenRequests else { throw Failure("Cached/key case unexpectedly refreshed") }
                try await observe(mode, before: before, configuration: configuration, accountID: original?.id, reply: reply,
                                  sends: ["submission-unchanged", "key-unchanged"].contains(mode) ? 1 : 0,
                                  state: keyMode || mode == "submission-disconnect" ? "missing" : "refreshed-fixture")
            }
            status = "Provider authorization checks passed"
        } catch { status = "Provider authorization checks failed: " + error.localizedDescription }
        PersonalContextSubmissionFixture.release()
        _ = try? await control("release-token")
        for task in tasks { task.cancel(); _ = await task.value }
        var cleanup = false
        do { try cleanupChecked(); cleanup = true }
        catch { status = "Provider authorization checks failed: cleanup failed" }
        struct Report: Encodable { let status: String; let observations: [Observation]; let cleanupVerified: Bool; let host: Audit? }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Report(status: status, observations: observations, cleanupVerified: cleanup, host: try? await audit()))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-authorization-report.json"), options: .atomic)
        } catch { status = "Provider authorization checks failed: report write failed" }
        return status
    }

    static func runStorageChecks() -> String {
        precondition(requested)
        struct Check: Encodable { let name: String; let passed: Bool }
        var checks: [Check] = []
        func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
            let passed = try value(); checks.append(.init(name: name, passed: passed))
            if !passed { throw Failure(name) }
        }
        let first = "synthetic.storage.42.first", legacy = "synthetic.storage.42.legacy"
        let other = "synthetic.storage.42.other", corrupt = "synthetic.storage.42.corrupt"
        let keys = [first, legacy, other, corrupt]
        defer { for key in keys { try? SecureStore.removeChecked(key) } }
        var status = "Credential storage checks failed"
        do {
            for key in keys { try SecureStore.removeChecked(key) }
            try check(SecureStore.stringChecked(first) == nil, "actual missing Keychain item is absent")
            try SecureStore.setChecked("SYNTHETIC-STORAGE-42-A", for: first)
            try SecureStore.setChecked("SYNTHETIC-STORAGE-42-OTHER", for: other)
            try check(SecureStore.stringChecked(first) == "SYNTHETIC-STORAGE-42-A", "actual Keychain add persists exact synthetic value")
            try SecureStore.setChecked("SYNTHETIC-STORAGE-42-B 🪴", for: first)
            try check(SecureStore.stringChecked(first) == "SYNTHETIC-STORAGE-42-B 🪴", "actual replacement updates existing item with complete Unicode")
            SecureStore.injectFailure(.write, key: first, status: errSecNotAvailable)
            var typedWrite = false
            do { try SecureStore.setChecked("SYNTHETIC-STORAGE-42-REJECTED", for: first) }
            catch let error as SecureStore.Failure { typedWrite = error.operation == .write && error.status == errSecNotAvailable }
            try check(typedWrite && SecureStore.stringChecked(first) == "SYNTHETIC-STORAGE-42-B 🪴", "explicit injected write status preserves actual prior Keychain value")
            UserDefaults.standard.set("SYNTHETIC-STORAGE-42-LEGACY", forKey: first)
            SecureStore.injectFailure(.read, key: first, status: errSecInteractionNotAllowed)
            var typedRead = false
            do { _ = try SecureStore.stringChecked(first) }
            catch let error as SecureStore.Failure { typedRead = error.operation == .read && error.status == errSecInteractionNotAllowed }
            try check(typedRead && UserDefaults.standard.string(forKey: first) == "SYNTHETIC-STORAGE-42-LEGACY" && SecureStore.stringChecked(first) == "SYNTHETIC-STORAGE-42-B 🪴", "explicit unavailable-read status never substitutes or migrates legacy defaults")
            SecureStore.injectFailure(.delete, key: first, status: errSecAuthFailed)
            var typedDelete = false
            do { try SecureStore.removeChecked(first) }
            catch let error as SecureStore.Failure { typedDelete = error.operation == .delete && error.status == errSecAuthFailed }
            try check(typedDelete && SecureStore.stringChecked(first) == "SYNTHETIC-STORAGE-42-B 🪴" && UserDefaults.standard.string(forKey: first) != nil, "explicit injected delete failure retains actual credential and legacy source for retry")
            try SecureStore.removeChecked(first)
            try check(SecureStore.stringChecked(first) == nil && UserDefaults.standard.object(forKey: first) == nil, "actual delete removes credential and its legacy rehydration source")
            try SecureStore.removeChecked(first)
            try check(SecureStore.stringChecked(other) == "SYNTHETIC-STORAGE-42-OTHER", "idempotent scoped deletion preserves another actual credential")
            UserDefaults.standard.set("SYNTHETIC-STORAGE-42-MIGRATION", forKey: legacy)
            SecureStore.injectFailure(.write, key: legacy, status: errSecNotAvailable)
            var migrationFailed = false
            do { _ = try SecureStore.stringChecked(legacy) }
            catch let error as SecureStore.Failure { migrationFailed = error.operation == .write && error.status == errSecNotAvailable }
            try check(migrationFailed && SecureStore.dataChecked(legacy) == nil && UserDefaults.standard.string(forKey: legacy) == "SYNTHETIC-STORAGE-42-MIGRATION", "failed checked migration keeps its only legacy copy and no phantom Keychain value")
            try check(SecureStore.stringChecked(legacy) == "SYNTHETIC-STORAGE-42-MIGRATION" && UserDefaults.standard.object(forKey: legacy) == nil, "successful migration commits actual Keychain data before removing legacy source")
            try SecureStore.setDataChecked(Data([0xff, 0xfe, 0x00]), for: corrupt)
            UserDefaults.standard.set("SYNTHETIC-STORAGE-42-STALE", forKey: corrupt)
            var corruptRejected = false
            do { _ = try SecureStore.stringChecked(corrupt) }
            catch let error as SecureStore.Failure { corruptRejected = error.operation == .read && error.status == errSecDecode }
            try check(corruptRejected && SecureStore.dataChecked(corrupt) == Data([0xff, 0xfe, 0x00]) && UserDefaults.standard.object(forKey: corrupt) != nil, "actual malformed UTF-8 yields typed decode failure without replacing it from stale defaults")
            try SecureStore.setChecked(nil, for: legacy)
            try check(SecureStore.stringChecked(legacy) == nil, "checked nil assignment performs actual scoped removal")
            for key in keys { try SecureStore.removeChecked(key) }
            try check(keys.allSatisfy { try SecureStore.dataChecked($0) == nil && UserDefaults.standard.object(forKey: $0) == nil }, "all dedicated synthetic credential and legacy fixtures are actually removed")
            if SecureStore.erasurePending { try SecureStore.eraseAllChecked() }
            try OAuthCredentialStore.disconnect()
            let account = OAuthCredentialStore.Account(clientID: "synthetic-client-42", scope: "synthetic-scope-42",
                accessToken: "SYNTHETIC-ACCOUNT-42-A", refreshToken: "SYNTHETIC-REFRESH-42-A", expiresAt: Date(timeIntervalSince1970: 2_000_000_000))
            let generation = ProviderAuthorizationRevision.current
            try OAuthCredentialStore.save(account, expectedRevision: generation)
            try check(OAuthCredentialStore.read() == account, "one actual Keychain record round-trips complete account identity, both tokens and expiry")
            let oldAccountData = try SecureStore.dataChecked(OAuthCredentialStore.key)
            var replacement = account; replacement.accessToken = "SYNTHETIC-ACCOUNT-42-B"; replacement.refreshToken = "SYNTHETIC-REFRESH-42-B"; replacement.expiresAt = account.expiresAt.addingTimeInterval(3600)
            SecureStore.injectFailure(.write, key: OAuthCredentialStore.key, status: errSecNotAvailable)
            var atomicWriteRejected = false
            do { try OAuthCredentialStore.save(replacement, expectedRevision: generation) }
            catch let error as SecureStore.Failure { atomicWriteRejected = error.operation == .write && error.status == errSecNotAvailable }
            try check(atomicWriteRejected && SecureStore.dataChecked(OAuthCredentialStore.key) == oldAccountData, "explicit injected account replacement failure preserves all actual prior credential bytes together")
            try check(OAuthCredentialStore.load(clientID: "different-client-42", scope: account.scope, expectedRevision: generation) == nil && OAuthCredentialStore.load(clientID: account.clientID, scope: "different-scope-42", expectedRevision: generation) == nil && OAuthCredentialStore.read() == account, "stored account is never rebound to a replacement client or scope")
            ProviderAuthorizationRevision.invalidate()
            var staleWriteRejected = false
            do { try OAuthCredentialStore.save(replacement, expectedRevision: generation) }
            catch ProviderAuthorizationRevision.Changed.configuration { staleWriteRejected = true }
            try check(staleWriteRejected && SecureStore.dataChecked(OAuthCredentialStore.key) == oldAccountData, "superseded generation rejects actual credential commit without changing the saved record")
            SecureStore.injectFailure(.delete, key: OAuthCredentialStore.key, status: errSecAuthFailed)
            var removalFailed = false
            do { try OAuthCredentialStore.disconnect() }
            catch let error as SecureStore.Failure { removalFailed = error.operation == .delete && error.status == errSecAuthFailed }
            var pendingBlocked = false
            do { _ = try OAuthCredentialStore.read() }
            catch OAuthCredentialStore.Failure.removalPending { pendingBlocked = true }
            try check(removalFailed && pendingBlocked && OAuthCredentialStore.removalPending && SecureStore.dataChecked(OAuthCredentialStore.key) == oldAccountData, "failed disconnect persists removal intent and blocks credential loading while actual stored bytes remain")
            try OAuthCredentialStore.disconnect()
            try check(OAuthCredentialStore.read() == nil && !OAuthCredentialStore.removalPending, "actual disconnect retry removes the record and clears pending intent")
            UserDefaults.standard.set("SYNTHETIC-LEGACY-ACCOUNT-42", forKey: "lumen.llm.oauth.token")
            UserDefaults.standard.set(account.expiresAt, forKey: "lumen.llm.oauth.expires")
            try SecureStore.setChecked("SYNTHETIC-LEGACY-REFRESH-42", for: "lumen.llm.oauth.refresh")
            let migrationGeneration = ProviderAuthorizationRevision.current
            SecureStore.injectFailure(.write, key: OAuthCredentialStore.key, status: errSecNotAvailable)
            var accountMigrationFailed = false
            do { _ = try OAuthCredentialStore.load(clientID: account.clientID, scope: account.scope, expectedRevision: migrationGeneration) }
            catch let error as SecureStore.Failure { accountMigrationFailed = error.operation == .write }
            try check(accountMigrationFailed && SecureStore.dataChecked(OAuthCredentialStore.key) == nil && SecureStore.dataChecked("lumen.llm.oauth.token") == nil && UserDefaults.standard.string(forKey: "lumen.llm.oauth.token") == "SYNTHETIC-LEGACY-ACCOUNT-42" && SecureStore.stringChecked("lumen.llm.oauth.refresh") == "SYNTHETIC-LEGACY-REFRESH-42", "failed atomic account migration preserves both original defaults/Keychain sources without creating a legacy copy")
            SecureStore.injectFailure(.delete, key: "lumen.llm.oauth.refresh", status: errSecAuthFailed)
            var cleanupFailed = false
            do { _ = try OAuthCredentialStore.load(clientID: account.clientID, scope: account.scope, expectedRevision: migrationGeneration) }
            catch let error as SecureStore.Failure { cleanupFailed = error.operation == .delete }
            let migrated = try OAuthCredentialStore.read()
            try check(cleanupFailed && migrated?.migratedLegacy == true && migrated?.accessToken == "SYNTHETIC-LEGACY-ACCOUNT-42" && migrated?.refreshToken == "SYNTHETIC-LEGACY-REFRESH-42" && migrated?.expiresAt == account.expiresAt && SecureStore.stringChecked("lumen.llm.oauth.refresh") != nil, "failed legacy cleanup returns no account while complete migrated credentials remain committed for retry")
            let retried = try OAuthCredentialStore.load(clientID: account.clientID, scope: account.scope, expectedRevision: migrationGeneration)
            try check(retried == migrated && SecureStore.dataChecked("lumen.llm.oauth.token") == nil && SecureStore.dataChecked("lumen.llm.oauth.refresh") == nil && UserDefaults.standard.object(forKey: "lumen.llm.oauth.expires") == nil, "migration cleanup retry retains the identical account and removes every redundant old source")
            try SecureStore.setDataChecked(Data("{\"version\":99}".utf8), for: OAuthCredentialStore.key)
            UserDefaults.standard.set("SYNTHETIC-STALE-LEGACY-42", forKey: "lumen.llm.oauth.token")
            var unknownRejected = false
            do { _ = try OAuthCredentialStore.load(clientID: account.clientID, scope: account.scope, expectedRevision: migrationGeneration) }
            catch OAuthCredentialStore.Failure.corrupt { unknownRejected = true }
            try check(unknownRejected && UserDefaults.standard.string(forKey: "lumen.llm.oauth.token") == "SYNTHETIC-STALE-LEGACY-42", "unknown or malformed present account cannot fall back to an old legacy account")
            try OAuthCredentialStore.disconnect()
            try check(OAuthCredentialStore.read() == nil && UserDefaults.standard.object(forKey: "lumen.llm.oauth.token") == nil, "disconnect also removes malformed account and legacy fallback source")
            try OAuthCredentialStore.save(account, expectedRevision: ProviderAuthorizationRevision.current)
            SecureStore.injectFailure(.delete, key: "synthetic.storage.42.service", status: errSecAuthFailed)
            var erasureFailed = false
            do { try SecureStore.eraseAllChecked() }
            catch let error as SecureStore.Failure { erasureFailed = error.operation == .delete && error.status == errSecAuthFailed }
            var erasureBlocked = false
            do { _ = try OAuthCredentialStore.read() }
            catch OAuthCredentialStore.Failure.removalPending { erasureBlocked = true }
            try check(erasureFailed && erasureBlocked && SecureStore.erasurePending && SecureStore.dataChecked(OAuthCredentialStore.key) != nil, "failed actual-service erasure boundary persists blocked intent without claiming the explicitly injected failure erased credentials")
            try SecureStore.eraseAllChecked()
            try check(!SecureStore.erasurePending && !OAuthCredentialStore.removalPending && OAuthCredentialStore.read() == nil, "actual service erasure retry clears credentials and both removal intents")
            status = "Credential storage checks passed"
        } catch { status = "Credential storage checks failed: " + error.localizedDescription }
        struct Report: Encodable { let status: String; let checks: [Check]; let scope: String }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Report(status: status, checks: checks, scope: "Actual signed-simulator Keychain values, atomic credential records, legacy sources and persistent intent flags; failure statuses explicitly injected at the checked boundary. No actual process relaunch, physical-device protected-data, full provider lifecycle or live-account proof."))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-storage-report.json"), options: .atomic)
        } catch { status = "Credential storage checks failed: report write failed" }
        return status
    }
}
#endif
