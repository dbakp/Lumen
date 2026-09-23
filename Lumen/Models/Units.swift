import Foundation

// MARK: - Unit formatting (metric / imperial, user choice)

public enum Units {
    public static func weight(_ kg: Double, _ system: UnitSystem, decimals: Int = 1) -> String {
        switch system {
        case .metric: return String(format: "%.\(decimals)f kg", kg)
        case .imperial: return String(format: "%.\(decimals)f lb", kg * 2.20462)
        }
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
        case .metric: return ml >= 1000 ? String(format: "%.1f L", ml / 1000) : "\(Int(ml)) ml"
        case .imperial: return String(format: "%.0f fl oz", ml / 29.5735)
        }
    }

    public static func kgFromLb(_ lb: Double) -> Double { lb / 2.20462 }
    public static func lbFromKg(_ kg: Double) -> Double { kg * 2.20462 }
}
