import Foundation

public struct HealthImportPreview: Sendable {
    public var days: [ImportedHealthDay]
    public var samples: Int
    public var skipped: Int
    public var sourceNames: [String]
}

public enum HealthImportError: LocalizedError {
    case unsupported, malformed(String), empty, tooLarge, portableTooLarge
    public var errorDescription: String? {
        switch self {
        case .unsupported: return "Choose Apple Health export.xml, a Lumen metrics CSV, or a metrics JSON file. Unzip the Apple Health export first."
        case .malformed(let message): return "The file could not be read. \(message)"
        case .empty: return "No supported measurements were found. Check the metric names, units and dates."
        case .portableTooLarge: return "CSV and JSON imports support up to 25 MB. Split this export into smaller files, then import them separately."
        case .tooLarge: return "This file exceeds the 500 MB import limit. Export a smaller date range."
        }
    }
}

/// Parsing runs away from the UI. XML uses a stream rather than loading the export into memory.
public enum HealthImportService {
    public static let units: [String: String] = ["steps":"count", "activeEnergy":"kcal", "exercise":"min", "sleep":"h", "restingHR":"bpm", "hrv":"ms", "weight":"kg", "water":"ml", "calories":"kcal", "protein":"g", "carbs":"g", "fat":"g"]
    public static func parse(url: URL, control: HealthImportControl = HealthImportControl(), progress: @escaping @Sendable (Int) -> Void = { _ in }) throws -> HealthImportPreview {
        try control.checkCancellation()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 500_000_000 else {
            if ["csv", "json"].contains(url.pathExtension.lowercased()) { throw HealthImportError.portableTooLarge }
            throw HealthImportError.tooLarge
        }
        let collector = Collector(control: control, progress: progress)
        switch url.pathExtension.lowercased() {
        case "xml":
            guard let stream = InputStream(url: url) else { throw HealthImportError.malformed("The file is unavailable.") }
            let parser = XMLParser(stream: stream)
            parser.shouldResolveExternalEntities = false
            parser.delegate = collector
            guard parser.parse() else {
                try control.checkCancellation()
                throw HealthImportError.malformed(parser.parserError?.localizedDescription ?? "Invalid XML.")
            }
        case "csv":
            guard size < 25_000_000 else { throw HealthImportError.portableTooLarge }
            let text = try String(contentsOf: url, encoding: .utf8)
            let rows = try csvRows(text, control: control)
            guard let header = rows.first else { throw HealthImportError.empty }
            let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard Set(["date", "metric", "value", "unit"]).isSubset(of: Set(names)), Set(names).count == names.count else {
                throw HealthImportError.malformed("CSV needs unique date,metric,value,unit columns; source is optional.")
            }
            for row in rows.dropFirst() where !row.allSatisfy(\.isEmpty) {
                try control.record(progress)
                guard row.count == names.count else { collector.skipped += 1; continue }
                let fields = Dictionary(uniqueKeysWithValues: zip(names, row))
                collector.portable(fields)
            }
        case "json":
            guard size < 25_000_000 else { throw HealthImportError.portableTooLarge }
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard let rows = object as? [[String: Any]] else { throw HealthImportError.malformed("JSON must be an array of metric objects.") }
            for row in rows {
                try control.record(progress)
                collector.portable(row.mapValues { String(describing: $0) })
            }
        default: throw HealthImportError.unsupported
        }
        try control.checkCancellation()
        progress(control.recordsProcessed)
        return try collector.preview()
    }

