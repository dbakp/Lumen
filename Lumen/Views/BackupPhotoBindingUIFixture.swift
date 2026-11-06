#if DEBUG && targetEnvironment(simulator)
import Foundation
import UIKit
import CryptoKit

/// Opt-in service integration using disposable synthetic inputs only.
@MainActor enum BackupPhotoBindingUIFixture {
    private enum Failure: Error { case check(String) }
    static func runChecks() async -> String {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Lumen-photo-binding-checked-" + UUID().uuidString)
        var checks: [String] = [], cases: [[String: Any]] = []
        var retainedSameRootTarget: URL?
        var status = "Backup photo checks failed"
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw Failure.check(name) }; checks.append(name)
        }
        func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        func rejectsChanged(_ name: String, _ work: () throws -> Void) throws {
            var rejected = false
            do { try work() } catch BackupError.recordsChanged { rejected = true }
            try check(rejected, name)
        }
        func seedTarget(_ name: String, owner: UUID) throws -> URL {
            let target = root.appendingPathComponent(name), encoder = BackupArchive.encoder()
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            for (file, data) in try ConversationFiles.encoded([], activeID: nil) { try data.write(to: target.appendingPathComponent(file)) }
            try Data("{\"syntheticUnavailableMeals\":".utf8).write(to: target.appendingPathComponent("meals.json"))
            try encoder.encode([HydrationLog]()).write(to: target.appendingPathComponent("water.json"))
            try encoder.encode([Workout]()).write(to: target.appendingPathComponent("workouts.json"))
            try encoder.encode(HealthGoals()).write(to: target.appendingPathComponent("goals.json"))
            try encoder.encode(DayMetrics.empty).write(to: target.appendingPathComponent("today.json"))
            try HealthWriteJournal(owner: owner).encoded().write(to: target.appendingPathComponent(HealthWriteFiles.name))
            return target
        }
        func currentFiles() throws -> [String: Data] {
            let directory = try LocalStore.checkedDirectory()
            guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { throw BackupError.invalid }
            var result: [String: Data] = [:]
            for case let file as URL in entries {
                let facts = try fm.attributesOfItem(atPath: file.path)
                if facts[.type] as? FileAttributeType == .typeRegular {
                    result[String(file.path.dropFirst(directory.path.count + 1))] = try HealthLocalFiles.readRegularData(file, limit: 1024 * 1024)
                }
            }
            return result
        }
        func jpeg(_ color: UIColor) throws -> Data {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
            }
            guard let data = image.jpegData(compressionQuality: 0.85) else { throw BackupError.invalid }
            return data
        }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let original = try jpeg(.systemTeal), changed = try jpeg(.systemOrange)
            try original.write(to: root.appendingPathComponent("original.jpg"))
            try changed.write(to: root.appendingPathComponent("changed.jpg"))
            try check(original != changed && BackupService.validPhoto(root.appendingPathComponent("original.jpg")) && BackupService.validPhoto(root.appendingPathComponent("changed.jpg")), "two different actual JPEGs pass the production image validator")
            var meal = Meal(id: "synthetic-photo-binding-meal", type: .lunch, items: [])
            meal.photoID = "synthetic-reviewed-photo"
            let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [meal], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
            let health = HealthStore.shared, sleep = SleepStore.shared
            for _ in 0..<300 where !health.conversationReady { try await Task.sleep(for: .milliseconds(25)) }
            try check(health.conversationReady, "normal healthy store startup completes before merge controls")
            for encrypted in [false, true] {
                let kind = encrypted ? "encrypted" : "legacy"
                var caseSnapshot = snapshot
                var caseMeal = Meal(id: "synthetic-photo-binding-" + kind, type: .lunch, items: [])
                caseMeal.photoID = meal.photoID; caseSnapshot.meals = [caseMeal]
                let input = root.appendingPathComponent(kind + (encrypted ? ".lumenbackup" : ".json"))
                let password = "Synthetic photo binding passphrase 43"
                if encrypted { try BackupPackage.write(caseSnapshot, photos: [meal.photoID!: root.appendingPathComponent("original.jpg")], password: password, to: input) }
                else { var legacy = caseSnapshot; legacy.photos = [meal.photoID!: original]; try BackupArchive.make(legacy).write(to: input) }
                let selected = try BackupService.select(input, control: .init())
                let preview = try BackupService.read(selected, password: encrypted ? password : "", control: .init())
                guard let reviewed = BackupService.recoveryInput(preview), let extracted = preview.photos[meal.photoID!] else { throw BackupError.invalid }
                try check(try reviewed.photoData(meal.photoID!) == original, kind + " actual checked photo review initially returns the original JPEG")
                try changed.write(to: extracted, options: .atomic)
                try selected.verify(control: .init())
                try check(try Data(contentsOf: input) == Data(contentsOf: selected.url), kind + " selected archive bytes remain exact after extracted-photo replacement")
                try rejectsChanged(kind + " typed photo review rejects the changed valid extracted JPEG") { _ = try reviewed.photoData(meal.photoID!) }
                try rejectsChanged(kind + " recovery payload rejects changed valid photo before staging") { _ = try reviewed.payload(domains: [.meals], omitPhotos: false, control: .init()) }
                let beforeMerge = try currentFiles()
                var mergeRejected = false
                do { try await BackupService.restore(preview, preferences: false, sleep: sleep, health: health, control: .init()) }
                catch BackupError.recordsChanged { mergeRejected = true }
                try check(mergeRejected && (try currentFiles()) == beforeMerge, kind + " healthy ordinary merge rejects changed photo and retains exact current files")
                try original.write(to: extracted, options: .atomic)
                let shown = try reviewed.photoData(meal.photoID!)
                try check(shown == original, kind + " restoring exact reviewed photo bytes permits retry")
                let payload = try reviewed.payload(domains: [.meals], omitPhotos: false, control: .init())
                let owner = UUID(), damaged = Data("{\"syntheticUnavailableMeals\":".utf8)
                let target = try seedTarget(kind + "-target", owner: owner)
                try HealthRecoverySelection.prepare(payload, into: target, owner: owner).commit()
                let saved = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: target.appendingPathComponent("meals.json")))
                guard let id = saved.first?.photoID else { throw BackupError.invalid }
                let installed = try Data(contentsOf: target.appendingPathComponent("photos/" + id + ".jpg"))
                try check(installed == original, kind + " recovery installs exact originally reviewed JPEG bytes")
                let copies = try fm.contentsOfDirectory(at: target.appendingPathComponent(HealthRecoveryCopies.name), includingPropertiesForKeys: nil)
                try check(copies.contains { (try? Data(contentsOf: $0.appendingPathComponent("meals.json"))) == damaged }, kind + " recovery preserves exact damaged current meal bytes")
                let receipts = try fm.contentsOfDirectory(at: target.appendingPathComponent(".health-recovery-history"), includingPropertiesForKeys: nil)
                let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: receipts[0])) as! [String: Any]
                let reviewedIdentities = try JSONDecoder().decode([String: BackupPhotoIdentity].self, from: JSONSerialization.data(withJSONObject: receipt["reviewedPhotos"]!))
                try check(reviewedIdentities[meal.photoID!] == BackupPhotoIdentity(data: original) && (receipt["photoDigests"] as? [String: String])?["photos/" + id + ".jpg"] == digest(original), kind + " receipt binds original reviewed photo identity and final copied-photo digest")
                let omissionTarget = try seedTarget(kind + "-omission", owner: owner)
                try fm.removeItem(at: extracted)
                let omission = try reviewed.payload(domains: [.meals], omitPhotos: true, control: .init())
                try HealthRecoverySelection.prepare(omission, into: omissionTarget, owner: owner).commit()
                let omittedMeals = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: omissionTarget.appendingPathComponent("meals.json")))
                try check(omittedMeals.count == 1 && omittedMeals[0].photoID == nil, kind + " explicit omission recovers meals when extracted photo is unavailable")
                try original.write(to: extracted, options: .atomic)
                try await BackupService.restore(preview, preferences: false, sleep: sleep, health: health, control: .init())
                guard let healthyMeal = health.meals.first(where: { $0.id == caseMeal.id }), let healthyID = healthyMeal.photoID else { throw BackupError.invalid }
                let healthyPhoto = try Data(contentsOf: LocalStore.checkedDirectory().appendingPathComponent("photos/" + healthyID + ".jpg"))
                try check(healthyPhoto == original, kind + " healthy ordinary merge installs checked original photo and live meal")
                cases.append(["kind": kind, "input": input.path, "target": target.path, "identity": try JSONSerialization.jsonObject(with: JSONEncoder().encode(selected.identity)),
                              "originalPhotoSHA256": digest(original), "changedPhotoSHA256": digest(changed), "shownPhotoSHA256": digest(shown), "installedPhotoSHA256": digest(installed),
                              "changedReviewRejected": true, "changedPayloadRejected": true, "healthyChangedMergeRejected": mergeRejected, "healthyPhotoID": healthyID,
                              "omissionTarget": omissionTarget.path])
                withExtendedLifetime((selected, preview, reviewed)) {}
            }
            let retainedOwner = UUID(), retained = try seedTarget("same-root-retained", owner: retainedOwner)
            var retainedMeal = Meal(id: "native-same-root-retained", type: .lunch, items: []); retainedMeal.photoID = "same-root"
            try BackupArchive.encoder().encode([retainedMeal]).write(to: retained.appendingPathComponent("meals.json"), options: .atomic)
            try fm.createDirectory(at: retained.appendingPathComponent("photos"), withIntermediateDirectories: false)
            try original.write(to: retained.appendingPathComponent("photos/same-root.jpg"))
            try fm.copyItem(at: retained, to: retained.appendingPathExtension("previous"))
            try Data("{\"syntheticUnavailableMeals\":".utf8).write(to: retained.appendingPathComponent("meals.json"), options: .atomic)
            try BackupFiles.openDirectory(retained, createIfMissing: false)
            guard let copy = try HealthRecoveryCopies.discover(in: retained).first else { throw BackupError.invalid }
            let selection = try HealthRecoverySelection.retained(copy, in: retained, domains: [.meals], validPhoto: BackupService.validPhoto)
            try HealthRecoverySelection.prepare(selection, into: retained, owner: retainedOwner).commit()
            let installedMeals = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: retained.appendingPathComponent("meals.json")))
            guard let installedID = installedMeals.first?.photoID else { throw BackupError.invalid }
            try check(installedMeals.count == 1 && installedMeals[0].id == retainedMeal.id
                && Data(contentsOf: retained.appendingPathComponent("photos/" + installedID + ".jpg")) == original,
                "actual native same-root retained meal/photo recovery accepts its own preservation hardlinks and installs reviewed bytes")
            retainedSameRootTarget = retained
            status = "Backup photo checks passed"
        } catch { status = "Backup photo checks failed: \(error)" }
        do {
            var report: [String: Any] = ["status": status, "root": root.path, "checks": checks, "cases": cases,
                "healthyRoot": try LocalStore.checkedDirectory().path,
                "scope": "Actual BackupService native legacy/encrypted readers, typed photo adapter, replacement, omission and healthy ordinary merge controls. Synthetic dedicated simulator only; no actual Files/photo UI, HealthKit, device or complete photo-recovery acceptance."]
            if let retainedSameRootTarget { report["retainedSameRootTarget"] = retainedSameRootTarget.path }
            let destination = try LocalStore.checkedDirectory().deletingLastPathComponent().appendingPathComponent("Lumen-photo-binding-checked.json")
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination, options: .atomic)
        } catch { return "Backup photo checks failed: report could not be saved" }
        return status
    }
}
#endif
