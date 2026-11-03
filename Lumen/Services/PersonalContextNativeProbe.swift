#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI

/// Synthetic integration only: both flags are required before full synthetic
/// instructions/history can enter the fixed credential-free loopback route.
@MainActor final class PersonalContextNativeProbe: ObservableObject {
    static let shared = PersonalContextNativeProbe()
    static var requested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetForUITests") && args.contains("-personal-provenance-probe")
    }
    static var usesSyntheticTransport: Bool {
        requested || PersonalContextUIFixture.isAuthorized
    }
    @Published private(set) var status = "Checking synthetic personal context…"
    private var started = false
    private struct Check: Codable { let name: String; let passed: Bool }
    private struct WriteFailure: Codable { let domain: String; let code: Int }
    private struct Audit: Codable {
        let route: String
        let bodySHA256: String
        let roles: [String]
        let canaries: [String: [String: Int]]
        func count(_ name: String, _ role: String) -> Int { canaries[name]?[role] ?? -1 }
    }
    private struct Failure: LocalizedError {
        let name: String
        var errorDescription: String? { name }
    }
    private func get(_ path: String) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil; configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: URL(string: "http://127.0.0.1:48731/" + path)!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 128_000 else { throw Failure(name: "synthetic control response invalid") }
        return data
    }
    private func audit() async throws -> [Audit] { try JSONDecoder().decode([Audit].self, from: await get("personal-audit")) }
    private func waitForRequest(_ count: Int) async throws {
        for _ in 0..<200 {
            if try await audit().count >= count { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure(name: "synthetic outgoing request did not arrive")
    }

    func run() async {
        guard Self.requested, !started else { return }; started = true
        if ProviderAuthorizationNativeProbe.requested { status = await ProviderAuthorizationNativeProbe.run(); return }
        if ProcessInfo.processInfo.arguments.contains("-library-authorization-checks") { await runLibraryChecks(); return }
        var checks: [Check] = []
        func check(_ value: Bool, _ name: String) throws {
            checks.append(.init(name: name, passed: value))
            if !value { throw Failure(name: name) }
        }
        let health = HealthStore.shared, companion = CompanionStore.shared, coach = ChatCoachService.shared
        var held = false
        var task: Task<String, Never>?
        var finalStatus = "Personal context checks failed"
        var writeFailure: WriteFailure?
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        do {
            for _ in 0..<200 where !health.conversationReady { try await Task.sleep(for: .milliseconds(50)) }
            try check(health.conversationReady && health.conversations.isEmpty, "actual empty startup is ready before synthetic personal-context checks")
            func save(_ context: PersonalHealthContext) throws { try companion.savePersonalContextChecked(context, expectedRevision: companion.personalContextRevision) }
            var a = PersonalHealthContext(); a.includeInAssistant = true; a.focus = "SYNTHETIC-PERSONAL-NOTE-40-A"
            var b = a; b.focus = "SYNTHETIC-PERSONAL-NOTE-40-B"
            var off = a; off.includeInAssistant = false
            try save(a)
            let snapshot = PersonalContextProvenance.included(a)
            let sent = try await health.sendUserMessageChecked(.init(role: .user, text: "SYNTHETIC-USER-QUESTION-40"), expectedConversationID: nil)
            let user = health.chat[0]
            let known = ChatMessage(role: .coach, text: "SYNTHETIC-KNOWN-ASSISTANT-40", recordContext: .guide(), personalContext: .withoutNotes)
            let matching = ChatMessage(role: .coach, text: "SYNTHETIC-MATCHING-ASSISTANT-40", recordContext: .guide(), personalContext: snapshot)
            let stale = ChatMessage(role: .coach, text: "SYNTHETIC-STALE-ASSISTANT-40", recordContext: .guide(), personalContext: .included(b))
            let legacy = ChatMessage(role: .coach, text: "SYNTHETIC-LEGACY-ASSISTANT-40", recordContext: .guide())
            var unsaved = a; unsaved.focus = "SYNTHETIC-PERSONAL-UNSAVED-40"
            let firstText = await coach.reply(to: "SYNTHETIC-PERSONAL-COMPLETE-40", health: health, sleepDebt: 0, conversationHistory: [user, known, matching, stale, legacy])
            let first = ChatMessage(role: .coach, text: firstText, provider: coach.lastReplySource, recordContext: coach.lastRecordContext, personalContext: coach.lastPersonalContext)
            var packets = try await audit()
            try check(packets.count == 1, "actual production HTTP request arrives once at the synthetic audit route")
            let packet = packets[0]
            try check(packet.roles == ["system", "user", "assistant", "assistant", "user"], "actual outgoing role order contains only eligible history plus the new question")
            try check(packet.count("noteA", "system") == 1 && packet.count("noteB", "system") == 0 && packet.count("unsaved", "system") == 0 && unsaved != companion.personalContext,
                      "actual system instructions include committed notes only, without the uncommitted local draft")
            try check(packet.count("known", "assistant") == 1 && packet.count("matching", "assistant") == 1 && packet.count("stale", "assistant") == 0 && packet.count("legacy", "assistant") == 0,
                      "actual outgoing history keeps known/matching assistants and omits changed-note and legacy assistants")
            try check(packet.count("user", "user") == 1 && firstText == "SYNTHETIC-PERSONAL-REPLY-40" && first.personalContext == snapshot,
                      "the accepted synthetic provider reply records the exact included-note snapshot and preserves the literal question")
            try check(first.provider == "Synthetic local provider", "test source label never claims an actual AI provider ran")
            guard let pendingID = health.retainConversationReply(first, owner: sent.owner, savePlan: false) else { throw Failure(name: "synthetic reply owner missing") }
            let before = try encoder.encode(health.conversations)
            let root = try LocalStore.checkedDirectory()
            func disk() throws -> [String: Data] {
                try Dictionary(uniqueKeysWithValues: ["conversations.json", "chat.json", "conversation-selection.json"].map {
                    ($0, try Data(contentsOf: root.appendingPathComponent($0)))
                })
            }
            let beforeDisk = try disk()
            var rejected = false
            do { _ = try await health.savePendingConversationReply(pendingID) } catch {
                let failure = error as NSError
                writeFailure = .init(domain: failure.domain, code: failure.code)
                rejected = failure.domain == NSCocoaErrorDomain
            }
            try check(rejected && (try encoder.encode(health.conversations)) == before && (try disk()) == beforeDisk && health.pendingConversationReplies.count == 1,
                      "actual Cocoa file-write failure preserves all three saved files byte-for-byte and retains the pending reply")
            try save(off)
            _ = try await health.savePendingConversationReply(pendingID)
            try check(try encoder.encode(health.chat.last) == encoder.encode(Optional(first)), "storage retry after withdrawal saves the identical reply packet and original note provenance")
            packets = try await audit()
            try check(packets.count == 1 && health.pendingConversationReplies.isEmpty, "actual pending storage retry performs no second provider request")
            let reopened = try LocalStore.loadConversationsChecked().conversations[0].messages
            try check(reopened.last?.personalContext == snapshot && reopened.last?.text == firstText && reopened.first?.id == user.id,
                      "actual conversation reopening preserves old-note provenance, reply text and user identity after withdrawal")
            _ = await coach.reply(to: "SYNTHETIC-PERSONAL-COMPLETE-40", health: health, sleepDebt: 0, conversationHistory: reopened + [known, legacy])
            packets = try await audit()
            try check(packets.count == 2, "the next actual request after withdrawal reaches the server")
            let withdrawn = packets[1]
            try check(withdrawn.count("noteA", "system") == 0 && withdrawn.count("noteB", "system") == 0 && withdrawn.count("returned", "assistant") == 0,
                      "actual withdrawn-note request contains neither private note context nor the retained old-note reply")
            try check(withdrawn.count("user", "user") == 1 && withdrawn.count("known", "assistant") == 1 && withdrawn.count("legacy", "assistant") == 0 && coach.lastPersonalContext == .withoutNotes,
                      "actual withdrawn history retains user questions and no-note assistants without upgrading legacy provenance")

            for mode in ["edit", "withdraw", "revert", "reload", "reset"] {
                try save(a)
                let expected = try await audit().count + 1
                _ = try await get("arm-personal"); held = true
                task = Task { await coach.reply(to: "Make a plan SYNTHETIC-PERSONAL-HELD-40", health: health, sleepDebt: 0, conversationHistory: []) }
                try await waitForRequest(expected)
                switch mode {
                case "edit": try save(b)
                case "withdraw": try save(off)
                case "revert": try save(b); try save(a)
                case "reload": companion.reloadAfterRestore()
                default: companion.reset()
                }
                _ = try await get("release-personal"); held = false
                let answer = await task!.value; task = nil
                try check(answer.contains("This reply wasn't kept") && !answer.contains("SYNTHETIC-PERSONAL-REPLY-40") && coach.lastReplySource == "Lumen notice",
                          "actual held response after \(mode) becomes a factual notice, never stale provider prose")
                try check(coach.lastPersonalContext == .withoutNotes && !coach.lastReplyCanBecomePlan,
                          "\(mode) notice has no-note provenance and cannot become an automatic plan")
            }

            try save(a)
            let countBeforeSearch = try await audit().count
            PersonalContextSearchFixture.arm()
            task = Task { await coach.reply(to: "SYNTHETIC-PERSONAL-COMPLETE-40", health: health, sleepDebt: 0, conversationHistory: []) }
            for _ in 0..<200 where !PersonalContextSearchFixture.holding { try await Task.sleep(for: .milliseconds(50)) }
            try check(PersonalContextSearchFixture.holding, "actual completed background search is suspended before its acceptance boundary")
            try save(off); PersonalContextSearchFixture.release()
            let searchAnswer = await task!.value; task = nil
            try check(searchAnswer.contains("This reply wasn't kept") && !PersonalContextSearchFixture.timedOut,
                      "a note change during the held background search rejects the stale result after explicit release")
            try check(try await audit().count == countBeforeSearch, "changed-note background search makes no provider request")
            let counts = try JSONSerialization.jsonObject(with: await get("counts")) as? [String: [String: Int]]
            try check(counts?["personal-held"]?["requests"] == 5 && counts?["personal-held"]?["releases"] == 5 && counts?["personal-held"]?["holdTimeouts"] == nil,
                      "all five held HTTP responses were explicitly released before timeout")
            try check(health.chat.last?.id == first.id && health.chat.count == 2,
                      "provenance checks never remove visible saved question/reply history")

            for mode in ["edit", "withdraw", "revert", "unchanged"] {
                try save(a)
                let revision = companion.personalContextRevision
                let beforeResolution = try await audit().count
                PersonalContextRouteFixture.arm()
                let resolvedReply = Task {
                    await coach.reply(to: "SYNTHETIC-PERSONAL-COMPLETE-40", health: health, sleepDebt: 0, conversationHistory: [])
                }
                defer { resolvedReply.cancel() }
                for _ in 0..<200 where !PersonalContextRouteFixture.holding { try await Task.sleep(for: .milliseconds(50)) }
                try check(PersonalContextRouteFixture.holding, "shared provider route resolution is actually suspended before \(mode)")
                switch mode {
                case "edit": try save(b)
                case "withdraw": try save(off)
                case "revert": try save(b); try save(a)
                default: break
                }
                PersonalContextRouteFixture.release()
                let answer = await resolvedReply.value
                let afterResolution = try await audit().count
                try check(!PersonalContextRouteFixture.timedOut && (mode == "unchanged"
                    ? answer == "SYNTHETIC-PERSONAL-REPLY-40" && afterResolution == beforeResolution + 1
                    : answer.contains("This reply wasn't kept") && coach.lastPersonalContext == .withoutNotes
                        && !coach.lastReplyCanBecomePlan && afterResolution == beforeResolution)
                    && (mode == "unchanged" ? revision == companion.personalContextRevision : revision != companion.personalContextRevision),
                    "actual coach route-resolution \(mode) uses original revision: changed context sends zero HTTP requests; unchanged context still sends")
            }
            let staleRevision = companion.personalContextRevision
            try save(off)
            let beforeStaleEntry = try await audit().count
            let staleChat = await AIService.shared.chat(instructions: a.assistantText, history: [], user: "SYNTHETIC-PERSONAL-COMPLETE-40",
                using: .openAIKey, expectedPersonalContextRevision: staleRevision)
            let afterStaleChat = try await audit().count
            try check(staleChat == nil && afterStaleChat == beforeStaleEntry,
                      "chat service refuses the caller's already-stale original revision before provider work")
            let stalePlan = await AIService.shared.scheduledPlan(request: .init(goal: "A synthetic routine", startDay: PlanDay.string(Date()), weeks: 2),
                context: a.assistantText, using: .openAIKey, expectedPersonalContextRevision: staleRevision)
            let afterStalePlan = try await audit().count
            try check(stalePlan == nil && afterStalePlan == beforeStaleEntry,
                      "scheduled-plan service refuses the caller's already-stale original revision before provider work")
            let exactPacket = try encoder.encode(Optional(first))
            let exported = try await BackupService.export(password: "Synthetic provenance passphrase 40", sleep: SleepStore.shared, health: health, control: .init())
            defer { exported.cleanup() }
            let source = try await Task.detached { try BackupService.select(exported.url, control: .init()) }.value
            defer { source.cleanup() }
            let preview = try await Task.detached { try BackupService.read(source, password: "Synthetic provenance passphrase 40", control: .init()) }.value
            let encryptedReply = preview.snapshot.conversations.first(where: { $0.id == sent.owner.conversationID })?.messages.last
            try check(try encoder.encode(encryptedReply) == exactPacket,
                      "actual iOS encrypted BackupService export/select/read retains the exact non-nil note provenance packet")
            try await health.deleteConversation(sent.owner.conversationID)
            try await BackupService.restore(preview, preferences: false, sleep: SleepStore.shared, health: health, control: .init())
            let restored = try LocalStore.loadConversationsChecked()
            let restoredReply = restored.conversations.first(where: { $0.id == sent.owner.conversationID })?.messages.last
            try check(try encoder.encode(restoredReply) == exactPacket && restored.selection != nil && restored.selection?.activeID == nil && health.chat.isEmpty && !companion.personalContext.includeInAssistant,
                      "actual encrypted restore recovers old-note provenance without restoring sharing or inventing an active selection")
            let readable = try await BackupService.exportReadable(sleep: SleepStore.shared, health: health, control: .init())
            defer { readable.cleanup() }
            let readableSource = try await Task.detached { try BackupService.selectReadable(readable.url, control: .init()) }.value
            defer { readableSource.cleanup() }
            let conversion = try await Task.detached { try BackupService.convertReadable(readableSource, control: .init()) }.value
            try check(try encoder.encode(conversion.snapshot.conversations.first(where: { $0.id == sent.owner.conversationID })?.messages.last) == exactPacket,
                      "actual iOS readable export/select/conversion preserves the non-nil personal-note provenance")
            try await health.deleteConversation(sent.owner.conversationID)
            try await BackupService.restoreReadable(conversion, domains: [.conversations], sleep: SleepStore.shared, health: health, control: .init())
            try await health.selectConversation(sent.owner.conversationID)
            try check(try encoder.encode(health.chat.last) == exactPacket && !companion.personalContext.includeInAssistant
                      && PersonalContextProvenance.history(health.chat, current: .included(companion.personalContext)).allSatisfy { $0.role == .user },
                      "actual readable restoration/reselection keeps literal history while excluding its old-note reply from new requests")
            finalStatus = "Personal context checks passed"
        } catch {
            finalStatus = "Personal context checks failed: " + error.localizedDescription
        }
        task?.cancel(); PersonalContextSearchFixture.release(); PersonalContextRouteFixture.release()
        if held { _ = try? await get("release-personal") }
        struct Report: Encodable { let status: String; let checks: [Check]; let requests: [Audit]; let writeFailure: WriteFailure? }
        let report = Report(status: finalStatus, checks: checks, requests: (try? await audit()) ?? [], writeFailure: writeFailure)
        do {
            let data = try encoder.encode(report)
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-personal-context-native-report.json"), options: .atomic)
            // XCTest can only observe completion after its report is saved.
            status = finalStatus
        } catch { status = "Personal context checks failed: report couldn't be saved" }
    }

    /// Full production coach, shared preparation/HTTP and actual checked stores.
    private func runLibraryChecks() async {
        struct Observation: Encodable {
            let mode: String
            let requestCount: Int
            let systemCanaryCount: Int
            let assistantCanaryCount: Int
            let reply: String
            let eligible: Bool
            let savedConversation: Bool
            let automaticPlanCount: Int
            let automaticStepCount: Int
        }
        var observations: [Observation] = []
        let health = HealthStore.shared, companion = CompanionStore.shared, coach = ChatCoachService.shared
        var task: Task<CoachReplyOutcome, Never>?
        var held = false
        var finalStatus = "Request authorization checks failed"
        do {
            for _ in 0..<200 where !health.conversationReady { try await Task.sleep(for: .milliseconds(50)) }
            guard health.conversationReady, health.conversations.isEmpty else { throw Failure(name: "checks startup not empty") }
            SemanticSearchService.shared.setEnabled(false)
            for mode in ["unchanged", "history-unchanged", "withdraw", "edit", "remove", "revert", "history", "lease", "held", "plan", "rejected", "urgent", "search-error", "local", "overlap", "submission-unchanged", "submission-withdraw", "submission-personal"] {
                var document = HealthDocument(title: "SYNTHETIC-LIBRARY-CONTEXT-41", kind: .note,
                    body: "SYNTHETIC-LIBRARY-CONTEXT-41. A synthetic flexible routine for planning.", source: "Synthetic fixture", includeInAssistant: true)
                try companion.saveChecked(document)
                var query = "Make a plan using SYNTHETIC-LIBRARY-CONTEXT-41"
                if ["held", "overlap"].contains(mode) { query += " SYNTHETIC-PERSONAL-HELD-40" }
                if mode == "plan" { query += " SYNTHETIC-PLAN-41" }
                if mode == "rejected" { query += " SYNTHETIC-REJECTED-41" }
                if mode == "local" { query += " SYNTHETIC-FAILURE-41" }
                if mode == "urgent" { query += " chest pain" }
                if mode == "search-error" { query += " Sample ID: AF-" + String(repeating: "1", count: 100) }
                if mode == "submission-personal" {
                    var notes = PersonalHealthContext(); notes.includeInAssistant = true; notes.focus = "SYNTHETIC-PERSONAL-NOTE-40-A"
                    try companion.savePersonalContextChecked(notes, expectedRevision: companion.personalContextRevision)
                }
                let finalPreparation = mode.hasPrefix("submission-")
                var history: [ChatMessage] = []
                if ["history", "history-unchanged"].contains(mode) {
                    let context = try await HybridLibrarySearch.search(query: query, documents: companion.documents, encoder: nil, enabled: false)
                    guard !context.passages.isEmpty else { throw Failure(name: "historical source not selected") }
                    history = [.init(role: .coach, text: "SYNTHETIC-LIBRARY-CONTEXT-41", recordContext: context, personalContext: .withoutNotes)]
                }
                let oldPlans = Set(companion.documents.filter { $0.kind == .plan }.map(\.id))
                let sent = try await health.sendUserMessageChecked(.init(role: .user, text: query), expectedConversationID: health.activeConversationID)
                let before = try await audit().count
                if ["held", "overlap"].contains(mode) { _ = try await get("arm-personal"); held = true }
                let early = ["urgent", "search-error"].contains(mode)
                if finalPreparation { PersonalContextSubmissionFixture.arm() } else if !early { PersonalContextRouteFixture.arm() }
                task = Task { await coach.replyOutcome(to: query, health: health, sleepDebt: 0, conversationHistory: history) }
                if !early {
                    for _ in 0..<200 where !(finalPreparation ? PersonalContextSubmissionFixture.holding : PersonalContextRouteFixture.holding) { try await Task.sleep(for: .milliseconds(25)) }
                    guard finalPreparation ? PersonalContextSubmissionFixture.holding : PersonalContextRouteFixture.holding else { throw Failure(name: mode + " route did not hold") }
                }
                switch mode {
                case "withdraw", "history", "submission-withdraw": document.includeInAssistant = false; try companion.saveChecked(document)
                case "edit": document.body += " Changed synthetic content."; try companion.saveChecked(document)
                case "remove": try companion.deleteDocumentChecked(document.id)
                case "revert":
                    document.includeInAssistant = false; try companion.saveChecked(document)
                    document.includeInAssistant = true; try companion.saveChecked(document)
                case "lease": SemanticSearchService.shared.removeModel()
                case "submission-personal":
                    var notes = companion.personalContext; notes.includeInAssistant = false
                    try companion.savePersonalContextChecked(notes, expectedRevision: companion.personalContextRevision)
                default: break
                }
                PersonalContextRouteFixture.release(); PersonalContextSubmissionFixture.release()
                var competing: (outcome: CoachReplyOutcome, owner: ConversationReplyOwner)?
                if ["held", "overlap"].contains(mode) {
                    try await waitForRequest(before + 1)
                    if mode == "overlap" {
                        try await health.newConversation()
                        let secondQuery = "Make a plan using SYNTHETIC-LIBRARY-CONTEXT-41 SYNTHETIC-PLAN-41"
                        let second = try await health.sendUserMessageChecked(.init(role: .user, text: secondQuery), expectedConversationID: nil)
                        let result = await coach.replyOutcome(to: secondQuery, health: health, sleepDebt: 0, conversationHistory: [])
                        guard result.canBecomePlan, result.source == "Synthetic local provider" else { throw Failure(name: "competing plan did not complete while first HTTP response held") }
                        competing = (result, second.owner)
                    }
                    document.includeInAssistant = false; try companion.saveChecked(document)
                    _ = try await get("release-personal"); held = false
                }
                let outcome = await task!.value; task = nil
                let answer = outcome.text
                let packets = try await audit(), newPackets = Array(packets.dropFirst(before))
                let blocked = ["withdraw", "edit", "remove", "revert", "history", "lease", "urgent", "search-error", "submission-withdraw", "submission-personal"].contains(mode)
                guard newPackets.count == (mode == "overlap" ? 2 : blocked ? 0 : 1) else { throw Failure(name: mode + " outgoing count") }
                if !blocked { guard newPackets[0].count("library41", "system") > 0 else { throw Failure(name: mode + " source missing") } }
                if mode == "history-unchanged" {
                    guard newPackets[0].count("library41", "assistant") == 1 else { throw Failure(name: "unchanged historical reply missing") }
                }
                let eligible = outcome.canBecomePlan && PlanBuilder.isRequest(query) && ChatCoachService.urgentResponse(for: query) == nil
                let expectedPlan = ["plan", "local"].contains(mode)
                guard eligible == expectedPlan, outcome.canBecomePlan == expectedPlan else { throw Failure(name: mode + " service eligibility") }
                if ["withdraw", "edit", "remove", "revert", "history", "lease", "held", "overlap"].contains(mode) {
                    guard answer.contains("changed during this reply"), !answer.contains("SYNTHETIC-PERSONAL-REPLY-40") else { throw Failure(name: mode + " notice missing") }
                }
                if mode == "submission-personal" {
                    guard answer.contains("Your personal notes or sharing choice changed"), outcome.personalContext == .withoutNotes else { throw Failure(name: "final submission personal authorization missing") }
                }
                guard !PersonalContextSubmissionFixture.timedOut else { throw Failure(name: "final preparation released by timeout") }
                if mode == "submission-withdraw" {
                    guard answer.contains("changed during this reply") else { throw Failure(name: "final Library submission notice missing") }
                }
                if let competing {
                    guard !coach.lastReplyCanBecomePlan, competing.outcome.canBecomePlan else { throw Failure(name: "immutable outcomes mixed across completions") }
                    let other = ChatMessage(role: .coach, text: competing.outcome.text, provider: competing.outcome.source,
                        recordContext: competing.outcome.recordContext, personalContext: competing.outcome.personalContext)
                    guard let otherID = health.retainConversationReply(other, owner: competing.owner, savePlan: competing.outcome.canBecomePlan) else { throw Failure(name: "competing reply owner lost") }
                    CoachView().saveReplyPlan(try await health.savePendingConversationReply(otherID))
                    let savedPlans = companion.documents.filter { $0.kind == .plan && $0.messageID == other.id }
                    let savedReply = health.conversations.first { $0.id == competing.owner.conversationID }?.messages.last
                    guard savedReply?.id == other.id, savedReply?.text == competing.outcome.text, savedReply?.provider == competing.outcome.source,
                          savedPlans.count == 1, savedPlans[0].steps.count == 3 else { throw Failure(name: "competing immutable plan save mixed with notice") }
                    observations.append(.init(mode: "overlap-plan", requestCount: 1, systemCanaryCount: newPackets[1].count("library41", "system"),
                        assistantCanaryCount: newPackets[1].count("library41", "assistant"), reply: other.text, eligible: true,
                        savedConversation: true, automaticPlanCount: 1, automaticStepCount: 3))
                    try await health.selectConversation(sent.owner.conversationID)
                }
                let reply = ChatMessage(role: .coach, text: answer, provider: outcome.source,
                    recordContext: outcome.recordContext, personalContext: outcome.personalContext)
                guard let id = health.retainConversationReply(reply, owner: sent.owner, savePlan: eligible) else { throw Failure(name: mode + " owner lost") }
                let pending = try await health.savePendingConversationReply(id)
                CoachView().saveReplyPlan(pending)
                let plans = companion.documents.filter { $0.kind == .plan && $0.messageID == reply.id }
                guard health.chat.last?.id == reply.id, plans.count == (expectedPlan ? 1 : 0),
                      oldPlans.isSubset(of: Set(companion.documents.filter { $0.kind == .plan }.map(\.id))) else { throw Failure(name: mode + " actual save path") }
                if mode == "withdraw" {
                    let manual = RecordRetrieval.savedDocument(from: reply, history: health.chat)
                    try companion.saveChecked(manual)
                    guard companion.documents.contains(where: { $0.id == manual.id && $0.body == answer && !$0.includeInAssistant && $0.kind == .note }) else { throw Failure(name: "manual save unavailable") }
                }
                observations.append(.init(mode: mode, requestCount: mode == "overlap" ? 1 : newPackets.count,
                    systemCanaryCount: newPackets.first?.count("library41", "system") ?? 0,
                    assistantCanaryCount: newPackets.first?.count("library41", "assistant") ?? 0,
                    reply: answer, eligible: eligible, savedConversation: health.chat.last?.id == reply.id,
                    automaticPlanCount: plans.count, automaticStepCount: plans.first?.steps.count ?? 0))
                if mode != "remove" { try companion.deleteDocumentChecked(document.id) }
            }
            finalStatus = "Request authorization checks passed"
        } catch { finalStatus = "Request authorization checks failed: " + error.localizedDescription }
        struct Report: Encodable { let status: String; let observations: [Observation]; let packets: [Audit] }
        let report = Report(status: finalStatus, observations: observations, packets: (try? await audit()) ?? [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(report).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-library-checks-report.json"), options: .atomic)
            status = finalStatus
        } catch { status = "Request authorization checks failed: report couldn't be saved" }
        task?.cancel(); PersonalContextRouteFixture.release(); PersonalContextSubmissionFixture.release()
        if held { _ = try? await get("release-personal") }
    }

}

/// A fresh reset creates an app-private receipt for one explicit synthetic UI
/// run. Its random token is carried only by XCTest on relaunch. It is outside
/// LumenData and never exported or restored with a user's backup.
@MainActor enum PersonalContextUIFixture {
    private struct Receipt: Codable { let nonce: UUID }
    private static var receiptURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-synthetic-personal-context-ui-receipt.json")
    }
    private static var nonce: UUID? {
        ProcessInfo.processInfo.environment["LUMEN_PERSONAL_TEST_NONCE"].flatMap(UUID.init(uuidString:))
    }
    static var isAuthorized: Bool {
        guard ProcessInfo.processInfo.arguments.contains("-personal-provenance-ui"), let nonce,
              let data = try? Data(contentsOf: receiptURL), data.count < 1024,
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data) else { return false }
        return receipt.nonce == nonce
    }
    static func prepareIfRequested() throws {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-resetForUITests"), args.contains("-personal-provenance-ui") else { return }
        try? FileManager.default.removeItem(at: receiptURL)
        guard let nonce else { return }
        try JSONEncoder().encode(Receipt(nonce: nonce)).write(to: receiptURL, options: .atomic)
        guard let index = args.firstIndex(of: "-personal-provenance-history-fixture"), args.indices.contains(index + 1) else { return }
        let mode = args[index + 1]
        guard ["legacy", "invalid", "unknownSources"].contains(mode) else { preconditionFailure("Unknown synthetic personal history fixture") }
        var provenance: PersonalContextProvenance? = mode == "unknownSources" ? .withoutNotes : nil
        if mode == "invalid" { var value = PersonalContextProvenance.withoutNotes; value.version = 2; provenance = value }
        let reply = ChatMessage(id: "synthetic-personal-history-reply-40", role: .coach,
            text: "Synthetic earlier reply with \(mode) provenance.", provider: "Synthetic older provider",
            recordContext: mode == "unknownSources" ? nil : .guide(), personalContext: provenance)
        let conversation = HealthConversation(id: "synthetic-personal-history-40", title: "Earlier synthetic conversation",
            messages: [.init(role: .user, text: "Synthetic earlier question."), reply])
        let root = try LocalStore.checkedDirectory()
        for (name, data) in try ConversationFiles.encoded([conversation], activeID: conversation.id) {
            try data.write(to: root.appendingPathComponent(name), options: .atomic)
        }
        var profile = UserProfile.default; profile.name = "Alex"; profile.onboardingDone = true
        try LocalStore.saveChecked(profile, as: "profile")
    }
}