    /// RFC 4180 quoting, including commas, escaped quotes and newlines in quoted fields.
    static func csvRows(_ text: String, control: HealthImportControl? = nil) throws -> [[String]] {
        try control?.checkCancellation()
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{feff}", with: ""))
        var i = 0
        while i < chars.count {
            if i.isMultiple(of: 4096) { try control?.checkCancellation() }
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if c == "\n" && !quoted { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw HealthImportError.malformed("An unterminated CSV quote was found.") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

private final class Collector: NSObject, XMLParserDelegate {
    let control: HealthImportControl
    let progress: @Sendable (Int) -> Void
    init(control: HealthImportControl, progress: @escaping @Sendable (Int) -> Void) {
        self.control = control; self.progress = progress
    }
    struct Key: Hashable { var day: Date; var metric: String; var source: String }
    struct Bucket { var sum = 0.0; var count = 0; var latestDate = Date.distantPast; var latest = 0.0; var intervals: [DateInterval] = [] }
    var buckets: [Key: Bucket] = [:]
    var samples = 0, skipped = 0
    var seen = Set<String>()
    let appleDate: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"; return f }()
    let dayDate: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f }()
    let iso = ISO8601DateFormatter()
    let map = ["HKQuantityTypeIdentifierStepCount":"steps", "HKQuantityTypeIdentifierActiveEnergyBurned":"activeEnergy", "HKQuantityTypeIdentifierAppleExerciseTime":"exercise", "HKQuantityTypeIdentifierRestingHeartRate":"restingHR", "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":"hrv", "HKQuantityTypeIdentifierBodyMass":"weight", "HKQuantityTypeIdentifierDietaryWater":"water", "HKQuantityTypeIdentifierDietaryEnergyConsumed":"calories", "HKQuantityTypeIdentifierDietaryProtein":"protein", "HKQuantityTypeIdentifierDietaryCarbohydrates":"carbs", "HKQuantityTypeIdentifierDietaryFatTotal":"fat"]
    func date(_ s: String) -> Date? {
        if let d = iso.date(from: s) ?? appleDate.date(from: s) { return d }
        if s.count == 10, let d = dayDate.date(from: s), dayDate.string(from: d) == s { return d }
        return nil
    }
    func portable(_ fields: [String: String]) {
        guard let ds = fields["date"], let d = date(ds), let metric = fields["metric"], let raw = fields["value"], let v = Double(raw), let unit = fields["unit"] else { skipped += 1; return }
        add(metric: metric, value: v, unit: unit, start: d, end: d, source: fields["source"] ?? "Imported file")
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String : String] = [:]) {
        do { try control.checkCancellation() } catch { parser.abortParsing(); return }
        guard elementName == "Record" else { return }
        do { try control.record(progress) } catch { parser.abortParsing(); return }
        guard let type = a["type"], let ds = a["startDate"], let start = date(ds), let de = a["endDate"], let end = date(de), end >= start else { skipped += 1; return }
        let source = a["sourceName"] ?? "Apple Health export"
        if type == "HKCategoryTypeIdentifierSleepAnalysis" {
            let value = a["value"] ?? ""
            guard value.contains("Asleep") else { skipped += 1; return }
            let seconds = end.timeIntervalSince(start)
            guard seconds > 0, seconds < 24 * 3600 else { skipped += 1; return }
            add(metric: "sleep", value: seconds / 3600, unit: "h", start: start, end: end, source: source, sleep: true)
        } else if let metric = map[type], let raw = a["value"], let value = Double(raw) {
            add(metric: metric, value: value, unit: a["unit"] ?? "", start: start, end: end, source: source)
        } else { skipped += 1 }
    }
    func add(metric: String, value raw: Double, unit: String, start: Date, end: Date, source: String, sleep: Bool = false) {
        guard let expected = HealthImportService.units[metric], raw.isFinite, raw >= 0, start <= Date().addingTimeInterval(60) else { skipped += 1; return }
        var value = raw
        if unit != expected {
            switch (metric, unit) {
            case ("water", "L"): value *= 1000
            case ("weight", "lb"): value *= 0.45359237
            case ("weight", "g"): value /= 1000
            case ("hrv", "s"): value *= 1000
            case ("restingHR", "count/min"): break
            case ("sleep", "min"): value /= 60
            case ("sleep", "s"): value /= 3600
            case ("calories", "kJ"), ("activeEnergy", "kJ"): value /= 4.184
            default: skipped += 1; return
            }
        }
        let limits: [String: Double] = ["sleep":24, "restingHR":300, "hrv":5000, "weight":700, "water":30000, "steps":300000, "activeEnergy":30000, "exercise":1440, "calories":50000, "protein":5000, "carbs":10000, "fat":5000]
        guard value <= (limits[metric] ?? .greatestFiniteMagnitude) else { skipped += 1; return }
        let fingerprint = "\(metric)|\(source)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(value)"
        guard seen.insert(fingerprint).inserted else { skipped += 1; return }
        let key = Key(day: Calendar.current.startOfDay(for: sleep ? end : start), metric: metric, source: source)
        var b = buckets[key] ?? Bucket()
        b.sum += value; b.count += 1
        if start >= b.latestDate { b.latestDate = start; b.latest = value }
        if sleep { b.intervals.append(DateInterval(start: start, end: end)) }
        buckets[key] = b; samples += 1
    }
    func preview() throws -> HealthImportPreview {
        try control.checkCancellation()
        guard !buckets.isEmpty else { throw HealthImportError.empty }
        var chosen: [Date: [String: (String, Bucket)]] = [:]
        // One source per metric per day: never sum two devices that observed the same activity.
        for (key, bucket) in buckets {
            try control.checkCancellation()
            let old = chosen[key.day]?[key.metric]
            if old == nil || bucket.count > old!.1.count || (bucket.count == old!.1.count && key.source < old!.0) {
                chosen[key.day, default: [:]][key.metric] = (key.source, bucket)
            }
        }
        let days = try chosen.map { day, metrics in
            try control.checkCancellation()
            var values: [String: Double] = [:], sources: [String: String] = [:]
            for (metric, pair) in metrics {
                let (source, b) = pair
                var value = b.sum
                if metric == "restingHR" || metric == "hrv" { value /= Double(b.count) }
                if metric == "weight" { value = b.latest }
                if metric == "sleep", !b.intervals.isEmpty {
                    var union: [DateInterval] = []
                    for interval in b.intervals.sorted(by: { $0.start < $1.start }) {
                        try control.checkCancellation()
                        if let last = union.last, interval.start <= last.end {
                            union[union.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
                        } else { union.append(interval) }
                    }
                    value = union.reduce(0) { $0 + $1.duration } / 3600
                }
                values[metric] = value; sources[metric] = source
            }
            return ImportedHealthDay(date: day, values: values, sources: sources)
        }.sorted { $0.date < $1.date }
        try control.checkCancellation()
        return HealthImportPreview(days: days, samples: samples, skipped: skipped, sourceNames: Array(Set(buckets.keys.map(\.source))).sorted())
    }
}
