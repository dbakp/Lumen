import Foundation
import CryptoKit
import ImageIO

/// Small opt-in inputs for actual Files-picker recovery checks. No user data,
/// photos, large histories or credentials are read. The password is synthetic.
enum HealthBackupUIFixtures {
    static let password = "Synthetic backup passphrase 42"

    static func writePhotos(to folder: URL, photo: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { throw BackupError.invalid }
        let bytes = try HealthLocalFiles.readRegularData(photo, limit: 4096)
        guard let image = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetType(image) as String? == "public.jpeg", CGImageSourceGetCount(image) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyOrientation] as? Int == 6,
              properties[kCGImagePropertyPixelWidth] as? Int == 72,
              properties[kCGImagePropertyPixelHeight] as? Int == 48 else { throw BackupError.invalid }
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let date = Date(timeIntervalSince1970: 1_793_620_800), id = "synthetic-file-review-photo"
        let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [],
            meals: [Meal(id: "synthetic-file-photo-meal", date: date, type: .lunch, items: [], photoID: id)],
            workouts: [], water: [HydrationLog(id: "synthetic-file-photo-water", date: date, ml: 246)],
            conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        let encrypted = folder.appendingPathComponent("Lumen-backup-health-photo-encrypted.lumenbackup")
        try BackupPackage.write(snapshot, photos: [id: photo], password: password, to: encrypted, now: date)
        var legacy = snapshot; legacy.photos = [id: bytes]
        let plain = folder.appendingPathComponent("Lumen-backup-health-photo-legacy.json")
        try BackupArchive.make(legacy, now: date).write(to: plain, options: .atomic)
        let opened = try BackupPackage.read(encrypted, password: password, temporaryRoot: folder)
        defer { opened.removeTemporaryFiles() }
        let (_, decoded) = try BackupArchive.read(Data(contentsOf: plain))
        guard opened.snapshot.meals.first?.photoID == id, opened.photos.count == 1,
              let extracted = opened.photos[id], try Data(contentsOf: extracted) == bytes,
              decoded.meals.first?.photoID == id, decoded.photos == [id: bytes] else { throw BackupError.invalid }
        var rows: [String: [String: String]] = [:]
        for file in [plain, encrypted] {
            let data = try Data(contentsOf: file)
            guard data.count < 256 * 1024 else { throw BackupError.tooLarge }
            rows[file.lastPathComponent] = ["bytes": String(data.count), "sha256": BackupArchive.digest(data)]
        }
        let manifest: [String: Any] = ["files": rows, "photoBytes": bytes.count, "photoSHA256": BackupArchive.digest(bytes),
            "photoID": id, "orientation": 6, "width": 72, "height": 48,
            "scope": "One actual known synthetic EXIF6 JPEG and meal in legacy/encrypted backups; no readable-export photos or larger photo matrix acceptance."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("health-backup-photo-manifest.json"), options: .atomic)
        print("Two small synthetic meal-photo backups checked through real readers; JPEG bytes exact.")
    }

    static func writeMultipleDomains(to folder: URL, photo: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { throw BackupError.invalid }
        let photoBytes = try HealthLocalFiles.readRegularData(photo, limit: 256 * 1024)
        guard CGImageSourceCreateWithData(photoBytes as CFData, nil) != nil else { throw BackupError.invalid }
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let date = Date(timeIntervalSince1970: 1_793_620_800), photoID = "synthetic-multi-shared-photo"
        let food = FoodItem(id: "synthetic-multi-food", name: "Synthetic tofu", grams: 125, calories: 190, proteinG: 20.25, carbsG: 3.5, fatG: 0, fiberG: 1.5, confidence: 0.84)
        var unknown = Workout(id: "synthetic-multi-unknown", kind: .walk, title: "Recovered walk", start: date, duration: 1200, activeCalories: 0, source: .manual)
        unknown.energyKnown = false; unknown.note = "Energy wasn't supplied."
        var zero = Workout(id: "synthetic-multi-zero", kind: .strength, title: "Recovered zero", start: date.addingTimeInterval(3600), duration: 1800, activeCalories: 0, distanceM: 0, avgHR: 94.5, source: .healthKit)
        zero.energyKnown = true; zero.energyIsEstimate = false
        var goals = HealthGoals(); goals.stepGoal = 321; goals.weightKg = nil; goals.heightCm = nil; goals.age = nil
        let snapshot = BackupSnapshot(profile: .default, goals: goals, habits: [], sleep: [],
            meals: [Meal(id: "synthetic-multi-meal-a", date: date, type: .lunch, items: [food], photoID: photoID, note: "First shared photo.", source: .manual),
                    Meal(id: "synthetic-multi-meal-b", date: date.addingTimeInterval(3600), type: .snack, items: [], photoID: photoID, source: .manual)],
            workouts: [unknown, zero], water: [HydrationLog(id: "synthetic-multi-water", date: date, ml: 246)],
            conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        let encrypted = folder.appendingPathComponent("Lumen-backup-health-multi-encrypted.lumenbackup")
        try BackupPackage.write(snapshot, photos: [photoID: photo], password: password, to: encrypted, now: date)
        var legacy = snapshot; legacy.photos = [photoID: photoBytes]
        let plain = folder.appendingPathComponent("Lumen-backup-health-multi-legacy.json")
        try BackupArchive.make(legacy, now: date).write(to: plain, options: .atomic)
        let readable = folder.appendingPathComponent("Lumen-readable-health-multi.json")
        try ReadableExport.write(snapshot, to: readable, now: date)
        let opened = try BackupPackage.read(encrypted, password: password, temporaryRoot: folder)
        defer { opened.removeTemporaryFiles() }
        let (_, decoded) = try BackupArchive.read(Data(contentsOf: plain))
        let converted = try ReadableExport.read(Data(contentsOf: readable))
        let (readableSnapshot, _) = try converted.selected([.water, .meals, .workouts, .goals])
        let encoder = BackupArchive.encoder()
        var expected: [String: Any] = [:]
        for (domain, bytes) in [("water", try encoder.encode(snapshot.water)), ("meals", try encoder.encode(snapshot.meals)),
                                ("workouts", try encoder.encode(snapshot.workouts)), ("goals", try encoder.encode(snapshot.goals))] {
            expected[domain] = try JSONSerialization.jsonObject(with: bytes)
        }
        guard try encoder.encode(opened.snapshot.water) == encoder.encode(snapshot.water),
              try encoder.encode(opened.snapshot.meals) == encoder.encode(snapshot.meals),
              try encoder.encode(opened.snapshot.workouts) == encoder.encode(snapshot.workouts),
              try encoder.encode(opened.snapshot.goals) == encoder.encode(snapshot.goals),
              try encoder.encode(decoded.meals) == encoder.encode(snapshot.meals),
              let extracted = opened.photos[photoID], try Data(contentsOf: extracted) == photoBytes,
              decoded.photos == [photoID: photoBytes], converted.missingPhotos == 2,
              readableSnapshot.meals.allSatisfy({ $0.photoID == nil }),
              try encoder.encode(readableSnapshot.workouts) == encoder.encode(snapshot.workouts),
              try encoder.encode(readableSnapshot.goals) == encoder.encode(snapshot.goals) else { throw BackupError.invalid }
        var rows: [String: Any] = [:]
        for file in [plain, encrypted, readable] {
            let bytes = try Data(contentsOf: file); guard bytes.count < 256 * 1024 else { throw BackupError.tooLarge }
            rows[file.lastPathComponent] = ["bytes": bytes.count, "sha256": BackupArchive.digest(bytes)]
        }
        let manifest: [String: Any] = ["files": rows, "expectedRecords": expected, "photoID": photoID,
            "photoBytes": photoBytes.count, "photoSHA256": BackupArchive.digest(photoBytes),
            "scope": "Four selected unavailable domains; two meals share one photo, unknown/zero energy and optional target values. Readable export omits both meal photo references; not healthy merge or full photo matrix."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("health-backup-multi-manifest.json"), options: .atomic)
        print("Four-domain recovery inputs checked through all three real readers; shared photo exact, readable omissions explicit.")
    }

    static func write(to folder: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { throw BackupError.invalid }
        try fm.createDirectory(at: folder, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        let date = Date(timeIntervalSince1970: 1_793_620_800)
        var profile = UserProfile.default
        profile.name = "Synthetic backup recovery"
        let snapshot = BackupSnapshot(
            profile: profile, goals: .init(), habits: [], sleep: [], meals: [],
            workouts: [], water: [HydrationLog(id: "synthetic-backup-recovery-water", date: date, ml: 246)],
            conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [],
            imports: [], personalContext: .init(), photos: [:])
        let encrypted = folder.appendingPathComponent("Lumen-backup-health-encrypted-small.lumenbackup")
        try BackupPackage.write(snapshot, photos: [:], password: password, to: encrypted)
        let legacy = folder.appendingPathComponent("Lumen-backup-health-legacy-small.json")
        try BackupArchive.make(snapshot, now: date).write(to: legacy, options: .atomic)
        let readable = folder.appendingPathComponent("Lumen-readable-health-small.json")
        try ReadableExport.write(snapshot, to: readable, now: date)
        // Check the actual generated formats through their real readers before
        // offering any of them to the native file importer.
        let opened = try BackupPackage.read(encrypted, password: password, temporaryRoot: folder)
        let expected = try BackupArchive.encoder().encode(snapshot.water)
        guard try BackupArchive.encoder().encode(opened.snapshot.water) == expected else { throw BackupError.invalid }
        let (_, old) = try BackupArchive.read(Data(contentsOf: legacy))
        let converted = try ReadableExport.read(Data(contentsOf: readable))
        let (plain, _) = try converted.selected([.water])
        guard try BackupArchive.encoder().encode(old.water) == expected,
              try BackupArchive.encoder().encode(plain.water) == expected else { throw BackupError.invalid }
        var rows: [String: [String: String]] = [:]
        for file in [encrypted, legacy, readable] {
            let bytes = try Data(contentsOf: file)
            guard bytes.count < 256 * 1024 else { throw BackupError.tooLarge }
            rows[file.lastPathComponent] = [
                "bytes": String(bytes.count),
                "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            ]
        }
        let manifest = try JSONSerialization.data(withJSONObject: [
            "scope": "Synthetic 246mL water, three distinct product input formats; no cache/photos/large history claim",
            "files": rows
        ], options: [.prettyPrinted, .sortedKeys])
        try manifest.write(to: folder.appendingPathComponent("health-backup-small-manifest.json"), options: .atomic)
        print("Small synthetic recovery inputs checked: encrypted backup, legacy JSON backup and readable export.")
    }
}
