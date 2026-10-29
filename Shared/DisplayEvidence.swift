import Foundation

/// Presence is carried by dictionary keys, including an explicitly recorded zero.
/// This packet describes a phone snapshot, not a new measurement made by a companion.
public struct DisplayEvidence: Codable, Equatable, Sendable {
    public var day: Date
    public var capturedAt: Date
    public var values: [String: Double]
    public var estimates: Set<String>
    public init(day: Date, capturedAt: Date, values: [String: Double], estimates: Set<String> = []) {
        self.day = day; self.capturedAt = capturedAt; self.values = values; self.estimates = estimates
    }
    public static let widgetKey = "widget.evidence.v1"
    public func isCurrent(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        [day, capturedAt, now].allSatisfy { $0.timeIntervalSince1970.isFinite }
        && capturedAt <= now.addingTimeInterval(60)
        && calendar.isDate(day, inSameDayAs: now)
        && calendar.isDate(capturedAt, inSameDayAs: day)
    }
    public func value(_ key: String, at now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard isCurrent(at: now, calendar: calendar), let value = values[key], value.isFinite,
              value >= 0, value < Double(Int.max / 2) else { return nil }
        if ["sleep", "sleepDebt"].contains(key), value > Double(Int.max / 2) / 3600 { return nil }
        return value
    }
    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data?) -> Self? { data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } }
}

public enum EvidenceFormat {
    public static func number(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < Double(Int.max / 2) else { return "Not recorded" }
        if value > 0 && value < 0.01 { return "<0.01" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
    public static func amount(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite, value >= 0, value < Double(Int.max / 2) else { return "Not recorded" }
        return number(value) + (unit.isEmpty ? "" : " " + unit)
    }
}

public enum StandHourEvidence {
    public struct Event: Sendable {
        public var start: Date
        public var stood: Bool
        public init(start: Date, stood: Bool) { self.start = start; self.stood = stood }
    }
    public static func count(_ events: [Event], start: Date, end: Date, calendar: Calendar = .current) -> Double? {
        let recorded = events.filter { $0.start.timeIntervalSince1970.isFinite && $0.start >= start && $0.start <= end }
        guard !recorded.isEmpty else { return nil }
        return Double(Set(recorded.filter(\.stood).compactMap { calendar.dateInterval(of: .hour, for: $0.start)?.start }).count)
    }
}
