import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI brain: Apple Intelligence first, no sign-in, no keys.
// Order: Private Cloud Compute (larger model, vision) → on-device model →
// the user's own OpenAI key (optional, Settings → Advanced) → built-in rules.

@MainActor
public final class AIService: ObservableObject {
    public static let shared = AIService()

    public enum Brain: Equatable {
        case privateCloud, onDevice, openAIKey, builtIn
        public var label: String {
            switch self {
            case .privateCloud: return "Apple Intelligence"
            case .onDevice: return "Apple Intelligence · on-device"
            case .openAIKey: return "OpenAI (your key)"
            case .builtIn: return "Built-in coach"
            }
        }
        public var detail: String {
            switch self {
            case .privateCloud: return "Private Cloud Compute — Apple can't see your data. No sign-in needed."
            case .onDevice: return "Runs entirely on this iPhone. No sign-in needed."
            case .openAIKey: return "Answers come from OpenAI using the key you added."
            case .builtIn: return "Turn on Apple Intelligence in iOS Settings for smarter answers and photo recognition."
            }
        }
        public var isAI: Bool { self != .builtIn }
    }

    @Published public var isWorking = false

    /// User opted to route through their own OpenAI key instead of Apple Intelligence.
    public var preferOpenAI: Bool {
        get { UserDefaults.standard.bool(forKey: "lumen.ai.preferOpenAI") }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.ai.preferOpenAI"); objectWillChange.send() }
    }

    public var brain: Brain {
        if preferOpenAI && LLMClient.isConfigured() { return .openAIKey }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *), PrivateCloudComputeLanguageModel().isAvailable { return .privateCloud }
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable { return .onDevice }
        #endif
        if LLMClient.isConfigured() { return .openAIKey }
        return .builtIn
    }

    /// Photo recognition needs a model with vision.
    public var canSeePhotos: Bool {
        switch brain {
        case .openAIKey: return true
        case .builtIn: return false
        case .privateCloud, .onDevice:
            #if canImport(FoundationModels)
            if #available(iOS 27.0, *) {
                if brain == .privateCloud { return PrivateCloudComputeLanguageModel().capabilities.contains(.vision) }
                return SystemLanguageModel.default.capabilities.contains(.vision)
            }
            #endif
            return false
        }
    }

    /// Can estimate a meal from a typed description.
    public var canReadDescriptions: Bool { brain.isAI }

    // MARK: Chat

    public func chat(instructions: String, history: [ChatMessage], user: String) async -> String? {
        isWorking = true; defer { isWorking = false }
        let transcript = history.suffix(10).map { ($0.role == .user ? "User: " : "Coach: ") + $0.text }.joined(separator: "\n")
        let fullInstructions = instructions + (transcript.isEmpty ? "" : "\n\nConversation so far:\n" + transcript)
        switch brain {
        case .openAIKey:
            let h = history.suffix(12).map { (role: $0.role == .user ? "user" : "assistant", text: $0.text) }
            return await LLMClient.coachChat(system: instructions, history: h, userText: user)
        case .privateCloud, .onDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard let session = makeSession(instructions: fullInstructions) else { return nil }
                return try? await session.respond(to: user).content
            }
            #endif
            return nil
        case .builtIn:
            return nil
        }
    }

    // MARK: Meals

    public func analyzeMeal(image: UIImage) async -> MealAnalysis? {
        isWorking = true; defer { isWorking = false }
        switch brain {
        case .openAIKey:
            guard let data = image.jpegData(compressionQuality: 0.6) else { return nil }
            return await NutritionEngine.shared.analyzeWithLLM(imageData: data)
        case .privateCloud, .onDevice:
            #if canImport(FoundationModels)
            if #available(iOS 27.0, *), canSeePhotos, let cg = image.cgImage,
               let session = makeSession(instructions: Self.mealInstructions) {
                let orientation = CGImagePropertyOrientation(image.imageOrientation)
                if let guess = try? await session.respond(generating: MealGuess.self, prompt: {
                    "Identify every food and drink on this plate and estimate realistic portions and nutrition."
                    Attachment(cg, orientation: orientation)
                }).content {
                    return guess.analysis
                }
            }
            #endif
            return nil
        case .builtIn:
            return nil
        }
    }

    public func estimateMeal(description: String) async -> MealAnalysis? {
        isWorking = true; defer { isWorking = false }
        switch brain {
        case .openAIKey:
            let prompt = Self.mealInstructions + "\nMeal: \(description)\nReply with JSON only: {\"headline\":..., \"coachingNote\":..., \"items\":[{\"name\":...,\"grams\":...,\"calories\":...,\"proteinG\":...,\"carbsG\":...,\"fatG\":...,\"fiberG\":...}]}"
            guard let text = await LLMClient.simplePrompt(prompt) else { return nil }
            return NutritionEngine.parseMealJSON(text)
        case .privateCloud, .onDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), let session = makeSession(instructions: Self.mealInstructions) {
                if let guess = try? await session.respond(to: "Meal: \(description)", generating: MealGuess.self).content {
                    return guess.analysis
                }
            }
            #endif
            return nil
        case .builtIn:
            return nil
        }
    }

    static let mealInstructions = """
    You are a precise nutrition assistant. Estimate each food's portion in grams and its calories, protein, carbs, fat and fiber. \
    Use typical restaurant/home portions when unsure. Keep names short and plain (e.g. "Grilled chicken breast"). \
    The coaching note is one friendly, practical sentence — never judgmental.
    """

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func makeSession(instructions: String) -> LanguageModelSession? {
        if #available(iOS 27.0, *) {
            let pcc = PrivateCloudComputeLanguageModel()
            if brain == .privateCloud, pcc.isAvailable { return LanguageModelSession(model: pcc, instructions: instructions) }
        }
        guard SystemLanguageModel.default.isAvailable else { return nil }
        return LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "One food item on the plate")
struct FoodGuess {
    @Guide(description: "Short plain name, e.g. 'Brown rice'")
    var name: String
    @Guide(description: "Estimated portion in grams")
    var grams: Int
    var calories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Int
}

@available(iOS 26.0, *)
@Generable(description: "Nutrition estimate for a meal")
struct MealGuess {
    @Guide(description: "A short title for the meal, e.g. 'Salmon, rice and greens'")
    var title: String
    var items: [FoodGuess]
    @Guide(description: "One friendly practical sentence about this meal")
    var coachingNote: String

    var analysis: MealAnalysis? {
        let foods = items.map { FoodItem(name: $0.name, grams: Double($0.grams), calories: Double($0.calories), proteinG: Double($0.proteinG),
                                         carbsG: Double($0.carbsG), fatG: Double($0.fatG), fiberG: Double($0.fiberG), confidence: 0.85) }
        guard !foods.isEmpty else { return nil }
        let kcal = foods.reduce(0) { $0 + $1.calories }
        return MealAnalysis(items: foods, totalCalories: kcal, headline: title, coachingNote: coachingNote, needsReview: true)
    }
}
#endif

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up; case .down: self = .down; case .left: self = .left; case .right: self = .right
        case .upMirrored: self = .upMirrored; case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored; case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
