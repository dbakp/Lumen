import Foundation

// MARK: - ChatCoachService: conversational coach with real data context.
// Uses Apple Intelligence (no sign-in) when available; otherwise a rule-based brain.

@MainActor
public final class ChatCoachService: ObservableObject {
    public static let shared = ChatCoachService()
    @Published public var isTyping = false
    @Published public private(set) var lastReplySource = "Built-in guide"
    public private(set) var lastRecordContext = RecordReplyContext.guide()

    private init() {}

    public func reply(to text: String, health: HealthStore, sleepDebt: TimeInterval, conversationHistory: [ChatMessage]? = nil) async -> String {
        isTyping = true
        lastReplySource = "Built-in guide"
        lastRecordContext = .guide()
        defer { isTyping = false }
        if let urgent = Self.urgentResponse(for: text) { return urgent }
        let history = conversationHistory ?? Array(health.chat.dropLast()) // latest user message is `text`
        let selectedBrain = AIService.shared.brain
        let documents = CompanionStore.shared.documents
        let modelLease = await SemanticSearchService.shared.lease()
        guard !Task.isCancelled else { return "" }
        let search = Task.detached(priority: .userInitiated) {
            try await HybridLibrarySearch.search(query: text, documents: documents, history: history, encoder: modelLease.encoder, enabled: modelLease.enabled)
        }
        let references: RecordReplyContext
        do {
            references = try await withTaskCancellationHandler(operation: { try await search.value }, onCancel: { search.cancel() })
        } catch {
            if Task.isCancelled { return "" }
            return "Library search couldn't finish. Try again, or open the record in Library."
        }
        guard !Task.isCancelled else { return "" }
        guard SemanticSearchService.shared.isCurrent(modelLease) else {
            return "Library search settings changed during this request. Send your question again to use the current settings."
        }
        // Consent/content may change while the background search is running.
        let currentDocuments = CompanionStore.shared.documents
        guard references.passages.allSatisfy({ RecordRetrieval.isCurrent($0, documents: currentDocuments) }) else {
            return "A shared Library record changed during this search. Send your question again to use the current text and sharing settings."
        }
        let safeHistory = RecordRetrieval.history(history, context: references, documents: currentDocuments)
        let instructions = CompanionStore.shared.context(health: health) + "\n\n" + CoachingEngine.contextPrompt(metrics: health.metrics, readiness: health.readiness, goals: health.goals,
                                                        workoutsToday: health.workoutsToday, estimatedSleepDebt: health.assistantSleepDebt) + "\nWhen asked for a plan, provide a short title, a brief reason tied to recorded data, and 3–5 numbered, flexible steps that can become a checklist. Do not alter medication or prescribe treatment."
        let fullInstructions = instructions + "\n\n" + RecordRetrieval.prompt(references)
        #if DEBUG && targetEnvironment(simulator)
        if SemanticSearchService.usesLocalReplyTest {
            let lookup = RecordRetrieval.localReply(references, query: text)
            lastRecordContext = lookup.1
            lastReplySource = "Local model test · no provider request"
            return lookup.0
        }
        #endif
        if let ai = await AIService.shared.chat(instructions: fullInstructions, history: safeHistory, user: text, using: selectedBrain),
           !ai.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !Task.isCancelled, SemanticSearchService.shared.isCurrent(modelLease),
                  references.passages.allSatisfy({ RecordRetrieval.isCurrent($0, documents: CompanionStore.shared.documents) }) else {
                return "Library records or search settings changed during this reply. Send your question again to use the current settings."
            }
            lastReplySource = selectedBrain.label
            let resolved = RecordRetrieval.resolving(ai.trimmingCharacters(in: .whitespacesAndNewlines), context: references)
            lastRecordContext = resolved.1
            return resolved.0
        }
        guard !Task.isCancelled else { return "" }
        guard SemanticSearchService.shared.isCurrent(modelLease),
              references.passages.allSatisfy({ RecordRetrieval.isCurrent($0, documents: CompanionStore.shared.documents) }) else {
            return "Library records or search settings changed during this reply. Send your question again to use the current settings."
        }
        if !PlanBuilder.isRequest(text), !references.passages.isEmpty || RecordRetrieval.isLibraryQuestion(text, history: history) {
            let lookup = RecordRetrieval.localReply(references, query: text)
            lastRecordContext = lookup.1
            lastReplySource = "Library lookup · on this iPhone"
            return lookup.0
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return localReply(userText: text, health: health, sleepDebt: sleepDebt)
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
