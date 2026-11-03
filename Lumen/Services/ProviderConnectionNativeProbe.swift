#if DEBUG && targetEnvironment(simulator)
import Foundation
import Security
import SwiftUI
import CryptoKit

extension ProviderAuthorizationNativeProbe {
    static func runTokenTransportChecks() async -> String {
        precondition(requested && ProcessInfo.processInfo.arguments.contains("-provider-token-transport-checks"))
        struct Observation: Encodable {
            let flow: String; let mode: String; let accepted: Bool; let accountBytesPreserved: Bool
            let accountIdentityPreserved: Bool; let tokenExchanges: Int; let chatPackets: Int
            let accountBeforeSHA256: String; let accountAfterSHA256: String
        }
        struct Report: Encodable { let status: String; let observations: [Observation]; let host: Audit; let cleanupVerified: Bool; let scope: String }
        let service = LLMConnectionService.shared
        let cases = ["valid", "mixed-case-bearer", "malformed", "duplicate", "escaped-duplicate", "nested-duplicate", "error", "null-error", "http-error", "oversized-header", "oversized-chunked", "redirect", "wrong-type", "wrong-token-type", "zero-expiry", "invalid-token", "invalid-utf8", "non-object", "cancelled", "cancel-before-task"]
        var observations: [Observation] = [], active: [Task<String?, Never>] = [], cleaned = false
        var status = "Token transport checks failed"
        func digest(_ data: Data?) -> String { data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing" }
        func account() throws -> OAuthCredentialStore.Account? {
            try SecureStore.dataChecked(OAuthCredentialStore.key).map { try JSONDecoder().decode(OAuthCredentialStore.Account.self, from: $0) }
        }
        func waitFor(_ condition: () async throws -> Bool) async throws {
            for _ in 0..<400 { if try await condition() { return }; try await Task.sleep(for: .milliseconds(25)) }
            throw Failure("Synthetic token boundary did not arrive")
        }
        func seedAccount(_ flow: String) throws -> OAuthCredentialStore.Account {
            try cleanupChecked()
            service.googleClientID = flow == "login" ? syntheticClientID : "synthetic-client-42"
            service.oauthScope = flow == "login" ? "openid email profile" : "synthetic-scope-42"
            service.oauthEndpoint = "http://127.0.0.1:48733/chat-a"; service.oauthModel = "synthetic-provider-42-a"; service.setMode(.oauth)
            let value = OAuthCredentialStore.Account(clientID: service.googleClientID, scope: service.oauthScope, accessToken: "synthetic-access-old-42", refreshToken: "synthetic-refresh-42", expiresAt: Date().addingTimeInterval(flow == "login" ? 3600 : -120))
            try OAuthCredentialStore.save(value, expectedRevision: ProviderAuthorizationRevision.current)
            return value
        }
        func startChat() -> Task<String?, Never> {
            let task = Task { await LLMClient.coachChat(system: "SYNTHETIC-PROVIDER-CONTEXT-42", history: [], userText: "SYNTHETIC-PROVIDER-QUESTION-42") }
            active.append(task); return task
        }
        do {
            for flow in ["refresh", "login"] {
                for mode in cases {
                    let old = try seedAccount(flow), beforeBytes = try SecureStore.dataChecked(OAuthCredentialStore.key)
                    _ = try await control("arm-response?case=" + (mode == "cancel-before-task" ? "valid" : mode))
                    let before = try await audit(), count = before.tokenTransportAudit?.count ?? 0
                    let positive = ["valid", "mixed-case-bearer"].contains(mode)
                    let task: Task<String?, Never>
                    if flow == "login" {
                        guard let attempt = service.beginSyntheticSignIn(), attempt.pkceMatches,
                              let challenge = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code_challenge" })?.value else { throw Failure("Synthetic sign-in preparation failed") }
                        _ = try await control("arm-login?challenge=" + challenge)
                        var callback = URLComponents(url: attempt.redirectURI, resolvingAgainstBaseURL: false)!
                        callback.queryItems = [.init(name: "state", value: attempt.state), .init(name: "code", value: syntheticAuthCode)]
                        let callbackURL = callback.url!
                        task = Task {
                            await service.finishSyntheticSignIn(callbackURL, id: attempt.id)
                            guard let updated = try? account(), updated.id != old.id, updated.accessToken == "synthetic-access-refreshed-42" else { return nil }
                            return "synthetic-signin-replaced"
                        }
                        active.append(task)
                    } else { task = startChat() }
                    if mode == "cancel-before-task" { task.cancel() }
                    if mode == "cancelled" {
                        try await waitFor { let a = try await audit(); return a.tokenTransportAudit?.count == count + 1 && a.tokenTransportAudit?.last?.streamStarted == true }
                        if flow == "login" { task.cancel() } else { service.setMode(.onDevice) }
                        _ = try await control("release-response")
                    }
                    let result = await task.value
                    if flow == "login", positive {
                        guard result == "synthetic-signin-replaced", await startChat().value == "SYNTHETIC-PROVIDER-REPLY-42" else { throw Failure("Valid sign-in control did not authorize its chat") }
                    }
                    try await waitFor { let a = try await audit(); return a.tokenTransportResponses == a.tokenTransportAudit?.count }
                    let after = try await audit(), afterBytes = try SecureStore.dataChecked(OAuthCredentialStore.key), updated = try account()
                    let preserved = beforeBytes == afterBytes, identity = updated?.id == old.id
                    let exchanges = (after.tokenTransportAudit?.count ?? 0) - count, chats = after.packets.count - before.packets.count
                    let accepted = flow == "login" ? result == "synthetic-signin-replaced" : result == "SYNTHETIC-PROVIDER-REPLY-42"
                    observations.append(.init(flow: flow, mode: mode, accepted: accepted, accountBytesPreserved: preserved, accountIdentityPreserved: identity, tokenExchanges: exchanges, chatPackets: chats, accountBeforeSHA256: digest(beforeBytes), accountAfterSHA256: digest(afterBytes)))
                    guard accepted == positive, preserved == !positive, identity == (flow == "refresh" || !positive), exchanges == (mode == "cancel-before-task" ? 0 : 1), chats == (positive ? 1 : 0), after.holdTimeouts == 0, after.tokenRedirectHits == 0 else { throw Failure("Token response observation failed: " + flow + "/" + mode) }
                }
            }
            // One cancelled waiter must not cancel another caller's shared refresh.
            let old = try seedAccount("refresh"), bytes = try SecureStore.dataChecked(OAuthCredentialStore.key)
            _ = try await control("arm-response?case=cancelled")
            let before = try await audit(), count = before.tokenTransportAudit?.count ?? 0
            let cancelled = startChat(), retained = startChat()
            try await waitFor { let a = try await audit(); return a.tokenTransportAudit?.count == count + 1 && a.tokenTransportAudit?.last?.streamStarted == true }
            cancelled.cancel(); _ = try await control("release-response")
            let cancelledResult = await cancelled.value, retainedResult = await retained.value
            try await waitFor { let a = try await audit(); return a.tokenTransportResponses == a.tokenTransportAudit?.count }
            let after = try await audit(), updatedBytes = try SecureStore.dataChecked(OAuthCredentialStore.key), updated = try account()
            guard cancelledResult == nil, retainedResult == "SYNTHETIC-PROVIDER-REPLY-42", updated?.id == old.id, updatedBytes != bytes,
                  (after.tokenTransportAudit?.count ?? 0) == count + 1, after.packets.count == before.packets.count + 1 else { throw Failure("Cancelled waiter disrupted shared refresh") }
            observations.append(.init(flow: "refresh", mode: "cancelled-shared-waiter", accepted: true, accountBytesPreserved: false, accountIdentityPreserved: true, tokenExchanges: 1, chatPackets: 1, accountBeforeSHA256: digest(bytes), accountAfterSHA256: digest(updatedBytes)))
            for mode in ["empty-request", "oversized-request", "withdrawn-before-submit", "cancelled-before-submit"] {
                _ = try seedAccount("refresh")
                let bytes = try SecureStore.dataChecked(OAuthCredentialStore.key), before = try await audit()
                var request = URLRequest(url: URL(string: "http://127.0.0.1:48733/adversarial-refresh")!); request.httpMethod = "POST"
                request.httpBody = mode == "empty-request" ? Data() : mode == "oversized-request" ? Data(repeating: 65, count: 256001) : Data("client_id=synthetic-client-42&refresh_token=synthetic-refresh-42&grant_type=refresh_token".utf8)
                let fixedRequest = request
                let task = Task { () -> Bool in
                    do { _ = try await OAuthTokenTransport.data(for: fixedRequest, authorizing: { mode != "withdrawn-before-submit" }); return false }
                    catch { return true }
                }
                if mode == "cancelled-before-submit" { task.cancel() }
                guard await task.value else { throw Failure("Invalid token submission accepted: " + mode) }
                let after = try await audit(), afterBytes = try SecureStore.dataChecked(OAuthCredentialStore.key)
                guard bytes == afterBytes, before.tokenTransportAudit?.count == after.tokenTransportAudit?.count, before.packets.count == after.packets.count else { throw Failure("Rejected token submission escaped: " + mode) }
                observations.append(.init(flow: "transport", mode: mode, accepted: false, accountBytesPreserved: true, accountIdentityPreserved: true, tokenExchanges: 0, chatPackets: 0, accountBeforeSHA256: digest(bytes), accountAfterSHA256: digest(afterBytes)))
            }
            let host = try await audit()
            guard host.tokenRedirectHits == 0, host.holdTimeouts == 0,
                  host.tokenTransportAudit?.allSatisfy({ $0.formMatches && $0.cookieAbsent && ($0.requestKind != "login" || $0.pkceMatches == true) }) == true else { throw Failure("Token form, cookie, redirect or PKCE boundary failed") }
            try cleanupChecked(); cleaned = true; status = "Token transport checks passed"
        } catch {
            active.forEach { $0.cancel() }; _ = try? await control("release-response")
            status = "Token transport checks failed: " + error.localizedDescription
        }
        do {
            try JSONEncoder().encode(Report(status: status, observations: observations, host: try await audit(), cleanupVerified: cleaned,
                scope: "Synthetic production OAuth refresh/sign-in and bounded ephemeral URLSession. Invalid responses preserve exact account bytes; valid controls send actual chat. Cancellation distinguishes sign-in task, refresh withdrawal and one shared waiter. No live provider, browser or physical-device acceptance."))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-token-transport-report.json"), options: .atomic)
        } catch { return "Token transport checks failed: report write failed" }
        return status
    }
}

/// Fixed synthetic restart controls for the production Settings reset service.
@MainActor enum AccountResetNativeFixture {
    static var requested: Bool {
        ProviderAuthorizationNativeProbe.requested && ProcessInfo.processInfo.arguments.contains("-provider-reset-checks") && mode != nil
    }
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        let modes = ["failure", "after-secrets"].filter { args.contains("-provider-reset-" + $0) }
        return modes.count == 1 ? modes[0] : nil
    }
    static let receiptURL = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-reset-receipt.json")
    static var hasReceipt: Bool { FileManager.default.fileExists(atPath: receiptURL.path) }
    private static var armed = false
    struct Interruption: Error { }
    static func arm() { precondition(requested && mode == "after-secrets"); armed = true }
    static func interruptAfterCredentialsIfArmed() throws {
        guard armed else { return }
        precondition(requested); armed = false; throw Interruption()
    }
}

