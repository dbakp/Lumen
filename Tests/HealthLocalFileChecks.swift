import Foundation

enum HealthLocalFileChecks {
    static func run(output: URL? = nil) throws {
        var checks: [String] = []
        func check(_ value: Bool, _ name: String) {
            precondition(value, name); checks.append(name); print("PASS: " + name)
        }
        func rejects(_ name: String, _ work: () throws -> Void) {
            var rejected = false
            do { try work() } catch { rejected = true }
            check(rejected, name)
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Lumen-health-local-files-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("water.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let record = HydrationLog(id: "synthetic-current-water", date: Date(timeIntervalSince1970: 1_700_000_000), ml: 137)
        let current = try encoder.encode([record])
        let old = try JSONEncoder().encode([record])
        let absent = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root)
        check(absent.value == nil && absent.boundary == .missing(legacy: nil), "actual absent current and legacy establish a new empty domain boundary")
        let migrated = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root, legacy: { old })
        check(migrated.value?.first?.id == record.id && !fm.fileExists(atPath: file.path), "missing current may read default-date legacy without writing a current file")
        try HealthLocalFiles.verify(migrated.boundary, domain: .water, from: root, legacy: { old })
        check(true, "unchanged missing-current legacy boundary remains valid")
        rejects("changed legacy invalidates the loaded model boundary") {
            try HealthLocalFiles.verify(migrated.boundary, domain: .water, from: root, legacy: { Data("[]".utf8) })
        }
        rejects("invalid existing legacy is a failed read, not a new empty domain") {
            _ = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root, legacy: { Data("{broken".utf8) })
        }
        try current.write(to: file)
        var legacyReads = 0
        let loaded = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root, legacy: { legacyReads += 1; return Data("{broken".utf8) })
        check(loaded.value?.first?.id == record.id && loaded.value?.first?.ml == 137 && legacyReads == 0,
              "existing valid current file bypasses even a corrupt legacy value")
        try HealthLocalFiles.verify(loaded.boundary, domain: .water, from: root)
        check(true, "healthy current byte boundary validates without mutation")
        rejects("new current file invalidates a previously missing-current model") {
            try HealthLocalFiles.verify(absent.boundary, domain: .water, from: root)
        }
        try Data("[]".utf8).write(to: file)
        let empty = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root, legacy: { legacyReads += 1; return old })
        check(empty.value?.isEmpty == true && legacyReads == 0, "deliberately empty current history does not resurrect legacy entries")
        rejects("valid replacement data cannot be overwritten using the old loaded boundary") {
            try HealthLocalFiles.verify(loaded.boundary, domain: .water, from: root)
        }
        for (label, data) in [
            ("truncated JSON", Data("{broken".utf8)),
            ("wrong record schema", Data("[{\"ml\":137}]".utf8)),
            ("duplicate object keys", Data("[{\"id\":\"first\",\"id\":\"second\"}]".utf8)),
            ("escaped duplicate keys", Data("[{\"id\":\"first\",\"i\\u0064\":\"second\"}]".utf8)),
            ("wrong root type", Data("{}".utf8))
        ] {
            try data.write(to: file)
            rejects(label + " rejects current read despite valid legacy") {
                _ = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root, legacy: { legacyReads += 1; return old })
            }
            check(try Data(contentsOf: file) == data && legacyReads == 0,
                  label + " retains exact current bytes and never consults legacy")
        }
        try fm.removeItem(at: file)
        rejects("deleting a current file invalidates the old model instead of authorizing legacy fallback") {
            try HealthLocalFiles.verify(loaded.boundary, domain: .water, from: root, legacy: { old })
        }
        try fm.createDirectory(at: file, withIntermediateDirectories: false)
        rejects("non-regular current directory is unreadable and never becomes a legacy migration") {
            _ = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root, legacy: { legacyReads += 1; return old })
        }
        var directory: ObjCBool = false
        check(fm.fileExists(atPath: file.path, isDirectory: &directory) && directory.boolValue && legacyReads == 0,
              "non-regular read retains directory and performs no legacy read")
        try fm.removeItem(at: file)
        let outside = root.appendingPathComponent("untouched-reference.json")
        try current.write(to: outside)
        try fm.createSymbolicLink(at: file, withDestinationURL: outside)
        rejects("symbolic-link current file is not followed or treated as missing") {
            _ = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root, legacy: { old })
        }
        check(try Data(contentsOf: outside) == current, "symlink rejection preserves referenced bytes")
        try fm.removeItem(at: file)
        try current.write(to: file)
        let recovered = try HealthLocalFiles.read([HydrationLog].self, domain: .water, from: root)
        check(recovered.boundary == loaded.boundary && recovered.value?.first?.ml == 137,
              "explicit healthy reload recovers original payload and boundary after file recovery")
        // Independent domains use their own canonical type/date formats.
        let meal = Meal(id: "synthetic-local-file-meal", type: .lunch, items: [])
        let workout = Workout(id: "synthetic-local-file-workout", kind: .walk, title: "Synthetic", start: record.date, duration: 600, activeCalories: 20, source: .manual)
        try encoder.encode([meal]).write(to: root.appendingPathComponent("meals.json"))
        try encoder.encode([workout]).write(to: root.appendingPathComponent("workouts.json"))
        try encoder.encode(HealthGoals()).write(to: root.appendingPathComponent("goals.json"))
        try encoder.encode(DayMetrics.empty).write(to: root.appendingPathComponent("today.json"))
        check(try HealthLocalFiles.read([Meal].self, domain: .meals, from: root).value?.first?.id == meal.id, "healthy meal domain retains original identity")
        check(try HealthLocalFiles.read([Workout].self, domain: .workouts, from: root).value?.first?.id == workout.id, "healthy workout domain retains original identity")
        check(try HealthLocalFiles.read(HealthGoals.self, domain: .goals, from: root).value?.weightKg == 75, "healthy goal domain retains original typed values")
        check(try HealthLocalFiles.read(DayMetrics.self, domain: .today, from: root).value != nil, "healthy daily-cache domain retains existing decoder format")
        if let output {
            let report: [String: Any] = ["status": "passed", "checks": checks, "count": checks.count,
                                        "scope": "Actual Foundation files and production checked reader/boundary. Native HealthStore mutation/UI/device acceptance is separate."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
    }
}
