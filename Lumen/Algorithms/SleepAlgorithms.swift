// Rise-parity sleep science algorithms.
// Covers: personalized sleep need, 14-night weighted sleep debt,
// simplified SAFTE / two-process circadian prediction, Energy Potential,
// melatonin window, sleep inertia, and smart bedtime planning.

import Foundation

// MARK: - Sleep need estimation

public struct SleepNeedEstimator {
    /// Estimate personal sleep need from history.
    /// Rise uses ~1yr of phone-use behavior. We approximate with:
    ///  - trimmed median of longer, consistent nights (ad-lib proxy)
    ///  - age adjustment, clamped to observed 5h...11.5h range.
    public static func estimate(
        episodes: [SleepEpisode],
        age: Int? = nil,
        chronotype: Chronotype = .intermediate
    ) -> (need: TimeInterval, confidence: Double) {
        let tail = episodes.suffix(120)
        var durations: [TimeInterval] = []
        durations.reserveCapacity(tail.count)
        for ep in tail {
            let d = ep.duration
            if d >= 4 * 3600 && d <= 13 * 3600 { durations.append(d) }
        }

        guard durations.count >= 5 else {
            return (defaultNeed(age: age), 0.25)
        }

        let sorted = durations.sorted()
        // Trimmed mean of upper half (closest to ad-lib sleep without alarm pressure)
        let upper = Array(sorted.dropFirst(sorted.count / 2))
        let medianUpper = median(upper)
        let overallMedian = median(sorted)

        // Blend: 65% ad-lib proxy + 35% overall median — stable, not inflated.
        var need = medianUpper * 0.65 + overallMedian * 0.35

        // Consistency bonus: very regular sleepers get a slightly tighter need.
        let sd = standardDeviation(sorted)
        if sd < 45 * 60 { need -= 5 * 60 }

        // Age adjustment (NSF-ish curve, gentle).
        if let age {
            if age < 18 { need += 30 * 60 }
            else if age > 60 { need -= 15 * 60 }
        }

        need = min(max(need, 5 * 3600), 11.5 * 3600)
        // Round to nearest 5 min.
        need = (need / 300).rounded() * 300

        let confidence = min(0.95, 0.35 + Double(min(durations.count, 60)) / 60 * 0.6)
        return (need, confidence)
    }

    public static func defaultNeed(age: Int?) -> TimeInterval {
        guard let age else { return 8 * 3600 + 10 * 60 } // median RISE user ≈ 8h
        switch age {
        case ..<13: return 9.5 * 3600
        case 13..<18: return 9 * 3600
        case 18..<26: return 8.25 * 3600
        case 26..<65: return 8 * 3600 + 10 * 60
        default: return 7.75 * 3600
        }
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 8 * 3600 }
        let s = values.sorted()
        if s.count % 2 == 1 { return s[s.count / 2] }
        return (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private static func standardDeviation(_ values: [TimeInterval]) -> TimeInterval {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let v = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(v)
    }
}

// MARK: - Sleep debt (14-night weighted, Rise method)

public struct SleepDebtCalculator {
    /// Rise method (publicly described): 14-night window, last night = 15%,
    /// remaining 85% spread over prior 13 nights with recency weighting.
    public static func weights(count: Int = 14) -> [Double] {
        precondition(count >= 1)
        guard count > 1 else { return [1.0] }
        let tau = 4.5
        var tail: [Double] = []
        for i in 1..<count { tail.append(exp(-Double(i) / tau)) }
        let tailSum = tail.reduce(0, +)
        var w: [Double] = [0.15]
        w += tail.map { $0 / tailSum * 0.85 }
        // Renormalize for safety.
        let s = w.reduce(0, +)
        return w.map { $0 / s }
    }

