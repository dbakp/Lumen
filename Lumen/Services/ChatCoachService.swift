import Foundation

// MARK: - ChatCoachService: conversational coach with real data context.
// Works offline with an excellent rule-based brain; upgrades to the user's
// connected AI (API key or OAuth — both set up from the phone) when available.

@MainActor
public final class ChatCoachService: ObservableObject {
    public static let shared = ChatCoachService()
    @Published public var isTyping = false

    private init() {}

    public var isLLMEnabled: Bool { LLMClient.isConfigured() }

    public func reply(to text: String, health: HealthStore, sleepDebt: TimeInterval) async -> String {
        isTyping = true
        defer { isTyping = false }
        if LLMClient.isConfigured(),
           let llm = await llmReply(userText: text, health: health, sleepDebt: sleepDebt) {
            return llm
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        return localReply(userText: text, health: health, sleepDebt: sleepDebt)
    }

    // MARK: local brain (fast, private, surprisingly good)

    func localReply(userText: String, health: HealthStore, sleepDebt: TimeInterval) -> String {
        let t = userText.lowercased()
        let score = health.readiness?.score ?? 72
        let proteinLeft = max(0, health.goals.proteinTarget() - Int(health.proteinEaten))
        let calLeft = health.goals.calorieTarget() - Int(health.caloriesEaten)

        if containsAny(t, ["tired", "exhausted", "low energy", "sleepy", "fatigue"]) {
            return "That heaviness makes sense — debt is \(String(format: "%.1f", sleepDebt/3600))h and readiness is \(score).\n\n• Get 10 min of daylight + water now — it shortens grogginess faster than coffee.\n• Keep caffeine before your cutoff and cap naps at 25 min.\n• Tonight: in bed 30 min earlier. One early night beats three perfect mornings."
        }
        if containsAny(t, ["workout", "train", "exercise", "run", "gym", "lift"]) {
            if score >= 75 { return "You're cleared to push. Do the hard session in the next 3 hours — warm up 10 min, main set 30–40 min at 8/10, then protein 30–40g within 2h. Cap it so tomorrow stays green." }
            if score >= 55 { return "Go moderate: 25–35 min Zone 2 (can talk in sentences) + a short walk after dinner. You'll adapt faster than forcing intervals today — hard day tomorrow when readiness rebounds." }
            return "Restore day wins. 15-min walk + mobility only. Fuel fully (\(calLeft) kcal left) and get to bed early — training through this dip just extends it."
        }
        if containsAny(t, ["eat", "food", "calorie", "protein", "hungry", "dinner", "lunch", "diet", "lose", "weight"]) {
            return "Fuel check: \(Int(health.caloriesEaten)) eaten of \(health.goals.calorieTarget()) kcal, protein \(Int(health.proteinEaten))g of \(health.goals.proteinTarget())g.\n\n• Tonight: palm-and-a-half of protein (~\(min(proteinLeft, 50))g) + fiber first, starch second.\n• \(calLeft > 0 ? "\(calLeft) kcal left — eat to the target, not under; under-fueling tanks tomorrow's readiness." : "Target reached — lighter evening protects sleep onset.")"
        }
        if containsAny(t, ["sleep", "bed", "insomnia", "nap", "wake"]) {
            return "Sleep is your highest-ROI lever right now (debt \(String(format: "%.1f", sleepDebt/3600))h).\n\n• Same wake ±30 min — even tomorrow.\n• Dim lights + screens 2h before bed, cool dark room.\n• If you nap: 20 min, before the afternoon dip ends. Late naps steal tonight."
        }
        if containsAny(t, ["stress", "anxious", "anxiety", "overwhelm"]) {
            return "Let's downshift the nervous system: 4-6 breathing (in 4, out 6) for 2 min, then a 10-min walk without audio. HRV \(health.metrics.hrvMS.map { Int($0) } ?? 0) ms suggests recovery is \(score >= 70 ? "available — movement will help" : "dipped — keep it gentle"). One small win, then bed on time."
        }
        if containsAny(t, ["hi", "hello", "hey", "morning", "evening"]) {
            return "\(greeting()): readiness \(score) — \(health.readiness?.headline ?? "ready"). \(health.plan?.briefing ?? "")\n\nTop move: \(health.plan?.bullets.first ?? "a short walk + water"). What are you deciding between today — training, food, or sleep?"
        }
        // Default: orient + next action.
        return "Got it. Right now: readiness \(score), \(Int(health.caloriesEaten))/\(health.goals.calorieTarget()) kcal, protein \(Int(health.proteinEaten))/\(health.goals.proteinTarget())g, steps \(Int(health.metrics.steps)).\n\nBest next move: \(health.plan?.bullets.first ?? "a 15-min walk + big glass of water"). Want a workout tweak, a meal call, or a sleep plan?"
    }

    private func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }
    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" }
    }

    // MARK: AI upgrade path (shared key/OAuth connection)

    private func llmReply(userText: String, health: HealthStore, sleepDebt: TimeInterval) async -> String? {
        let meals = health.meals.filter { Calendar.current.isDateInToday($0.date) }
        let system = CoachingEngine.contextPrompt(metrics: health.metrics, readiness: health.readiness, goals: health.goals, mealsToday: meals, workoutsToday: health.workoutsToday, sleepDebt: sleepDebt, debtFile: sleepDebt, history: health.chat)
        let history = health.chat.suffix(12).map { (role: $0.role == .user ? "user" : "assistant", text: $0.text) }
        return await LLMClient.coachChat(system: system, history: history, userText: userText)
    }
}
