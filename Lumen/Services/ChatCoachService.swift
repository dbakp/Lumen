import Foundation

// MARK: - ChatCoachService: conversational coach with real data context.
// Uses Apple Intelligence (no sign-in) when available; otherwise a rule-based brain.

/// One request owns its text, provenance and automatic-plan decision together.
/// Mutable display state must never be used to save another request's outcome.
struct CoachReplyOutcome: Sendable {
    let text: String
    let source: String
    let recordContext: RecordReplyContext
    let personalContext: PersonalContextProvenance
    let canBecomePlan: Bool
}

@MainActor
public final class ChatCoachService: ObservableObject {
    public static let shared = ChatCoachService()
    @Published public var isTyping = false
    @Published public private(set) var lastReplySource = "Built-in guide"
    public private(set) var lastRecordContext = RecordReplyContext.guide()
    public private(set) var lastPersonalContext = PersonalContextProvenance.withoutNotes
    public private(set) var lastReplyCanBecomePlan = false

    private init() {}

    public func reply(to text: String, health: HealthStore, sleepDebt: TimeInterval, conversationHistory: [ChatMessage]? = nil) async -> String {
        await replyOutcome(to: text, health: health, sleepDebt: sleepDebt, conversationHistory: conversationHistory).text
    }

    func replyOutcome(to text: String, health: HealthStore, sleepDebt: TimeInterval, conversationHistory: [ChatMessage]? = nil,
                      expectedProviderConfiguration: LLMConnectionService.Configuration? = nil, usingBrain: AIService.Brain? = nil) async -> CoachReplyOutcome {
        isTyping = true
        defer { isTyping = false }
        let result = await makeReply(to: text, health: health, sleepDebt: sleepDebt, conversationHistory: conversationHistory,
                                     expectedProviderConfiguration: expectedProviderConfiguration, usingBrain: usingBrain)
        lastReplySource = result.source; lastRecordContext = result.recordContext
        lastPersonalContext = result.personalContext; lastReplyCanBecomePlan = result.canBecomePlan
        return result
    }

