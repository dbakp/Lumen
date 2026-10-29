import Foundation

/// Canonical storage units and recorded-day summaries. No ranges here imply a clinical assessment.
enum ImportedMetrics {
    static let labels = ["sleep":"Sleep", "steps":"Steps", "exercise":"Exercise", "activeEnergy":"Active energy", "restingHR":"Resting heart rate", "hrv":"Heart rate variability", "water":"Water logged", "weight":"Weight", "heartRate":"Heart rate", "respiratoryRate":"Breathing rate", "spo2":"Oxygen saturation", "vo2max":"VO₂ max", "bodyFat":"Body fat", "bmi":"Body mass index"]
    static let evidenceKeys = ["sleep", "steps", "exercise", "activeEnergy", "restingHR", "hrv", "water", "weight", "heartRate", "respiratoryRate", "spo2", "vo2max", "bodyFat", "bmi"]
    static func displayUnit(_ key: String) -> String { key == "bmi" ? "" : HealthImportService.units[key] ?? "" }
    static let percentageKeys: Set<String> = ["spo2", "bodyFat"]
    static let meanKeys: Set<String> = ["restingHR", "hrv", "heartRate", "respiratoryRate", "spo2", "vo2max", "bodyFat", "bmi"]
    static let explanations = [
        "heartRate": "Mean of recorded heart-rate samples on each day. Readings can cluster around exercise; this is not a resting-heart-rate measure.",
        "respiratoryRate": "Mean of recorded breathing-rate samples on each day, in breaths per minute. Device and measurement conditions can differ.",
        "spo2": "Mean of recorded oxygen-saturation samples on each day. These are source readings, not a continuous monitor or a diagnosis.",
        "vo2max": "Mean of recorded VO₂ max values on each day. Wearable estimates and lab measurements can use different methods.",
        "bodyFat": "Mean of recorded body-fat percentages on each day. Measurement methods and devices can differ.",
        "bmi": "Mean of recorded body mass index values on each day. This is a recorded body measurement, not an assessment of your health."
    ]
}