    /// Episodes ordered OLDEST → NEWEST; uses last 14 with actual sleep.
    /// The MOST RECENT night carries 15% (index 13 gets weights[0]).
    /// Missing nights pad as full-need (no contribution).
    /// Oversleep (actual > need) repays debt (negative contribution). Floor at 0.
    public static func debt(
        sleepNeed: TimeInterval,
        recentDurationsOldestFirst: [TimeInterval],
        missingNightAssumption: TimeInterval? = nil
    ) -> TimeInterval {
        let w = weights(count: 14)
        // Take last 14, pad front with missing assumption if short.
        var durs = Array(recentDurationsOldestFirst.suffix(14))
        while durs.count < 14 {
            durs.insert(missingNightAssumption ?? sleepNeed, at: 0)
        }
        var total: TimeInterval = 0
        for (i, dur) in durs.enumerated() {
            // Reverse: durs[13] is last night → w[0] (15%).
            total += w[durs.count - 1 - i] * (sleepNeed - dur)
        }
        // Weights sum to 1 (weighted mean shortfall); scale to an accumulated
        // 14-night figure with dampening 0.55: nightly −1h × 14n ≈ 7.7h debt.
        total = total * 14 * 0.55
        return max(0, total)
    }

    /// Per-night contributions oldest → newest (positive = added debt).
    public static func contributions(
        sleepNeed: TimeInterval,
        recentDurationsOldestFirst: [TimeInterval]
    ) -> [TimeInterval] {
        let w = weights(count: 14)
        var durs = Array(recentDurationsOldestFirst.suffix(14))
        while durs.count < 14 { durs.insert(sleepNeed, at: 0) }
        return durs.enumerated().map { i, dur in w[durs.count - 1 - i] * (sleepNeed - dur) * 14 * 0.55 }
    }
}

// MARK: - Circadian / SAFTE-lite (two-process model)

public struct CircadianPrediction: Sendable {
    public var habitualBedtime: DateComponents // time-of-day
    public var habitualWake: DateComponents
    public var midSleep: Date // tonight reference
    public var dimLightMelatoninOnset: Date
    public var melatoninWindow: ClosedRange<Date>
    public var wakeZone: ClosedRange<Date>
    public var grogginessEnds: Date
    public var morningPeak: Date
    public var middayDip: Date
    public var afternoonPeak: Date
    public var windDown: Date
    public var caffeineCutoff: Date
    public var napDeadline: Date
    public var curve: [EnergyPoint]
    public var chronotype: Chronotype
}

public struct EnergyPoint: Identifiable, Sendable {
    public var id: Double { time }
    public var time: Double // seconds since midnight
    public var energy: Double // 0...1
    public var label: String?
}

public struct CircadianModel {
    /// Predict today's rhythm from recent episodes + wake time.
    /// Inputs: recent episodes (for habitual times), today's wake date, sleep debt.
    public static func predict(
        calendar: Calendar = .current,
        recentEpisodes: [SleepEpisode],
        todayWake: Date,
        sleepDebt: TimeInterval,
        chronotype: Chronotype
    ) -> CircadianPrediction {
        let recent = Array(recentEpisodes.suffix(14))
        let bedSecs = circularMean(recent.map { secondsSinceMidnight($0.bedtime, calendar: calendar) }.filter { $0 >= 0 })
            ?? (23 * 3600 + 30 * 60)
        let wakeSecs = circularMean(recent.map { secondsSinceMidnight($0.wakeTime, calendar: calendar) }.filter { $0 >= 0 })
            ?? secondsSinceMidnight(todayWake, calendar: calendar)

        let startOfDay = calendar.startOfDay(for: todayWake)
        func at(_ secs: Double) -> Date { startOfDay.addingTimeInterval(secs) }

        // Chronotype shift: owls push DLMO later.
        let chronoShift: Double
        switch chronotype {
        case .morning: chronoShift = -30 * 60
        case .intermediate: chronoShift = 0
        case .evening: chronoShift = 45 * 60
        }

        // DLMO ≈ habitual bedtime − 2h (+ chrono shift).
        let dlmoSecs = mod24(bedSecs - 2 * 3600 + chronoShift)

        // Melatonin window: 1h starting at DLMO (best time to fall asleep).
        let melStart = at(dlmoSecs)
        let melWindow = melStart...(melStart.addingTimeInterval(3600))

        let wakeT = todayWake
        // Sleep inertia: 15–90 min from debt + short sleep + waking in melatonin window.
        let lastDuration = recent.last?.duration ?? 8 * 3600
        var inertiaMin = 20.0
        inertiaMin += min(40, (sleepDebt / 3600) * 6)          // +6 min per debt hour, cap 40
        if lastDuration < 6 * 3600 { inertiaMin += 15 }
        if melWindow.contains(wakeT) { inertiaMin += 20 }
        inertiaMin = min(90, max(10, inertiaMin))
        let groggyEnds = wakeT.addingTimeInterval(inertiaMin * 60)

        // Key landmarks relative to wake (classic post-wake curve).
        let morningPeak = wakeT.addingTimeInterval(2.5 * 3600)
        let middayDip = wakeT.addingTimeInterval(7 * 3600)
        let afternoonPeak = wakeT.addingTimeInterval(10 * 3600)
        let windDown = at(dlmoSecs - 3600) // 1h before DLMO: dim lights
        let caffeineCutoff = at(mod24(bedSecs - 10 * 3600))
        let napDeadline = wakeT.addingTimeInterval(8 * 3600)
        let wakeZone = wakeT...(wakeT.addingTimeInterval(30 * 60))

        // Energy curve: circadian sinusoid + homeostatic decay + inertia dip.
        var curve: [EnergyPoint] = []
        let wakeSec = secondsSinceMidnight(wakeT, calendar: calendar)
        // Circadian peak ~ afternoonPeak time.
        let peakSec = secondsSinceMidnight(afternoonPeak, calendar: calendar)
        for m in stride(from: 0, to: 24 * 60, by: 15) {
            let t = Double(m) * 60
            let dt = t - wakeSec
            // Only model wake period (wake → bedtime); night gets low values.
            let hoursAwake = max(0, dt) / 3600
            // Homeostatic pressure builds: H = 1 - exp(-hA/18.2)
            let homeostatic = 1 - exp(-hoursAwake / 18.2)
            // Circadian: cos peaked at peakSec.
            let phase = (t - peakSec) / 86400 * 2 * .pi
            let circ = (cos(phase) + 1) / 2 // 0...1, 1 at peak
            // Dip injection at midday: gaussian dip.
            let dipC = secondsSinceMidnight(middayDip, calendar: calendar)
            let dip = exp(-pow(t - dipC, 2) / (2 * pow(90 * 60, 2))) * 0.18
            var e = circ * 0.72 + (1 - homeostatic) * 0.38 - dip
            // Grogginess ramp in first inertiaMin.
            if dt >= 0 && dt < inertiaMin * 60 {
                e *= 0.45 + 0.55 * (dt / (inertiaMin * 60))
            }
            // Night / asleep region — keep energy low.
            let bedMod = mod24(bedSecs)
            let inAsleepRegion: Bool = {
                if bedMod > wakeSec {
                    // Normal schedule: asleep after bedtime or well before wake.
                    return t < wakeSec - 3600 || t > bedMod + 1800
                } else {
                    // Late-night bedtime wrapping past midnight.
                    return t < wakeSec - 3600 && t > bedMod + 1800
                }
            }()
            if inAsleepRegion {
                e = min(e, 0.18)
            }
            // Debt drags whole curve down.
            e -= min(0.25, (sleepDebt / 3600) * 0.03)
            e = min(1, max(0.03, e))
            curve.append(EnergyPoint(time: t, energy: e))
        }

        func dc(_ secs: Double) -> DateComponents {
            var c = DateComponents()
            let s = Int(mod24(secs))
            c.hour = s / 3600; c.minute = (s % 3600) / 60
            return c
        }

        return CircadianPrediction(
            habitualBedtime: dc(bedSecs),
            habitualWake: dc(wakeSecs),
            midSleep: todayWake,
            dimLightMelatoninOnset: melStart,
            melatoninWindow: melWindow,
            wakeZone: wakeZone,
            grogginessEnds: groggyEnds,
            morningPeak: morningPeak,
            middayDip: middayDip,
            afternoonPeak: afternoonPeak,
            windDown: windDown,
            caffeineCutoff: caffeineCutoff,
            napDeadline: napDeadline,
            curve: curve,
            chronotype: chronotype
        )
    }

