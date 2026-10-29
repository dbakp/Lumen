import Foundation
import UserNotifications

/// One optional, non-repeating check-in. Refresh on sync and each local log mutation.
@MainActor
public final class NotificationManager: ObservableObject {
    public static let shared = NotificationManager()
    @Published public var authorized = false
    private let requestID = "lumen.contextual-check-in"
    @discardableResult public func request() async -> Bool {
        do { authorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { authorized = false }
        return authorized
    }
    public func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    public func reschedule(from store: SleepStore) { refreshContext(health: .shared) }
    /// Compatibility for older callers; habit timing no longer creates generic repeating alerts.
    public func schedule(habits: [SleepHabit], wakeToday: Date, bedtimeTonight: Date, melatoninStart: Date) { refreshContext(health: .shared) }

    public func refreshContext(health: HealthStore) {
        let center = UNUserNotificationCenter.current()
        // Migrate away from every generic pending request created by previous releases.
        center.removeAllPendingNotificationRequests()
        let companion = CompanionStore.shared
        let prefs = companion.reminders
        guard authorized, prefs.enabled else { return }
        let now = Date(), calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        guard !ReminderPolicy.isQuiet(hour: hour, start: prefs.quietStart, end: prefs.quietEnd) else { return }
        // Symptoms and low energy deserve room, not an exercise/hydration pressure nudge.
        guard companion.activeSymptoms.isEmpty, companion.latestCheckIn.map({ $0.energy > 2 && $0.stress < 4 }) ?? true else { return }
        let useful = !health.workoutsToday.isEmpty || (health.metrics.sleepSeconds.map { $0 < 7 * 3600 } ?? false)
        guard useful else { return }
        let oldTarget = UserDefaults.standard.object(forKey: "lumen.reminder.target") as? Date
        if let oldTarget, calendar.isDateInToday(oldTarget), oldTarget <= now { return }
        let target = oldTarget.flatMap { calendar.isDateInToday($0) && $0 > now ? $0 : nil } ?? now.addingTimeInterval(20 * 60)
        guard calendar.isDateInToday(target), !ReminderPolicy.isQuiet(hour: calendar.component(.hour, from: target), start: prefs.quietStart, end: prefs.quietEnd) else { return }
        let perspective = companion.perspective(health: health)
        let content = UNMutableNotificationContent()
        content.title = prefs.showDetails ? perspective.title : "Your Lumen check-in"
        content.body = prefs.showDetails ? perspective.body : "A moment to check in with yourself. Open Lumen for your latest context."
        content.sound = .default
        content.userInfo = ["url": "lumen://today"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, target.timeIntervalSinceNow), repeats: false)
        UserDefaults.standard.set(target, forKey: "lumen.reminder.target")
        center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
    }
}
