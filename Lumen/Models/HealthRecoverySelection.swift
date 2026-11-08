import Foundation
import CryptoKit

/// An explicitly chosen replacement for failed local health domains. This is
/// separate from ordinary backup merge and never imports external-work intent.
enum HealthRecoverySelection {
    struct Payload: Sendable {
        let domains: Set<HealthLocalFiles.Domain>
        fileprivate let files: [String: Data]
        fileprivate let photos: [String: URL]
        fileprivate let photoDigests: [String: String]
        fileprivate let source: String
        fileprivate var fileSource: BackupRecoverySource? = nil
        fileprivate var reviewedPhotos: [String: BackupPhotoIdentity] = [:]
        fileprivate var legacyOrigins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin] = [:]

        /// Expose only the acquisition rule, never the retained raw observations.
        var requiresExistingLegacyRoot: Bool { !legacyOrigins.isEmpty }
    }

    /// Attach observations owned by the same explicit review; never recapture a
    /// changed value while retrying or silently authorize an unselected domain.
    static func bindingLegacyOrigins(_ origins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin], to payload: Payload) throws -> Payload {
        guard payload.legacyOrigins.isEmpty, Set(origins.keys).isSubset(of: payload.domains),
              origins.allSatisfy({ $0.key == $0.value.value.domain }),
              origins.values.reduce(0, { $0 + $1.value.bytes.count }) <= HealthLegacyRecoveryOrigin.aggregateLimit else { throw BackupError.invalid }
        var bound = payload; bound.legacyOrigins = origins; return bound
    }

    static func records(_ reviewed: HealthRecoveryCopies.Preview, domain: HealthLocalFiles.Domain, in root: URL,
                        control: BackupOperationControl = .init()) throws -> Data {
        try HealthRecoveryCopies.verify(reviewed, in: root, control: control)
        guard let observation = reviewed.domains.first(where: { $0.domain == domain }), observation.state == .readable else { throw BackupError.invalid }
        let file = root.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(reviewed.id).appendingPathComponent(domain.rawValue + ".json")
        let bytes = try checkedData(file, limit: HealthLocalFiles.limit, control: control)
        guard digest(bytes) == observation.digest else { throw BackupError.recordsChanged }
        try HealthLocalFiles.validateCurrentData(bytes, domain: domain, control: control)
        try control.checkCancellation()
        return bytes
    }

    static func photoData(_ reviewed: HealthRecoveryCopies.Preview, id: String, in root: URL,
                          control: BackupOperationControl = .init()) throws -> Data {
        try HealthRecoveryCopies.verify(reviewed, in: root, control: control)
        guard BackupArchive.safePhotoID(id),
              let photo = reviewed.domains.first(where: { $0.domain == .meals })?.photos.first(where: { $0.id == id }),
              photo.state == .readable, let expected = photo.digest else { throw BackupError.missingPhoto }
        let directory = root.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(reviewed.id).appendingPathComponent("photos")
        #if DEBUG && targetEnvironment(simulator)
        HealthReadUIFixture.willReadPhotoPayload(control: control)
        #endif
        let bytes = try checkedData(directory.appendingPathComponent(id + ".jpg"), limit: BackupArchive.maxPhotoBytes, control: control)
        guard digest(bytes) == expected else { throw BackupError.recordsChanged }
        try control.checkCancellation()
        return bytes
    }

    static func retained(_ reviewed: HealthRecoveryCopies.Preview, in root: URL,
                         domains: Set<HealthLocalFiles.Domain>, omittingPhotos: Set<String> = [],
                         control: BackupOperationControl = .init(),
                         validPhoto: (URL) -> Bool) throws -> Payload {
        try control.checkCancellation()
        try HealthRecoveryCopies.verify(reviewed, in: root, control: control)
        guard !domains.isEmpty else { throw BackupError.invalid }
        let directory = root.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(reviewed.id)
        var files: [String: Data] = [:], photos: [String: URL] = [:], digests: [String: String] = [:]
        for domain in domains {
            try control.checkCancellation()
            guard let observation = reviewed.domains.first(where: { $0.domain == domain }), observation.state == .readable else { throw BackupError.invalid }
            let file = domain.rawValue + ".json"
            let bytes = try checkedData(directory.appendingPathComponent(file), limit: HealthLocalFiles.limit, control: control)
            guard digest(bytes) == observation.digest else { throw BackupError.recordsChanged }
            try HealthLocalFiles.validateCurrentData(bytes, domain: domain, control: control)
            files[file] = bytes
            if domain == .meals {
                for photo in observation.photos where !omittingPhotos.contains(photo.id) {
                    let url = directory.appendingPathComponent("photos").appendingPathComponent(photo.id + ".jpg")
                    guard photo.state == .readable, let expected = photo.digest else { throw BackupError.missingPhoto }
                    photos[photo.id] = url; digests[photo.id] = expected
                }
            }
        }
        return try preparePayload(files, photos: photos, digests: digests, domains: domains,
                                  omittingPhotos: omittingPhotos, source: "retained:" + reviewed.id,
                                  control: control, validPhoto: validPhoto)
    }

    /// Both encrypted backup and reviewed readable-import paths can supply
    /// their checked snapshot. Today is not in those formats: never pretend a
    /// missing daily cache was recovered from an archive.
    static func backup(_ snapshot: BackupSnapshot, photos: [String: URL],
                       domains: Set<HealthLocalFiles.Domain>, omittingPhotos: Set<String> = [],
                       control: BackupOperationControl = .init(), source: BackupRecoverySource? = nil,
                       validPhoto: (URL) -> Bool) throws -> Payload {
        if let source { _ = try source.lease.verifiedBoundary(control: control) }
        guard !domains.isEmpty, !domains.contains(.today) else { throw BackupError.invalid }
        try BackupArchive.validate(snapshot, availablePhotoIDs: Set(photos.keys))
        let encoder = BackupArchive.encoder()
        var files: [String: Data] = [:], selectedPhotos: [String: URL] = [:], digests: [String: String] = [:]
        for domain in domains {
            try control.checkCancellation()
            let bytes: Data
            switch domain {
            case .water: bytes = try encoder.encode(snapshot.water)
            case .meals: bytes = try encoder.encode(snapshot.meals)
            case .workouts: bytes = try encoder.encode(snapshot.workouts)
            case .goals: bytes = try encoder.encode(snapshot.goals)
            case .today: throw BackupError.invalid
            }
            files[domain.rawValue + ".json"] = bytes
        }
        if domains.contains(.meals) {
            for id in Set(snapshot.meals.compactMap(\.photoID)) where !omittingPhotos.contains(id) {
                guard let photo = photos[id] else { throw BackupError.missingPhoto }
                selectedPhotos[id] = photo
                if let source {
                    guard let expected = source.photoIdentities[id] else { throw BackupError.missingPhoto }
                    _ = try expected.read(photo, control: control)
                    digests[id] = expected.sha256
                } else { digests[id] = digest(try checkedData(photo, limit: BackupArchive.maxPhotoBytes, control: control)) }
            }
        }
        var payload = try preparePayload(files, photos: selectedPhotos, digests: digests, domains: domains,
                                  omittingPhotos: omittingPhotos, source: source.map { "selected-file:" + $0.lease.identity.sha256 } ?? "reviewed-backup",
                                  control: control, validPhoto: validPhoto)
        payload.fileSource = source
        if let source { payload.reviewedPhotos = source.photoIdentities.filter { selectedPhotos[$0.key] != nil } }
        return payload
    }

    private static func preparePayload(_ input: [String: Data], photos: [String: URL], digests: [String: String],
                                       domains: Set<HealthLocalFiles.Domain>, omittingPhotos: Set<String>, source: String,
                                       control: BackupOperationControl, validPhoto: (URL) -> Bool) throws -> Payload {
        var files = input, photoFiles: [String: URL] = [:], photoDigests: [String: String] = [:]
        if let mealData = files["meals.json"] {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            var meals = try decoder.decode([Meal].self, from: mealData)
            let ids = Set(meals.compactMap(\.photoID))
            guard omittingPhotos.isSubset(of: ids) else { throw BackupError.invalid }
            var replacements: [String: String] = [:]
            for id in ids where !omittingPhotos.contains(id) {
                try control.checkCancellation()
                guard let file = photos[id], let expected = digests[id],
                      digest(try checkedData(file, limit: BackupArchive.maxPhotoBytes, control: control)) == expected,
                      validPhoto(file) else { throw BackupError.missingPhoto }
                let freshID = UUID().uuidString, path = "photos/" + freshID + ".jpg"
                replacements[id] = freshID; photoFiles[path] = file; photoDigests[path] = expected
            }
            for index in meals.indices {
                if let old = meals[index].photoID { meals[index].photoID = replacements[old] }
            }
            files["meals.json"] = try BackupArchive.encoder().encode(meals)
        } else if !omittingPhotos.isEmpty { throw BackupError.invalid }
        guard files.values.reduce(0, { $0 + $1.count }) <= BackupPackage.maxMetadataBytes else { throw BackupPackage.PackageError.metadataTooLarge }
        for domain in domains { try HealthLocalFiles.validateCurrentData(files[domain.rawValue + ".json"]!, domain: domain, control: control) }
        try control.checkCancellation()
        return Payload(domains: domains, files: files, photos: photoFiles, photoDigests: photoDigests, source: source)
    }

    static func prepare(_ payload: Payload, into root: URL, owner: UUID,
                        control: BackupOperationControl = .init(),
                        legacy: @escaping @Sendable (String) throws -> Any? = { UserDefaults.standard.object(forKey: $0) }) throws -> BackupFileTransaction {
        try control.checkCancellation()
        let originalIntent = try intentData(in: root)
        var journal = try originalIntent.map(HealthWriteJournal.decode) ?? HealthWriteJournal(owner: owner)
        guard journal.owner == owner else { throw HealthWriteJournal.Failure.foreignOwner }
        journal.rotateLifecycle()
        var files = payload.files
        files[HealthWriteFiles.name] = try journal.encoded()
        if let source = payload.fileSource { _ = try source.lease.verifiedBoundary(control: control) }
        var receipt: [String: Any] = ["source": payload.source, "domains": payload.domains.map(\.rawValue).sorted(),
                                      "recordDigests": payload.files.mapValues(digest), "photoDigests": payload.photoDigests,
                                      "recoveredAt": ISO8601DateFormatter().string(from: Date())]
        if let source = payload.fileSource {
            receipt["fileSource"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source.lease.identity))
            receipt["omittedPhotoCount"] = source.omittedPhotoCount
            receipt["reviewedPhotos"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload.reviewedPhotos))
        }
        files[".health-recovery-history/" + UUID().uuidString + ".json"] = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        let transaction = try ConversationFiles.prepareHealthRecovery(files, photoFiles: payload.photos,
                                                                      domains: payload.domains, photoDigests: payload.photoDigests,
                                                                      into: root, control: control, legacyOrigins: payload.legacyOrigins, legacy: legacy)
        guard try intentData(in: root) == originalIntent else { throw BackupError.recordsChanged }
        if let source = payload.fileSource {
            let boundary = try source.lease.verifiedBoundary(control: control)
            try transaction.retainSource(source, boundary: boundary)
        }
        return transaction
    }

    private static func intentData(in root: URL) throws -> Data? {
        let file = root.appendingPathComponent(HealthWriteFiles.name)
        do { _ = try FileManager.default.attributesOfItem(atPath: file.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        return try checkedData(file, limit: HealthWriteJournal.maxBytes)
    }

    private static func checkedData(_ url: URL, limit: Int, control: BackupOperationControl? = nil) throws -> Data {
        try control?.checkCancellation()
        guard try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.type] as? FileAttributeType == .typeDirectory else { throw BackupError.invalid }
        return try HealthLocalFiles.readRegularData(url, limit: limit, control: control)
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
