import Foundation

@MainActor enum PreferenceChecks {
    @MainActor private final class Gate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async { if !open { await withCheckedContinuation { waiters.append($0) } } }
        func release() { open = true; let saved = waiters; waiters = []; for waiter in saved { waiter.resume() } }
    }
    @MainActor private final class Backend {
        let entered = Gate(), release = Gate()
        var events: [String] = []
        var pending: String?
        func delayedAdd() async { events.append("add-start"); entered.release(); await release.wait(); pending = "health details"; events.append("add-finish") }
        func remove() { events.append("remove"); pending = nil }
    }
    private enum Expected: Error { case disk, scheduling }

    static func run() async throws {
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }; print("PASS: " + message)
        }
        let defaults = ReminderPreferences()
        check(!defaults.enabled && !defaults.showDetails && defaults.quietStart == 21 && defaults.quietEnd == 8, "reminder defaults keep check-ins and lock-screen health details off")
        let reminderCopy = try JSONDecoder().decode(ReminderPreferences.self, from: JSONEncoder().encode(defaults))
        check(reminderCopy == defaults, "existing reminder JSON round-trips without a schema change")
        var context = PersonalHealthContext(); context.focus = "SYNTHETIC-PRIVATE-FOCUS"; context.notes = "SYNTHETIC-PRIVATE-NOTE"
        check(!context.assistantText.contains(context.focus) && !context.assistantText.contains(context.notes), "unshared personal notes are omitted from actual assistant text")
        context.includeInAssistant = true
        check(context.assistantText.contains(context.focus) && context.assistantText.contains(context.notes), "explicit shared context includes the saved reference notes")
        context.includeInAssistant = false
        let copy = try JSONDecoder().decode(PersonalHealthContext.self, from: JSONEncoder().encode(context))
        check(copy == context && !copy.assistantText.contains(context.focus), "withdrawn context consent survives existing JSON encoding and keeps notes local")

        let requests = ReminderEnableRequests(), owner = UUID()
        var commits = 0
        let denied = try await requests.enable(owner: owner, authorize: { false }, commit: { commits += 1 })
        check(denied == .denied && commits == 0 && !requests.isRequesting, "denied notification access never commits enabled preferences")
        let enabled = try await requests.enable(owner: owner, authorize: { true }, commit: { commits += 1 })
        check(enabled == .enabled && commits == 1 && !requests.isRequesting, "current allowed notification intent commits once after authorization")
        do { _ = try await requests.enable(owner: owner, authorize: { true }, commit: { throw Expected.disk }); fatalError("disk failure swallowed") }
        catch Expected.disk { check(!requests.isRequesting, "failed preference commit propagates and releases its permission request") }
        let entered = Gate(), release = Gate()
        let pending = Task { try await requests.enable(owner: owner, authorize: { entered.release(); await release.wait(); return true }, commit: { commits += 1 }) }
        await entered.wait(); requests.cancel(owner: UUID())
        check(requests.isRequesting, "a different departing editor cannot cancel the active permission owner")
        requests.cancel(owner: owner); release.release()
        let cancelled = try await pending.value
        check(cancelled == .cancelled && commits == 1, "departing editor cancels a pending enable without a late preference write")
        let firstEntered = Gate(), firstRelease = Gate(), secondEntered = Gate(), secondRelease = Gate()
        let first = Task { try await requests.enable(owner: owner, authorize: { firstEntered.release(); await firstRelease.wait(); return true }, commit: { commits += 100 }) }
        await firstEntered.wait()
        let second = Task { try await requests.enable(owner: UUID(), authorize: { secondEntered.release(); await secondRelease.wait(); return true }, commit: { commits += 1 }) }
        await secondEntered.wait(); firstRelease.release()
        let superseded = try await first.value
        check(superseded == .cancelled && requests.isRequesting && commits == 1, "older permission completion neither enables reminders nor clears a newer request")
        secondRelease.release(); let current = try await second.value
        check(current == .enabled && commits == 2 && !requests.isRequesting, "only the latest allowed permission intent reaches its checked commit")
        let resetEntered = Gate(), resetRelease = Gate()
        let reset = Task { try await requests.enable(owner: owner, authorize: { resetEntered.release(); await resetRelease.wait(); return true }, commit: { commits += 100 }) }
        await resetEntered.wait(); requests.cancel(); resetRelease.release(); let resetResult = try await reset.value
        check(resetResult == .cancelled && commits == 2, "disable/reset invalidation prevents an older allowed reply from turning reminders on")
        let taskEntered = Gate(), taskRelease = Gate()
        let task = Task { try await requests.enable(owner: owner, authorize: { taskEntered.release(); await taskRelease.wait(); return true }, commit: { commits += 100 }) }
        await taskEntered.wait(); task.cancel(); taskRelease.release(); let taskResult = try await task.value
        check(taskResult == .cancelled && commits == 2, "cancelled permission task cannot publish a later allowed reply")

        let legacy = Backend()
        let legacyAdd = Task { await legacy.delayedAdd() }; await legacy.entered.wait(); legacy.remove(); legacy.release.release(); await legacyAdd.value
        check(legacy.pending != nil, "legacy independent notification removal permits a late detail-bearing request to reappear")
        let updates = OrderedReminderUpdates(), backend = Backend()
        var failures = 0, successes = 0
        let old = updates.replace(remove: { backend.remove() }, add: { await backend.delayedAdd() }, succeeded: { successes += 1 }, failed: { _ in failures += 1 })
        await backend.entered.wait()
        let off = updates.replace(remove: { backend.remove() }, add: nil, failed: { _ in failures += 1 })
        check(backend.pending == nil && backend.events.last == "remove", "turning check-ins off requests immediate pending-notification removal")
        backend.release.release(); await old.value; await off.value
        check(backend.pending == nil && backend.events.last == "remove", "ordered removal follows a delayed add callback and leaves no pending check-in")
        check(successes == 0 && failures == 0, "a superseded notification add cannot record a current scheduling success")
        let coalesced = Backend(), writes = OrderedReminderUpdates()
        let original = writes.replace(remove: { coalesced.remove() }, add: { await coalesced.delayedAdd() }, failed: { _ in failures += 1 })
        await coalesced.entered.wait()
        let middle = writes.replace(remove: { coalesced.remove() }, add: { coalesced.events.append("obsolete-add"); coalesced.pending = "obsolete details" }, failed: { _ in failures += 1 })
        let latest = writes.replace(remove: { coalesced.remove() }, add: { coalesced.events.append("generic-add"); coalesced.pending = "generic" }, succeeded: { successes += 1 }, failed: { _ in failures += 1 })
        coalesced.release.release(); await original.value; await middle.value; await latest.value
        check(coalesced.pending == "generic" && !coalesced.events.contains("obsolete-add"), "newer privacy-safe notification content wins and unstarted obsolete updates are skipped")
        check(successes == 1 && failures == 0, "only the current completed replacement publishes its scheduling success")
        let failed = writes.replace(remove: { coalesced.remove() }, add: { throw Expected.scheduling }, failed: { _ in failures += 1 })
        await failed.value
        check(failures == 1 && coalesced.pending == nil, "current notification scheduling failure is reported without leaving an old detail-bearing request")
        let recovered = writes.replace(remove: { coalesced.remove() }, add: { coalesced.pending = "retry" }, succeeded: { successes += 1 }, failed: { _ in failures += 1 })
        await recovered.value
        check(coalesced.pending == "retry" && successes == 2, "a completed failure releases the queue for a later current retry")
    }
}
