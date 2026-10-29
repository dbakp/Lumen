import Foundation

// MARK: - ChatCoachService: conversational coach with real data context.
// Uses Apple Intelligence (no sign-in) when available; otherwise a rule-based brain.

@MainActor
public final class ChatCoachService: ObservableObject {
    public static let shared = ChatCoachService()
    @Published public var isTyping = false
    @Published public private(set) var lastReplySource = "Built-in guide"

    private init() {}

    public func reply(to text: String, health: HealthStore, sleepDebt: TimeInterval, conversationHistory: [ChatMessage]? = nil) async -> String {
        isTyping = true
        lastReplySource = "Built-in guide"
        defer { isTyping = false }
        if let urgent = Self.urgentResponse(for: text) { return urgent }
        let history = conversationHistory ?? Array(health.chat.dropLast()) // latest user message is `text`
        let instructions = CompanionStore.shared.context(health: health) + "\n\n" + CoachingEngine.contextPrompt(metrics: health.metrics, readiness: health.readiness, goals: health.goals,
                                                        mealsToday: health.mealsToday, workoutsToday: health.workoutsToday,
                                                        sleepDebt: sleepDebt, debtFile: sleepDebt, history: history, totalCalories: health.caloriesEaten, totalProtein: health.proteinEaten) + "\nWhen asked for a plan, provide a short title, a brief reason tied to recorded data, and 3–5 numbered, flexible steps that can become a checklist. Do not alter medication or prescribe treatment."
        if let ai = await AIService.shared.chat(instructions: instructions, history: history, user: text),
           !ai.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastReplySource = AIService.shared.brain.label
            return ai.trimmingCharacters(in: .whitespacesAndNewlines)
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
            return "Your logs today include \(Int(health.caloriesEaten)) kcal, \(Int(health.proteinEaten)) g protein and \(Int(health.waterTodayML)) ml water. These are recorded amounts, not proof of your total intake.\n\nChoose a meal that suits your appetite and preferences. If you exercised, consider food and water afterwards. I can't infer nutritional deficiencies from these logs."
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
