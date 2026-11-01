#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI
import UserNotifications

/// Explicit synthetic verification only: real checked stores and notification
/// APIs, with a compact report in this dedicated app's temporary directory.
@MainActor final class PreferenceNativeProbe: ObservableObject {
    static let shared = PreferenceNativeProbe()
    static var requested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetForUITests") && args.contains("-preference-native-probe")
    }
    @Published private(set) var status = "Checking synthetic preferences…"
    private var started = false
    private static var changedContext = false
    private static var failedSchedule = false
    private static var heldAccess = false
    private static var preparedFixtures = false
    static func fixture(_ flag: String) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetForUITests") && args.contains(flag)
    }
    static func prepareFixtures(health: HealthStore) throws {
        guard fixture("-preference-schedule-failure"), !preparedFixtures else { return }; preparedFixtures = true
        UserDefaults.standard.removeObject(forKey: "lumen.reminder.target")
        try health.addManualWorkout(kind: .walk, minutes: 15, kcal: 40, start: Date().addingTimeInterval(-900))
        let hour = Calendar.current.component(.hour, from: Date())
        try CompanionStore.shared.updateRemindersChecked { $0.quietStart = (hour + 6) % 24; $0.quietEnd = (hour + 7) % 24 }
    }
    static func changeContextIfRequested(_ store: CompanionStore) throws {
        guard fixture("-preference-context-change"), !changedContext else { return }; changedContext = true
        var newer = store.personalContext; newer.focus = "Synthetic newer notes"; newer.includeInAssistant = false
        try store.savePersonalContextChecked(newer, expectedRevision: store.personalContextRevision)
    }
    static func failScheduleIfRequested() throws {
        guard fixture("-preference-schedule-failure"), !failedSchedule else { return }; failedSchedule = true
        throw Failure(name: "Controlled synthetic notification scheduling failure")
    }
    static func holdAccessIfRequested() async {
        guard fixture("-preference-access-hold"), !heldAccess else { return }; heldAccess = true
        // Presentation-only hold after the actual framework permission reply.
        try? await Task.sleep(for: .seconds(15))
    }
    private struct Check: Codable { let name: String; let passed: Bool }
    private struct Pending: Codable { let identifier: String; let title: String; let body: String; let nextTrigger: Date? }
    private struct Snapshot: Codable { let phase: String; let date: Date; let preferences: ReminderPreferences; let pending: [Pending] }
    private struct Report: Codable { let status: String; let checks: [Check]; let snapshots: [Snapshot]; let scope: String }
    private struct Failure: LocalizedError { let name: String; var errorDescription: String? { name } }

    func run() async {
        guard Self.requested, !started else { return }; started = true
        var checks: [Check] = [], snapshots: [Snapshot] = []
        func check(_ passed: Bool, _ name: String) throws {
            checks.append(.init(name: name, passed: passed)); if !passed { throw Failure(name: name) }
        }
        let store = CompanionStore.shared, health = HealthStore.shared, notifications = NotificationManager.shared
        let center = UNUserNotificationCenter.current()
        func snapshot(_ phase: String) async -> [UNNotificationRequest] {
            let pending = await center.pendingNotificationRequests()
            snapshots.append(.init(phase: phase, date: Date(), preferences: store.reminders,
                pending: pending.map { .init(identifier: $0.identifier, title: $0.content.title, body: $0.content.body, nextTrigger: ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()) }))
            return pending
        }
        do {
            health.resetAll()
            UserDefaults.standard.removeObject(forKey: "lumen.reminder.target")
            var context = PersonalHealthContext(); context.focus = "SYNTHETIC-NATIVE-REFERENCE-38"; context.includeInAssistant = true
            try store.savePersonalContextChecked(context, expectedRevision: store.personalContextRevision)
            try check(store.context(health: health).contains(context.focus), "saved-on context reaches the actual context builder")
            context.includeInAssistant = false
            try store.savePersonalContextChecked(context, expectedRevision: store.personalContextRevision)
            try check(!store.context(health: health).contains(context.focus), "saved withdrawal removes personal notes from the actual context builder")
            try check(LocalStore.load(PersonalHealthContext.self, from: "personal-context") == context, "withdrawn notes and consent are actually stored together")

            let staleRevision = store.personalContextRevision
            var externalContext = context; externalContext.focus = "Synthetic external preference update"
            var externalReminders = store.reminders; externalReminders.quietStart = 18; externalReminders.quietEnd = 7
            try LocalStore.saveChecked(externalContext, as: "personal-context")
            try LocalStore.saveChecked(externalReminders, as: "reminder-preferences")
            store.persist()
            try check(LocalStore.load(PersonalHealthContext.self, from: "personal-context") == externalContext, "unrelated record persistence preserves newer context on disk")
            try check(LocalStore.load(ReminderPreferences.self, from: "reminder-preferences") == externalReminders, "unrelated record persistence preserves newer reminder preferences on disk")
            store.reloadAfterRestore()
            try check(store.personalContext == externalContext && store.reminders == externalReminders, "restore reload installs actual saved notes and reminder preferences")
            var staleDraft = context; staleDraft.includeInAssistant = true
            do {
                try store.savePersonalContextChecked(staleDraft, expectedRevision: staleRevision)
                throw Failure(name: "stale draft unexpectedly saved")
            } catch BackupError.recordsChanged {
                try check(store.personalContext == externalContext && !store.personalContext.includeInAssistant, "stale draft cannot overwrite restored notes or re-enable sharing")
            }
            try check(LocalStore.load(PersonalHealthContext.self, from: "personal-context") == externalContext, "stale rejection preserves the saved context file")

            try health.addManualWorkout(kind: .walk, minutes: 15, kcal: 40, start: Date().addingTimeInterval(-900))
            let hour = Calendar.current.component(.hour, from: Date())
            try store.updateRemindersChecked { $0.quietStart = (hour + 6) % 24; $0.quietEnd = (hour + 7) % 24; $0.showDetails = false }
            let result = try await store.enableReminders(owner: UUID())
            try check(result == .enabled && notifications.authorized, "real notification authorization and checked enable complete")
            await notifications.refreshContext(health: health).value
            let generic = await snapshot("generic-enabled")
            try check(generic.count == 1 && generic[0].identifier == "lumen.contextual-check-in", "actual notification center contains one contextual request")
            try check(generic[0].content.title == "Your Lumen check-in" && generic[0].content.body == "A moment to check in with yourself. Open Lumen for your latest context.", "default pending notification contains only generic private copy")
            try check(generic[0].trigger?.repeats == false && (generic[0].trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() != nil, "actual contextual notification is non-repeating with a future trigger")
            try store.updateRemindersChecked { $0.showDetails = true }
            await notifications.refreshContext(health: health).value
            let detailed = await snapshot("details-enabled")
            try check(detailed.count == 1 && detailed[0].content.title != "Your Lumen check-in" && !detailed[0].content.body.isEmpty, "explicit details consent replaces the actual pending content")
            try store.updateRemindersChecked { $0.showDetails = false }
            await notifications.refreshContext(health: health).value
            let hidden = await snapshot("details-withdrawn")
            try check(hidden.count == 1 && hidden[0].content.title == "Your Lumen check-in" && hidden[0].content.body == generic[0].content.body, "withdrawing details replaces actual health text with generic copy")
            try store.disableRemindersChecked()
            await notifications.refreshContext(health: health).value
            let off = await snapshot("check-ins-disabled")
            try check(off.isEmpty, "saved check-ins-off removes actual pending notification requests")
            try check(LocalStore.load(ReminderPreferences.self, from: "reminder-preferences") == store.reminders && !store.reminders.enabled && !store.reminders.showDetails, "disabled private reminder preferences match the saved file")
            status = "Preference checks passed"
        } catch { status = "Preference checks failed: " + error.localizedDescription }
        let report = Report(status: status, checks: checks, snapshots: snapshots,
            scope: "Actual production checked stores, Foundation files, context builder and UNUserNotificationCenter on a synthetic iOS simulator. Controlled callback races are separate pure checks. No notification delivery, signed-device, disk-exhaustion, power-loss, live-provider or clinical claim.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Lumen-preference-native-report.json")
        do { try encoder.encode(report).write(to: output, options: .atomic) }
        catch { status = "Preference checks failed: report could not be saved" }
    }
}
#endif
