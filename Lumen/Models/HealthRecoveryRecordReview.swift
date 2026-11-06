import Foundation

/// Read-only typed inspection. Decode once, format only the selected record or
/// child page; a large meal/reading must not eagerly create every detail row.
enum HealthRecoveryRecordReview {
    struct Field: Sendable, Equatable {
        let label: String
        let value: String
        init(_ label: String, _ value: String) { self.label = label; self.value = value }
    }
    enum Document: Sendable {
        case water([HydrationLog]), meals([Meal]), workouts([Workout]), goals(HealthGoals), today(DayMetrics)
        static func decode(_ data: Data, domain: HealthLocalFiles.Domain, control: BackupOperationControl? = nil) throws -> Self {
            try HealthLocalFiles.validateCurrentData(data, domain: domain, control: control)
            let decoder = BackupArchive.decoder()
            let document: Self
            switch domain {
            case .water: document = .water(try decoder.decode([HydrationLog].self, from: data))
            case .meals: document = .meals(try decoder.decode([Meal].self, from: data))
            case .workouts: document = .workouts(try decoder.decode([Workout].self, from: data))
            case .goals: document = .goals(try decoder.decode(HealthGoals.self, from: data))
            case .today: document = .today(try decoder.decode(DayMetrics.self, from: data))
            }
            try control?.checkCancellation()
            return document
        }
        var count: Int {
            switch self { case .water(let a): a.count; case .meals(let a): a.count; case .workouts(let a): a.count; case .goals, .today: 1 }
        }
        func page(at index: Int) -> Page? {
            guard index >= 0, index < count else { return nil }
            switch self {
            case .water(let a): return .water(a[index])
            case .meals(let a): return .meal(a[index])
            case .workouts(let a): return .workout(a[index])
            case .goals(let a): return .goals(a)
            case .today(let a): return .day(a)
            }
        }
    }
    enum Page: Sendable {
        case water(HydrationLog), meal(Meal), food(FoodItem), workout(Workout), goals(HealthGoals), day(DayMetrics)
        case metric(String, DayMetrics), component(String, HealthMetricComponent), query(HealthMetricQuery)
        case origin(HealthLogOrigin), imported(WorkoutImportOrigin), workoutMetadata(Workout), cache(DayMetrics), photo(String), text(String, String)

