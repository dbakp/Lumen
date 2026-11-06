import Foundation

/// Fresh operation-owned raw values. Overlapping requests each return their own
/// observations; only the current source/request/day can publish or install.
@MainActor
final class HealthTodayReadCoordinator {
    enum Failure: Error { case unavailable, changed }
    struct Request: Sendable {
        let id: UUID
        let source: UUID
        let start: Date
        let end: Date
        let calendar: String
        let timeZone: String
        let queries: HealthReadingQueryGroup
    }
    struct Readings: Sendable {
        let request: Request
        let raw: HealthDailyCache.RawReadings
    }
    struct Selection: Sendable {
        fileprivate let source: UUID
        fileprivate let latest: UUID?
        let day: Date
        fileprivate let capturedAt: Date
        fileprivate let calendar: String
        fileprivate let timeZone: String
        fileprivate let available: Bool
        func matchesSourceAndDay(_ other: Selection) -> Bool {
            source == other.source && day == other.day && calendar == other.calendar
                && timeZone == other.timeZone && available == other.available
        }
    }
    private var source = UUID()
    private var latest: UUID?
    private var active: [UUID: HealthReadingQueryGroup] = [:]

    /// Clear has no query result, but still belongs to the current source,
    /// request selection, availability and day. Disconnected clear is explicit.
    func captureSelection(available: Bool, now: Date = Date(), calendar: Calendar = .current) -> Selection {
        Selection(source: source, latest: latest, day: calendar.startOfDay(for: now), capturedAt: now,
                  calendar: String(describing: calendar.identifier), timeZone: calendar.timeZone.identifier, available: available)
    }

    func isCurrent(_ selection: Selection, available: Bool, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !Task.isCancelled && selection.source == source && selection.latest == latest && selection.available == available
            && selection.calendar == String(describing: calendar.identifier) && selection.timeZone == calendar.timeZone.identifier
            && selection.day == calendar.startOfDay(for: now) && selection.capturedAt <= now
    }

    func read(available: Bool, now: Date = Date(), calendar: Calendar = .current,
              query: @escaping @Sendable (String, Date, Date, HealthReadingQueryGroup) async throws -> HealthMetricReading) async throws -> Readings {
        guard available else { throw Failure.unavailable }
        let request = Request(id: UUID(), source: source, start: calendar.startOfDay(for: now), end: now,
                              calendar: String(describing: calendar.identifier), timeZone: calendar.timeZone.identifier,
                              queries: HealthReadingQueryGroup())
        latest = request.id; active[request.id] = request.queries
        defer { active.removeValue(forKey: request.id) }
        return try await withTaskCancellationHandler {
            try request.queries.checkCancellation()
            let observations = try await withThrowingTaskGroup(of: (String, HealthMetricReading).self) { group in
                for key in HealthDailyCache.queryKeys {
                    group.addTask {
                        try request.queries.checkCancellation()
                        return (key, try await query(key, request.start, request.end, request.queries))
                    }
                }
                var readings: [String: HealthMetricReading] = [:]
                for try await (key, reading) in group { readings[key] = reading }
                return readings
            }
            try request.queries.checkCancellation()
            return Readings(request: request, raw: try HealthDailyCache.rawReadings(observations, start: request.start, end: request.end))
        } onCancel: { request.queries.cancel() }
    }

    func isCurrent(_ readings: Readings, available: Bool, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let request = readings.request
        return !Task.isCancelled && available && !request.queries.isCancelled && request.source == source && latest == request.id
            && request.calendar == String(describing: calendar.identifier) && request.timeZone == calendar.timeZone.identifier
            && request.start == calendar.startOfDay(for: now) && request.end <= now
    }

    func invalidate() {
        source = UUID(); latest = nil
        let requests = Array(active.values); active = [:]
        requests.forEach { $0.cancel() }
    }
}
