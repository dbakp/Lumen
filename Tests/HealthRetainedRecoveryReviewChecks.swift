import Foundation
import CryptoKit

enum HealthRetainedRecoveryReviewChecks {
    private final class Result: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set(_ value: Bool) { lock.lock(); self.value = value; lock.unlock() }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
    static func run(output: URL? = nil) throws {
        let fm = FileManager.default
        let area = fm.temporaryDirectory.appendingPathComponent("Lumen-retained-owner-" + UUID().uuidString)
        try fm.createDirectory(at: area, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: area) }
        let root = area.appendingPathComponent("current"), previous = root.appendingPathExtension("previous")
        let encoder = BackupArchive.encoder()
        let water = try encoder.encode([HydrationLog(id: "retained-owner-water", ml: 137)])
        var meal = Meal(id: "retained-owner-meal", type: .lunch, items: []); meal.photoID = "retained-owner-photo"
        let meals = try encoder.encode([meal]), damaged = Data("{retained-owner-damaged".utf8)
        let photoURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Design/native/health-write-order/health-backup-photo-original-r1.jpg")
        let photo = try Data(contentsOf: photoURL)
        for directory in [root, previous] {
            try fm.createDirectory(at: directory.appendingPathComponent("photos"), withIntermediateDirectories: true)
            for (name, data) in try ConversationFiles.encoded([], activeID: nil) { try data.write(to: directory.appendingPathComponent(name)) }
            try water.write(to: directory.appendingPathComponent("water.json"))
            try meals.write(to: directory.appendingPathComponent("meals.json"))
            try Data("[]".utf8).write(to: directory.appendingPathComponent("workouts.json"))
            try photo.write(to: directory.appendingPathComponent("photos/retained-owner-photo.jpg"))
        }
        try damaged.write(to: root.appendingPathComponent("water.json"))
        try damaged.write(to: root.appendingPathComponent("meals.json"))
        try damaged.write(to: root.appendingPathComponent("workouts.json"))
        let choices = try HealthRecoveryCopies.discover(in: root)
        guard let preview = choices.first(where: { $0.complete && $0.domains.contains(where: { $0.domain == .meals && $0.state == .readable }) }) else { throw BackupError.invalid }
        try fm.removeItem(at: root.appendingPathComponent("meals.json"))
        try fm.removeItem(at: root.appendingPathComponent("workouts.json"))
        var checks: [[String: Any]] = [], completed = false
        defer {
            if let output {
                let report: [String: Any] = ["status": completed ? "PASS" : "FAILED", "checks": checks,
                    "scope": "Actual retained owner, catalog reads, origin lease and preparation; isolated temporary files and raw legacy closure. No LocalStore locking, SwiftUI navigation, native or full app acceptance.",
                    "fixturePhotoSHA256": SHA256.hash(data: photo).map { String(format: "%02x", $0) }.joined(),
                    "fixtureRootRemovedOnReturn": true]
                do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output) }
                catch { print("Unable to retain owner checks: \(error)") }
            }
        }
        func check(_ label: String, _ value: @autoclosure () throws -> Bool) throws {
            let passed = try value(); checks.append(["name": label, "passed": passed]); print("\(passed ? "PASS" : "FAIL"): \(label)")
            guard passed else { throw BackupError.invalid }
        }
        func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
        func capture(_ session: HealthRetainedRecoveryReviewSession) throws {
            try session.captureOrigins(control: .init()) { domains, control in
                try HealthLegacyRecoveryOrigin.captureReview(domains, in: root,
                    legacy: { $0 == HealthLocalFiles.Domain.meals.legacyKey ? damaged : "retained String" }, control: control)
            }
        }
        let session = HealthRetainedRecoveryReviewSession(preview, in: root)
        try check("payload requires completed fresh capture", rejects { _ = try session.payload(domains: [.water], legacyDomains: [], omittingPhotos: [], control: .init(), validPhoto: { _ in true }) })
        try capture(session)
        try check("fresh capture classifies failed file separately from Data and String legacy", session.originMetadata?.fileDomains == [.water] && session.originMetadata?.legacyDomains == [.meals, .workouts])
        try check("record child reads exact reviewed records", try session.records(domain: .meals, control: .init()) == meals)
        try check("photo child reads exact reviewed photo", try session.photoData("retained-owner-photo", control: .init()) == photo)
        try check("child reads preserve ready authority", !session.isClosed && session.originState == .ready)
        try check("second capture cannot replace reviewed origins", rejects { try capture(session) })
        try check("failed second capture preserves existing ready origins", session.originState == .ready && session.originMetadata?.legacyDomains == [.meals, .workouts])
        try check("unselected legacy binding rejected", rejects { _ = try session.payload(domains: [.water], legacyDomains: [.meals], omittingPhotos: [], control: .init(), validPhoto: { _ in true }) })
        try check("missing selected legacy binding rejected", rejects { _ = try session.payload(domains: [.meals], legacyDomains: [], omittingPhotos: [], control: .init(), validPhoto: { _ in true }) })
        let payload = try session.payload(domains: [.meals, .workouts], legacyDomains: [.meals, .workouts], omittingPhotos: [], control: .init(), validPhoto: { _ in true })
        try check("selected Data and String origins bound to payload", payload.requiresExistingLegacyRoot && payload.domains == [.meals, .workouts])
        try check("changed raw legacy rejected by actual preparation", rejects {
            let transaction = try HealthRecoverySelection.prepare(payload, into: root, owner: UUID(), legacy: { _ in Data("changed".utf8) })
            transaction.discard()
        })
        try check("stale preparation preserves damaged current file", try Data(contentsOf: root.appendingPathComponent("water.json")) == damaged)
        let finalControl = BackupOperationControl(), registration = try session.beginOperation(control: finalControl)
        // This registration deliberately outlives payload preparation, as in the UI commit caller.
        finalControl.setCancellationHandler { precondition(session.isClosed); session.endOperation(registration) }
        session.close()
        try check("close cancels commit registration with reentrant callback outside lock", rejects { try finalControl.checkCancellation() })
        try check("close clears origin metadata and marks closed", session.isClosed && session.originState == .closed && session.originMetadata == nil)
        try check("closed owner rejects fresh operation", rejects { _ = try session.beginOperation(control: .init()) })
        try check("closed owner rejects records", rejects { _ = try session.records(domain: .meals, control: .init()) })
        try check("closed owner rejects photo", rejects { _ = try session.photoData("retained-owner-photo", control: .init()) })
        try check("closed owner rejects payload", rejects { _ = try session.payload(domains: [.water], legacyDomains: [], omittingPhotos: [], control: .init(), validPhoto: { _ in true }) })
        session.close()
        try check("idempotent close preserves permanent retained copy", try HealthRecoverySelection.records(preview, domain: .meals, in: root) == meals)
        let fresh = HealthRetainedRecoveryReviewSession(preview, in: root)
        try check("reselection has distinct owner with no inherited capture", fresh.id != session.id && fresh.originState == .initial && fresh.originMetadata == nil)
        try Data("[]".utf8).write(to: root.appendingPathComponent("meals.json"))
        try capture(fresh)
        try check("fresh review excludes newly healthy file despite failed legacy", fresh.originMetadata?.ineligibleDomains.contains(.meals) == true && fresh.originMetadata?.legacyDomains == [.workouts])
        try check("healthy selected domain cannot produce payload", rejects { _ = try fresh.payload(domains: [.meals], legacyDomains: [], omittingPhotos: [], control: .init(), validPhoto: { _ in true }) })
        fresh.close()
        let racing = HealthRetainedRecoveryReviewSession(preview, in: root)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        let result = Result(), captureControl = BackupOperationControl()
        DispatchQueue.global().async {
            do {
                try racing.captureOrigins(control: captureControl) { domains, control in
                    let snapshot = try HealthLegacyRecoveryOrigin.captureReview(domains, in: root, legacy: { _ in damaged }, control: control)
                    entered.signal(); release.wait(); return snapshot
                }
            } catch is CancellationError { result.set(true) } catch { }
            finished.signal()
        }
        let didEnter = entered.wait(timeout: .now() + 5) == .success
        racing.close(); release.signal()
        let didFinish = finished.wait(timeout: .now() + 5) == .success
        try check("close while capture holds snapshot rejects late completion", didEnter && didFinish && result.get())
        try check("late completion cannot resurrect cleared metadata", racing.isClosed && racing.originMetadata == nil && racing.originState == .closed)
        let scope = HealthRetainedRecoveryReviewScope()
        let childHeld = try scope.review(preview, in: root)
        try capture(childHeld)
        try check("enclosing scope permits child record reads", try childHeld.records(domain: .meals, control: .init()) == meals)
        let childControl = BackupOperationControl(), childOperation = try childHeld.beginOperation(control: childControl)
        scope.close()
        try check("container close clears child-held ready authority", childHeld.isClosed && childHeld.originMetadata == nil)
        try check("container close cancels operation held by child", rejects { try childControl.checkCancellation() })
        childHeld.endOperation(childOperation)
        try check("dismissed container cannot open another review", rejects { _ = try scope.review(preview, in: root) })
        let nextScope = HealthRetainedRecoveryReviewScope(), firstOwner = try nextScope.review(preview, in: root)
        let nextOwner = try nextScope.review(preview, in: root)
        try check("new selection retires prior scope owner", firstOwner.isClosed && !nextOwner.isClosed && nextOwner.id != firstOwner.id)
        nextScope.close()
        let retrying = HealthRetainedRecoveryReviewSession(preview, in: root), suspended = BackupOperationControl()
        let suspendEntered = DispatchSemaphore(value: 0), suspendRelease = DispatchSemaphore(value: 0), suspendDone = DispatchSemaphore(value: 0)
        let suspendedResult = Result()
        DispatchQueue.global().async {
            do {
                try retrying.captureOrigins(control: suspended) { domains, control in
                    let snapshot = try HealthLegacyRecoveryOrigin.captureReview(domains, in: root, legacy: { _ in damaged }, control: control)
                    suspendEntered.signal(); suspendRelease.wait(); return snapshot
                }
            } catch is CancellationError { suspendedResult.set(true) } catch { }
            suspendDone.signal()
        }
        let suspendStarted = suspendEntered.wait(timeout: .now() + 5) == .success
        retrying.suspendOriginCapture(control: suspended)
        try check("suspending pending capture cancels its real control and resets phase", suspendStarted && rejects { try suspended.checkCancellation() } && retrying.originState == .initial)
        try capture(retrying)
        suspendRelease.signal()
        let suspendFinished = suspendDone.wait(timeout: .now() + 5) == .success
        try check("late suspended worker rejects after fresh capture", suspendFinished && suspendedResult.get())
        try check("old suspended worker cannot clear fresh ready origins", retrying.originState == .ready && retrying.originMetadata?.legacyDomains == [.workouts])
        retrying.close()
        let changedSource = HealthRetainedRecoveryReviewSession(preview, in: root)
        let retainedRoot = root.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(preview.id)
        let retainedMeals = retainedRoot.appendingPathComponent("meals.json")
        try Data("[]".utf8).write(to: retainedMeals, options: .atomic)
        try check("changed retained records rejected by owner reads", rejects { _ = try changedSource.records(domain: .meals, control: .init()) })
        try meals.write(to: retainedMeals, options: .atomic)
        let retainedPhoto = retainedRoot.appendingPathComponent("photos/retained-owner-photo.jpg")
        try Data("changed synthetic photo".utf8).write(to: retainedPhoto, options: .atomic)
        try check("changed retained photo rejected by owner reads", rejects { _ = try changedSource.photoData("retained-owner-photo", control: .init()) })
        try photo.write(to: retainedPhoto, options: .atomic)
        try check("source mutation checks preserve and restore exact permanent inputs", try changedSource.records(domain: .meals, control: .init()) == meals && changedSource.photoData("retained-owner-photo", control: .init()) == photo)
        changedSource.close()
        completed = true
    }
}