    // MARK: helpers

    static func secondsSinceMidnight(_ date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0))
    }

    static func mod24(_ s: Double) -> Double {
        var r = s.truncatingRemainder(dividingBy: 86400)
        if r < 0 { r += 86400 }
        return r
    }

    /// Circular mean for times-of-day.
    static func circularMean(_ secs: [Double]) -> Double? {
        guard !secs.isEmpty else { return nil }
        var sx = 0.0, sy = 0.0
        for s in secs {
            let a = s / 86400 * 2 * .pi
            sx += cos(a); sy += sin(a)
        }
        sx /= Double(secs.count); sy /= Double(secs.count)
        var a = atan2(sy, sx)
        if a < 0 { a += 2 * .pi }
        return a / (2 * .pi) * 86400
    }

    /// Smart bedtime: given wake goal + need + current debt, suggest bedtime tonight.
    /// Shifts earlier max 30 min/night to protect circadian stability.
    public static func suggestedBedtime(
        wakeGoal: Date,
        sleepNeed: TimeInterval,
        sleepDebt: TimeInterval,
        habitualBedtime: Date,
        payExtraMin: Double = 0
    ) -> (bedtime: Date, note: String) {
        // Base: wake − need − sleep latency (15m).
        var target = wakeGoal.addingTimeInterval(-sleepNeed - 15 * 60)
        // If debt > 5h, add up to 60 min extra catch-up.
        if sleepDebt > 5 * 3600 {
            target.addTimeInterval(min(-30 * 60, -(sleepDebt - 5 * 3600) * 0.15))
        }
        target.addTimeInterval(-payExtraMin * 60)
        // Limit advance to 30 min earlier than habitual per night.
        let earliest = habitualBedtime.addingTimeInterval(-30 * 60)
        // Handle day wrap: compare time-of-day.
        if target < earliest && habitualBedtime.timeIntervalSince(target) < 12 * 3600 {
            let fmt = DateFormatter(); fmt.timeStyle = .short
            return (earliest, "Shifting just 30 min earlier tonight to protect your rhythm — consistency pays debt faster than one big crash.")
        }
        if sleepDebt < 3600 {
            return (target, "Right on rhythm. This bedtime protects your low debt.")
        }
        return (target, "This repays debt gradually without wrecking tomorrow's rhythm.")
    }

    /// Sleep inertia (grogginess) estimate in minutes.
    public static func inertiaMinutes(debt: TimeInterval, lastDuration: TimeInterval, wokeInMelatoninWindow: Bool) -> Double {
        var m = 20.0 + min(40, (debt / 3600) * 6)
        if lastDuration < 6 * 3600 { m += 15 }
        if wokeInMelatoninWindow { m += 20 }
        return min(90, max(10, m))
    }

    /// Energy Potential 0–100, tied to debt (like Rise).
    public static func energyPotential(debt: TimeInterval) -> Int {
        let d = debt / 3600
        // 0h → 100, 5h → ~60, 10h → ~30, 15h → ~12
        let score = 100 * exp(-d / 9.5) - max(0, d - 8) * 1.5
        return Int(min(100, max(5, score.rounded())))
    }
}