extension ProviderAuthorizationNativeProbe {
    static func runAccountResetChecks() async -> String {
        precondition(AccountResetNativeFixture.requested)
        struct Receipt: Codable { let mode: String; let pid: Int32; let connectionSHA256: String; let accountSHA256: String; let profileSHA256: String; let profileContentSHA256: String; let localSHA256: String }
        struct Report: Encodable { let status: String; let mode: String; let phase: String; let pid: Int32; let originalPID: Int32; let checks: [String]; let scope: String }
        let mode = AccountResetNativeFixture.mode!, resume = ProcessInfo.processInfo.arguments.contains("-provider-reset-resume")
        let phase = resume ? "resume" : "prepare", defaults = UserDefaults.standard
        let keepKey = "synthetic.storage.42.reset-keep", localName = "synthetic-reset-42"
        var checks: [String] = [], originalPID = getpid(), status = "Account reset checks failed"
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { throw Failure(name) }; checks.append(name)
        }
        func digest(_ bytes: Data?) -> String { bytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing" }
        func file(_ name: String) -> Data? { try? Data(contentsOf: LocalStore.directory.appendingPathComponent(name + ".json")) }
        func profileContentDigest() throws -> String {
            guard let bytes = file("profile") else { throw Failure("Profile file missing") }
            return digest(try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: bytes), options: [.sortedKeys]))
        }
        do {
            let receipt: Receipt
            if resume {
                receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: AccountResetNativeFixture.receiptURL))
                originalPID = receipt.pid
                try check(receipt.mode == mode && getpid() != receipt.pid, "new process reads original receipt without reseeding")
            } else {
                try SecureStore.eraseAllChecked()
                var record = ProviderConnectionStore.Record(); record.mode = "key"; record.preset = "custom"
                record.endpoint = "http://127.0.0.1:48733/caller-chat"; record.model = "synthetic-provider-42-a"; record.apiKey = "synthetic-key-42-a"; record.preferExternal = true
                record.clientID = syntheticClientID; record.oauthEndpoint = record.endpoint; record.oauthModel = record.model
                try ProviderConnectionStore.save(record, expectedRevision: ProviderAuthorizationRevision.current)
                try OAuthCredentialStore.save(.init(clientID: record.clientID, scope: record.scope, accessToken: "synthetic-access-old-42", refreshToken: "synthetic-refresh-42", expiresAt: Date().addingTimeInterval(3600)), expectedRevision: ProviderAuthorizationRevision.current)
                for key in ["lumen.llm.key", "strava.clientID", "strava.clientSecret", "strava.token", "strava.refresh"] { try SecureStore.setChecked("synthetic-key-42-a", for: key) }
                defaults.set("synthetic-key-42-a", forKey: "lumen.llm.key")
                defaults.set(true, forKey: keepKey); AppGroup.defaults.set(true, forKey: keepKey)
                var profile = UserProfile.default; profile.name = "Synthetic Reset42"
                SleepStore.shared.profile = profile; SleepStore.shared.persist()
                try LocalStore.saveChecked(["SYNTHETIC-RESET-42"], as: localName)
                receipt = Receipt(mode: mode, pid: getpid(), connectionSHA256: digest(try SecureStore.dataChecked(ProviderConnectionStore.key)), accountSHA256: digest(try SecureStore.dataChecked(OAuthCredentialStore.key)), profileSHA256: digest(file("profile")), profileContentSHA256: try profileContentDigest(), localSHA256: digest(file(localName)))
                try JSONEncoder().encode(receipt).write(to: AccountResetNativeFixture.receiptURL, options: .atomic)
                if mode == "failure" { SecureStore.injectFailure(.delete, key: "synthetic.storage.42.service", status: errSecInteractionNotAllowed) }
                else { AccountResetNativeFixture.arm() }
                var expectedFailure = false
                do { try AccountReset.eraseAll(health: .shared, sleep: .shared) }
                catch let error as SecureStore.Failure { expectedFailure = mode == "failure" && error.operation == .delete && error.status == errSecInteractionNotAllowed }
                catch is AccountResetNativeFixture.Interruption { expectedFailure = mode == "after-secrets" }
                try check(expectedFailure, "production reset stops at the declared failed or interrupted credential phase")
            }
            try check(defaults.bool(forKey: keepKey) && AppGroup.defaults.bool(forKey: keepKey), "local and shared defaults remain before local erasure")
            if !resume { try check(digest(file("profile")) == receipt.profileSHA256, "failed or interrupted reset retains exact profile file bytes before restart") }
            try check(profileContentDigest() == receipt.profileContentSHA256 && digest(file(localName)) == receipt.localSHA256, "complete original profile contents and exact local fixture bytes remain")
            if mode == "failure" {
                try check(SecureStore.erasurePending, "failed secret deletion retains durable blocking intent")
                try check(digest(SecureStore.dataChecked(ProviderConnectionStore.key)) == receipt.connectionSHA256 && digest(SecureStore.dataChecked(OAuthCredentialStore.key)) == receipt.accountSHA256, "failed secret deletion preserves exact whole connection and account bytes")
            } else {
                try check(!SecureStore.erasurePending, "completed credential phase clears its own pending marker")
                try check(SecureStore.dataChecked(ProviderConnectionStore.key) == nil && SecureStore.dataChecked(OAuthCredentialStore.key) == nil && defaults.object(forKey: "lumen.llm.key") == nil, "interruption after secret deletion cannot rehydrate connection account or legacy key")
            }
            try check(!LLMClient.isConfigured(), "interrupted reset has no configured external route")
            if resume {
                try AccountReset.eraseAll(health: .shared, sleep: .shared)
                try check(file(localName) == nil && !defaults.bool(forKey: keepKey) && !AppGroup.defaults.bool(forKey: keepKey), "actual reset retry removes local fixture and both defaults canaries")
                try check(SleepStore.shared.profile.name != "Synthetic Reset42" && !SleepStore.shared.profile.onboardingDone, "completed reset returns to fresh profile and onboarding")
                for key in [ProviderConnectionStore.key, OAuthCredentialStore.key, "lumen.llm.key", "strava.clientID", "strava.clientSecret", "strava.token", "strava.refresh"] {
                    try check(SecureStore.dataChecked(key) == nil && defaults.object(forKey: key) == nil, "checked credential cleanup: " + key)
                }
                try check(!SecureStore.erasurePending && !LLMClient.isConfigured(), "completed reset leaves no pending or configured external connection")
                try FileManager.default.removeItem(at: AccountResetNativeFixture.receiptURL)
                try check(!AccountResetNativeFixture.hasReceipt, "synthetic reset receipt removed")
            }
            status = "Account reset checks passed: " + mode + " " + phase
        } catch { status = "Account reset checks failed: " + error.localizedDescription }
        do {
            try JSONEncoder().encode(Report(status: status, mode: mode, phase: phase, pid: getpid(), originalPID: originalPID, checks: checks,
                scope: "Production Settings AccountReset service with fixed synthetic profile, local file, defaults and checked Keychain. Actual normal process restart, injected secret-delete failure and deterministic interruption after credential deletion. Not power-loss, filesystem erasure failure, HealthKit background delivery or Strava late-refresh acceptance."))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-reset-" + mode + "-" + phase + ".json"), options: .atomic)
        } catch { return "Account reset checks failed: report write failed" }
        return status
    }
}

