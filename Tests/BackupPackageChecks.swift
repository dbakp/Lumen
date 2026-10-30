import Foundation
import AppleArchive
import System

/// Exercises the production stream with actual encrypted files and hostile authenticated payloads.
enum BackupPackageChecks {
    static func run(in parent: URL, sample: BackupSnapshot) throws {
        func check(_ value: Bool, _ label: String) { precondition(value, label); print("PASS: " + label) }
        let fm = FileManager.default, root = parent.appendingPathComponent("encrypted-backup-checks")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let previews = root.appendingPathComponent("previews"); try fm.createDirectory(at: previews, withIntermediateDirectories: true)
        let password = "Synthetic backup passphrase 42"
        var snapshot = sample; snapshot.photos = [:]
        var photos: [String: URL] = [:]
        for (id, bytes) in sample.photos { let file = root.appendingPathComponent(id + ".jpg"); try bytes.write(to: file); photos[id] = file }
        let first = root.appendingPathComponent("first.lumenbackup")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let control = BackupOperationControl()
        try BackupPackage.write(snapshot, photos: photos, password: password, to: first, now: now, control: control)
        let restored = try BackupPackage.read(first, password: password, temporaryRoot: previews)
        defer { restored.removeTemporaryFiles() }
        check(restored.manifest.createdAt == now && restored.manifest.version == 2, "encrypted backup keeps its authenticated date and format version")
        check(tryEqual(snapshot, restored.snapshot), "streamed records preserve every legacy model field without a whole-archive payload")
        var local = snapshot; local.meals = []; local.documents = []; local.symptoms[0].note = "Newer local edit"
        let fileMerge = try restored.snapshot.mergingFileBacked(into: local, restorePreferences: false, photoFiles: restored.photos)
        let copiedID = fileMerge.snapshot.meals[0].photoID!
        check(copiedID != "photo-1" && fileMerge.photos[copiedID] == restored.photos["photo-1"] && fileMerge.snapshot.photos.isEmpty, "file-backed restore remaps photo identities without loading their bytes")
        check(fileMerge.snapshot.symptoms[0].note == "Newer local edit" && !fileMerge.snapshot.documents[0].includeInAssistant, "file-backed restore uses the existing current-copy and fresh-consent rules")
        let mergedAgain = try restored.snapshot.mergingFileBacked(into:fileMerge.snapshot, restorePreferences:false, photoFiles:restored.photos)
        check(mergedAgain.snapshot.recordCount == fileMerge.snapshot.recordCount && mergedAgain.photos.isEmpty, "repeated file-backed restore adds neither duplicate records nor photo copies")
        let photo = try Data(contentsOf: restored.photos["photo-1"]!)
        check(photo == sample.photos["photo-1"] && restored.snapshot.photos.isEmpty, "photos round-trip through private files without populating an in-memory photo dictionary")
        check(control.progress.completed == control.progress.total && control.progress.completed > 0, "encrypted creation reports actual completed records and photos")
        let encrypted = try Data(contentsOf: first)
        check(encrypted.range(of: Data("Imported focus".utf8)) == nil && encrypted.range(of: Data("Headache".utf8)) == nil, "shared archive bytes do not expose plaintext health notes")
        let second = root.appendingPathComponent("second.lumenbackup")
        try BackupPackage.write(snapshot, photos: photos, password: password, to: second, now: now)
        let other = try Data(contentsOf: second)
        check(other != encrypted, "identical backups and passwords produce independently randomized encrypted containers")
        func reject(_ action: () throws -> Void, _ label: String) {
            do { try action(); fatalError(label) } catch { print("PASS: " + label) }
        }
        var invalidLocal = local; invalidLocal.importedDays = [sample.importedDays[0], sample.importedDays[0]]
        do {
            _ = try restored.snapshot.mergingFileBacked(into:invalidLocal,restorePreferences:false,photoFiles:restored.photos)
            fatalError("Malformed current identities were accepted")
        } catch BackupError.currentDataInvalid { print("PASS: malformed current identities fail before merging and identify the current data as the problem") }
        reject({ _ = try restored.snapshot.mergingFileBacked(into:local,restorePreferences:false,photoFiles:[:]) }, "file-backed merge refuses missing incoming meal-photo references")
        reject({ _ = try BackupPackage.read(first, password: "Different password", temporaryRoot: previews) }, "wrong passwords never produce a preview")
        let previewCount = try fm.contentsOfDirectory(atPath: previews.path).count
        let broken = root.appendingPathComponent("tampered.lumenbackup")
        var altered = encrypted; altered[altered.count / 2] ^= 0x01; try altered.write(to: broken)
        reject({ _ = try BackupPackage.read(broken, password: password, temporaryRoot: previews) }, "ciphertext modification is rejected before records become restorable")
        try encrypted.dropLast(128).write(to: broken)
        reject({ _ = try BackupPackage.read(broken, password: password, temporaryRoot: previews) }, "truncated encrypted containers cannot be accepted as complete backups")
        check(try fm.contentsOfDirectory(atPath: previews.path).count == previewCount, "failed unlocks and corrupt files leave no decrypted preview directories")
        reject({ try BackupPackage.write(snapshot, photos: photos, password: "short", to: root.appendingPathComponent("short")) }, "new encrypted backups require the stated minimum passphrase length")
        reject({ try BackupPackage.write(snapshot, photos: photos, password: password, to: first) }, "encrypted creation refuses to replace an existing destination")
        check(try Data(contentsOf: first) == encrypted, "a refused overwrite leaves the prior backup byte-for-byte intact")
        let cancelled = BackupOperationControl(); cancelled.cancel()
        reject({ try BackupPackage.write(snapshot, photos: photos, password: password, to: root.appendingPathComponent("cancelled"), control: cancelled) }, "cancelled creation publishes no archive")
        reject({ _ = try BackupPackage.read(first, password: password, temporaryRoot: previews, control: cancelled) }, "cancelled reading returns no preview")

        // A genuinely >100 MB encrypted archive, using incompressible synthetic bytes.
        let random = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/urandom")); defer { try? random.close() }
        let noise = try random.read(upToCount: 4 * 1024 * 1024)!
        let photoFile = root.appendingPathComponent("synthetic-random-photo"); try noise.write(to: photoFile)
        var large = snapshot; large.meals = (0..<27).map { Meal(id:"large-meal-\($0)", type:.lunch, items:[], photoID:"large-photo-\($0)") }
        let largePhotos = Dictionary(uniqueKeysWithValues: (0..<27).map { ("large-photo-\($0)", photoFile) })
        let big = root.appendingPathComponent("large.lumenbackup")
        try BackupPackage.write(large, photos: largePhotos, password: password, to: big)
        let fileSize = try big.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        check(fileSize > BackupArchive.maxBytes, "streamed encrypted backups exceed the legacy 100 MB file ceiling with real output bytes")
        let largeRead = try BackupPackage.read(big, password: password, temporaryRoot: previews)
        check(largeRead.photos.count == 27 && largeRead.snapshot.meals.count == 27 && largeRead.snapshot.photos.isEmpty, "a backup above 100 MB is read into bounded photo files and complete record metadata")
        let lastPhoto = try Data(contentsOf: largeRead.photos["large-photo-26"]!)
        check(lastPhoto == noise, "large-archive photo bytes retain their exact content")
        largeRead.removeTemporaryFiles()
        final class CancelBox: @unchecked Sendable { weak var control: BackupOperationControl? }
        let writeBox = CancelBox()
        let midWrite = BackupOperationControl { p in if p.bytes > 8 * 1024 * 1024 { writeBox.control?.cancel() } }; writeBox.control = midWrite
        let stopped = root.appendingPathComponent("stopped.lumenbackup")
        reject({ try BackupPackage.write(large, photos: largePhotos, password: password, to: stopped, control: midWrite) }, "cancellation after photo streaming starts discards the incomplete encrypted file")
        let rootFiles = try fm.contentsOfDirectory(atPath: root.path)
        check(!fm.fileExists(atPath: stopped.path) && rootFiles.allSatisfy { !$0.hasSuffix(".partial") }, "cancelled creation removes its own partial file and publishes nothing")
        let readBox = CancelBox()
        let midRead = BackupOperationControl { p in if p.bytes > 8 * 1024 * 1024 { readBox.control?.cancel() } }; readBox.control = midRead
        reject({ _ = try BackupPackage.read(big, password: password, temporaryRoot: previews, control: midRead) }, "cancellation during decrypted-photo staging returns no restore preview")
        check(try fm.contentsOfDirectory(atPath: previews.path).count == previewCount, "cancellation removes all decrypted staged photos")
        let link = root.appendingPathComponent("photo-link"); try fm.createSymbolicLink(at: link, withDestinationURL: photoFile)
        var linked = photos; linked["photo-1"] = link
        reject({ try BackupPackage.write(snapshot, photos: linked, password: password, to: root.appendingPathComponent("link-backup")) }, "photo symlinks cannot redirect encrypted backup reads")

        // Authenticate malformed record streams with the platform codec to exercise parser boundaries.
        func seal(_ plaintext: Data, to url: URL) throws {
            let c = ArchiveEncryptionContext(profile: .hkdf_sha256_aesctr_hmac__scrypt__none, compressionAlgorithm:.lzfse)
            try c.setPassword(password)
            let file = ArchiveByteStream.fileStream(path:FilePath(url.path), mode:.writeOnly, options:[.create,.truncate], permissions:FilePermissions(rawValue:0o600))!
            let stream = ArchiveByteStream.encryptionStream(writingTo:file, encryptionContext:c,threadCount:1)!
            defer { try? stream.close(); try? file.close() }
            try plaintext.withUnsafeBytes { b in var n=0; while n<b.count { n += try stream.write(from:UnsafeRawBufferPointer(rebasing:b[n...])) } }
            try stream.close(); try file.close()
        }
        func frame(_ kind: String, bytes: Data, id: String? = nil, declaredLength: Int? = nil) throws -> Data {
            var header: [String:Any] = ["kind":kind,"length":declaredLength ?? bytes.count]
            if let id { header["id"] = id }
            let h = try JSONSerialization.data(withJSONObject: header, options:.sortedKeys)
            var n = UInt32(h.count).bigEndian
            return withUnsafeBytes(of:&n) { Data($0) } + h + bytes
        }
        let manifest = try BackupArchive.encoder().encode(restored.manifest)
        let head = try frame("manifest", bytes:manifest)
        let hostile = root.appendingPathComponent("hostile.lumenbackup")
        func rejectsStream(_ plaintext: Data, _ label: String) throws {
            try seal(plaintext, to:hostile)
            reject({ _ = try BackupPackage.read(hostile, password:password, temporaryRoot:previews) }, label)
        }
        try rejectsStream(Data([255,255,255,255]), "authenticated oversized frame headers are rejected before allocation")
        try rejectsStream(head + frame("photo", bytes:Data([1]), id:"../outside"), "authenticated photo path traversal is rejected without writing outside preview storage")
        try rejectsStream(head + frame("documents", bytes:Data(), declaredLength:Int.max), "authenticated oversized record lengths are rejected before allocation")
        try rejectsStream(head + frame("unknown-domain", bytes:Data([1])), "unknown archive domains are rejected rather than silently restored")
        try rejectsStream(head + frame("end", bytes:Data()), "a valid encrypted end marker cannot hide missing declared records")
        try rejectsStream(head, "an authenticated but incomplete record stream cannot become a preview")
        check(try fm.contentsOfDirectory(atPath: previews.path).count == previewCount && !fm.fileExists(atPath:root.appendingPathComponent("outside").path), "hostile authenticated streams clean their owned staging directories and cannot escape them")
        var oversized = snapshot
        oversized.documents[0].body = String(repeating:"x",count:BackupPackage.maxRecordBytes)
        reject({ try BackupPackage.write(oversized, photos:photos, password:password,to:root.appendingPathComponent("oversized")) }, "a single oversized record is rejected without publishing a backup")
        // A sparse file exercises the actual input-size guard without allocating 2 GiB.
        let oversizedInput = root.appendingPathComponent("over-limit.lumenbackup")
        try Data().write(to:oversizedInput)
        let oversizedHandle = try FileHandle(forWritingTo:oversizedInput)
        try oversizedHandle.truncate(atOffset:UInt64(BackupPackage.maxFileBytes + 1)); try oversizedHandle.close()
        do {
            _ = try BackupPackage.read(oversizedInput,password:password,temporaryRoot:previews)
            fatalError("Oversized encrypted input was accepted")
        } catch BackupPackage.PackageError.tooLarge { print("PASS: the actual 2 GiB input-size guard rejects an oversized sparse file before decryption") }
        try fm.removeItem(at:oversizedInput)
        // File-backed restore is prepared separately from its short storage commit.
        let store = root.appendingPathComponent("LumenData")
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        let original = Data("original records".utf8), updated = Data("merged records".utf8)
        try original.write(to: store.appendingPathComponent("water.json"))
        try Data("preserve future domain".utf8).write(to: store.appendingPathComponent("future-domain.json"))
        let revisions = BackupStorageRevision(), captured = revisions.current
        let prepared = try BackupFileTransaction.prepare(["water.json":updated], photoFiles:["photos/new-photo.jpg":photos["photo-1"]!], into:store)
        check(try Data(contentsOf:store.appendingPathComponent("water.json")) == original && !fm.fileExists(atPath:store.appendingPathComponent("photos/new-photo.jpg").path), "restore preparation cannot alter current records or photos")
        try revisions.commit(ifUnchanged:captured) { try prepared.commit() }
        check(try Data(contentsOf:store.appendingPathComponent("water.json")) == updated && Data(contentsOf:store.appendingPathComponent("photos/new-photo.jpg")) == sample.photos["photo-1"], "a prepared restore installs its merged records and streamed photos together")
        check(try String(contentsOf:store.appendingPathComponent("future-domain.json")) == "preserve future domain", "file-backed restore preserves unknown local domains")
        reject({ try prepared.commit() }, "a prepared restore cannot be installed twice")
        let staleRevision = revisions.current
        let stale = try BackupFileTransaction.prepare(["water.json":original],photoFiles:[:],into:store)
        revisions.write { try? Data("newer current edit".utf8).write(to:store.appendingPathComponent("water.json")) }
        reject({ try revisions.commit(ifUnchanged:staleRevision) { try stale.commit() } }, "a local write during preparation rejects the stale restore commit")
        stale.discard()
        check(try String(contentsOf:store.appendingPathComponent("water.json")) == "newer current edit", "a rejected stale restore leaves the newer edit intact")
        reject({ _ = try BackupFileTransaction.prepare(["../escape":original],photoFiles:[:],into:store) }, "restore staging rejects paths outside its owned directory")
        let stageCount = try fm.contentsOfDirectory(atPath:root.path).filter { $0.contains(".restore-") }.count
        let cloneBox = CancelBox()
        let stopClone = BackupOperationControl { progress in if progress.bytes > 0 { cloneBox.control?.cancel() } }; cloneBox.control = stopClone
        reject({ _ = try BackupFileTransaction.prepare(["water.json":original],photoFiles:[:],into:store,control:stopClone) }, "restore cancellation stops before installing the prepared directory")
        check(try fm.contentsOfDirectory(atPath:root.path).filter { $0.contains(".restore-") }.count == stageCount && String(contentsOf:store.appendingPathComponent("water.json")) == "newer current edit", "cancelled restore removes staged files and preserves current records")
        let storeLink = store.appendingPathComponent("external-link")
        try fm.createSymbolicLink(at:storeLink,withDestinationURL:photoFile)
        reject({ _ = try BackupFileTransaction.prepare([:],photoFiles:[:],into:store) }, "restore refuses to copy symlinks from existing local storage")
        try fm.removeItem(at:storeLink)
        let failedWriteRevision = revisions.current
        reject({ try revisions.write { throw BackupError.invalid } }, "failed local writes retain their reported failure")
        check(revisions.current != failedWriteRevision, "even an attempted local mutation invalidates an in-flight restore")
        final class Counter: @unchecked Sendable {
            private let lock = NSLock(); private var count = 0
            func add() { lock.lock(); count += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        }
        let cancellationCount = Counter(), providerControl = BackupOperationControl()
        providerControl.cancel()
        providerControl.setCancellationHandler { cancellationCount.add() }
        check(cancellationCount.value == 1, "provider cancellation registered after a cancel request runs immediately")
        providerControl.setCancellationHandler(nil); providerControl.cancel()
        check(cancellationCount.value == 1, "completed provider operations release their cancellation handler")
        let raceRevision = BackupStorageRevision(), raceGeneration = raceRevision.current
        let writerEntered = DispatchSemaphore(value:0), releaseWriter = DispatchSemaphore(value:0)
        let writerDone = DispatchSemaphore(value:0), commitDone = DispatchSemaphore(value:0), installed = Counter(), rejected = Counter()
        DispatchQueue.global().async {
            raceRevision.write { writerEntered.signal(); _ = releaseWriter.wait(timeout:.now()+10) }
            writerDone.signal()
        }
        check(writerEntered.wait(timeout:.now()+10) == .success, "a real concurrent local writer enters the storage barrier")
        DispatchQueue.global().async {
            do { try raceRevision.commit(ifUnchanged:raceGeneration) { installed.add() } }
            catch BackupError.recordsChanged { rejected.add() }
            catch { }
            commitDone.signal()
        }
        check(commitDone.wait(timeout:.now()+0.05) == .timedOut, "restore cannot commit while a concurrent local writer holds the barrier")
        releaseWriter.signal()
        check(writerDone.wait(timeout:.now()+10) == .success && commitDone.wait(timeout:.now()+10) == .success && installed.value == 0 && rejected.value == 1, "the waiting restore observes the completed write and rejects its stale revision")
        // Legacy compatibility is independent of the new authenticated stream format.
        let legacy = try BackupArchive.make(sample)
        let decoded = try BackupArchive.read(legacy)
        check(decoded.0.version == 1 && decoded.1.photos == sample.photos, "existing version-one JSON backups remain readable after the streamed format is introduced")
    }
    private static func tryEqual(_ a: BackupSnapshot, _ b: BackupSnapshot) -> Bool {
        (try? BackupArchive.encoder().encode(a)) == (try? BackupArchive.encoder().encode(b))
    }
}
