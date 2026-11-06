import Foundation
import ImageIO
import Darwin

enum BackupPhotoBindingChecks {
    static func run(output: URL? = nil) throws {
        let fm = FileManager.default, base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let root = fm.temporaryDirectory.appendingPathComponent("Lumen-photo-binding-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let original = try Data(contentsOf: base.appendingPathComponent("Design/native/health-write-order/health-backup-photo-original-r1.jpg"))
        let changed = try Data(contentsOf: base.appendingPathComponent("Design/native/health-write-order/health-backup-photo-changed-r1.jpg"))
        let originalIdentity = try BackupPhotoIdentity(data: original)
        var checks: [String] = []
        func check(_ value: Bool, _ name: String) { precondition(value, name); checks.append(name); print("PASS: " + name) }
        func rejects(_ name: String, _ work: () throws -> Void) {
            var rejected = false; do { try work() } catch { rejected = true }; check(rejected, name)
        }
        func valid(_ url: URL) -> Bool {
            guard let bytes = try? HealthLocalFiles.readRegularData(url, limit: BackupArchive.maxPhotoBytes),
                  let image = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetType(image) as String? == "public.jpeg",
                  CGImageSourceGetCount(image) == 1, CGImageSourceGetStatus(image) == .statusComplete,
                  CGImageSourceCreateImageAtIndex(image, 0, nil) != nil else { return false }
            return CGImageSourceGetStatusAtIndex(image, 0) == .statusComplete
        }
        let originalFile = root.appendingPathComponent("original.jpg"), changedFile = root.appendingPathComponent("changed.jpg")
        try original.write(to: originalFile); try changed.write(to: changedFile)
        check(original != changed && valid(originalFile) && valid(changedFile), "actual baseline native JPEG originals decode as two different valid images")
        rejects("empty photo identity rejects") { _ = try BackupPhotoIdentity(data: Data()) }
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("reviewed photo read checks caller cancellation before opening") { _ = try originalIdentity.read(originalFile, control: cancelled) }
        func seed(_ name: String) throws -> URL {
            let target = root.appendingPathComponent(name), encoder = BackupArchive.encoder()
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            for (path, data) in try ConversationFiles.encoded([], activeID: nil) { try data.write(to: target.appendingPathComponent(path)) }
            try Data("{\"syntheticUnavailableMeals\":".utf8).write(to: target.appendingPathComponent("meals.json"))
            try encoder.encode([HydrationLog]()).write(to: target.appendingPathComponent("water.json"))
            try encoder.encode([Workout]()).write(to: target.appendingPathComponent("workouts.json"))
            try encoder.encode(HealthGoals()).write(to: target.appendingPathComponent("goals.json"))
            try encoder.encode(DayMetrics.empty).write(to: target.appendingPathComponent("today.json"))
            return target
        }
        func files(_ target: URL) throws -> [String: Data] {
            var result: [String: Data] = [:]
            for case let file as URL in fm.enumerator(at: target, includingPropertiesForKeys: nil)! {
                if (try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType) == .typeRegular {
                    result[String(file.path.dropFirst(target.path.count + 1))] = try Data(contentsOf: file)
                }
            }
            return result
        }
        for encrypted in [false, true] {
          for mode in ["shared", "two", "empty"] {
            let name = (encrypted ? "encrypted-" : "legacy-") + mode
            let workspace = try BackupWorkspace(base: root), file = workspace.directory.appendingPathComponent("selected-backup")
            var first = Meal(id: "first", type: .lunch, items: []), second = Meal(id: "second", type: .dinner, items: [])
            first.photoID = mode == "empty" ? nil : "one"; second.photoID = mode == "empty" ? nil : mode == "shared" ? "one" : "two"
            let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [first, second], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
            let inputPhotos = mode == "empty" ? [:] : mode == "shared" ? ["one": originalFile] : ["one": originalFile, "two": changedFile]
            var decoded: BackupSnapshot, photos: [String: URL] = [:], identities: [String: BackupPhotoIdentity] = [:]
            var contents: BackupPackage.Contents?
            if encrypted {
                try BackupPackage.write(snapshot, photos: inputPhotos, password: "Synthetic checked photo passphrase 43", to: file)
                let opened = try BackupPackage.read(file, password: "Synthetic checked photo passphrase 43", temporaryRoot: workspace.directory)
                contents = opened; decoded = opened.snapshot; photos = opened.photos; identities = opened.photoIdentities
            } else {
                var legacy = snapshot; legacy.photos = try inputPhotos.mapValues { try Data(contentsOf: $0) }
                try BackupArchive.make(legacy).write(to: file)
                let value = try BackupArchive.read(Data(contentsOf: file)).1
                decoded = value; decoded.photos = [:]
                for (id, data) in value.photos {
                    let photo = workspace.directory.appendingPathComponent(id + ".jpg"); try data.write(to: photo)
                    photos[id] = photo; identities[id] = try BackupPhotoIdentity(data: data)
                }
            }
            check(try photos.allSatisfy { try identities[$0.key]!.read($0.value) == Data(contentsOf: inputPhotos[$0.key]!) }, name + " decoded photo identities match actual archive bytes")
            let identity = try BackupSourceIdentity.measure(file, named: name, format: encrypted ? .encryptedBackup : .legacyJSONBackup, limit: BackupPackage.maxFileBytes)
            let source = BackupRecoverySource(lease: .init(file: file, identity: identity, workspace: workspace), photoWorkspace: nil, contents: contents, photoIdentities: identities)
            func payload(_ omissions: Set<String> = [], source value: BackupRecoverySource? = nil) throws -> HealthRecoverySelection.Payload {
                try HealthRecoverySelection.backup(decoded, photos: photos, domains: [.meals], omittingPhotos: omissions, source: value ?? source, validPhoto: valid)
            }
            let owner = UUID(), target = try seed(name), preparedPayload = try payload()
            try HealthRecoverySelection.prepare(preparedPayload, into: target, owner: owner).commit()
            let meals = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: target.appendingPathComponent("meals.json")))
            check(meals.count == 2 && meals.compactMap(\.photoID).count == (mode == "empty" ? 0 : 2), name + " checked recovery installs complete selected meal metadata")
            if mode != "empty" {
                check(try Data(contentsOf: target.appendingPathComponent("photos/" + meals[0].photoID! + ".jpg")) == original, name + " recovered first photo matches original reviewed JPEG")
                check((meals[0].photoID == meals[1].photoID) == (mode == "shared"), name + " shared versus distinct photo references remain correct")
                if mode == "two" {
                    check(try Data(contentsOf: target.appendingPathComponent("photos/" + meals[1].photoID! + ".jpg")) == changed, name + " recovered second photo independently matches its distinct reviewed JPEG")
                }
            }
            let receiptURL = try fm.contentsOfDirectory(at: target.appendingPathComponent(".health-recovery-history"), includingPropertiesForKeys: nil)[0]
            let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as! [String: Any]
            let recorded = try JSONDecoder().decode([String: BackupPhotoIdentity].self, from: JSONSerialization.data(withJSONObject: receipt["reviewedPhotos"]!))
            check(recorded == identities && (receipt["photoDigests"] as! [String: String]).count == identities.count, name + " receipt binds exact original reviewed photo identities and copied digests")
            if mode == "empty" { continue }
            try Data("{\"syntheticUnavailableMeals\":".utf8).write(to: target.appendingPathComponent("meals.json"), options: .atomic)
            let extracted = photos["one"]!, before = try files(target)
            try changed.write(to: extracted, options: .atomic)
            try identity.verify(file)
            rejects(name + " valid JPEG replacement after review rejects typed photo read") { _ = try identities["one"]!.read(extracted) }
            rejects(name + " valid JPEG replacement before payload rejects recovery") { _ = try payload() }
            rejects(name + " changed source after payload rejects actual staging") { _ = try HealthRecoverySelection.prepare(preparedPayload, into: target, owner: owner) }
            check(try files(target) == before, name + " rejected changed-photo preparation retains every canonical/private/receipt byte")
            try original.write(to: extracted, options: .atomic)
            let staged = try HealthRecoverySelection.prepare(try payload(), into: target, owner: owner)
            try changed.write(to: extracted, options: .atomic)
            rejects(name + " changed extracted source after preparation rejects installation") { try staged.commit() }
            staged.discard(); try original.write(to: extracted, options: .atomic)
            let mutatedStage = try HealthRecoverySelection.prepare(try payload(), into: target, owner: owner)
            let stage = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(target.lastPathComponent + ".restore-") }!
            let stagedMeals = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: stage.appendingPathComponent("meals.json")))
            let stagedPhoto = stage.appendingPathComponent("photos/" + stagedMeals[0].photoID! + ".jpg")
            var stamp = stat()
            guard lstat(stagedPhoto.path, &stamp) == 0 else { throw BackupError.invalid }
            var corrupt = original; corrupt[0] ^= 1
            try corrupt.write(to: stagedPhoto)
            let times = [stamp.st_atimespec, stamp.st_mtimespec]
            guard times.withUnsafeBufferPointer({ utimensat(AT_FDCWD, stagedPhoto.path, $0.baseAddress, 0) }) == 0 else { throw BackupError.invalid }
            var after = stat()
            guard lstat(stagedPhoto.path, &after) == 0 else { throw BackupError.invalid }
            check(after.st_ino == stamp.st_ino && after.st_size == stamp.st_size
                && after.st_mtimespec.tv_sec == stamp.st_mtimespec.tv_sec && after.st_mtimespec.tv_nsec == stamp.st_mtimespec.tv_nsec
                && (after.st_ctimespec.tv_sec != stamp.st_ctimespec.tv_sec || after.st_ctimespec.tv_nsec != stamp.st_ctimespec.tv_nsec),
                name + " actual stage fault preserves inode, length and exact nanosecond mtime while changing ctime")
            rejects(name + " same-length in-place stage mutation with restored mtime rejects installation") { try mutatedStage.commit() }
            mutatedStage.discard()
            check(try files(target) == before, name + " rejected source/stage installation retains every original byte and receipt")
            try fm.removeItem(at: extracted); try fm.createSymbolicLink(at: extracted, withDestinationURL: originalFile)
            rejects(name + " photo symbolic link rejects without following original JPEG") { _ = try payload() }
            try fm.removeItem(at: extracted); try fm.createDirectory(at: extracted, withIntermediateDirectories: false)
            rejects(name + " photo directory rejects") { _ = try payload() }
            try fm.removeItem(at: extracted)
            rejects(name + " missing photo rejects unless explicitly omitted") { _ = try payload() }
            var omittedSource = source; omittedSource.omittedPhotoCount = identities.count
            let omitted = try payload(Set(identities.keys), source: omittedSource), omissionTarget = try seed(name + "-omitted")
            try HealthRecoverySelection.prepare(omitted, into: omissionTarget, owner: owner).commit()
            let omittedMeals = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: omissionTarget.appendingPathComponent("meals.json")))
            check(omittedMeals.count == 2 && omittedMeals.allSatisfy { $0.photoID == nil }, name + " explicit omission preserves both meal records without photo references")
            let omittedReceiptURL = try fm.contentsOfDirectory(at: omissionTarget.appendingPathComponent(".health-recovery-history"), includingPropertiesForKeys: nil)[0]
            let omittedReceipt = try JSONSerialization.jsonObject(with: Data(contentsOf: omittedReceiptURL)) as! [String: Any]
            check(omittedReceipt["omittedPhotoCount"] as? Int == identities.count
                && (omittedReceipt["reviewedPhotos"] as? [String: Any])?.isEmpty == true
                && (omittedReceipt["photoDigests"] as? [String: String])?.isEmpty == true,
                name + " omission receipt counts unique omitted photos and claims no recovered photo bytes")
            try original.write(to: extracted)
            let handle = try FileHandle(forWritingTo: extracted); try handle.truncate(atOffset: UInt64(BackupArchive.maxPhotoBytes + 1)); try handle.close()
            rejects(name + " sparse oversized extracted photo rejects before a full read") { _ = try payload() }
            check(try Data(contentsOf: originalFile) == original, name + " original independent JPEG remains unchanged across unsafe-source failures")
          }
        }
        weak var observedPhotoOwner: BackupWorkspace?
        let lifetimeTarget = try seed("last-photo-owner"), lifetimeOwner = UUID()
        func prepareOwnedPhotos() throws -> (BackupFileTransaction, URL) {
            let originalOwner = try BackupWorkspace(base: root), photoOwner = try BackupWorkspace(base: root)
            observedPhotoOwner = photoOwner
            let input = originalOwner.directory.appendingPathComponent("selected-backup"), photo = photoOwner.directory.appendingPathComponent("reviewed.jpg")
            try Data("synthetic selected input lease".utf8).write(to: input); try original.write(to: photo)
            let identity = try BackupSourceIdentity.measure(input, named: "owned-source", format: .legacyJSONBackup, limit: 100)
            var meal = Meal(id: "owned-photo", type: .lunch, items: []); meal.photoID = "owned"
            let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [meal], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
            let source = BackupRecoverySource(lease: .init(file: input, identity: identity, workspace: originalOwner), photoWorkspace: photoOwner, contents: nil, photoIdentities: ["owned": originalIdentity])
            let payload = try HealthRecoverySelection.backup(snapshot, photos: ["owned": photo], domains: [.meals], source: source, validPhoto: valid)
            return (try HealthRecoverySelection.prepare(payload, into: lifetimeTarget, owner: lifetimeOwner), photo)
        }
        var held: (BackupFileTransaction, URL)? = try prepareOwnedPhotos()
        let heldPhoto = held!.1
        BackupWorkspace.finishCleanupForVerification()
        check(observedPhotoOwner != nil && fm.fileExists(atPath: heldPhoto.path), "prepared transaction alone retains the separately owned extracted photo workspace after payload/UI release")
        try held!.0.commit()
        check(observedPhotoOwner != nil && fm.fileExists(atPath: heldPhoto.path), "final source checks can still read exact extracted photo through actual installation")
        held = nil; BackupWorkspace.finishCleanupForVerification()
        check(observedPhotoOwner == nil && !fm.fileExists(atPath: heldPhoto.path), "final transaction release retires only its last-owned photo workspace")
        let sameRootOutput = root.appendingPathComponent("same-root-outcome.json")
        try runOwnLinkBaseline(output: sameRootOutput, expectingRejection: false)
        let sameRoot = try JSONSerialization.jsonObject(with: Data(contentsOf: sameRootOutput))
        check(true, "actual same-root retained meal/photo recovery succeeds through private-copy hardlink preservation")
        if let output {
            try JSONSerialization.data(withJSONObject: ["status": "passed", "count": checks.count, "checks": checks,
                "sameRootOutcome": sameRoot,
                "scope": "Actual legacy/encrypted readers, original photo digests, shared/two/empty photos, real staging/source/stage mutation failures, omission and receipts. Native UIKit service and actual Files/meal/photo UI remain separately required."], options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }

    static func runOwnLinkBaseline(output: URL, expectingRejection: Bool = true) throws {
        let fm = FileManager.default, base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let root = fm.temporaryDirectory.appendingPathComponent("Lumen-photo-own-link-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        var completed = false
        defer { if completed { try? fm.removeItem(at: root) } }
        let target = root.appendingPathComponent("current"), previous = target.appendingPathExtension("previous")
        try fm.createDirectory(at: target.appendingPathComponent("photos"), withIntermediateDirectories: true)
        let photo = try Data(contentsOf: base.appendingPathComponent("Design/native/health-write-order/health-backup-photo-original-r1.jpg"))
        var meal = Meal(id: "same-root-retained-meal", type: .lunch, items: []); meal.photoID = "same-root"
        let encoder = BackupArchive.encoder(), owner = UUID()
        for (file, bytes) in try ConversationFiles.encoded([], activeID: nil) { try bytes.write(to: target.appendingPathComponent(file)) }
        try encoder.encode([meal]).write(to: target.appendingPathComponent("meals.json"))
        try encoder.encode([HydrationLog]()).write(to: target.appendingPathComponent("water.json"))
        try encoder.encode([Workout]()).write(to: target.appendingPathComponent("workouts.json"))
        try encoder.encode(HealthGoals()).write(to: target.appendingPathComponent("goals.json"))
        try encoder.encode(DayMetrics.empty).write(to: target.appendingPathComponent("today.json"))
        try HealthWriteJournal(owner: owner).encoded().write(to: target.appendingPathComponent(HealthWriteFiles.name))
        try photo.write(to: target.appendingPathComponent("photos/same-root.jpg"))
        try fm.copyItem(at: target, to: previous)
        let damaged = Data("{\"syntheticUnavailableMeals\":".utf8)
        try damaged.write(to: target.appendingPathComponent("meals.json"), options: .atomic)
        try BackupFiles.openDirectory(target, createIfMissing: false)
        let preview = try HealthRecoveryCopies.discover(in: target).first!
        let sourcePhoto = target.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(preview.id).appendingPathComponent("photos/same-root.jpg")
        let payload = try HealthRecoverySelection.retained(preview, in: target, domains: [.meals], validPhoto: { file in
            guard let data = try? Data(contentsOf: file), let image = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
            return CGImageSourceCreateImageAtIndex(image, 0, nil) != nil
        })
        let transaction = try HealthRecoverySelection.prepare(payload, into: target, owner: owner)
        func stamp() throws -> [String: String] {
            var value = stat(); guard lstat(sourcePhoto.path, &value) == 0 else { throw BackupError.invalid }
            return ["inode": String(value.st_ino), "size": String(value.st_size), "links": String(value.st_nlink),
                    "mtime": "\(value.st_mtimespec.tv_sec).\(value.st_mtimespec.tv_nsec)",
                    "ctime": "\(value.st_ctimespec.tv_sec).\(value.st_ctimespec.tv_nsec)"]
        }
        let before = try stamp()
        var rejected = false, failure = ""
        do { try transaction.commit() } catch { rejected = true; failure = String(describing: error) }
        let after = try stamp()
        guard rejected == expectingRejection, try Data(contentsOf: sourcePhoto) == photo,
              before["inode"] == after["inode"], before["size"] == after["size"], before["mtime"] == after["mtime"],
              before["ctime"] != after["ctime"] else { throw BackupError.invalid }
        var recoveredPhoto: String? = nil
        if expectingRejection {
            guard try Data(contentsOf: target.appendingPathComponent("meals.json")) == damaged else { throw BackupError.invalid }
        } else {
            let recovered = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: target.appendingPathComponent("meals.json")))
            guard recovered.count == 1, recovered[0].id == meal.id, let id = recovered[0].photoID,
                  try Data(contentsOf: target.appendingPathComponent("photos/" + id + ".jpg")) == photo else { throw BackupError.invalid }
            recoveredPhoto = id
        }
        var report: [String: Any] = ["status": expectingRejection ? "REPRODUCED: unchanged same-root retained photo recovery rejected after own hardlink preservation" : "passed: same-root retained meal and exact photo recover through own hardlinks",
            "failure": failure, "before": before, "after": after, "sourcePhotoSHA256": BackupArchive.digest(photo),
            "originalPhotoBytes": photo.base64EncodedString(), "damagedMealBytes": damaged.base64EncodedString(),
            "scope": "Actual previous-copy discovery, retained-photo payload, same-root preparation and commit. Exact source bytes/inode/size/mtime unchanged; own preserve-copy links change ctime. Foundation filesystem case, not native UI or full photo acceptance."]
        if let recoveredPhoto { report["recoveredPhotoID"] = recoveredPhoto; report["recoveredPhotoSHA256"] = BackupArchive.digest(photo) }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        transaction.discard()
        completed = true
        print(expectingRejection ? "REPRODUCED: same-root retained photo rejected with unchanged bytes and own ctime/link changes" : "CHECKED: same-root retained photo installs exact reviewed bytes through own hardlinks")
    }
}