    private func makeReply(to text: String, health: HealthStore, sleepDebt: TimeInterval, conversationHistory: [ChatMessage]?,
                           expectedProviderConfiguration: LLMConnectionService.Configuration?, usingBrain: AIService.Brain?) async -> CoachReplyOutcome {
        var lastReplySource = "Built-in guide"
        var lastRecordContext = RecordReplyContext.guide()
        var lastPersonalContext = PersonalContextProvenance.withoutNotes
        var lastReplyCanBecomePlan = false
        func finish(_ text: String) -> CoachReplyOutcome {
            .init(text: text, source: lastReplySource, recordContext: lastRecordContext,
                  personalContext: lastPersonalContext, canBecomePlan: lastReplyCanBecomePlan)
        }
        func contextNotice(expected: UUID) -> String? {
            guard let text = personalContextChangeNotice(expected: expected) else { return nil }
            lastReplySource = "Lumen notice"; lastRecordContext = .guide()
            lastPersonalContext = .withoutNotes; lastReplyCanBecomePlan = false
            return text
        }
        if let urgent = Self.urgentResponse(for: text) { return finish(urgent) }
        func localDataNotice() -> String? {
            do { try health.requireAllLocalHealthData(); return nil }
            catch {
                lastReplySource = "Lumen notice"; lastRecordContext = .guide()
                lastPersonalContext = .withoutNotes; lastReplyCanBecomePlan = false
                return "Saved health data couldn't be opened, so I can't reliably use your history or targets for this reply. Open Settings and retry opening saved data. Your saved files haven't been replaced."
            }
        }
        if let notice = localDataNotice() { return finish(notice) }
        let personalRevision = CompanionStore.shared.personalContextRevision
        let personalSnapshot = PersonalContextProvenance.included(CompanionStore.shared.personalContext)
        let previous = conversationHistory ?? Array(health.chat.dropLast()) // latest user message is `text`
        let history = PersonalContextProvenance.history(previous, current: personalSnapshot)
        let providerConfiguration = expectedProviderConfiguration ?? LLMConnectionService.shared.configuration()
        let selectedBrain = usingBrain ?? AIService.shared.brain
        let providerSource = selectedBrain == .openAIKey ? LLMConnectionService.shared.providerLabel : selectedBrain.label
        func providerNotice() -> String? {
            guard LLMConnectionService.shared.configuration() != providerConfiguration else { return nil }
            lastReplySource = "Lumen notice"; lastRecordContext = .guide()
            lastPersonalContext = .withoutNotes; lastReplyCanBecomePlan = false
            return "Your AI connection changed. This reply wasn't kept. Send your question again to use the current connection. Input already sent to a provider can't be recalled."
        }
        if let notice = providerNotice() { return finish(notice) }
        let libraryRevision = CompanionStore.shared.libraryRevision
        let documents = CompanionStore.shared.documents
        let modelLease = await SemanticSearchService.shared.lease()
        guard !Task.isCancelled else { return finish("") }
        let search = Task.detached(priority: .userInitiated) {
            let result = try await HybridLibrarySearch.search(query: text, documents: documents, history: history, encoder: modelLease.encoder, enabled: modelLease.enabled)
            #if DEBUG && targetEnvironment(simulator)
            try await PersonalContextSearchFixture.waitIfArmed()
            #endif
            return result
        }
        let references: RecordReplyContext
        do {
            references = try await withTaskCancellationHandler(operation: { try await search.value }, onCancel: { search.cancel() })
        } catch {
            if Task.isCancelled { return finish("") }
            if let notice = contextNotice(expected: personalRevision) { return finish(notice) }
            if let notice = providerNotice() { return finish(notice) }
            if let problem = error as? RecordRetrieval.SearchError { return finish(problem.localizedDescription) }
            return finish("Library search couldn't finish. Try again, or open the record in Library.")
        }
        guard !Task.isCancelled else { return finish("") }
        if let notice = contextNotice(expected: personalRevision) { return finish(notice) }
        if let notice = providerNotice() { return finish(notice) }
        guard CompanionStore.shared.libraryRevision == libraryRevision, SemanticSearchService.shared.isCurrent(modelLease) else {
            return finish("Library records or search settings changed during this request. Send your question again to use the current settings.")
        }
        // Consent/content may change while the background search is running.
        let currentDocuments = CompanionStore.shared.documents
        guard references.passages.allSatisfy({ RecordRetrieval.isCurrent($0, documents: currentDocuments) }) else {
            return finish("A shared Library record changed during this search. Send your question again to use the current text and sharing settings.")
        }
        let personalHistory = PersonalContextProvenance.history(history, current: .included(CompanionStore.shared.personalContext))
        let safeHistory = RecordRetrieval.history(personalHistory, context: references, documents: currentDocuments)
        if let notice = localDataNotice() { return finish(notice) }
        let instructions = CompanionStore.shared.context(health: health) + "\n\n" + CoachingEngine.contextPrompt(metrics: health.metrics, readiness: health.readiness, goals: health.goals,
                                                        workoutsToday: health.workoutsToday, estimatedSleepDebt: health.assistantSleepDebt) + "\nWhen asked for a plan, provide a short title, a brief reason tied to recorded data, and 3–5 numbered, flexible steps that can become a checklist. Do not alter medication or prescribe treatment."
        let fullInstructions = instructions + "\n\n" + RecordRetrieval.prompt(references)
        // Capture the original packet's authorization, never a freshly approved
        // replacement. The provider rechecks this after credential preparation.
        let submissionAllowed: @MainActor () -> Bool = {
            (try? health.requireAllLocalHealthData()) != nil &&
            LLMConnectionService.shared.configuration() == providerConfiguration &&
            CompanionStore.shared.libraryRevision == libraryRevision && SemanticSearchService.shared.isCurrent(modelLease) &&
            references.passages.allSatisfy { RecordRetrieval.isCurrent($0, documents: CompanionStore.shared.documents) } &&
            safeHistory.filter { $0.role == .coach }.allSatisfy { message in
                guard let context = message.recordContext, context.isValid else { return false }
                return context.passages.allSatisfy { RecordRetrieval.isCurrent($0, documents: CompanionStore.shared.documents) }
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        if SemanticSearchService.usesLocalReplyTest {
            let lookup = RecordRetrieval.localReply(references, query: text)
            lastRecordContext = lookup.1
            lastReplySource = "Local model test · no provider request"
            return finish(lookup.0)
        }
        #endif
        if let ai = await AIService.shared.chat(instructions: fullInstructions, history: safeHistory, user: text, using: selectedBrain,
                                              expectedPersonalContextRevision: personalRevision,
                                              expectedProviderRevision: providerConfiguration.revision, submissionAllowed: submissionAllowed),
           !ai.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let notice = contextNotice(expected: personalRevision) { return finish(notice) }
            if let notice = providerNotice() { return finish(notice) }
            guard !Task.isCancelled, submissionAllowed() else {
                return finish("Library records or search settings changed during this reply. Send your question again to use the current settings.")
            }
            if let resolved = RecordRetrieval.validatedModelReply(ai, context: references) {
                lastReplySource = providerSource
                #if DEBUG && targetEnvironment(simulator)
                if PersonalContextNativeProbe.usesSyntheticTransport && !ProviderAuthorizationNativeProbe.usesConfiguredCallerTransport { lastReplySource = "Synthetic local provider" }
                #endif
                lastRecordContext = resolved.1
                lastPersonalContext = personalSnapshot
                lastReplyCanBecomePlan = PlanBuilder.isRequest(text) && PlanBuilder.hasAutomaticActions(resolved.0)
                return finish(resolved.0)
            }
            // Discard the whole rejected answer, including claims next to any
            // valid citations. Literal lookup uses the freshly checked packet;
            // even a plan request cannot retain prose with broken references.
            let lookup = RecordRetrieval.localReply(references, query: text)
            lastRecordContext = lookup.1
            lastReplySource = "Library lookup · on this iPhone"
            return finish(lookup.0)
        }
        guard !Task.isCancelled else { return finish("") }
        if let notice = contextNotice(expected: personalRevision) { return finish(notice) }
        if let notice = providerNotice() { return finish(notice) }
        guard submissionAllowed() else {
            return finish("Library records or search settings changed during this reply. Send your question again to use the current settings.")
        }
        if !PlanBuilder.isRequest(text), !references.passages.isEmpty || RecordRetrieval.isLibraryQuestion(text, history: history) {
            let lookup = RecordRetrieval.localReply(references, query: text)
            lastRecordContext = lookup.1
            lastReplySource = "Library lookup · on this iPhone"
            return finish(lookup.0)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return finish("") }
        if let notice = contextNotice(expected: personalRevision) { return finish(notice) }
        if let notice = providerNotice() { return finish(notice) }
        guard submissionAllowed() else {
            return finish("Library records or search settings changed during this reply. Send your question again to use the current settings.")
        }
        let answer = localReply(userText: text, health: health, sleepDebt: sleepDebt)
        lastReplyCanBecomePlan = PlanBuilder.isRequest(text) && PlanBuilder.hasAutomaticActions(answer)
        return finish(answer)
    }

    private func personalContextChangeNotice(expected: UUID) -> String? {
        guard CompanionStore.shared.personalContextRevision != expected else { return nil }
        return "Your personal notes or sharing choice changed. This reply wasn't kept. Send your question again to use the saved choice. Input already sent to a provider can't be recalled."
    }

    // MARK: local brain (fast, private, surprisingly good)

    func localReply(userText: String, health: HealthStore, sleepDebt: TimeInterval) -> String {
        let t = userText.lowercased()
        let companion = CompanionStore.shared
        let perspective = companion.perspective(health: health)
        let evidence = perspective.evidence.map { "• " + $0 }.joined(separator: "\n")
        if PlanBuilder.isRequest(t) {
            return "A flexible plan for today\n\n" + perspective.body + "\n\n" + evidence + "\n\n1. Check how you feel before deciding on activity. Skip a hard session if pain or fatigue is present.\n2. Record your next meal and water if helpful; a missing log doesn't mean you haven't eaten.\n3. Leave time for your usual sleep routine tonight.\n\nThis is a wellness draft, not a treatment plan. Adjust it to your needs."
        }
        if containsAny(t, ["pain", "headache", "symptom", "hurt", "migraine"]) {
            let recent = companion.activeSymptoms.first
            let lead = recent.map { "You logged \($0.name.lowercased()) in your \($0.location.lowercased()) at \($0.severity)/10 on \($0.date.formatted(date: .abbreviated, time: .shortened))." } ?? "I don't have a symptom log to compare yet."
            return lead + "\n\nRecord when it started, how it feels, how long it lasts and what changes it. These details can help you discuss it with a clinician, but they don't show the cause. For symptoms that persist, worsen or concern you, contact a clinician."
        }
        if containsAny(t, ["eat", "food", "protein", "dinner", "water"]) {
            return HealthContextPrompt.intakeReply(metrics: health.metrics)
        }
        return perspective.body + "\n\nWhat I'm using:\n" + evidence + "\n\nI'm using the built-in guide for this reply. Enable an available AI provider in Settings for a wider conversation."
    }

    /// Deterministic triage runs before any model; a request for a plan must not mask urgent symptoms.
    public static func urgentResponse(for text: String) -> String? {
        let t = text.lowercased()
        let flags = ["chest pain", "can't breathe", "cannot breathe", "difficulty breathing", "shortness of breath", "worst headache", "sudden severe headache", "one-sided weakness", "one sided weakness", "fainting", "passed out", "slurred speech"]
        guard flags.contains(where: t.contains) else { return nil }
        return "These symptoms can need urgent medical attention. If they are happening now, contact local emergency services or seek emergency care now. Don't wait for a chat response or an exercise plan. Lumen cannot assess or rule out an emergency."
    }

    private func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }
    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" }
    }
}