@MainActor enum PersonalContextSearchFixture {
    private static var armed = false
    static private(set) var holding = false
    static private(set) var timedOut = false
    static func arm() { precondition(PersonalContextNativeProbe.requested); armed = true; timedOut = false }
    static func release() { armed = false }
    static func waitIfArmed() async throws {
        if PersonalContextUIFixture.isAuthorized && ProcessInfo.processInfo.arguments.contains("-library-search-hold-ui") {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 60
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (_, response) = try await session.data(from: URL(string: "http://127.0.0.1:48731/prepared-hold")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return
        }
        guard PersonalContextNativeProbe.requested, armed else { return }
        holding = true
        defer { holding = false }
        for _ in 0..<200 {
            try Task.checkCancellation()
            if !armed { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        timedOut = true; armed = false
    }
}

/// Holds the production route-resolution boundary without real credentials.
@MainActor enum PersonalContextRouteFixture {
    private static var armed = false
    static private(set) var holding = false
    static private(set) var timedOut = false
    static func arm() { precondition(PersonalContextNativeProbe.requested); armed = true; timedOut = false }
    static func release() { armed = false }
    static func resolve(_ route: LLMClient.ChatRoute) async -> LLMClient.ChatRoute? {
        guard PersonalContextNativeProbe.requested, armed else { return route }
        holding = true
        defer { holding = false }
        for _ in 0..<200 {
            if Task.isCancelled { return nil }
            if !armed { return route }
            try? await Task.sleep(for: .milliseconds(50))
        }
        timedOut = true; armed = false
        return nil
    }
}
/// Holds only explicitly armed, synthetic final request preparation.
@MainActor enum PersonalContextSubmissionFixture {
    private static var armed = false
    static private(set) var holding = false
    static private(set) var timedOut = false
    static func arm() { precondition(PersonalContextNativeProbe.requested); armed = true; timedOut = false }
    static func release() { armed = false }
    static func waitIfArmed() async {
        guard PersonalContextNativeProbe.requested, armed else { return }
        holding = true
        defer { holding = false }
        for _ in 0..<200 {
            if Task.isCancelled { return }
            if !armed { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        timedOut = true; armed = false
    }
}

#endif
