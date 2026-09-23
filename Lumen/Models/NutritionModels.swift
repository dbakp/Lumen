import Foundation

public enum MealType: String, Codable, Sendable, CaseIterable {
    case breakfast, lunch, dinner, snack
    public var label: String { rawValue.capitalized }
    public static func forHour(_ h: Int) -> MealType {
        switch h { case 5..<11: return .breakfast; case 11..<15: return .lunch; case 17..<22: return .dinner; default: return .snack }
    }
}

public struct FoodItem: Identifiable, Codable, Sendable {
    public var id: String
    public var name: String
    public var grams: Double
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double
    public var confidence: Double
    public init(id: String = UUID().uuidString, name: String, grams: Double, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double = 0, confidence: Double = 0.8) {
        self.id = id; self.name = name; self.grams = grams; self.calories = calories
        self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.fiberG = fiberG; self.confidence = confidence
    }
}

public struct Meal: Identifiable, Codable, Sendable {
    public var id: String
    public var date: Date
    public var type: MealType
    public var items: [FoodItem]
    public var photoID: String?
    public var note: String?
    public var source: HealthSource
    public init(id: String = UUID().uuidString, date: Date = Date(), type: MealType, items: [FoodItem], photoID: String? = nil, note: String? = nil, source: HealthSource = .manual) {
        self.id = id; self.date = date; self.type = type; self.items = items
        self.photoID = photoID; self.note = note; self.source = source
    }
    public var calories: Double { items.reduce(0) { $0 + $1.calories } }
    public var protein: Double { items.reduce(0) { $0 + $1.proteinG } }
    public var carbs: Double { items.reduce(0) { $0 + $1.carbsG } }
    public var fat: Double { items.reduce(0) { $0 + $1.fatG } }
    public var fiber: Double { items.reduce(0) { $0 + $1.fiberG } }
}

public struct HydrationLog: Identifiable, Codable, Sendable {
    public var id: String
    public var date: Date
    public var ml: Double
    public init(id: String = UUID().uuidString, date: Date = Date(), ml: Double) {
        self.id = id; self.date = date; self.ml = ml
    }
}

public struct MealAnalysis: Sendable {
    public var items: [FoodItem]
    public var totalCalories: Double
    public var headline: String
    public var coachingNote: String
    public var needsReview: Bool
}

public struct ChatMessage: Identifiable, Codable, Sendable {
    public var id: String
    public var role: Role
    public var text: String
    public var date: Date
    public enum Role: String, Codable, Sendable { case user, coach }
    public init(id: String = UUID().uuidString, role: Role, text: String, date: Date = Date()) {
        self.id = id; self.role = role; self.text = text; self.date = date
    }
}

public struct Insight: Identifiable, Sendable {
    public var id: String
    public var icon: String
    public var tint: String
    public var title: String
    public var body: String
    public var action: String?
    public init(id: String = UUID().uuidString, icon: String, tint: String, title: String, body: String, action: String? = nil) {
        self.id = id; self.icon = icon; self.tint = tint; self.title = title; self.body = body; self.action = action
    }
}
