import Foundation

enum WorkoutReconciliation {
    static func sameSession(_ a: Workout, _ b: Workout) -> Bool {
        if a.id == b.id { return true }
        if let id = a.stravaID, id == b.stravaID { return true }
        // Preserve user-entered sessions. Only reconcile near-identical sessions from external sources.
        guard a.source != .manual, b.source != .manual, a.kind == b.kind else { return false }
        if let left = a.importOrigin, let right = b.importOrigin, left.sourceName == right.sourceName { return false }
        if a.importOrigin == nil && b.importOrigin == nil && a.source == b.source { return false }
        if a.kind == .other {
            guard let aType = a.importOrigin?.activityType, let bType = b.importOrigin?.activityType, aType == bType else { return false }
        }
        return abs(a.start.timeIntervalSince(b.start)) <= 60 && abs(a.duration - b.duration) <= max(60, max(a.duration, b.duration) * 0.03)
    }
    /// A minute index limits comparison work when restoring years of activity history.
    private struct Index {
        var ids: [String: Int] = [:]
        var strava: [Int64: Int] = [:]
        var minutes: [Int: Set<Int>] = [:]
        func minute(_ date: Date) -> Int? {
            let value = date.timeIntervalSince1970
            guard value.isFinite, abs(value) < 1e12 else { return nil }
            return Int(floor(value / 60))
        }
        mutating func insert(_ workout: Workout, at index: Int) {
            ids[workout.id] = index
            if let id = workout.stravaID { strava[id] = index }
            if let key = minute(workout.start) { minutes[key, default: []].insert(index) }
        }
        func match(_ workout: Workout, in records: [Workout]) -> Int? {
            if let index = ids[workout.id] { return index }
            if let id = workout.stravaID, let index = strava[id] { return index }
            guard let minute = minute(workout.start) else { return nil }
            for key in (minute - 1)...(minute + 1) {
                for index in (minutes[key] ?? []).sorted() where WorkoutReconciliation.sameSession(records[index], workout) { return index }
            }
            return nil
        }
    }
    static func merge(_ incoming: [Workout], into current: [Workout], preferExisting: Bool = false) -> [Workout] {
        var result = current
        var index = Index()
        for (i, workout) in current.enumerated() { index.insert(workout, at: i) }
        for workout in incoming {
            if let i = index.match(workout, in: result) {
                // Live source records take priority over exported copies. Reimports update imported copies.
                if !preferExisting && (result[i].importOrigin != nil || workout.importOrigin == nil) {
                    result[i] = workout; index.insert(workout, at: i)
                }
            } else { index.insert(workout, at: result.count); result.append(workout) }
        }
        return result.sorted { $0.start < $1.start }
    }
    static func matches(_ incoming: [Workout], current: [Workout]) -> Int {
        var index = Index()
        for (i, workout) in current.enumerated() { index.insert(workout, at: i) }
        return incoming.filter { index.match($0, in: current) != nil }.count
    }
}
