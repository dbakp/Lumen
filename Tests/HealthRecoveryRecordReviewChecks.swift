import Foundation
import CryptoKit

enum HealthRecoveryRecordReviewChecks {
    static func run(output: URL? = nil) throws {
        typealias Review = HealthRecoveryRecordReview
        let fm = FileManager.default
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = repo.appendingPathComponent("Design/native/health-write-order/health-record-baseline-r1-outcome.json")
        let fixture = try Data(contentsOf: fixtureURL)
        let audit = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
        let files = audit["files"] as! [String: [String: Any]]
        func bytes(_ path: String) -> Data { Data(base64Encoded: files[path]!["base64"] as! String)! }
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label); print("PASS: " + label) }
        func field(_ page: Review.Page, _ label: String) -> String? { page.fields.first { $0.label == label }?.value }
        func localized(_ value: String) -> String { value.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".") }
        func children(_ page: Review.Page) -> [Review.Page] { (0..<page.childCount).compactMap { page.child(at: $0) } }
        func rejects(_ label: String, _ work: () throws -> Void) { var failed = false; do { try work() } catch { failed = true }; check(failed, label) }
        let decoder = BackupArchive.decoder(), encoder = BackupArchive.encoder()
        let water = try Review.Document.decode(bytes("previous/water.json"), domain: .water)
        let meals = try Review.Document.decode(bytes("previous/meals.json"), domain: .meals)
        let workouts = try Review.Document.decode(bytes("previous/workouts.json"), domain: .workouts)
        let goals = try Review.Document.decode(bytes("previous/goals.json"), domain: .goals)
        let daily = try Review.Document.decode(bytes("previous/today.json"), domain: .today)
        check([water.count, meals.count, workouts.count, goals.count, daily.count] == [2,2,2,1,1], "review decodes exact native baseline bytes across all five domains with actual two-record lists")
        check(water.page(at: -1) == nil && water.page(at: 2) == nil, "out-of-range review navigation cannot access another record")
        let empty = try Review.Document.decode(Data("[]".utf8), domain: .water)
        check(empty.count == 0 && empty.page(at: 0) == nil, "valid empty history remains a zero-record document")
        rejects("damaged records cannot enter typed recovery review") { _ = try Review.Document.decode(bytes("current/water.json"), domain: .water) }
        var invalid = HealthGoals(); invalid.stepGoal = -1
        rejects("typed recovery review applies semantic validation before presenting goals") { _ = try Review.Document.decode(encoder.encode(invalid), domain: .goals) }
        let w = water.page(at: 0)!
        check(w.title == "137 mL" && field(w, "Amount") == "137 mL", "water list and full detail retain the actual amount")
        check(field(w, "Record ID") == "synthetic-detailed-water" && field(w, "Note") == "Synthetic water note for complete record review.", "water inspection exposes saved identity and complete note")
        check(field(w, "Last edited") != "Not provided" && w.childCount == 1, "water retains edited time and optional conversation origin")
        let origin = w.child(at: 0)!
        check(field(origin, "Statement") == "I drank 137 ml of water." && field(origin, "Conversation ID") == "synthetic-review-conversation" && field(origin, "Message ID") == "synthetic-review-message", "conversation provenance retains the actual statement and both source identities")
        check(field(origin, "Prepared by") == "Local draft" && field(origin, "Confirmed at") != "Not provided", "conversation preparation and confirmation remain visible")
        check(water.page(at: 1)!.childCount == 0 && field(water.page(at: 1)!, "Note") == "Not provided", "missing water note and origin stay explicitly absent")
        let unknown = workouts.page(at: 0)!, zero = workouts.page(at: 1)!
        let originalWorkouts = try decoder.decode([Workout].self, from: bytes("previous/workouts.json"))
        let unknownMetadata = Review.Page.workoutMetadata(originalWorkouts[0]), zeroMetadata = Review.Page.workoutMetadata(originalWorkouts[1])
        check(unknown.subtitle.contains("Energy not provided") && !unknown.subtitle.contains("0 kcal"), "actual native unknown-energy baseline becomes unknown rather than recorded zero")
        check(zero.subtitle.contains("0 kcal") && !zero.subtitle.contains("About"), "actual native explicitly recorded zero remains zero rather than missing or estimated")
        check(field(unknown, "Active energy") == "Energy not provided" && field(unknownMetadata, "Energy provided") == "No", "workout detail applies the saved energy-presence flag")
        var legacy = try decoder.decode([Workout].self, from: bytes("previous/workouts.json"))[0]
        legacy.energyKnown = nil; legacy.energyIsEstimate = nil
        check(Review.Page.workout(legacy).subtitle.contains("Energy not provided"), "legacy zero without presence is not a measurement")
        legacy.activeCalories = 123.25
        check(Review.Page.workout(legacy).subtitle.contains(localized("About 123.25 kcal")), "legacy nonzero manual energy keeps the established estimate semantics")
        legacy.source = .healthKit; legacy.energyKnown = true; legacy.energyIsEstimate = false
        check(Review.Page.workout(legacy).subtitle.contains(localized("123.25 kcal")) && !Review.Page.workout(legacy).subtitle.contains("About"), "supplied non-estimated workout energy is not relabeled an estimate")
        check(field(zero, "Distance") == "0 m" && field(zero, "Average heart rate") == localized("94.5 bpm"), "optional known-zero distance and heart rate retain their exact values and units")
        check(field(zeroMetadata, "Strava ID") == "123456" && field(zeroMetadata, "Route data") == "synthetic-route-data" && field(zero, "Last edited") != "Not provided", "workout identifiers, route and edited time are inspectable")
        let imported = zero.child(at: 0)!
        check(field(imported, "Filename") == "synthetic-health-export.zip" && field(imported, "Source") == "Synthetic export source" && field(imported, "Duration reported") == "Yes", "workout import filename/source/duration provenance is retained")
        check(field(imported.child(at: 0)!, "Text") == "Synthetic import warning." && field(imported, "Ended at") != "Not provided", "import warnings and actual end time are inspectable")
        let meal = meals.page(at: 0)!
        check(meal.childCount == 3 && meals.page(at: 1)!.childCount == 2, "shared-photo meals expose each actual food item and one photo reference")
        let food = meal.child(at: 0)!
        check(field(food, "Amount") == "125 g" && field(food, "Protein") == localized("20.25 g") && field(food, "Carbohydrates") == localized("3.5 g") && field(food, "Fat") == localized("10.75 g") && field(food, "Fibre") == localized("1.5 g"), "food detail preserves grams and every nutrient instead of names only")
        check(field(food, "Saved confidence score") == localized("0.84") && field(food, "Food ID") == "synthetic-tofu", "saved food confidence remains a score with its original identity")
        check(food.footer?.contains("not a measure of accuracy") == true && field(meal, "Photo reference") == "synthetic-review-photo", "food confidence is not presented as calibrated accuracy and photo identity stays visible")
        let g = goals.page(at: 0)!
        check(["Weight","Height","Age"].allSatisfy { field(g, $0) == "Not provided" }, "missing target body fields remain missing rather than default measurements")
        check(g.fields.count == 10 && field(g, "Sex") == "Not specified", "all target fields, including unspecified sex, are inspectable")
        let day = daily.page(at: 0)!
        let metrics = children(day)
        let steps = metrics.first { $0.title == "Steps" }!, waterMetric = metrics.first { $0.title == "Water" }!, energy = metrics.first { $0.title == "Active energy" }!
        check(steps.subtitle == "0 steps" && waterMetric.subtitle == "No reading", "daily review distinguishes actual source-recorded zero from absent water")
        check(energy.subtitle == localized("About 123.5 kcal") && field(energy, "Overlapping sources") == "Kept separate", "estimated daily energy and overlap provenance stay explicit")
        let component = energy.child(at: 0)!
        check(field(component, "Source") == "Synthetic estimate source" && field(component, "Source type") == "Health import" && field(component, "Aggregation") == "Reported day" && field(component, "Estimate") == "Yes", "daily source components preserve source, aggregation and estimate status")
        check(field(component, "Period starts") != "Not provided" && field(component, "Period ends") != "Not provided" && field(component, "Checked at") != "Not provided" && field(component, "Latest sample") == "Not provided", "component dates and a missing sample time remain distinct")
        check(field(waterMetric.child(at: 0)!, "Outcome") == "No samples returned", "empty Health query is displayed as no samples rather than measured zero")
        let cache = metrics.last!
        check(cache.title == "Saved cache metadata" && cache.fields.count == 22 && field(cache, "Stored resting heart rate") == localized("58.5 bpm") && field(cache, "Stored sleep") == "25200 seconds" && field(cache, "Stored weight") == localized("72.6 kg"), "all raw cache scalar fields remain available separately from reading semantics")
        var blank = DayMetrics.empty
        check(children(.day(blank)).filter { ["Steps","Water","Active energy","Stand or roll hours"].contains($0.title) }.allSatisfy { $0.subtitle == "No reading" }, "legacy empty cache counters never become recorded zeros")
        blank.recordTotal(0, for: "steps")
        check(children(.day(blank)).first { $0.title == "Steps" }?.subtitle == "0 steps", "explicit legacy total presence preserves a genuine zero")
        blank.steps = 777; blank.readings = ["steps": .unknown]
        check(children(.day(blank)).first { $0.title == "Steps" }?.subtitle == "No reading", "explicit unknown reading cannot fall back to a conflicting raw cache value")
        let failedQuery = HealthMetricQuery(start: blank.date, end: blank.date.addingTimeInterval(60), checkedAt: blank.date.addingTimeInterval(70), outcome: .failed)
        blank.readings?["steps"] = .init(components: [], healthQuery: failedQuery)
        let failedMetric = children(.day(blank)).first { $0.title == "Steps" }!
        check(failedMetric.subtitle == "No reading" && field(failedMetric.child(at: 0)!, "Outcome") == "Check failed", "failed Health query remains unknown with an explicit failed outcome")
        check(failedMetric.childCount == 1 && field(failedMetric, "Source") == "No source components", "a failed query does not invent a source or a zero component")
        blank.readings?["future-key"] = .init(components: [.init(value: 0.000001, origin: .localLog, source: "Synthetic future source", start: blank.date, aggregation: .latest)])
        check(children(.day(blank)).contains { $0.title == "future-key" && $0.subtitle == "1e-06" }, "unknown saved metric keys and tiny nonzero values remain inspectable without rounding to zero")
        var longWater = try decoder.decode([HydrationLog].self, from: bytes("previous/water.json"))[0]
        let long = String(repeating: "Synthetic multi-line note 🧭\n", count: 180) + "Exact final marker."
        longWater.note = long
        check(field(.water(longWater), "Note") == long, "long Unicode notes remain exact for on-demand full-text inspection")

        let outer = fm.temporaryDirectory.appendingPathComponent("Lumen-record-review-" + UUID().uuidString)
        try fm.createDirectory(at: outer, withIntermediateDirectories: true); defer { try? fm.removeItem(at: outer) }
        for (path, row) in files {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw BackupError.invalid }
            let file = outer.appendingPathComponent(path); try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(base64Encoded: row["base64"] as! String)!.write(to: file)
        }
        let root = outer.appendingPathComponent("current")
        let preview = try HealthRecoveryCopies.previews(in: root).first { $0.domains.first { $0.domain == .meals }?.state == .readable }!
        let jpeg = bytes("previous/photos/synthetic-review-photo.jpg")
        check(try HealthRecoverySelection.photoData(preview, id: "synthetic-review-photo", in: root) == jpeg, "photo review returns the exact actual native JPEG bytes after source verification")
        let photo = root.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(preview.id).appendingPathComponent("photos/synthetic-review-photo.jpg")
        try Data("changed".utf8).write(to: photo, options: .atomic)
        rejects("photo review rejects changed bytes rather than showing an unreviewed image") { _ = try HealthRecoverySelection.photoData(preview, id: "synthetic-review-photo", in: root) }
        try fm.removeItem(at: photo)
        rejects("photo review preserves a missing-photo error rather than an empty image") { _ = try HealthRecoverySelection.photoData(preview, id: "synthetic-review-photo", in: root) }
        try jpeg.write(to: photo, options: .atomic)
        rejects("photo review rejects unsafe identifiers") { _ = try HealthRecoverySelection.photoData(preview, id: "../outside", in: root) }
        check(try HealthRecoverySelection.photoData(preview, id: "synthetic-review-photo", in: root) == jpeg, "photo review can retry after the exact source is restored")
        func cancellation(_ label: String, _ work: () throws -> Void) {
            var stopped = false
            do { try work() } catch is CancellationError { stopped = true } catch { }
            check(stopped, label)
        }
        let cancelled = BackupOperationControl(); cancelled.cancel()
        cancellation("cancelled bounded read exits before opening a missing file") {
            _ = try HealthLocalFiles.readRegularData(outer.appendingPathComponent("absent"), limit: 10, control: cancelled)
        }
        cancellation("cancelled retained verification is not reported as a missing source") {
            try HealthRecoveryCopies.verify(preview, in: outer.appendingPathComponent("absent"), control: cancelled)
        }
        cancellation("retained record review shares its caller cancellation control") {
            _ = try HealthRecoverySelection.records(preview, domain: .water, in: root, control: cancelled)
        }
        cancellation("retained photo review shares its caller cancellation control") {
            _ = try HealthRecoverySelection.photoData(preview, id: "synthetic-review-photo", in: root, control: cancelled)
        }
        cancellation("cancelled typed decode exits without classifying malformed bytes as damaged data") {
            _ = try Review.Document.decode(Data("{".utf8), domain: .water, control: cancelled)
        }
        let raw = outer.appendingPathComponent("bounded-read.bin"), payload = Data(repeating: 0x5a, count: 256 * 1024)
        try payload.write(to: raw)
        func tree() throws -> [String: String] {
            var result: [String: String] = [:]
            for case let file as URL in fm.enumerator(at: outer, includingPropertiesForKeys: nil)! {
                let type = try fm.attributesOfItem(atPath: file.path)[.type] as! FileAttributeType
                let key = String(file.path.dropFirst(outer.path.count))
                result[key] = type.rawValue + (type == .typeRegular ? ":" + SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined() : "")
            }
            return result
        }
        let beforeReads = try tree(), beforeCatalog = try HealthRecoveryCopies.previews(in: root)
        let chunkProbe = RecordReadCancelProbe(ordinal: 1)
        let chunkControl = BackupOperationControl(observer: { chunkProbe.observe($0) }); chunkProbe.attach(chunkControl)
        cancellation("a real multi-chunk descriptor read stops when cancelled by its first chunk observation") {
            _ = try HealthLocalFiles.readRegularData(raw, limit: payload.count, control: chunkControl)
        }
        check(chunkProbe.reads == [64 * 1024], "cancelled descriptor read consumes only one bounded chunk rather than the remaining file")
        check(try HealthLocalFiles.readRegularData(raw, limit: payload.count) == payload, "uncontrolled bounded reader remains compatible and retries exact bytes after cancellation")
        let photoPhase = BackupOperationControl(); photoPhase.update(.checkingPhotos, completed: 1, total: 2)
        _ = try HealthLocalFiles.readRegularData(raw, limit: payload.count, control: photoPhase)
        var keptPhotoPhase = false
        if case .checkingPhotos = photoPhase.progress.stage { keptPhotoPhase = photoPhase.progress.completed == 1 && photoPhase.progress.total == 2 }
        check(keptPhotoPhase, "cooperative file reads preserve the caller's photo-check stage and item counts")
        let manifestProbe = RecordReadCancelProbe(ordinal: 1)
        let manifestControl = BackupOperationControl(observer: { manifestProbe.observe($0) }); manifestProbe.attach(manifestControl)
        cancellation("cancelled retained manifest read throws instead of publishing an incomplete catalog choice") {
            _ = try HealthRecoveryCopies.previews(in: root, control: manifestControl)
        }
        let domainProbe = RecordReadCancelProbe(ordinal: 2)
        let domainControl = BackupOperationControl(observer: { domainProbe.observe($0) }); domainProbe.attach(domainControl)
        cancellation("retained domain verification propagates cancellation after its manifest read") {
            try HealthRecoveryCopies.verify(preview, in: root, control: domainControl)
        }
        let directory = photo.deletingLastPathComponent().deletingLastPathComponent()
        for name in ["manifest.json"] + HealthLocalFiles.Domain.allCases.map({ $0.rawValue + ".json" }) {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(name)) { precondition(data.count != jpeg.count) }
        }
        let photoProbe = RecordReadCancelProbe(byteCount: Int64(jpeg.count))
        let photoControl = BackupOperationControl(observer: { photoProbe.observe($0) }); photoProbe.attach(photoControl)
        cancellation("retained photo-byte verification remains cancellable within the checked copy traversal") {
            _ = try HealthRecoverySelection.photoData(preview, id: "synthetic-review-photo", in: root, control: photoControl)
        }
        let checkedPhoto = try BackupPhotoIdentity(data: jpeg), checkedProbe = RecordReadCancelProbe(ordinal: 1)
        let checkedControl = BackupOperationControl(observer: { checkedProbe.observe($0) }); checkedProbe.attach(checkedControl)
        cancellation("selected-file checked photo reads forward cancellation into their actual descriptor read") {
            _ = try checkedPhoto.read(photo, control: checkedControl)
        }
        check(try checkedPhoto.read(photo) == jpeg, "checked original JPEG identity retries exact bytes after an interrupted read")
        let expectedWater = try Data(contentsOf: directory.appendingPathComponent("water.json"))
        check(try HealthRecoverySelection.records(preview, domain: .water, in: root) == expectedWater, "retained records retry exact reviewed bytes after interrupted verification")
        check(try HealthRecoveryCopies.previews(in: root) == beforeCatalog, "cancelled verification leaves the complete recovery catalog unchanged")
        check(try tree() == beforeReads, "interrupted reads preserve every current/private/source file and receipt byte")
        check(try Data(contentsOf: fixtureURL) == fixture, "complete record inspection leaves frozen source evidence unchanged")
        if let output {
            let report: [String: Any] = ["status":"passed", "count":checks.count, "checks":checks, "fixture":"health-record-baseline-r1-outcome.json", "fixtureSHA256":SHA256.hash(data: fixture).map { String(format: "%02x", $0) }.joined(), "scope":"Actual typed decode/semantic review and Foundation photo-byte/source checks against native baseline bytes. Native rendering, ImageIO JPEG decode and product navigation require separate checks."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: output)
        }
    }
}

/// The production progress callback runs synchronously on the reader. Lock the
/// observations so the same probe also remains valid on a detached worker.
private final class RecordReadCancelProbe: @unchecked Sendable {
    private let lock = NSLock()
    private weak var control: BackupOperationControl?
    private var values: [Int64] = []
    private let ordinal: Int?
    private let byteCount: Int64?
    init(ordinal: Int? = nil, byteCount: Int64? = nil) { self.ordinal = ordinal; self.byteCount = byteCount }
    func attach(_ control: BackupOperationControl) { lock.lock(); self.control = control; lock.unlock() }
    var reads: [Int64] { lock.lock(); defer { lock.unlock() }; return values }
    func observe(_ progress: BackupOperationControl.Progress) {
        guard case .reading = progress.stage else { return }
        lock.lock(); values.append(progress.bytes)
        let stop = ordinal == values.count || byteCount == progress.bytes, target = control
        lock.unlock()
        if stop { target?.cancel() }
    }
}
