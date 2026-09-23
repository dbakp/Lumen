import Foundation

// MARK: - CoachingEngine: the brain.
// Built on published exercise-physiology, sleep and nutrition research:
// readiness from HRV+RHR+sleep debt+strain balance; strain target; protein-first
// calorie coaching; 3-bullet day plan; kind, specific, never shaming.

public enum CoachingEngine {

    // MARK: readiness 0-100

    public static func readiness(metrics: DayMetrics, sleepDebt: TimeInterval, workoutsToday: [Workout], goals: HealthGoals) -> Readiness {
        var score = 82
        var factors: [Readiness.ReadinessFactor] = []

        // Sleep debt drag (biggest lever).
        let debtH = sleepDebt / 3600
        let debtDrag = Int(min(30, debtH * 4.5))
        score -= debtDrag
        factors.append(.init(id: "sleep", label: "Sleep debt", delta: -debtDrag,
            detail: debtH < 1 ? "You're well rested." : debtH < 5 ? "You're \(String(format: "%.1f", debtH)) hours behind on sleep." : "You're \(String(format: "%.1f", debtH)) hours behind on sleep — rest matters most today."))

        // HRV vs implied baseline (uses absolute zones when no history).
        if let hrv = metrics.hrvMS {
            let (d, msg): (Int, String)
            switch hrv {
            case 80...: (d, msg) = (6, "Your body looks very well recovered.")
            case 50..<80: (d, msg) = (2, "Your body looks recovered.")
            case 35..<50: (d, msg) = (-4, "Your body is still recovering — keep things easy.")
            default: (d, msg) = (-9, "Your body needs rest — sleep and gentle movement help most.")
            }
            score += d
            factors.append(.init(id: "hrv", label: "HRV \(Int(hrv)) ms", delta: d, detail: msg))
        }

        // Resting HR.
        if let rhr = metrics.restingHR {
            let (d, msg): (Int, String)
            if rhr <= 55 { (d, msg) = (4, "\(Int(rhr)) bpm — a calm, strong heart.") }
            else if rhr <= 65 { (d, msg) = (1, "\(Int(rhr)) bpm — normal for you.") }
            else if rhr <= 72 { (d, msg) = (-3, "\(Int(rhr)) bpm — a little higher than ideal.") }
            else { (d, msg) = (-7, "\(Int(rhr)) bpm — your body is working hard. Go easy.") }
            score += d
            factors.append(.init(id: "rhr", label: "Resting HR", delta: d, detail: msg))
        }

        // Yesterday's strain vs today's readiness (avoid stacking red days).
        let yesterdayLoad = workoutsToday.reduce(0) { $0 + $1.activeCalories }
        if yesterdayLoad > 900 {
            score -= 5
            factors.append(.init(id: "strain", label: "Yesterday's load", delta: -5, detail: "You trained hard recently — your body gets stronger while it rests."))
        }

        score = min(100, max(5, score))
        let headline: String
        switch score {
        case 85...: headline = "Ready for a big day"
        case 70..<85: headline = "Good to go"
        case 55..<70: headline = "Take it steady"
        default: headline = "Rest and recover"
        }
        // Strain target scales with readiness.
        let base = Int(goals.activeCalGoal)
        let target: ClosedRange<Int>
        switch score {
        case 85...: target = (base - 50)...(base + 350)
        case 70..<85: target = (base - 100)...(base + 200)
        case 55..<70: target = (base - 200)...(base + 50)
        default: target = 150...(base - 150)
        }
        return Readiness(score: score, factors: factors, headline: headline, strainTarget: target)
    }

    // MARK: day plan

