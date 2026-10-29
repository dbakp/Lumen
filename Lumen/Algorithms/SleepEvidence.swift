import Foundation

/// Describes recorded entries without filling calendar gaps or treating time in bed as measured sleep.
public enum SleepEvidence {
    public struct Recent: Sendable {
        public var entries: [SleepEpisode]
        public var recordedDays: Int
        public var meanDuration: TimeInterval? { entries.isEmpty ? nil : entries.reduce(0) { $0 + $1.duration } / Double(entries.count) }
    }
    public static func usable(_ episode: SleepEpisode, now: Date = Date()) -> Bool {
        episode.bedtime.timeIntervalSince1970.isFinite && episode.wakeTime.timeIntervalSince1970.isFinite
        && episode.wakeTime <= now && episode.bedtime < episode.wakeTime
        && episode.duration.isFinite && episode.duration > 0
        && episode.duration <= episode.timeInBed + 1
    }
    public static func latest(_ episodes: [SleepEpisode], now: Date = Date()) -> SleepEpisode? {
        episodes.filter { usable($0, now: now) }.max { $0.wakeTime < $1.wakeTime }
    }
    public static func today(_ episodes: [SleepEpisode], now: Date = Date(), calendar: Calendar = .current) -> SleepEpisode? {
        episodes.filter { usable($0, now: now) && calendar.isDate($0.wakeTime, inSameDayAs: now) }.max { $0.wakeTime < $1.wakeTime }
    }
    public static func recent(_ episodes: [SleepEpisode], days: Int = 7, now: Date = Date(), calendar: Calendar = .current) -> Recent {
        let start = calendar.date(byAdding: .day, value: 1 - max(1, days), to: calendar.startOfDay(for: now)) ?? now
        let entries = episodes.filter { usable($0, now: now) && $0.wakeTime >= start }.sorted { $0.wakeTime < $1.wakeTime }
        return .init(entries: entries, recordedDays: Set(entries.map { calendar.startOfDay(for: $0.wakeTime) }).count)
    }
    /// Circular spread avoids treating 23:55 and 00:05 as twelve hours apart.
    public static func wakeSpread(_ episodes: [SleepEpisode], now: Date = Date(), calendar: Calendar = .current) -> TimeInterval? {
        let recent = recent(episodes, now: now, calendar: calendar)
        guard recent.recordedDays >= 2 else { return nil }
        let seconds = recent.entries.map { CircadianModel.secondsSinceMidnight($0.wakeTime, calendar: calendar) }
        let angles = seconds.map { $0 / 86400 * 2 * Double.pi }
        let x = angles.reduce(0) { $0 + cos($1) }, y = angles.reduce(0) { $0 + sin($1) }
        guard hypot(x, y) / Double(angles.count) > 0.0001 else { return nil }
        let mean = atan2(y, x)
        let deviations = angles.map { atan2(sin($0 - mean), cos($0 - mean)) / (2 * Double.pi) * 86400 }
        return sqrt(deviations.reduce(0) { $0 + $1 * $1 } / Double(deviations.count))
    }
    public static func needEstimationEntries(_ episodes: [SleepEpisode], now: Date = Date(), calendar: Calendar = .current) -> [SleepEpisode] {
        let recent = recent(episodes, days: 120, now: now, calendar: calendar).entries.filter { $0.source == .wearable && $0.asleepSeconds != nil && (4 * 3600...13 * 3600).contains($0.duration) }
        guard Set(recent.map { calendar.startOfDay(for: $0.wakeTime) }).count >= 5 else { return [] }
        return recent
    }
    public static func predictionEntries(_ episodes: [SleepEpisode], now: Date = Date(), calendar: Calendar = .current) -> [SleepEpisode] {
        let recent = recent(episodes, days: 14, now: now, calendar: calendar)
        guard today(episodes, now: now, calendar: calendar) != nil, recent.recordedDays >= 3 else { return [] }
        return recent.entries
    }
}
