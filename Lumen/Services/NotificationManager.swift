import Foundation
import UserNotifications

// MARK: - Smart habit reminders timed to circadian prediction

@MainActor
public final class NotificationManager: ObservableObject {
    public static let shared = NotificationManager()
    @Published public var authorized = false

    public func request() async {
        do {
            authorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorized = false
        }
    }

    /// Schedule enabled habits relative to wake / bedtime / melatonin window.
    public func schedule(habits: [SleepHabit], wakeToday: Date, bedtimeTonight: Date, melatoninStart: Date) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard authorized else { return }
        let cal = Calendar.current
        for habit in habits where habit.isEnabled {
            let fire: Date
            switch habit.anchor {
            case .wakePlus:
                fire = wakeToday.addingTimeInterval(habit.offset)
            case .bedtimeMinus:
                fire = bedtimeTonight.addingTimeInterval(-habit.offset)
            case .fixedClock:
                fire = wakeToday.addingTimeInterval(habit.offset)
            }
            // Don't schedule in the past; push to tomorrow same time.
            var target = fire
            if target < Date().addingTimeInterval(60) {
                target = cal.date(byAdding: .day, value: 1, to: fire) ?? fire
            }
            let content = UNMutableNotificationContent()
            content.title = habit.title
            content.body = habit.detail
            content.sound = .default
            let comps = cal.dateComponents([.hour, .minute], from: target)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: "lumen.\(habit.id)", content: content, trigger: trigger)
            center.add(req)
        }
        // Bedtime + wind-down anchors.
        scheduleOne(id: "lumen.winddown", title: "Wind down", body: "Lights low, screens dim. Melatonin rises in ~1 hour.", date: melatoninStart.addingTimeInterval(-3600))
        scheduleOne(id: "lumen.bedtime", title: "Melatonin window is open", body: "The easiest 60 minutes to fall asleep starts now.", date: melatoninStart)
    }

    private func scheduleOne(id: String, title: String, body: String, date: Date) {
        var target = date
        if target < Date().addingTimeInterval(60) {
            target = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        content.interruptionLevel = .timeSensitive
        let comps = Calendar.current.dateComponents([.hour, .minute], from: target)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
