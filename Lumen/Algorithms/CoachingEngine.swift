import Foundation

// MARK: - CoachingEngine: the brain.
// Built on published exercise-physiology, sleep and nutrition research:
// readiness from HRV+RHR+sleep debt+strain balance; strain target; protein-first
// calorie coaching; 3-bullet day plan; kind, specific, never shaming.

public enum CoachingEngine {

    // MARK: readiness 0-100

    public static func readiness(metrics: DayMetrics, sleepDebt: TimeInterval, workoutsToday: [Workout], goals: HealthGoals, hrvBaseline: Double? = nil, restingHRBaseline: Double? = nil) -> Readiness {
        var score = 82
        var factors: [Readiness.ReadinessFactor] = []

        // Sleep debt drag (biggest lever).
        let debtH = sleepDebt / 3600
        let debtDrag = Int(min(30, debtH * 4.5))
        score -= debtDrag
        factors.append(.init(id: "sleep", label: "Sleep debt", delta: -debtDrag,
            detail: debtH < 1 ? "You're well rested." : debtH < 5 ? "You're \(String(format: "%.1f", debtH)) hours behind on sleep." : "You're \(String(format: "%.1f", debtH)) hours behind on sleep — rest matters most today."))

        if let hrv = metrics.hrvMS {
            let delta: Int
            let detail: String
            if let baseline = hrvBaseline, baseline > 0 {
                let ratio = hrv / baseline
                delta = ratio < 0.8 ? -6 : ratio > 1.15 ? 3 : 0
                detail = "\(Int(hrv)) ms today; recent personal average \(Int(baseline)) ms. A change alone does not establish recovery or illness."
            } else { delta = 0; detail = "\(Int(hrv)) ms recorded. At least seven prior days are needed for a personal comparison." }
            score += delta
            factors.append(.init(id: "hrv", label: "Heart rate variability", delta: delta, detail: detail))
        }
        if let rhr = metrics.restingHR {
            let delta = restingHRBaseline.map { rhr > $0 + 5 ? -4 : 0 } ?? 0
            score += delta
            let comparison = restingHRBaseline.map { "Recent personal average \(Int($0)) bpm." } ?? "Building your personal baseline."
            factors.append(.init(id: "rhr", label: "Resting heart rate", delta: delta, detail: "\(Int(rhr)) bpm recorded. " + comparison))
        }

        // Yesterday's strain vs today's readiness (avoid stacking red days).
        let yesterdayLoad = workoutsToday.reduce(0) { $0 + $1.activeCalories }
        if yesterdayLoad > 900 {
            score -= 5
            factors.append(.init(id: "strain", label: "Today’s load", delta: -5, detail: "You trained hard recently — your body gets stronger while it rests."))
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
        let base = max(100, Int(goals.activeCalGoal))
        let lower = max(0, base - (score >= 70 ? 100 : 250))
        let upper = max(lower, base + (score >= 85 ? 250 : score >= 70 ? 100 : -50))
        let target = lower...upper
        return Readiness(score: score, factors: factors, headline: headline, strainTarget: target)
    }

    // MARK: day plan

    public static func dayPlan(metrics: DayMetrics, readiness: Readiness?, goals: HealthGoals, sleepDebt: TimeInterval, eaten: Double, protein: Double, waterML: Double) -> DayPlan {
        let score = readiness?.score ?? 50
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
            bullets.append("There is room in your logged protein target. Choose a meal that suits your appetite.")
        } else {
            bullets.append("Your logged protein target is reached. Let appetite and preferences guide your next meal.")
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
        let score = readiness?.score ?? 50

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

    public static func contextPrompt(metrics: DayMetrics, readiness: Readiness?, goals: HealthGoals, mealsToday: [Meal], workoutsToday: [Workout], sleepDebt: TimeInterval, debtFile: TimeInterval, history: [ChatMessage], totalCalories: Double? = nil, totalProtein: Double? = nil) -> String {
        let eaten = totalCalories ?? mealsToday.reduce(0) { $0 + $1.calories }
        let protein = totalProtein ?? mealsToday.reduce(0) { $0 + $1.protein }
        let workoutSummary = workoutsToday.isEmpty ? "none yet" : workoutsToday.map { "\($0.title) \(Int($0.duration / 60)) min" }.joined(separator: ", ")
        func v(_ d: Double?, _ unit: String) -> String { d.map { "\(Int($0)) \(unit)" } ?? "unknown" }
        let time = Date().formatted(date: .omitted, time: .shortened)
        return """
        You are Lumen, a supportive wellness companion (sleep, training and nutrition). The person is not technical.
        Style: plain everyday words, no jargon or abbreviations; 2–4 short sentences, then at most 3 bullet points if useful. \
        Be specific to their numbers. Never shame food or body. No diagnoses — if they mention chest pain, fainting, disordered eating \
        or other red flags, urge emergency care if current or sudden, rather than routine coaching.
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
