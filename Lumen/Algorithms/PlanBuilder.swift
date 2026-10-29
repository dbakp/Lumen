import Foundation

public enum PlanBuilder {
    public static func isRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.range(of: #"\b(no plan|don’t|don't|do not|not asking for)\b"#, options: .regularExpression) != nil { return false }
        return t.range(of: #"^\s*plan\b|\b(make|create|build|draft|write|suggest|give|need|want|help|please|can|could)\b.*\b(plan|routine|schedule)\b"#, options: .regularExpression) != nil
    }
    public static func steps(from text: String) -> [PlanStep] {
        let lines = text.components(separatedBy: .newlines)
        let numbered = #"^\s*\d+[.)]\s+"#
        let bullets = #"^\s*[-•*]\s+(?:\[[ xX]\]\s*)?"#
        // Evidence is often bulleted before numbered actions. Only the actions become tasks.
        let pattern = lines.contains { $0.range(of: numbered, options: .regularExpression) != nil } ? numbered : bullets
        let items = lines.compactMap { line -> String? in
            guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
            let title = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
        if items.isEmpty { return [PlanStep(title: "Review and adapt this draft"), PlanStep(title: "Check in after trying it")] }
        return Array(items.prefix(14)).map { PlanStep(title: $0) }
    }
}
