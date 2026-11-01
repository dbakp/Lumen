import Foundation
import FoundationModels

@main struct AvailabilityProbe {
    static func main() throws {
        var result: [String: Any] = ["operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
                                     "scope": "Read-only local SystemLanguageModel availability; no inference, cloud request or settings change."]
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available: result["availability"] = "available"
            case .unavailable(let reason):
                result["availability"] = "unavailable"
                switch reason {
                case .deviceNotEligible: result["reason"] = "deviceNotEligible"
                case .appleIntelligenceNotEnabled: result["reason"] = "appleIntelligenceNotEnabled"
                case .modelNotReady: result["reason"] = "modelNotReady"
                @unknown default: result["reason"] = "unknown"
                }
            }
            result["supportsEnglish"] = model.supportsLocale(Locale(identifier: "en_US"))
            result["contextTokens"] = model.contextSize
        } else { result["availability"] = "unsupportedOperatingSystem" }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
