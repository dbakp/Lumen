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
            detail: debtH < 1 ? "Rested — bank it." : debtH < 5 ? "\(String(format: "%.1f", debtH))h debt is costing focus." : "\(String(format: "%.1f", debtH))h debt — recovery day wins."))

        // HRV vs implied baseline (uses absolute zones when no history).
        if let hrv = metrics.hrvMS {
            let (d, msg): (Int, String)
            switch hrv {
            case 80...: (d, msg) = (6, "HRV high — nervous system is primed.")
            case 50..<80: (d, msg) = (2, "HRV in your productive band.")
            case 35..<50: (d, msg) = (-4, "HRV a touch low — keep intensity easy.")
            default: (d, msg) = (-9, "HRV low — prioritize sleep + easy movement.")
            }
            score += d
            factors.append(.init(id: "hrv", label: "HRV \(Int(hrv)) ms", delta: d, detail: msg))
        }

        // Resting HR.
        if let rhr = metrics.restingHR {
            let (d, msg): (Int, String)
            if rhr <= 55 { (d, msg) = (4, "Resting HR \(Int(rhr)) — efficient recovery.") }
            else if rhr <= 65 { (d, msg) = (1, "Resting HR \(Int(rhr)) — normal.") }
            else if rhr <= 72 { (d, msg) = (-3, "Resting HR \(Int(rhr)) — slightly elevated.") }
            else { (d, msg) = (-7, "Resting HR \(Int(rhr)) — body is working hard. Go easy.") }
            score += d
            factors.append(.init(id: "rhr", label: "Resting HR", delta: d, detail: msg))
        }

        // Yesterday's strain vs today's readiness (avoid stacking red days).
        let yesterdayLoad = workoutsToday.reduce(0) { $0 + $1.activeCalories }
        if yesterdayLoad > 900 {
            score -= 5
            factors.append(.init(id: "strain", label: "Yesterday's load", delta: -5, detail: "Big day yesterday — adaptation happens today."))
        }

        score = min(100, max(5, score))
        let headline: String
        switch score {
        case 85...: headline = "Primed — take on the hard thing."
        case 70..<85: headline = "Ready — a strong, full day."
        case 55..<70: headline = "Steady — moderate wins compound."
        default: headline = "Restore — protect sleep, move gently."
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
            bullets.append("Train hard today — \(readiness?.strainTarget.upperBound ?? 800) kcal window. Hard intervals + strength shine.")
        } else if score >= 70 {
            bullets.append("Do the planned workout at 8/10 effort. Cap it at 60 min so tomorrow stays green.")
        } else if score >= 55 {
            bullets.append("Easy aerobic 20–30 min + walk after meals. Intensity can wait a day.")
        } else {
            bullets.append("No hard training. 15-min walk + stretch. Extra 30 min in bed tonight pays more than any workout.")
        }
        // 2. Fuel prescription from what's logged.
        let proteinLeft = max(0, proteinTarget - Int(protein))
        if proteinLeft > 60 {
            bullets.append("Protein gap: ~\(proteinLeft)g left. Anchor dinner around palm-and-a-half of protein + fiber.")
        } else if proteinLeft > 0 {
            bullets.append("Nearly there — \(proteinLeft)g protein to go. A yogurt or shake closes it.")
        } else {
            bullets.append("Protein target hit. Keep dinner lighter on starch so sleep onset stays fast.")
        }
        // 3. Recovery prescription.
        let waterLeft = max(0, waterTarget - Int(waterML))
        if sleepDebt > 5 * 3600 {
            bullets.append("Debt is high — in bed 30 min earlier tonight, screens dim 2h before. The #1 performance lever.")
        } else if waterLeft > 1200 {
            bullets.append("Hydration gap: ~\(waterLeft) ml. Front-load water now — evening catch-up wrecks sleep.")
        } else {
            bullets.append("Protect the wind-down: dim lights, cool room, same wake time tomorrow ±30 min.")
        }

        let briefing: String
        if score >= 85 { briefing = "Your body is primed. This is a day to be ambitious — train, create, decide." }
        else if score >= 70 { briefing = "A strong day. Spend energy early, coast intelligently in the evening." }
        else if score >= 55 { briefing = "A steady day. Moderate effort everywhere beats heroic effort anywhere." }
        else { briefing = "A restore day. The win is going to bed earlier with low debt — everything else is bonus." }

        let suggestion: String
        if score >= 85 { suggestion = "Hard run / intervals + strength" }
        else if score >= 70 { suggestion = "Planned workout, 8/10 effort" }
        else if score >= 55 { suggestion = "Zone 2 + walk 25 min" }
        else { suggestion = "Walk + mobility only" }

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
            out.append(Insight(icon: "moon.fill", tint: "#8B7CFF", title: "Sleep debt is your limiter",
                body: "Debt of \(String(format: "%.1f", sleepDebt/3600))h drags focus more than any workout boosts it. Earlier bed beats extra coffee — 30 min tonight.",
                action: "See energy schedule"))
        }
        if let hrv = metrics.hrvMS, hrv < 40 {
            out.append(Insight(icon: "waveform.path.ecg", tint: "#FF6B6B", title: "Recovery is dipped",
                body: "HRV \(Int(hrv)) ms is below your productive band. Keep training easy and eat to the full target — under-fueling delays bounce-back.",
                action: "Go easy today"))
        }
        let protein = mealsToday.reduce(0) { $0 + $1.protein }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 15 && protein < Double(goals.proteinTarget()) * 0.5 {
            out.append(Insight(icon: "fork.knife", tint: "#4ADE80", title: "Protein is behind pace",
                body: "You're at \(Int(protein))g of \(goals.proteinTarget())g. A protein-first dinner (\(goals.proteinTarget() - Int(protein))g to go) protects muscle without extra restriction.",
                action: "Log dinner"))
        }
        if metrics.steps > 0 && metrics.steps < goals.stepGoal * 0.5 && hour >= 16 {
            let left = Int(goals.stepGoal - metrics.steps)
            out.append(Insight(icon: "figure.walk", tint: "#22D3EE", title: "A walk closes the gap",
                body: "\(left) steps to goal — a 15-min walk after dinner covers ~1,500 and deepens sleep pressure. Two birds.",
                action: "Take a walk"))
        }
        if !workoutsToday.isEmpty {
            let w = workoutsToday.last!
            out.append(Insight(icon: w.kind.icon, tint: "#FBBF24", title: "\(w.title) logged · \(Int(w.activeCalories)) kcal",
                body: "Nice work. Refuel with 25–40g protein within 2h and keep the evening easy — adaptation happens tonight.",
                action: nil))
        } else if score >= 70 && hour < 18 {
            out.append(Insight(icon: "bolt.fill", tint: "#FBBF24", title: "Your window is open",
                body: "Readiness \(score) + daylight left = perfect training conditions. Even 25 min counts fully toward the ring.",
                action: "Start workout"))
        }
        if metrics.waterML < 1200 && hour >= 14 {
            out.append(Insight(icon: "drop.fill", tint: "#38BDF8", title: "Water before evening",
                body: "Hydration speeds everything — cognition, HRV, sleep onset. Front-load now so you're not up at night.",
                action: "Log water"))
        }
        if out.isEmpty {
            out.append(Insight(icon: "checkmark.seal.fill", tint: "#4ADE80", title: "On track",
                body: "Nothing needs fixing. Protect the routine — same wake, protein-first meals, lights low tonight.",
                action: nil))
        }
        return Array(out.prefix(5))
    }

    // MARK: chat context builder (for ChatCoachService + any LLM)

    public static func contextPrompt(metrics: DayMetrics, readiness: Readiness?, goals: HealthGoals, mealsToday: [Meal], workoutsToday: [Workout], sleepDebt: TimeInterval, debtFile: TimeInterval, history: [ChatMessage]) -> String {
        let eaten = mealsToday.reduce(0) { $0 + $1.calories }
        let protein = mealsToday.reduce(0) { $0 + $1.protein }
        let workoutSummary = workoutsToday.map { "\($0.title) \(Int($0.duration / 60))min" }.joined(separator: ", ")
        return """
        You are Lumen, a kind elite performance coach (exercise physiologist + sleep scientist + dietitian).
        Rules: specific over generic; 2-4 sentences + at most 3 bullets; never shame food or body; no medical diagnosis; if red flags (chest pain, fainting, eating disorder), urge a clinician.
        User context: readiness \(readiness?.score ?? 72) (\(readiness?.headline ?? "")); sleep debt \(String(format: "%.1f", sleepDebt/3600))h; steps \(Int(metrics.steps)); active \(Int(metrics.activeCalories)) kcal / goal \(Int(goals.activeCalGoal)); exercise \(Int(metrics.exerciseMin)) min; RHR \(metrics.restingHR.map { Int($0) } ?? -1); HRV \(metrics.hrvMS.map { Int($0) } ?? -1) ms; eaten \(Int(eaten))/\(goals.calorieTarget()) kcal; protein \(Int(protein))/\(goals.proteinTarget())g; water \(Int(metrics.waterML)) ml; workouts today: \(workoutSummary);
        Answer with what to do next today.
        """
    }
}
