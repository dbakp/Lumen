import Foundation

public enum HealthHistorySummary {
    /// Bounded summaries give the assistant historical context without uploading raw exports.
    /// Averages use recorded days only; gaps are reported, never silently filled with zero.
    public static func summarize(_ days: [ImportedHealthDay], now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let first = days.map(\.date).min(), let last = days.map(\.date).max() else { return "No imported history." }
        var lines = ["Imported coverage: \(days.count) recorded days, \(first.formatted(date: .abbreviated, time: .omitted)) through \(last.formatted(date: .abbreviated, time: .omitted))."]
        for window in [7, 30, 90, 365] {
            let start = calendar.date(byAdding: .day, value: -(window - 1), to: calendar.startOfDay(for: now))!
            let selected = days.filter { $0.date >= start && $0.date <= now }
            guard !selected.isEmpty else { continue }
            lines.append("Last \(window) days: \(selected.count) days with any imported readings. Per metric, mean of recorded days only:")
            for key in HealthImportService.units.keys.sorted() {
                let values = selected.compactMap { $0.values[key] }
                guard !values.isEmpty else { continue }
                let mean = values.reduce(0, +) / Double(values.count)
                lines.append("\(key): \(String(format: "%.1f", mean)) \(HealthImportService.units[key]!) mean; \(values.count)/\(window) days; range \(String(format: "%.1f", values.min()!))–\(String(format: "%.1f", values.max()!)).")
            }
        }
        if days.contains(where: { $0.values.keys.contains(where: { ImportedMetrics.meanKeys.contains($0) }) }) {
            lines.append("Discrete health signals are arithmetic sample means per day from one selected source, not continuous readings. Heart rate is distinct from resting heart rate. Devices and measurement conditions can differ; do not infer a diagnosis or cause.")
        }
        return lines.joined(separator: "\n")
    }
}
