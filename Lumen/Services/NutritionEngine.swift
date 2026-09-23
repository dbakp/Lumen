import Foundation

// MARK: - NutritionEngine: food search + parsing for AI estimates.
// Photo and description estimates come from AIService. Without AI we never
// pretend to recognise a photo — the user picks from this food list instead.

@MainActor
public final class NutritionEngine: ObservableObject {
    public static let shared = NutritionEngine()
    private init() {}

    /// Typical single servings. Values per serving shown.
    public static let foods: [FoodItem] = [
        f("Espresso", 30, 2, 0, 0, 0), f("Cappuccino", 240, 110, 6, 9, 5), f("Latte (oat milk)", 350, 180, 3, 26, 7),
        f("Orange juice", 250, 110, 2, 26, 0), f("Protein shake", 350, 180, 30, 8, 3, 2), f("Smoothie (fruit)", 400, 250, 4, 55, 2, 5),
        f("Banana", 120, 105, 1, 27, 0, 3), f("Apple", 180, 95, 0, 25, 0, 4), f("Berries", 150, 70, 1, 17, 0, 4), f("Orange", 150, 70, 1, 18, 0, 3),
        f("Greek yogurt", 170, 100, 17, 6, 0), f("Skyr with berries", 250, 190, 20, 24, 1, 3), f("Oatmeal with berries", 320, 310, 11, 58, 6, 9),
        f("Granola with milk", 250, 400, 12, 60, 12, 5), f("Scrambled eggs (2)", 120, 200, 13, 2, 15), f("Boiled egg", 50, 78, 6, 1, 5),
        f("Avocado toast", 180, 320, 8, 30, 19, 8), f("Toast with butter", 60, 190, 4, 22, 9, 2), f("Croissant", 60, 240, 5, 26, 13, 1),
        f("Rye bread with cheese", 90, 230, 12, 20, 11, 4), f("Pancakes (3)", 230, 520, 12, 80, 16, 2),
        f("Chicken breast", 150, 250, 46, 0, 5), f("Salmon fillet", 150, 310, 34, 0, 20), f("Steak", 200, 500, 50, 0, 32),
        f("Tofu", 150, 180, 20, 4, 10, 2), f("Tuna (can)", 120, 130, 28, 0, 1), f("Meatballs (6)", 180, 400, 26, 10, 28, 1),
        f("White rice", 180, 230, 4, 50, 0, 1), f("Brown rice", 180, 220, 5, 46, 2, 3), f("Pasta", 200, 310, 11, 62, 2, 3),
        f("Potatoes", 200, 170, 4, 38, 0, 4), f("Sweet potato", 200, 180, 4, 41, 0, 6), f("Quinoa", 180, 220, 8, 39, 4, 5),
        f("Mixed salad", 200, 90, 3, 10, 5, 4), f("Roasted vegetables", 200, 150, 4, 18, 7, 6), f("Broccoli", 150, 50, 4, 10, 0, 4),
        f("Chicken Caesar salad", 350, 480, 36, 18, 30, 4), f("Poke bowl", 450, 600, 32, 70, 20, 6), f("Burrito bowl", 450, 640, 40, 60, 20, 9),
        f("Chicken wrap", 300, 520, 32, 48, 20, 4), f("Club sandwich", 300, 600, 32, 45, 32, 3), f("Burger", 250, 600, 30, 42, 33, 2),
        f("Fries", 150, 470, 5, 60, 23, 5), f("Pizza (2 slices)", 250, 570, 24, 66, 22, 4), f("Sushi (8 pieces)", 280, 400, 16, 70, 5, 3),
        f("Pad thai", 400, 620, 24, 80, 22, 4), f("Chicken curry with rice", 450, 700, 36, 80, 24, 5), f("Lasagna", 350, 600, 32, 45, 32, 4),
        f("Spaghetti bolognese", 400, 620, 32, 75, 20, 5), f("Soup (vegetable)", 350, 150, 5, 22, 4, 5), f("Ramen", 550, 550, 22, 70, 18, 4),
        f("Hummus with veg", 150, 220, 7, 18, 14, 6), f("Nuts (handful)", 30, 180, 6, 6, 16, 3), f("Protein bar", 60, 210, 20, 22, 7, 5),
        f("Dark chocolate (4 squares)", 40, 220, 3, 17, 16, 4), f("Ice cream (2 scoops)", 130, 280, 5, 32, 15, 1), f("Cookie", 40, 200, 2, 26, 10, 1),
        f("Glass of wine", 150, 125, 0, 4, 0), f("Beer", 330, 150, 1, 13, 0), f("Soda", 330, 140, 0, 35, 0),
    ]

    private static func f(_ name: String, _ g: Double, _ kcal: Double, _ p: Double, _ c: Double, _ fat: Double, _ fiber: Double = 0) -> FoodItem {
        FoodItem(id: "food-\(name)", name: name, grams: g, calories: kcal, proteinG: p, carbsG: c, fatG: fat, fiberG: fiber, confidence: 1)
    }

    public static func quickAdds() -> [FoodItem] { Array(foods.prefix(12)) }

    public func search(_ query: String, recent: [FoodItem] = []) -> [FoodItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        let pool = (recent + Self.foods).filter { seen.insert($0.name.lowercased()).inserted }
        if q.isEmpty { return Array(pool.prefix(30)) }
        return pool.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: OpenAI-key vision path

    func analyzeWithLLM(imageData: Data) async -> MealAnalysis? {
        guard let content = await LLMClient.visionMealJSON(imageData: imageData) else { return nil }
        return Self.parseMealJSON(content)
    }

    static func parseMealJSON(_ text: String) -> MealAnalysis? {
        guard let inner = extractJSON(text)?.data(using: .utf8),
              let meal = try? JSONSerialization.jsonObject(with: inner) as? [String: Any],
              let itemsJSON = meal["items"] as? [[String: Any]] else { return nil }
        func num(_ d: [String: Any], _ k: String) -> Double {
            if let v = d[k] as? Double { return v }
            if let v = d[k] as? Int { return Double(v) }
            if let v = d[k] as? String { return Double(v) ?? 0 }
            return 0
        }
        let items = itemsJSON.map { d in
            FoodItem(name: d["name"] as? String ?? "Food", grams: num(d, "grams") == 0 ? 200 : num(d, "grams"), calories: num(d, "calories"),
                     proteinG: num(d, "proteinG"), carbsG: num(d, "carbsG"), fatG: num(d, "fatG"), fiberG: num(d, "fiberG"), confidence: 0.85)
        }
        guard !items.isEmpty else { return nil }
        let kcal = items.reduce(0) { $0 + $1.calories }
        return MealAnalysis(items: items, totalCalories: kcal, headline: (meal["headline"] as? String) ?? items.map(\.name).joined(separator: ", "),
                            coachingNote: (meal["coachingNote"] as? String) ?? "", needsReview: true)
    }

    /// Tolerate markdown fences around the JSON payload.
    static func extractJSON(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("{") { return t }
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") { return String(t[start...end]) }
        return nil
    }
}