        var title: String {
            switch self {
            case .water(let a): return a.ml.formatted() + " mL"
            case .meal(let a): return a.type.label + " · " + a.calories.formatted() + " kcal"
            case .food(let a): return a.name.isEmpty ? "Food entry" : a.name
            case .workout(let a): return a.title.isEmpty ? "Workout" : a.title
            case .goals: return "Saved targets"
            case .day: return "Saved daily readings"
            case .metric(let key, _): return HealthMetricCatalog.labels[key] ?? key
            case .component(_, let a): return a.source.isEmpty ? "Source component" : a.source
            case .query: return "Health check"
            case .origin: return "Conversation origin"
            case .imported: return "Import details"
            case .workoutMetadata: return "Saved workout metadata"
            case .cache: return "Saved cache metadata"
            case .photo: return "Meal photo"
            case .text(let title, _): return title
            }
        }
        var subtitle: String {
            switch self {
            case .water(let a): return date(a.date)
            case .meal(let a): return date(a.date)
            case .workout(let a): return date(a.start) + "\n" + a.energyDescription
            case .day(let a): return date(a.date)
            case .metric(let key, let day):
                guard let value = metricValue(key, day) else { return "No reading" }
                return (day.readings?[key]?.isEstimate == true ? "About " : "") + amount(value, HealthMetricCatalog.units[key] ?? "")
            case .food(let a): return amount(a.grams, "g")
            case .component(let key, let a): return (a.isEstimate ? "About " : "") + amount(a.value, HealthMetricCatalog.units[key] ?? "")
            default: return ""
            }
        }
        var fields: [Field] {
            switch self {
            case .water(let a):
                return [.init("Amount", amount(a.ml, "mL")), .init("Recorded at", date(a.date)), .init("Note", savedText(a.note)), .init("Last edited", date(a.lastEditedAt)), .init("Record ID", a.id)]
            case .meal(let a):
                return [.init("Meal", a.type.label), .init("Recorded at", date(a.date)), .init("Food energy", amount(a.calories, "kcal")), .init("Protein", amount(a.protein, "g")), .init("Carbohydrates", amount(a.carbs, "g")), .init("Fat", amount(a.fat, "g")), .init("Fibre", amount(a.fiber, "g")), .init("Source", a.source.label), .init("Note", savedText(a.note)), .init("Photo reference", savedText(a.photoID)), .init("Record ID", a.id)]
            case .food(let a):
                return [.init("Name", savedText(a.name)), .init("Amount", amount(a.grams, "g")), .init("Food energy", amount(a.calories, "kcal")), .init("Protein", amount(a.proteinG, "g")), .init("Carbohydrates", amount(a.carbsG, "g")), .init("Fat", amount(a.fatG, "g")), .init("Fibre", amount(a.fiberG, "g")), .init("Saved confidence score", number(a.confidence)), .init("Food ID", a.id)]
            case .workout(let a):
                return [.init("Title", savedText(a.title)), .init("Activity", a.kind.label), .init("Started at", date(a.start)), .init("Duration", amount(a.duration, "seconds")), .init("Active energy", a.energyDescription), .init("Distance", amount(a.distanceM, "m")), .init("Average heart rate", amount(a.avgHR, "bpm")), .init("Source", a.sourceDescription), .init("Note", savedText(a.note)), .init("Last edited", date(a.lastEditedAt))]
            case .workoutMetadata(let a):
                return [.init("Source category", a.source.label), .init("Strava ID", a.stravaID.map(String.init) ?? "Not provided"), .init("Route data", savedText(a.polyline)), .init("Stored energy value", amount(a.activeCalories, "kcal")), .init("Energy provided", yesNo(a.energyKnown)), .init("Energy estimate flag", yesNo(a.energyIsEstimate)), .init("Record ID", a.id)]
            case .goals(let a):
                return [.init("Steps", amount(a.stepGoal, "steps")), .init("Active energy", amount(a.activeCalGoal, "kcal")), .init("Exercise", amount(a.exerciseGoalMin, "min")), .init("Stand or roll", "\(a.standGoal) hours"), .init("Weight", amount(a.weightKg, "kg")), .init("Height", amount(a.heightCm, "cm")), .init("Age", a.age.map(String.init) ?? "Not provided"), .init("Sex", a.sex == .unspecified ? "Not specified" : a.sex.rawValue.capitalized), .init("Activity", a.activityLevel.label), .init("Goal", a.goal.label)]
            case .day(let a): return [.init("Saved day", date(a.date))]
            case .metric(let key, let day):
                let reading = day.readings?[key]
                return [.init("Saved value", subtitle), .init("Saved day", date(day.date)), .init("Source", reading.map { $0.components.isEmpty ? "No source components" : $0.sourceLabel } ?? (metricValue(key, day) == nil ? "Not recorded" : "Legacy cache; original source not recorded")), .init("Overlapping sources", reading.map { $0.overlapKeptSeparate ? "Kept separate" : "Not marked" } ?? "Not recorded")]
            case .component(let key, let a):
                return [.init("Value", amount(a.value, HealthMetricCatalog.units[key] ?? "")), .init("Source", savedText(a.source)), .init("Source type", originLabel(a.origin)), .init("Aggregation", aggregationLabel(a.aggregation)), .init("Period starts", date(a.start)), .init("Period ends", date(a.end)), .init("Latest sample", date(a.lastSampleAt)), .init("Checked at", date(a.checkedAt)), .init("Estimate", yesNo(a.isEstimate))]
            case .query(let a):
                let outcome: String
                switch a.outcome { case .recorded: outcome = "Samples found"; case .noData: outcome = "No samples returned"; case .failed: outcome = "Check failed" }
                return [.init("Outcome", outcome), .init("Period starts", date(a.start)), .init("Period ends", date(a.end)), .init("Checked at", date(a.checkedAt))]
            case .origin(let a):
                return [.init("Confirmed at", date(a.confirmedAt)), .init("Statement", savedText(a.statement)), .init("Prepared by", savedText(a.preparedBy)), .init("Conversation ID", savedText(a.conversationID)), .init("Message ID", savedText(a.messageID))]
            case .imported(let a):
                return [.init("Source", savedText(a.sourceName)), .init("Activity type", savedText(a.activityType)), .init("Ended at", date(a.end)), .init("Filename", savedText(a.filename)), .init("Duration reported", yesNo(a.durationWasReported)), .init("Import warnings", a.warnings.map { String($0.count) } ?? "Not recorded")]
            case .cache(let a):
                return [.init("Saved day", date(a.date)), .init("Stored steps", amount(a.steps, "steps")), .init("Stored active energy", amount(a.activeCalories, "kcal")), .init("Stored resting energy", amount(a.restingCalories, "kcal")), .init("Stored exercise", amount(a.exerciseMin, "min")), .init("Stored stand or roll", "\(a.standHours) hours"), .init("Stored average heart rate", amount(a.avgHR, "bpm")), .init("Stored resting heart rate", amount(a.restingHR, "bpm")), .init("Stored heart rate variability", amount(a.hrvMS, "ms")), .init("Stored breathing rate", amount(a.respiratoryRate, "breaths/min")), .init("Stored oxygen saturation", amount(a.spo2, "%")), .init("Stored VO₂ max", amount(a.vo2max, "ml/kg/min")), .init("Stored weight", amount(a.weightKg, "kg")), .init("Stored sleep", amount(a.sleepSeconds, "seconds")), .init("Stored food energy", amount(a.dietaryCalories, "kcal")), .init("Stored protein", amount(a.dietaryProtein, "g")), .init("Stored carbohydrates", amount(a.dietaryCarbs, "g")), .init("Stored fat", amount(a.dietaryFat, "g")), .init("Stored water", amount(a.waterML, "mL")), .init("Lumen nutrition excluded", yesNo(a.excludesLumenNutrition)), .init("Totals marked present", a.recordedTotalKeys.map { $0.isEmpty ? "None" : $0.sorted().joined(separator: ", ") } ?? "Not recorded"), .init("Reading metadata", a.readings.map { "\($0.count) metrics" } ?? "Not recorded")]
            case .photo(let id): return [.init("Photo reference", id)]
            case .text(_, let value): return [.init("Text", savedText(value))]
            }
        }
        var footer: String? {
            switch self {
            case .food: return "This is a saved estimate score, not a measure of accuracy."
            case .cache: return "Stored zeros can mean no reading. The daily readings show which values were recorded."
            case .workoutMetadata: return "The stored energy value can be zero when no energy was provided."
            default: return nil
            }
        }
        var childCount: Int {
            switch self {
            case .water(let a): return a.logOrigin == nil ? 0 : 1
            case .meal(let a): return a.items.count + (a.photoID == nil ? 0 : 1)
            case .workout(let a): return (a.logOrigin == nil ? 0 : 1) + (a.importOrigin == nil ? 0 : 1) + 1
            case .day(let a): return metricKeys(a).count + 1
            case .metric(let key, let a): return (a.readings?[key]?.components.count ?? 0) + (a.readings?[key]?.healthQuery == nil ? 0 : 1)
            case .imported(let a): return a.warnings?.count ?? 0
            default: return 0
            }
        }
        func child(at index: Int) -> Page? {
            guard index >= 0, index < childCount else { return nil }
            switch self {
            case .water(let a): return a.logOrigin.map(Page.origin)
            case .meal(let a): return index < a.items.count ? .food(a.items[index]) : a.photoID.map(Page.photo)
            case .workout(let a):
                if let origin = a.logOrigin, index == 0 { return .origin(origin) }
                if let imported = a.importOrigin, index == (a.logOrigin == nil ? 0 : 1) { return .imported(imported) }
                return .workoutMetadata(a)
            case .day(let a):
                let keys = metricKeys(a); return index < keys.count ? .metric(keys[index], a) : .cache(a)
            case .metric(let key, let a):
                guard let reading = a.readings?[key] else { return nil }
                return index < reading.components.count ? .component(key, reading.components[index]) : reading.healthQuery.map(Page.query)
            case .imported(let a): return a.warnings.map { .text("Import warning \(index + 1)", $0[index]) }
            default: return nil
            }
        }
    }