    public static func dayPlan(metrics: DayMetrics, readiness: Readiness?, goals: HealthGoals, sleepDebt: TimeInterval, eaten: Double, protein: Double, waterML: Double) -> DayPlan {
        let score = readiness?.score ?? 72
        let calTarget = goals.calorieTarget()
        let proteinTarget = goals.proteinTarget()
        let waterTarget = Int((goals.weightKg ?? 75) * 35) // ml, ~35ml/kg

        var bullets: [String] = []
        // 1. Movement prescription from readiness.
        if score >= 85 {
            bullets.append("A great day for a hard workout — push yourself.")
        } else if score >= 70 {
            bullets.append("Go for your usual workout, and keep it under an hour.")
        } else if score >= 55 {
            bullets.append("Keep exercise light: a 20–30 minute walk or easy ride.")
        } else {
            bullets.append("Skip hard exercise today. A short walk and some stretching is plenty.")
        }
        // 2. Fuel prescription from what's logged.
        let proteinLeft = max(0, proteinTarget - Int(protein))
        if proteinLeft > 60 {
            bullets.append("Build your next meals around protein — about \(proteinLeft) g to go today.")
        } else if proteinLeft > 0 {
            bullets.append("Almost at your protein goal — a yogurt or eggs will get you there.")
        } else {
            bullets.append("Protein goal reached. Keep dinner light for better sleep.")
        }
        // 3. Recovery prescription.
        let waterLeft = max(0, waterTarget - Int(waterML))
        if sleepDebt > 5 * 3600 {
            bullets.append("Go to bed 30 minutes earlier tonight — you're behind on sleep.")
        } else if waterLeft > 1200 {
            bullets.append("Drink a couple of glasses of water before the evening.")
        } else {
            bullets.append("Wind down tonight with dim lights and no screens in bed.")
        }

        let briefing: String
        if score >= 85 { briefing = "You're well recovered — a good day to be ambitious." }
        else if score >= 70 { briefing = "A solid day. Use your energy early and relax in the evening." }
        else if score >= 55 { briefing = "A steady day. Moderate effort will serve you best." }
        else { briefing = "A rest day. Going to bed early is the best thing you can do." }

        let suggestion: String
        if score >= 85 { suggestion = "Hard workout" }
        else if score >= 70 { suggestion = "Your usual workout" }
        else if score >= 55 { suggestion = "Light exercise" }
        else { suggestion = "Walk and stretch" }

        return DayPlan(
            briefing: briefing,
            bullets: Array(bullets.prefix(3)),
            calorieTarget: calTarget,
            proteinTargetG: proteinTarget,
            waterTargetML: waterTarget,
            caffeineCutoff: nil,
            workoutSuggestion: suggestion,
            bedtimeTonight: nil
        )
    }

    // MARK: insights feed