/// A nonce-bound, simulator-only host for the unmodified production sheet.
enum ProviderConnectionUIFixture {
    private struct Receipt: Codable { let nonce: UUID }
    private static var receiptURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-ui-receipt.json") }
    private static var nonce: UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-provider-ui-nonce"), args.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: args[index + 1])
    }
    private static var requested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetForUITests") && args.contains("-provider-connection-ui") && nonce != nil
    }
    static var isAuthorized: Bool {
        guard requested, let bytes = try? Data(contentsOf: receiptURL), let receipt = try? JSONDecoder().decode(Receipt.self, from: bytes) else { return false }
        return receipt.nonce == nonce
    }
    static var resuming: Bool { isAuthorized && ProcessInfo.processInfo.arguments.contains("-provider-connection-ui-resume") }
    static var testsReset: Bool { isAuthorized && ProcessInfo.processInfo.arguments.contains("-provider-ui-fail-reset") }
    static func prepareIfRequested() throws {
        guard requested, let nonce else { return }
        guard !ProcessInfo.processInfo.arguments.contains("-provider-connection-ui-resume") else { throw ProviderConnectionStore.Failure.changed }
        try SecureStore.eraseAllChecked()
        try JSONEncoder().encode(Receipt(nonce: nonce)).write(to: receiptURL, options: .atomic)
        var record = ProviderConnectionStore.Record()
        record.mode = "key"; record.preset = "custom"; record.apiKey = "synthetic-key-42-a"
        record.endpoint = "http://127.0.0.1:48733/caller-chat"; record.model = "synthetic-provider-42-a"; record.preferExternal = true
        record.clientID = "123456789-synthetic42.apps.googleusercontent.com"
        record.oauthEndpoint = record.endpoint; record.oauthModel = record.model
        try ProviderConnectionStore.save(record, expectedRevision: ProviderAuthorizationRevision.current)
        try OAuthCredentialStore.save(.init(clientID: record.clientID, scope: record.scope, accessToken: "synthetic-access-old-42", refreshToken: "synthetic-refresh-42", expiresAt: Date().addingTimeInterval(3600)), expectedRevision: ProviderAuthorizationRevision.current)
        var profile = UserProfile.default; profile.name = "Alex"; profile.onboardingDone = true
        try LocalStore.saveChecked(profile, as: "profile")
        if ProcessInfo.processInfo.arguments.contains("-provider-ui-dark") { UserDefaults.standard.set("dark", forKey: "lumen.appearance") }
        if ProcessInfo.processInfo.arguments.contains("-provider-ui-fail-save") {
            SecureStore.injectFailure(.write, key: ProviderConnectionStore.key, status: errSecNotAvailable)
        }
        if ProcessInfo.processInfo.arguments.contains("-provider-ui-fail-cleanup") {
            try SecureStore.setChecked("synthetic-key-42-a", for: "lumen.llm.key")
            SecureStore.injectFailure(.delete, key: "lumen.llm.key", status: errSecInteractionNotAllowed)
        }
        if ProcessInfo.processInfo.arguments.contains("-provider-ui-fail-remove") {
            SecureStore.injectFailure(.write, key: ProviderConnectionStore.key, status: errSecNotAvailable)
        }
        if testsReset { SecureStore.injectFailure(.delete, key: "synthetic.storage.42.service", status: errSecInteractionNotAllowed) }
    }
    @MainActor private static var changedSavedConnection = false
    @MainActor static func changeSavedConnectionIfRequested(dirty: Bool) {
        guard dirty, isAuthorized, !changedSavedConnection, ProcessInfo.processInfo.arguments.contains("-provider-ui-stale-save") else { return }
        changedSavedConnection = true
        Task { @MainActor in LLMConnectionService.shared.model = "synthetic-provider-42-b"; capture(dirty: true) }
    }
    @MainActor static func capture(dirty: Bool) {
        guard isAuthorized, let nonce else { return }
        do {
            let bytes = try SecureStore.dataChecked(ProviderConnectionStore.key)
            let record = try bytes.map { try JSONDecoder().decode(ProviderConnectionStore.Record.self, from: $0) }
            let classification = record?.apiKey == nil ? "missing" : record?.apiKey == "synthetic-key-42-a" ? "fixture-a" : record?.apiKey == "synthetic-key-42-b" ? "fixture-b" : "unexpected"
            let service = LLMConnectionService.shared
            let profileBytes = try? Data(contentsOf: LocalStore.directory.appendingPathComponent("profile.json"))
            let profileContent = try profileBytes.map { try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: $0), options: [.sortedKeys]) }
            let object: [String: Any] = ["nonce": nonce.uuidString, "pid": getpid(), "dirty": dirty,
                "authorizationRevision": ProviderAuthorizationRevision.current.uuidString,
                "recordSHA256": bytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing",
                "apiKeyClass": classification, "recordID": record?.id.uuidString ?? "missing",
                "endpoint": record?.endpoint == "http://127.0.0.1:48733/caller-chat" ? "fixed-loopback" : "other",
                "apiEndpointClass": record?.endpoint == "http://127.0.0.1:48733/caller-chat" ? "fixture-a" : record?.endpoint == "http://127.0.0.1:48733/chat-b" ? "fixture-b" : "other",
                "oauthEndpointClass": record?.oauthEndpoint == "http://127.0.0.1:48733/caller-chat" ? "fixture-a" : record?.oauthEndpoint == "http://127.0.0.1:48733/chat-b" ? "fixture-b" : "other",
                "oauthClientClass": record?.clientID == "123456789-synthetic42.apps.googleusercontent.com" ? "fixture-a" : record?.clientID == "123456789-synthetic43.apps.googleusercontent.com" ? "fixture-b" : "other",
                "oauthScopeClass": record?.scope == "openid email profile" ? "fixture-a" : record?.scope == "openid email" ? "fixture-b" : "other",
                "oauthModelClass": record?.oauthModel == "synthetic-provider-42-a" ? "fixture-a" : record?.oauthModel == "synthetic-provider-42-b" ? "fixture-b" : "other",
                "oauthAccountSHA256": try SecureStore.dataChecked(OAuthCredentialStore.key).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing",
                "mode": record?.mode ?? "missing", "preset": record?.preset ?? "missing",
                "modelClass": record?.model == "synthetic-provider-42-a" ? "fixture-a" : record?.model == "synthetic-provider-42-b" ? "fixture-b" : "other",
                "preferExternal": record?.preferExternal ?? false,
                "testResultClass": service.lastTestResult == nil ? "missing" : service.lastTestResult == "Lumen AI link OK" ? "success" : "other",
                "testBusy": service.isBusy,
                "profileSHA256": profileBytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing",
                "profileContentSHA256": profileContent.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing",
                "legacyCleanupPending": record?.legacyCleanupPending ?? false,
                "keyRemovalPending": ProviderConnectionStore.removalPending,
                "oauthRemovalPending": OAuthCredentialStore.removalPending, "globalRemovalPending": SecureStore.erasurePending,
                "oauthAccountPresent": try SecureStore.dataChecked(OAuthCredentialStore.key) != nil,
                "legacyAPIKeyPresent": try SecureStore.dataChecked("lumen.llm.key") != nil,
                "configured": LLMClient.isConfigured()]
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-ui-live.json"), options: .atomic)
        } catch { preconditionFailure("Synthetic connection UI read-back failed") }
    }
}

