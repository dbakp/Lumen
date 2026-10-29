import Foundation
import HealthKit
import WatchConnectivity
import WidgetKit

// MARK: - Watch-side state: the phone's snapshot + live activity read on the wrist.

@MainActor
final class WatchStore: NSObject, ObservableObject {
    static let shared = WatchStore()
    static let groupID = "group.com.dbakp.lumen"

    @Published var snapshot: WatchSnapshot?
    @Published var activity: DisplayEvidence?
    @Published var heartRateDate: Date?
    @Published var savedWatchWater: DisplayEvidence?
    @Published var savingWater = false
    @Published var waterError: String?

    func activityValue(_ key: String, at now: Date = Date()) -> Double? { activity?.value(key, at: now) }
    var waterLoggedHere: Double? { savedWatchWater?.value("water") }

    private let hk = HKHealthStore()
    private var defaults: UserDefaults { UserDefaults(suiteName: Self.groupID) ?? .standard }

    override init() {
        super.init()
        snapshot = WatchSnapshot.decode(defaults.data(forKey: WatchSnapshot.storeKey))
        // Design review hook (simulator screenshots).
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-watchPreview") { snapshot = .preview }
        #endif
        savedWatchWater = DisplayEvidence.decode(defaults.data(forKey: "watch.savedWater.v1"))
    }

    func start() {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        Task { await requestHealth(); await refreshActivity() }
    }

    var isStale: Bool {
        guard let s = snapshot else { return true }
        return s.observations?.isCurrent() != true
    }

    // MARK: Snapshot

    fileprivate func apply(_ data: Data) {
        guard let s = WatchSnapshot.decode(data), s.canReplace(snapshot) else { return }
        snapshot = s
        defaults.set(s.encoded(), forKey: WatchSnapshot.storeKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func requestSnapshot() {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([WatchMessage.requestSnapshot: true])
    }

    // MARK: Actions

    func toggleRitual(_ id: String) {
        guard var s = snapshot, let i = s.rituals.firstIndex(where: { $0.id == id }) else { return }
        s.rituals[i].done.toggle()
        snapshot = s
        defaults.set(s.encoded(), forKey: WatchSnapshot.storeKey)
        WCSession.default.transferUserInfo([WatchMessage.toggleRitual: id])
    }

    func logWater(_ ml: Double) {
        guard !savingWater, ml.isFinite, (1...10000).contains(ml) else { return }
        savingWater = true; waterError = nil
        Task {
            defer { savingWater = false }
            let now = Date()
            let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater), quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml), start: now, end: now)
            do {
                try await hk.save(sample)
                let previous = savedWatchWater?.value("water", at: now) ?? 0
                savedWatchWater = .init(day: Calendar.current.startOfDay(for: now), capturedAt: now, values: ["water": previous + ml])
                defaults.set(savedWatchWater?.encoded(), forKey: "watch.savedWater.v1")
                if WCSession.default.activationState == .activated { WCSession.default.transferUserInfo([WatchMessage.loggedWater: ml]) }
            } catch { waterError = "Couldn’t save water to Apple Health. Your total has not changed. Review write access and try again." }
        }
    }

    // MARK: Health on the wrist

    func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let read: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
                                       HKQuantityType(.appleExerciseTime), HKCategoryType(.appleStandHour),
                                       HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate)]
        let share: Set<HKSampleType> = [HKQuantityType(.dietaryWater)]
        try? await hk.requestAuthorization(toShare: share, read: read)
    }

    func refreshActivity() async {
        let start = Calendar.current.startOfDay(for: Date()), end = Date()
        async let steps = sum(.stepCount, .count(), start, end)
        async let active = sum(.activeEnergyBurned, .kilocalorie(), start, end)
        async let exercise = sum(.appleExerciseTime, .minute(), start, end)
        async let stand = standHours(start, end)
        async let heart = latest(.heartRate, HKUnit(from: "count/min"), start, end)
        let (s, a, e, st, hr) = await (steps, active, exercise, stand, heart)
        var values: [String: Double] = [:]
        for (key, value) in [("steps", s), ("activeEnergy", a), ("exercise", e), ("stand", st), ("heartRate", hr.value)] { if let value { values[key] = value } }
        activity = .init(day: start, capturedAt: Date(), values: values)
        heartRateDate = hr.date
    }
    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            hk.execute(HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                continuation.resume(returning: error == nil ? statistics?.sumQuantity()?.doubleValue(for: unit) : nil)
            })
        }
    }
    private struct Sample { var value: Double?; var date: Date? }
    private func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> Sample {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            hk.execute(HKSampleQuery(sampleType: HKQuantityType(id), predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                let sample = samples?.first as? HKQuantitySample
                let usable = error == nil && sample.map { $0.endDate <= end } == true
                continuation.resume(returning: .init(value: usable ? sample?.quantity.doubleValue(for: unit) : nil, date: usable ? sample?.endDate : nil))
            })
        }
    }
    private func standHours(_ start: Date, _ end: Date) async -> Double? {
        let type = HKCategoryType(.appleStandHour)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            hk.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil else { continuation.resume(returning: nil); return }
                let entries = ((samples as? [HKCategorySample]) ?? []).filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue || $0.value == HKCategoryValueAppleStandHour.idle.rawValue }
                continuation.resume(returning: StandHourEvidence.count(entries.map { .init(start: $0.startDate, stood: $0.value == HKCategoryValueAppleStandHour.stood.rawValue) }, start: start, end: end))
            })
        }
    }

}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext[WatchSnapshot.contextKey] as? Data
        Task { @MainActor in
            if let ctx { self.apply(ctx) }
            if self.isStale { self.requestSnapshot() }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchSnapshot.contextKey] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }
}