    public static func insights(metrics: DayMetrics, readiness: Readiness?, goals: HealthGoals, mealsToday: [Meal], workoutsToday: [Workout], sleepDebt: TimeInterval) -> [Insight] {
        var out: [Insight] = []
        let score = readiness?.score ?? 72

        if sleepDebt > 5 * 3600 {
            out.append(Insight(icon: "moon.fill", tint: "#8B7CFF", title: "Sleep is holding you back",
                body: "You're \(String(format: "%.1f", sleepDebt/3600)) hours behind. Going to bed 30 minutes earlier tonight will help more than extra coffee.",
                action: "See energy schedule"))
        }
        if let hrv = metrics.hrvMS, hrv < 40 {
            out.append(Insight(icon: "waveform.path.ecg", tint: "#FF6B6B", title: "Your body is still recovering",
                body: "Keep exercise easy today and eat enough — skipping meals slows recovery.",
                action: "Go easy today"))
        }
        let protein = mealsToday.reduce(0) { $0 + $1.protein }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 15 && protein < Double(goals.proteinTarget()) * 0.5 {
            out.append(Insight(icon: "fork.knife", tint: "#4ADE80", title: "Room for more protein",
                body: "You've had \(Int(protein)) g of \(goals.proteinTarget()) g. Make protein the star of dinner — chicken, fish, tofu or eggs.",
                action: "Log dinner"))
        }
        if metrics.steps > 0 && metrics.steps < goals.stepGoal * 0.5 && hour >= 16 {
            let left = Int(goals.stepGoal - metrics.steps)
            out.append(Insight(icon: "figure.walk", tint: "#22D3EE", title: "A walk closes the gap",
                body: "\(left.formatted()) steps to go. A 15-minute walk after dinner covers about 1,500 and helps you sleep.",
                action: "Take a walk"))
        }
        if !workoutsToday.isEmpty {
            let w = workoutsToday.last!
            out.append(Insight(icon: w.kind.icon, tint: "#FBBF24", title: "\(w.title) logged · \(Int(w.activeCalories)) kcal",
                body: "Nice work. Have a protein-rich meal in the next couple of hours and take the evening easy.",
                action: nil))
        } else if score >= 70 && hour < 18 {
            out.append(Insight(icon: "bolt.fill", tint: "#FBBF24", title: "A good time to move",
                body: "You're well recovered and there's daylight left — even 25 minutes of exercise counts.",
                action: "Start workout"))
        }
        if metrics.waterML < 1200 && hour >= 14 {
            out.append(Insight(icon: "drop.fill", tint: "#38BDF8", title: "Water before evening",
                body: "Drink some water now so you're not catching up late and waking up at night.",
                action: "Log water"))
        }
        if out.isEmpty {
            out.append(Insight(icon: "checkmark.seal.fill", tint: "#4ADE80", title: "You're on track",
                body: "Nothing to fix today. Keep your routine — same wake time, good meals, dim lights tonight.",
                action: nil))
        }
        return Array(out.prefix(5))
    }

    // MARK: chat context builder (for ChatCoachService + any LLM)

    public static func contextPrompt(metrics: DayMetrics, readiness: Readiness?, goals: HealthGoals, mealsToday: [Meal], workoutsToday: [Workout], sleepDebt: TimeInterval, debtFile: TimeInterval, history: [ChatMessage]) -> String {
        let eaten = mealsToday.reduce(0) { $0 + $1.calories }
        let protein = mealsToday.reduce(0) { $0 + $1.protein }
        let workoutSummary = workoutsToday.isEmpty ? "none yet" : workoutsToday.map { "\($0.title) \(Int($0.duration / 60)) min" }.joined(separator: ", ")
        func v(_ d: Double?, _ unit: String) -> String { d.map { "\(Int($0)) \(unit)" } ?? "unknown" }
        let time = Date().formatted(date: .omitted, time: .shortened)
        return """
        You are Lumen, a warm, expert health coach (sleep, training and nutrition). The person is not technical.
        Style: plain everyday words, no jargon or abbreviations; 2–4 short sentences, then at most 3 bullet points if useful. \
        Be specific to their numbers. Never shame food or body. No diagnoses — if they mention chest pain, fainting, disordered eating \
        or other red flags, kindly suggest seeing a clinician.
        Right now it is \(time). Their data today:
        - Readiness: \(readiness.map { "\($0.score)/100 (\($0.headline))" } ?? "not enough data yet")
        - Sleep debt: \(String(format: "%.1f", sleepDebt / 3600)) hours
        - Steps: \(Int(metrics.steps)) of \(Int(goals.stepGoal)); active energy \(Int(metrics.activeCalories)) of \(Int(goals.activeCalGoal)) kcal; exercise \(Int(metrics.exerciseMin)) min
        - Resting heart rate: \(v(metrics.restingHR, "bpm")); heart rate variability: \(v(metrics.hrvMS, "ms"))
        - Food: \(Int(eaten)) of \(goals.calorieTarget()) kcal, protein \(Int(protein)) of \(goals.proteinTarget()) g; water \(Int(metrics.waterML)) ml
        - Workouts today: \(workoutSummary)
        - Goal: \(goals.goal.label)
        """
    }
}
