import Foundation
import HealthKit

// MARK: - HealthKit integration (optional, graceful fallback to phone-based tracking)

@MainActor
public final class HealthKitManager: ObservableObject {
    public static let shared = HealthKitManager()
    @Published public var isAuthorized = false
    @Published public var lastSync: Date?
    @Published public var statusMessage = "Not connected"

    private let store = HKHealthStore()

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization() async {
        guard isAvailable else {
            statusMessage = "HealthKit not available on this device"
            return
        }
        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount),
              let hr = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleep, steps, hr])
            isAuthorized = true
            statusMessage = "Connected — sleep + activity sync on"
            lastSync = Date()
        } catch {
            statusMessage = "Health access denied — phone tracking still works"
        }
    }

    /// Fetch recent sleep samples and convert to SleepEpisodes (asleep intervals merged per night).
    public func fetchRecentSleep(days: Int = 30) async -> [SleepEpisode] {
        guard isAvailable, isAuthorized,
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    cont.resume(returning: []); return
                }
                let asleep = samples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                // Merge samples within 90 min gaps into nightly episodes.
                var episodes: [SleepEpisode] = []
                var curStart: Date?; var curEnd: Date?
                for s in asleep.sorted(by: { $0.startDate < $1.startDate }) {
                    if let cs = curStart, let ce = curEnd {
                        if s.startDate.timeIntervalSince(ce) < 90*60 {
                            curEnd = max(ce, s.endDate)
                        } else {
                            if curEnd!.timeIntervalSince(cs) > 3*3600 {
                                episodes.append(SleepEpisode(bedtime: cs, wakeTime: curEnd!, source: .wearable))
                            }
                            curStart = s.startDate; curEnd = s.endDate
                        }
                    } else {
                        curStart = s.startDate; curEnd = s.endDate
                    }
                }
                if let cs = curStart, let ce = curEnd, ce.timeIntervalSince(cs) > 3*3600 {
                    episodes.append(SleepEpisode(bedtime: cs, wakeTime: ce, source: .wearable))
                }
                cont.resume(returning: episodes)
            }
            self.store.execute(q)
        }
    }
}
