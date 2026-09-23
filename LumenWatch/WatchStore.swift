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
    @Published var steps: Double = 0
    @Published var activeEnergy: Double = 0
    @Published var exerciseMin: Double = 0
    @Published var standHours: Double = 0
    @Published var heartRate: Double?
    @Published var restingHR: Double?
    @Published var waterLoggedHere: Double = 0

    private let hk = HKHealthStore()
    private var defaults: UserDefaults { UserDefaults(suiteName: Self.groupID) ?? .standard }

    override init() {
        super.init()
        snapshot = WatchSnapshot.decode(defaults.data(forKey: WatchSnapshot.storeKey))
        // Design review hook (simulator screenshots).
        if ProcessInfo.processInfo.arguments.contains("-watchPreview") { snapshot = .preview }
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
        return !Calendar.current.isDateInToday(s.generatedAt)
    }

    // MARK: Snapshot

    fileprivate func apply(_ data: Data) {
        guard var s = WatchSnapshot.decode(data) else { return }
        // Keep optimistic ritual toggles that the phone hasn't echoed yet.
        s.generatedAt = Date()
        snapshot = s
        waterLoggedHere = 0
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
        waterLoggedHere += ml
        Task {
            let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater),
                                          quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
                                          start: Date(), end: Date())
            try? await hk.save(sample)
            WCSession.default.transferUserInfo([WatchMessage.loggedWater: ml])
        }
    }

    // MARK: Health on the wrist

    func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let read: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
                                       HKQuantityType(.appleExerciseTime), HKQuantityType(.appleStandTime),
                                       HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate)]
        let share: Set<HKSampleType> = [HKQuantityType(.dietaryWater)]
        try? await hk.requestAuthorization(toShare: share, read: read)
    }

    func refreshActivity() async {
        let start = Calendar.current.startOfDay(for: Date())
        async let s = sum(.stepCount, .count(), start)
        async let a = sum(.activeEnergyBurned, .kilocalorie(), start)
        async let e = sum(.appleExerciseTime, .minute(), start)
        async let st = sum(.appleStandTime, .hour(), start)
        async let hr = latest(.heartRate, HKUnit(from: "count/min"))
        async let rhr = latest(.restingHeartRate, HKUnit(from: "count/min"))
        steps = await s ?? 0
        activeEnergy = await a ?? 0
        exerciseMin = await e ?? 0
        standHours = (await st ?? 0).rounded()
        heartRate = await hr
        restingHR = await rhr
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            hk.execute(HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: pred, options: .cumulativeSum) { _, s, _ in
                cont.resume(returning: s?.sumQuantity()?.doubleValue(for: unit))
            })
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            hk.execute(HKSampleQuery(sampleType: HKQuantityType(id), predicate: nil, limit: 1, sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
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