struct ProviderConnectionUIRoot: View {
    @State private var showing = false
    var body: some View {
        VStack(spacing: 20) {
            Text("Synthetic connection settings").font(.headline)
            Text("Fixed loopback credentials only.").font(.footnote)
            Button(ProviderConnectionUIFixture.testsReset ? "Open Settings" : "Open AI connection") { showing = true }.accessibilityIdentifier("openAIConnectionFixture")
        }
        .sheet(isPresented: $showing) {
            if ProviderConnectionUIFixture.testsReset { SettingsView() }
            else { CoachSetupSheet() }
        }
        .onAppear { ProviderConnectionUIFixture.capture(dirty: false) }
    }
}

extension ProviderAuthorizationNativeProbe {
    static func runConnectionChecks() async -> String {
        precondition(requested && ProcessInfo.processInfo.arguments.contains("-provider-connection-checks"))
        struct Check: Encodable { let name: String; let passed: Bool }
        struct Report: Encodable { let status: String; let checks: [Check]; let cleanupVerified: Bool; let scope: String }
        let service = LLMConnectionService.shared
        var checks: [Check] = [], cleanup = false, status = "Connection storage checks failed"
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            let passed = try condition(); checks.append(.init(name: name, passed: passed))
            if !passed { throw Failure(name) }
        }
        func seedLegacy() throws {
            try SecureStore.eraseAllChecked()
            UserDefaults.standard.set("key", forKey: "lumen.llm.mode")
            UserDefaults.standard.set("custom", forKey: "lumen.llm.preset")
            UserDefaults.standard.set("http://127.0.0.1:48733/chat-a", forKey: "lumen.llm.endpoint")
            UserDefaults.standard.set("synthetic-provider-42-a", forKey: "lumen.llm.model")
            UserDefaults.standard.set(true, forKey: "lumen.ai.preferOpenAI")
            try SecureStore.setChecked("synthetic-key-42-a", for: "lumen.llm.key")
        }
        do {
            try seedLegacy()
            let original = try service.connectionDraft(), configuration = service.configuration()
            try check(original.apiKey == "synthetic-key-42-a" && original.mode == "key" && original.endpoint.hasSuffix("chat-a") && original.preferExternal, "read-only legacy preview retains the complete original recipient and key")
            _ = service.apiKey; _ = service.endpoint; _ = AIService.shared.brain
            try check(SecureStore.dataChecked(ProviderConnectionStore.key) == nil && SecureStore.stringChecked("lumen.llm.key", migrateLegacy: false) == original.apiKey && UserDefaults.standard.string(forKey: "lumen.llm.endpoint") == original.endpoint, "opening and status reads neither migrate the secret nor rewrite the preset")
            var draft = original; draft.endpoint = "http://127.0.0.1:48733/chat-b"; draft.model = "synthetic-provider-42-b"; draft.apiKey = "synthetic-key-42-b"
            try check(service.configuration() == configuration && service.apiKey == "synthetic-key-42-a", "editing a detached draft leaves live credentials and route untouched")
            SecureStore.injectFailure(.write, key: ProviderConnectionStore.key, status: errSecNotAvailable)
            var failed = false
            do { try ProviderConnectionStore.save(original, expectedRevision: configuration.revision) }
            catch let error as SecureStore.Failure { failed = error.operation == .write }
            try check(failed && SecureStore.dataChecked(ProviderConnectionStore.key) == nil && SecureStore.stringChecked("lumen.llm.key") == original.apiKey, "failed first atomic migration preserves its only legacy secret")
            let migrated = try ProviderConnectionStore.loadForRouting(expectedRevision: configuration.revision)
            try check(migrated.id == original.id && migrated.endpoint == original.endpoint && migrated.apiKey == original.apiKey && !migrated.legacyCleanupPending, "first real migration preserves the captured identity and complete tuple")
            try check(SecureStore.dataChecked("lumen.llm.key") == nil && UserDefaults.standard.object(forKey: "lumen.llm.endpoint") == nil && service.configuration() == configuration, "successful migration retires old sources without invalidating the original request")
            let prepared = await service.prepareAuthorization(expectedRevision: configuration.revision)
            try check(prepared?.endpoint.absoluteString == original.endpoint && prepared?.bearer == original.apiKey && prepared?.model == original.model, "actual route preparation uses the migrated original recipient-key pair")
            try service.saveConnectionChecked(draft, expected: service.configuration())
            let saved = try ProviderConnectionStore.read()!
            try check(saved.endpoint == draft.endpoint && saved.model == draft.model && saved.apiKey == draft.apiKey && saved.id != original.id && saved.preferExternal, "explicit checked save atomically commits a new recipient, model, key and identity")
            let bytes = try SecureStore.dataChecked(ProviderConnectionStore.key)
            var replacement = saved; replacement.apiKey = "synthetic-key-42-a"; replacement.endpoint = original.endpoint
            SecureStore.injectFailure(.write, key: ProviderConnectionStore.key, status: errSecNotAvailable)
            failed = false
            do { try service.saveConnectionChecked(replacement, expected: service.configuration()) }
            catch let error as SecureStore.Failure { failed = error.operation == .write }
            try check(failed && SecureStore.dataChecked(ProviderConnectionStore.key) == bytes && !LLMClient.isConfigured(), "failed replacement preserves exact old record bytes and blocks routing with a checked error")
            try service.saveConnectionChecked(replacement, expected: service.configuration())
            try check(service.apiKey == replacement.apiKey && service.endpoint == replacement.endpoint && service.credentialProblem == nil && LLMClient.isConfigured(), "retry commits the retained draft and restores the configured route")
            let stale = service.configuration()
            service.model = "synthetic-provider-42-a"
            let newer = try SecureStore.dataChecked(ProviderConnectionStore.key)
            var changed = false
            do { try service.saveConnectionChecked(replacement, expected: stale) } catch ProviderConnectionStore.Failure.changed { changed = true }
            try check(changed && SecureStore.dataChecked(ProviderConnectionStore.key) == newer, "stale settings draft cannot overwrite a newer saved connection")
            var invalid = try service.connectionDraft(); invalid.endpoint = "https://example.invalid/#fragment"
            failed = false
            do { try service.saveConnectionChecked(invalid, expected: service.configuration()) } catch ProviderConnectionStore.Failure.invalidDraft { failed = true }
            try check(failed && SecureStore.dataChecked(ProviderConnectionStore.key) == newer, "invalid active recipient is rejected before any credential write")
            try SecureStore.setDataChecked(Data("{\"version\":999}".utf8), for: ProviderConnectionStore.key)
            try SecureStore.setChecked("synthetic-key-42-a", for: "lumen.llm.key")
            failed = false
            do { _ = try ProviderConnectionStore.preview() } catch ProviderConnectionStore.Failure.corrupt { failed = true }
            try check(failed && service.apiKey.isEmpty && !LLMClient.isConfigured(), "malformed present record never rehydrates a legacy key")
            try service.removeAPIKeyChecked()
            try check(ProviderConnectionStore.read()?.apiKey == nil && SecureStore.dataChecked("lumen.llm.key") == nil && !ProviderConnectionStore.removalPending, "checked removal recovers a corrupt record and retires the shadowed legacy secret")
            try service.saveAPIKeyChecked("synthetic-key-42-a")
            let beforeRemoval = try SecureStore.dataChecked(ProviderConnectionStore.key)
            SecureStore.injectFailure(.write, key: ProviderConnectionStore.key, status: errSecInteractionNotAllowed)
            failed = false
            do { try service.removeAPIKeyChecked() } catch let error as SecureStore.Failure { failed = error.operation == .write }
            try check(failed && ProviderConnectionStore.removalPending && SecureStore.dataChecked(ProviderConnectionStore.key) == beforeRemoval && !LLMClient.isConfigured(), "failed removal durably marks intent, preserves bytes and blocks routing")
            try service.removeAPIKeyChecked()
            try check(!ProviderConnectionStore.removalPending && ProviderConnectionStore.read()?.apiKey == nil, "removal retry clears the stored key and its pending intent")
            for secondWrite in [false, true] {
                try seedLegacy()
                var retained = try service.connectionDraft(); retained.endpoint = "http://127.0.0.1:48733/chat-b"; retained.model = "synthetic-provider-42-b"; retained.apiKey = "synthetic-key-42-b"
                if secondWrite { SecureStore.injectFailure(.write, key: ProviderConnectionStore.key, status: errSecNotAvailable, afterSuccessfulMatches: 1) }
                else { SecureStore.injectFailure(.delete, key: "lumen.llm.key", status: errSecInteractionNotAllowed) }
                failed = false
                do { try service.saveConnectionChecked(retained, expected: service.configuration()) }
                catch let error as SecureStore.Failure { failed = error.operation == (secondWrite ? .write : .delete) }
                let pending = try ProviderConnectionStore.read()!
                try check(failed && pending.legacyCleanupPending && pending.endpoint == retained.endpoint && pending.apiKey == retained.apiKey && !LLMClient.isConfigured(), "failed " + (secondWrite ? "cleanup-marker write" : "old-key deletion") + " retains one complete new tuple and a durable routing block")
                try check(SecureStore.dataChecked("lumen.llm.key") == nil ? secondWrite : !secondWrite, "legacy source removal state matches the actual failed boundary")
                try service.saveConnectionChecked(retained, expected: service.configuration())
                try check(ProviderConnectionStore.read()?.legacyCleanupPending == false && SecureStore.dataChecked("lumen.llm.key") == nil && service.apiKey == retained.apiKey && service.endpoint == retained.endpoint && LLMClient.isConfigured(), "cleanup retry retains the requested tuple, clears the marker and removes every old API-key source")
            }
            try cleanupChecked(); cleanup = true
            status = "Connection storage checks passed"
        } catch { status = "Connection storage checks failed: " + error.localizedDescription }
        if !cleanup { try? SecureStore.eraseAllChecked(); try? cleanupChecked() }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Report(status: status, checks: checks, cleanupVerified: cleanup,
                scope: "Actual signed-simulator checked Keychain/defaults/service state with fixed synthetic keys and explicitly injected status failures. No HTTP, settings UI, live credentials, process-relaunch or power-loss acceptance in this suite."))
                .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-provider-connection-report.json"), options: .atomic)
        } catch { return "Connection storage checks failed: report write failed" }
        return status
    }
}
#endif
