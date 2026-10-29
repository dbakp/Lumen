import Foundation

// MARK: - Unit formatting (metric / imperial, user choice)

public enum Units {
    public static func weight(_ kg: Double, _ system: UnitSystem, decimals: Int = 1) -> String {
        let value = system == .metric ? kg : kg * 2.20462
        guard value.isFinite, value >= 0 else { return "Not recorded" }
        let precision = min(4, max(0, decimals)), threshold = pow(10.0, -Double(precision))
        let amount = value > 0 && value < threshold ? "<" + threshold.formatted(.number.precision(.fractionLength(precision))) : value.formatted(.number.precision(.fractionLength(precision)))
        return amount + (system == .metric ? " kg" : " lb")
    }

    public static func height(_ cm: Double, _ system: UnitSystem) -> String {
        switch system {
        case .metric: return "\(Int(cm.rounded())) cm"
        case .imperial:
            let totalIn = Int((cm / 2.54).rounded())
            return "\(totalIn / 12)′ \(totalIn % 12)″"
        }
    }

    public static func distance(_ meters: Double, _ system: UnitSystem) -> String {
        switch system {
        case .metric: return String(format: "%.1f km", meters / 1000)
        case .imperial: return String(format: "%.1f mi", meters / 1609.34)
        }
    }

    public static func water(_ ml: Double, _ system: UnitSystem) -> String {
        switch system {
        case .metric: return ml >= 1000 ? EvidenceFormat.amount(ml / 1000, unit: "L") : EvidenceFormat.amount(ml, unit: "ml")
        case .imperial: return EvidenceFormat.amount(ml / 29.5735, unit: "fl oz")
        }
    }

    public static func kgFromLb(_ lb: Double) -> Double { lb / 2.20462 }
    public static func lbFromKg(_ kg: Double) -> Double { kg * 2.20462 }
}
