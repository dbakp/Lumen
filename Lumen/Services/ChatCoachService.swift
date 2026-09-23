import Foundation

// MARK: - ChatCoachService: conversational coach with real data context.
// Uses Apple Intelligence (no sign-in) when available; otherwise a rule-based brain.

@MainActor
public final class ChatCoachService: ObservableObject {
    public static let shared = ChatCoachService()
    @Published public var isTyping = false

    private init() {}

    public func reply(to text: String, health: HealthStore, sleepDebt: TimeInterval) async -> String {
        isTyping = true
        defer { isTyping = false }
        let history = Array(health.chat.dropLast()) // latest user message is `text`
        let instructions = CoachingEngine.contextPrompt(metrics: health.metrics, readiness: health.readiness, goals: health.goals,
                                                        mealsToday: health.mealsToday, workoutsToday: health.workoutsToday,
                                                        sleepDebt: sleepDebt, debtFile: sleepDebt, history: history)
        if let ai = await AIService.shared.chat(instructions: instructions, history: history, user: text),
           !ai.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ai.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return localReply(userText: text, health: health, sleepDebt: sleepDebt)
    }

    // MARK: local brain (fast, private, surprisingly good)

    func localReply(userText: String, health: HealthStore, sleepDebt: TimeInterval) -> String {
        let t = userText.lowercased()
        let score = health.readiness?.score
        let debt = String(format: "%.1f", sleepDebt / 3600)
        let proteinLeft = max(0, health.goals.proteinTarget() - Int(health.proteinEaten))
        let calLeft = health.goals.calorieTarget() - Int(health.caloriesEaten)

        if containsAny(t, ["tired", "exhausted", "low energy", "sleepy", "fatigue"]) {
            return "That makes sense — you're about \(debt) hours behind on sleep.\n\n• Get outside for 10 minutes and drink a glass of water — it wakes you up faster than coffee.\n• If you nap, keep it under 25 minutes and before mid-afternoon.\n• Go to bed 30 minutes earlier tonight."
        }
        if containsAny(t, ["workout", "train", "exercise", "run", "gym", "lift"]) {
            guard let score else {
                return "I don't know how recovered you are yet. Start with a moderate workout you enjoy, and after a night of sleep data I'll tell you when to push and when to rest."
            }
            if score >= 75 { return "Yes — you're well recovered, so today is a good day to push. Warm up for 10 minutes, keep the hard part to 30–40 minutes, and have a protein-rich meal afterwards." }
            if score >= 55 { return "Keep it moderate today — an easy run, ride or brisk walk where you can still talk comfortably. Save the hard session for when you're more rested." }
            return "Take it easy today. A gentle walk and some stretching is plenty. Eat well and get to bed early — you'll bounce back faster than if you push through."
        }
        if containsAny(t, ["eat", "food", "calorie", "protein", "hungry", "dinner", "lunch", "diet", "lose", "weight"]) {
            return "So far you've had \(Int(health.caloriesEaten)) of \(health.goals.calorieTarget()) calories and \(Int(health.proteinEaten)) g of protein.\n\n• Make protein the star of your next meal — chicken, fish, tofu, eggs or yogurt (about \(min(proteinLeft, 50)) g).\n• Fill half the plate with vegetables.\n• \(calLeft > 0 ? "You have \(calLeft) calories left — eating enough helps you recover." : "You've reached your calories — keep the evening light so you sleep well.")"
        }
        if containsAny(t, ["sleep", "bed", "insomnia", "nap", "wake"]) {
            return "Sleep is your biggest lever right now (about \(debt) hours behind).\n\n• Wake up at the same time every day, even weekends.\n• Dim the lights and put screens away an hour before bed.\n• Keep the bedroom cool, dark and quiet."
        }
        if containsAny(t, ["stress", "anxious", "anxiety", "overwhelm"]) {
            return "Let's slow things down. Breathe in for 4 seconds and out for 6, for two minutes. Then take a 10-minute walk without your phone. One small step at a time — and try to get to bed on time tonight."
        }
        if containsAny(t, ["hi", "hello", "hey", "morning", "evening", "approach", "today"]) {
            let lead = score.map { "Your readiness is \($0) — \(health.readiness?.headline.lowercased() ?? "")." } ?? "I'm still getting to know you."
            return "\(greeting())! \(lead)\n\nFor today: \(health.plan?.bullets.first ?? "a short walk and a big glass of water are a great start."). Want help with training, food or sleep?"
        }
        return "Here's where you are today: \(Int(health.metrics.steps).formatted()) steps, \(Int(health.caloriesEaten)) of \(health.goals.calorieTarget()) calories, \(Int(health.proteinEaten)) g protein.\n\nA good next step: \(health.plan?.bullets.first ?? "a 15-minute walk and a glass of water"). Ask me about training, food or sleep anytime."
    }

    private func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }
    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" }
    }
}