    static func metricValue(_ key: String, _ day: DayMetrics) -> Double? {
        if let reading = day.readings?[key] { return reading.value }
        if DayMetrics.cumulativeKeys.contains(key) { return day.recordedTotal(key) }
        switch key {
        case "sleep": return day.sleepSeconds.map { $0 / 3600 }
        case "heartRate": return day.avgHR
        case "restingHR": return day.restingHR
        case "hrv": return day.hrvMS
        case "respiratoryRate": return day.respiratoryRate
        case "spo2": return day.spo2
        case "vo2max": return day.vo2max
        case "weight": return day.weightKg
        case "calories": return day.dietaryCalories
        case "protein": return day.dietaryProtein
        case "carbs": return day.dietaryCarbs
        case "fat": return day.dietaryFat
        default: return nil
        }
    }
    private static func metricKeys(_ day: DayMetrics) -> [String] {
        HealthMetricCatalog.keys + Set((day.readings ?? [:]).keys).union(day.recordedTotalKeys ?? []).subtracting(HealthMetricCatalog.keys).sorted()
    }
    private static func number(_ value: Double) -> String {
        let string = String(value)
        let exact = string.hasSuffix(".0") ? String(string.dropLast(2)) : string
        return exact.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
    private static func amount(_ value: Double?, _ unit: String) -> String {
        value.map { number($0) + (unit.isEmpty ? "" : " " + unit) } ?? "Not provided"
    }
    private static func savedText(_ value: String?) -> String { value.map { $0.isEmpty ? "Empty text" : $0 } ?? "Not provided" }
    private static func yesNo(_ value: Bool?) -> String { value.map { $0 ? "Yes" : "No" } ?? "Not recorded" }
    private static func date(_ value: Date?) -> String {
        guard let value else { return "Not provided" }
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .long
        return formatter.string(from: value)
    }
    private static func originLabel(_ origin: HealthMetricComponent.Origin) -> String {
        switch origin { case .healthKit: "Apple Health"; case .healthImport: "Health import"; case .localLog: "Local log"; case .sleepHistory: "Sleep history"; case .legacyCache: "Legacy cache" }
    }
    private static func aggregationLabel(_ aggregation: HealthMetricComponent.Aggregation) -> String {
        switch aggregation { case .total: "Total"; case .average: "Average"; case .latest: "Latest value"; case .reportedDay: "Reported day" }
    }
}
