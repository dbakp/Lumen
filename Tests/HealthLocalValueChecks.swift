import Foundation

enum HealthLocalValueChecks {
    private struct Case {
        let name: String; let domain: HealthLocalFiles.Domain
        let current: Data; let legacy: Data
        let load: (URL, Data?) throws -> Bool
    }
    private static func cases() throws -> [Case] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let legacyEncoder = JSONEncoder(); legacyEncoder.outputFormatting = [.sortedKeys]
        func row<T: Codable>(_ value: T, _ domain: HealthLocalFiles.Domain, _ name: String) throws -> Case {
            Case(name: name, domain: domain, current: try encoder.encode(value), legacy: try legacyEncoder.encode(value),
                 load: { root, old in try HealthLocalFiles.read(T.self, domain: domain, from: root, legacy: { old }).value != nil })
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let water = HydrationLog(id: "synthetic-water", date: date, ml: 137)
        var badWater = water; badWater.ml = -1
        var largeWater = water; largeWater.ml = 10001
        let food = FoodItem(id: "synthetic-food", name: "Synthetic", grams: 100, calories: 200, proteinG: 10, carbsG: 20, fatG: 3, fiberG: 2)
        var negativeFood = food; negativeFood.calories = -1
        var uncertainFood = food; uncertainFood.confidence = 2
        let meal = Meal(id: "synthetic-meal", date: date, type: .lunch, items: [food])
        let workout = Workout(id: "synthetic-workout", kind: .walk, title: "Synthetic", start: date, duration: 600, activeCalories: 20, source: .manual)
        var negativeWorkout = workout; negativeWorkout.duration = -1
        var badOrigin = workout
        badOrigin.importOrigin = .init(sourceName: "Synthetic", activityType: "Walk", end: date.addingTimeInterval(-1))
        var goals = HealthGoals(); goals.stepGoal = 1e300
        var age = HealthGoals(); age.age = 151
        var day = DayMetrics.empty; day.date = date; day.steps = -1
        var reading = DayMetrics.empty; reading.date = date
        reading.readings = ["water": .init(components: [.init(value: -1, origin: .localLog, source: "Synthetic", start: date, aggregation: .total)])]
        var reversed = DayMetrics.empty; reversed.date = date
        reversed.readings = ["water": .init(components: [.init(value: 137, origin: .localLog, source: "Synthetic", start: date, end: date.addingTimeInterval(-1), aggregation: .total)])]
        return try [
            row([badWater], .water, "negative water"), row([largeWater], .water, "oversized single water log"),
            row([water, water], .water, "duplicate water identities"),
            row([meal, meal], .meals, "duplicate meal identities"),
            row([Meal(id: "synthetic-invalid-meal", date: date, type: .lunch, items: [food, food])], .meals, "duplicate food identities"),
            row([Meal(id: "synthetic-invalid-meal", date: date, type: .lunch, items: [negativeFood])], .meals, "negative meal nutrient"),
            row([Meal(id: "synthetic-invalid-meal", date: date, type: .lunch, items: [uncertainFood])], .meals, "invalid food confidence"),
            row([workout, workout], .workouts, "duplicate workout identities"),
            row([negativeWorkout], .workouts, "negative workout duration"), row([badOrigin], .workouts, "reversed imported workout interval"),
            row(goals, .goals, "unsafe numeric goal"), row(age, .goals, "invalid goal age"),
            row(day, .today, "negative cached total"), row(reading, .today, "negative cached reading component"),
            row(reversed, .today, "reversed cached reading interval")
        ]
    }

    static func baseline(output: URL) throws {
        let fm = FileManager.default, outer = fm.temporaryDirectory.appendingPathComponent("Lumen-local-value-baseline-" + UUID().uuidString)
        try fm.createDirectory(at: outer, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outer) }
        let root = outer.appendingPathComponent("LumenData")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        var accepted: [[String: Any]] = []
        for row in try cases() {
            let file = root.appendingPathComponent(row.domain.rawValue + ".json")
            try row.current.write(to: file)
            let loaded = try row.load(root, nil)
            guard loaded, try Data(contentsOf: file) == row.current else { throw HealthLocalFiles.Failure.invalid }
            accepted.append(["case": row.name, "domain": row.domain.rawValue, "accepted": loaded,
                             "currentBytes": row.current.base64EncodedString(), "legacyBytes": row.legacy.base64EncodedString(), "unchanged": true])
        }
        // Independent real-file baseline: preparation currently retires a good
        // prior health file because only conversations are checked first.
        try fm.removeItem(at: root)
        let previous = root.appendingPathExtension("previous")
        let conversations = try ConversationFiles.encoded([], activeID: nil)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let water = try encoder.encode([HydrationLog(id: "synthetic-prior-water", ml: 137)])
        let goals = try encoder.encode(HealthGoals())
        for folder in [root, previous] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            for (name, data) in conversations { try data.write(to: folder.appendingPathComponent(name)) }
            try water.write(to: folder.appendingPathComponent("water.json"))
            try goals.write(to: folder.appendingPathComponent("goals.json"))
        }
        let damaged = Data("{synthetic damaged current water".utf8)
        try damaged.write(to: root.appendingPathComponent("water.json"))
        let priorBefore = try Data(contentsOf: previous.appendingPathComponent("water.json"))
        let transaction = try ConversationFiles.prepareLinkedChange(["goals.json": goals], into: root)
        let priorLost = !fm.fileExists(atPath: previous.path)
        transaction.discard()
        guard priorLost, try Data(contentsOf: root.appendingPathComponent("water.json")) == damaged else { throw HealthLocalFiles.Failure.invalid }
        let report: [String: Any] = ["status": "pre-repair defects reproduced", "acceptedInvalidCases": accepted,
                                   "acceptedCount": accepted.count,
                                   "previousCopy": ["retiredDuringPreparation": priorLost,
                                                    "goodPreviousWaterBytes": priorBefore.base64EncodedString(), "damagedCurrentWaterBytes": damaged.base64EncodedString(), "currentDamagedRetained": true],
                                   "scope": "Actual Foundation files and unchanged production reader/preparation. Invalid values were accepted; a good previous water copy disappeared during unrelated preparation. Not a repaired/native HealthStore/UI/device pass."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print("REPRODUCED: \(accepted.count) typed invalid current payloads accepted; good previous water retired during unrelated preparation.")
    }

    static func run(output: URL? = nil) throws {
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label); print("PASS: " + label) }
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("Lumen-local-values-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        for row in try cases() {
            let file = root.appendingPathComponent(row.domain.rawValue + ".json")
            try row.current.write(to: file)
            var rejected = false
            do { _ = try row.load(root, nil) } catch { rejected = true }
            let unchanged = try Data(contentsOf: file) == row.current
            check(rejected && unchanged, row.name + " rejects current payload without replacing original bytes")
            try fm.removeItem(at: file)
            rejected = false
            do { _ = try row.load(root, row.legacy) } catch { rejected = true }
            check(rejected && !fm.fileExists(atPath: file.path), row.name + " rejects legacy payload without creating a replacement file")
        }
        if let output {
            let report: [String: Any] = ["status": "passed", "count": checks.count, "checks": checks,
                                        "scope": "Same frozen invalid cases as pre-repair baseline; actual production reader on current and legacy date formats. Healthy/archive/native controls are separate."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }
}
