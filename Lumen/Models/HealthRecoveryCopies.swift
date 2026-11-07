import Foundation
import CryptoKit

/// Private, local recovery material. Nothing here is live health history or
/// authorization to replay an old Health journal. Keeping it within LumenData
/// lets explicit checked account reset erase it with the same directory swap.
enum HealthRecoveryCopies {
    static let name = ".health-recovery"
    static let intentProvenanceName = "device-intent.json"
    static let erasureMarker = ".completed-local-erasure"
    static let erasureMarkerData = Data("Lumen completed local erasure v1".utf8)
    private static let lock = NSRecursiveLock()
    static func serialized<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try work()
    }
    private struct LegacyDescriptor: Codable, Equatable {
        let file: String
        let sha256: String
    }
    private struct Manifest: Codable {
        let version: Int
        let createdAt: Date
        let domains: [String]
        let photos: Bool
        let intent: Bool?
        var legacyOrigins: [String: LegacyDescriptor]? = nil
    }

    struct LegacyRetention: Sendable {
        fileprivate let directory: String
        fileprivate let files: [String: Data]
    }
    private static func legacyName(_ domain: HealthLocalFiles.Domain) -> String { "legacy-origin-" + domain.rawValue + ".json" }

    static func verifyLegacyRetention(_ retained: LegacyRetention, in stage: URL, control: BackupOperationControl) throws {
        try control.checkCancellation()
        let directory = stage.appendingPathComponent(name).appendingPathComponent(retained.directory)
        try realDirectory(directory)
        for (path, expected) in retained.files {
            let actual = try boundedData(directory.appendingPathComponent(path), limit: HealthLegacyRecoveryOrigin.envelopeLimit, control: control)
            guard actual == expected else { throw HealthLocalFiles.Failure.changed }
        }
        try control.checkCancellation()
    }

    /// A catalog is an observation, never permission to overwrite current data.
    /// Retained raw files can be damaged too. Keep that distinct from an empty,
    /// valid history, and never decode device-intent.json as recovery records.
    struct Preview: Equatable, Sendable {
        let id: String
        let createdAt: Date?
        let complete: Bool
        let domains: [DomainPreview]
        let hasIntentProvenance: Bool
        let manifestDigest: String?
    }
    struct DomainPreview: Equatable, Sendable {
        let domain: HealthLocalFiles.Domain
        let state: State
        let recordCount: Int?
        let digest: String?
        let photos: [PhotoPreview]
        enum State: String, Sendable { case notIncluded, readable, unavailable }
    }
    struct PhotoPreview: Equatable, Sendable {
        let id: String
        let state: State
        let digest: String?
        // Readable bytes still require the platform image decoder before use.
        enum State: String, Sendable { case missing, readable, unavailable }
    }

    /// Discovery prepares private material but never retires .previous or
    /// installs records. Only metadata and hard links are captured under the
    /// swap lock; validation runs on those inputs after releasing that lock.
    static func discover(in root: URL, control: BackupOperationControl = .init()) throws -> [Preview] {
        if let discovery = try captureDiscovery(in: root, control: control) {
            try discovery.prepare(control: control)
            try discovery.publish(control: control)
        }
        // A completed reset also excludes unexpected leftover private material
        // from product choices. The forensic read-only catalog stays separate.
        try control.checkCancellation()
        if try completedErasure(in: root) { return [] }
        return try previews(in: root, control: control)
    }

    final class Discovery {
        fileprivate struct Stamp: Equatable, Codable {
            let kind: String
            let inode: UInt64
            let device: UInt64
            let size: UInt64
            let modified: Date?
            let children: [String]?
        }
        private let root: URL, workspace: URL, snapshot: URL
        private let stamps: [String: Stamp]
        private let missing: Set<String>
        private let incidentID: String
        private var prepared = false
        fileprivate init(root: URL, workspace: URL, snapshot: URL, stamps: [String: Stamp], missing: Set<String>) throws {
            self.root = root; self.workspace = workspace; self.snapshot = snapshot; self.stamps = stamps; self.missing = missing
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            incidentID = "discovered-" + HealthRecoveryCopies.digest(try encoder.encode(stamps) + encoder.encode(missing.sorted()))
        }
        deinit { try? FileManager.default.removeItem(at: workspace) }

        func prepare(control: BackupOperationControl = .init()) throws {
            try control.checkCancellation()
            guard !prepared else { throw HealthLocalFiles.Failure.changed }
            let priorBase = snapshot.appendingPathExtension("previous").appendingPathComponent(name)
            let priorIDs = try attributes(priorBase) == nil ? Set<String>() : Set(children(priorBase).map(\.lastPathComponent))
            try preservePrevious(in: snapshot, control: control)
            try control.checkCancellation()
            let base = snapshot.appendingPathComponent(name)
            if try attributes(base) != nil {
                for entry in try children(base) where !priorIDs.contains(entry.lastPathComponent) {
                    try FileManager.default.moveItem(at: entry, to: base.appendingPathComponent(incidentID))
                }
            }
            prepared = true
        }

        func publish(control: BackupOperationControl = .init()) throws {
            try control.checkCancellation()
            guard prepared else { throw HealthLocalFiles.Failure.changed }
            try serialized {
                try control.checkCancellation()
                for (path, wanted) in stamps {
                    guard try Self.stamp(URL(fileURLWithPath: path), listing: wanted.children != nil) == wanted else {
                        throw HealthLocalFiles.Failure.changed
                    }
                }
                for path in missing {
                    guard try attributes(URL(fileURLWithPath: path)) == nil else { throw HealthLocalFiles.Failure.changed }
                }
                guard try !completedErasure(in: root) else { throw HealthLocalFiles.Failure.changed }
                let source = snapshot.appendingPathComponent(name)
                guard try attributes(source) != nil else { return }
                let base = try privateDirectory(in: root)
                for entry in try children(source) {
                    try control.checkCancellation()
                    let target = base.appendingPathComponent(entry.lastPathComponent)
                    if try attributes(target) != nil {
                        // Existing prior copies share every captured inode. A
                        // generated incident has a new small manifest only.
                        let generated = entry.lastPathComponent == incidentID
                        guard try Self.sameLinkedTree(entry, target, ignoringManifest: generated),
                              !generated || Self.sameManifest(entry, target) else { throw HealthLocalFiles.Failure.changed }
                        continue
                    }
                    // A later discovery can need fewer domains than an older
                    // incident. Reuse an intact covering copy, including its
                    // exact device-intent provenance, before publishing another.
                    // Existing private material is never removed or rewritten.
                    if entry.lastPathComponent == incidentID,
                       try hasCoveringCopy(for: entry, in: base, control: control) { continue }
                    let pending = base.appendingPathComponent("pending-" + UUID().uuidString)
                    var installed = false
                    defer { if !installed { try? FileManager.default.removeItem(at: pending) } }
                    try linkTree(from: entry, to: pending)
                    try control.checkCancellation()
                    try FileManager.default.moveItem(at: pending, to: target)
                    installed = true
                }
            }
        }

        fileprivate static func stamp(_ file: URL, listing: Bool = false) throws -> Stamp? {
            guard let facts = try attributes(file), let kind = facts[.type] as? FileAttributeType,
                  let inode = facts[.systemFileNumber] as? NSNumber, let device = facts[.systemNumber] as? NSNumber else { return nil }
            return Stamp(kind: kind.rawValue, inode: inode.uint64Value, device: device.uint64Value,
                         size: kind == .typeRegular ? (facts[.size] as? NSNumber)?.uint64Value ?? 0 : 0,
                         modified: kind == .typeRegular ? facts[.modificationDate] as? Date : nil,
                         children: listing ? try children(file).map(\.lastPathComponent) : nil)
        }
        private static func sameLinkedTree(_ a: URL, _ b: URL, ignoringManifest: Bool, depth: Int = 0) throws -> Bool {
            guard depth <= 8, let x = try stamp(a), let y = try stamp(b), x.kind == y.kind else { return false }
            if x.kind == FileAttributeType.typeDirectory.rawValue {
                let left = try children(a).filter { !ignoringManifest || $0.lastPathComponent != "manifest.json" }
                let right = try children(b).filter { !ignoringManifest || $0.lastPathComponent != "manifest.json" }
                guard left.map(\.lastPathComponent) == right.map(\.lastPathComponent) else { return false }
                for (l, r) in zip(left, right) {
                    if try !sameLinkedTree(l, r, ignoringManifest: false, depth: depth + 1) { return false }
                }
                return true
            }
            return x.kind == FileAttributeType.typeRegular.rawValue && x == y
        }
        private static func sameManifest(_ a: URL, _ b: URL) -> Bool {
            do {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let manifest = try decoder.decode(Manifest.self, from: boundedData(a.appendingPathComponent("manifest.json"), limit: 64_000))
                return matchingManifest(in: b, manifest)
            } catch { return false }
        }
    }

    static func captureDiscovery(in root: URL, control: BackupOperationControl = .init()) throws -> Discovery? {
        try control.checkCancellation()
        return try serialized {
            try realDirectory(root)
            let previous = root.appendingPathExtension("previous")
            guard try attributes(previous) != nil, try !completedErasure(in: root) else { return nil }
            try realDirectory(previous)
            let fm = FileManager.default
            let workspace = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + ".discovery-" + UUID().uuidString)
            try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            var finished = false
            defer { if !finished { try? fm.removeItem(at: workspace) } }
            let snapshot = workspace.appendingPathComponent("current"), prior = snapshot.appendingPathExtension("previous")
            try fm.createDirectory(at: snapshot, withIntermediateDirectories: false)
            try fm.createDirectory(at: prior, withIntermediateDirectories: false)
            var stamps: [String: Discovery.Stamp] = [:]
            var missing: Set<String> = []
            stamps[root.path] = try Discovery.stamp(root)
            stamps[previous.path] = try Discovery.stamp(previous)
            func capture(_ source: URL, _ destination: URL, depth: Int = 0) throws {
                try control.checkCancellation()
                guard depth <= 8, stamps.count < 1_000_000, let stamp = try Discovery.stamp(source) else { throw HealthLocalFiles.Failure.invalid }
                if stamp.kind == FileAttributeType.typeDirectory.rawValue {
                    stamps[source.path] = try Discovery.stamp(source, listing: true)
                    try fm.createDirectory(at: destination, withIntermediateDirectories: false)
                    for child in try children(source) { try capture(child, destination.appendingPathComponent(child.lastPathComponent), depth: depth + 1) }
                } else {
                    guard stamp.kind == FileAttributeType.typeRegular.rawValue else { throw HealthLocalFiles.Failure.invalid }
                    stamps[source.path] = stamp
                    try fm.linkItem(at: source, to: destination)
                }
            }
            for file in HealthLocalFiles.Domain.allCases.map({ $0.rawValue + ".json" }) + [HealthWriteFiles.name, erasureMarker] {
                let live = root.appendingPathComponent(file)
                if let stamp = try Discovery.stamp(live) {
                    stamps[live.path] = stamp
                    if stamp.kind == FileAttributeType.typeRegular.rawValue { try fm.linkItem(at: live, to: snapshot.appendingPathComponent(file)) }
                    else {
                        // Represent an unsupported current path as unavailable,
                        // without following it or copying unrelated raw children.
                        try fm.createDirectory(at: snapshot.appendingPathComponent(file), withIntermediateDirectories: false)
                    }
                } else { missing.insert(live.path) }
                let old = previous.appendingPathComponent(file)
                if try attributes(old) != nil { try capture(old, prior.appendingPathComponent(file)) }
                else { missing.insert(old.path) }
            }
            for folder in ["photos", name] {
                let old = previous.appendingPathComponent(folder)
                if try attributes(old) != nil { try capture(old, prior.appendingPathComponent(folder)) }
                else { missing.insert(old.path) }
            }
            // Missing paths also participate in the publication guard.
            // Root/prior directory identities protect directory swaps; marker
            // presence is checked explicitly again before any publication.
            for (path, wanted) in stamps {
                guard try Discovery.stamp(URL(fileURLWithPath: path), listing: wanted.children != nil) == wanted else { throw HealthLocalFiles.Failure.changed }
            }
            for path in missing {
                guard try attributes(URL(fileURLWithPath: path)) == nil else { throw HealthLocalFiles.Failure.changed }
            }
            let result = try Discovery(root: root, workspace: workspace, snapshot: snapshot, stamps: stamps, missing: missing)
            finished = true
            return result
        }
    }

    /// Bounded reads of real files only. A broken entry stays visible, without
    /// preventing a different retained copy from being reviewed. No path here
    /// invokes generic .previous retirement or changes live/private bytes.
    static func previews(in root: URL, control: BackupOperationControl = .init()) throws -> [Preview] {
        // Observations can become stale. Recheck them before staging rather
        // than holding the directory-swap lock through potentially large reads.
        do {
            try control.checkCancellation()
            try realDirectory(root)
            let base = root.appendingPathComponent(name)
            guard try attributes(base) != nil else { return [] }
            return try children(base).map { try control.checkCancellation(); return try preview($0, control: control) }
        }
    }

    /// Recheck the exact reviewed entry before any later staging operation.
    /// The install still needs the current-data/revision guard; this only
    /// establishes that the recovery source has not changed since review.
    static func verify(_ reviewed: Preview, in root: URL, control: BackupOperationControl = .init()) throws {
        try control.checkCancellation()
        do {
            try realDirectory(root)
            let base = root.appendingPathComponent(name)
            try realDirectory(base)
            guard !reviewed.id.isEmpty, !reviewed.id.contains("/"), !reviewed.id.contains("\\"),
                  reviewed.id != ".", reviewed.id != "..", !reviewed.id.contains("\0"),
                  reviewed.complete, try preview(base.appendingPathComponent(reviewed.id), control: control) == reviewed else {
                throw HealthLocalFiles.Failure.changed
            }
            try control.checkCancellation()
        }
    }

    private static func preview(_ directory: URL, control: BackupOperationControl = .init()) throws -> Preview {
        try control.checkCancellation()
        let id = directory.lastPathComponent
        // Do not follow a symlink masquerading as a copy directory. A pending
        // archive is not a published recovery choice, even with a manifest.
        guard (try? realDirectory(directory)) != nil else {
            return Preview(id: id, createdAt: nil, complete: false, domains: [], hasIntentProvenance: false, manifestDigest: nil)
        }
        let manifestData: Data?
        do { manifestData = try boundedData(directory.appendingPathComponent("manifest.json"), limit: 64_000, control: control) }
        catch is CancellationError { throw CancellationError() }
        catch { manifestData = nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let manifest: Manifest? = try manifestData.flatMap { bytes in
            do {
                try JSONFieldAudit.check(bytes, control: control)
                let value = try decoder.decode(Manifest.self, from: bytes)
                guard validManifestShape(value), try validManifestEncoding(bytes, manifest: value), value.createdAt.timeIntervalSince1970.isFinite,
                      abs(value.createdAt.timeIntervalSince1970) <= 1_000_000_000_000,
                      value.domains.count <= HealthLocalFiles.Domain.allCases.count,
                      Set(value.domains).count == value.domains.count,
                      value.domains.allSatisfy({ HealthLocalFiles.Domain(rawValue: $0) != nil }) else { return nil }
                return value
            } catch is CancellationError { throw CancellationError() }
            catch { return nil }
        }
        var observations: [DomainPreview] = []
        var legacyComplete = true
        if let manifest, manifest.version == 2 {
            var expected = Set(manifest.domains.map { manifest.legacyOrigins?[$0]?.file ?? $0 + ".json" })
            expected.insert("manifest.json")
            if manifest.photos { expected.insert("photos") }
            if manifest.intent ?? false { expected.insert(intentProvenanceName) }
            legacyComplete = Set(try children(directory).map(\.lastPathComponent)) == expected
        }
        let malformedLegacyManifest = manifest == nil && manifestData.flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }.map { ($0["version"] as? Int) == 2 || $0["legacyOrigins"] != nil } == true
        for domain in HealthLocalFiles.Domain.allCases {
            try control.checkCancellation()
            let file = directory.appendingPathComponent(domain.rawValue + ".json")
            let originFile = directory.appendingPathComponent(legacyName(domain))
            let descriptor = manifest?.legacyOrigins?[domain.rawValue]
            let hasOriginPath: Bool
            do { hasOriginPath = try attributes(originFile) != nil }
            catch is CancellationError { throw CancellationError() }
            catch { legacyComplete = false; observations.append(.init(domain: domain, state: .unavailable, recordCount: nil, digest: nil, photos: [])); continue }
            if descriptor != nil || hasOriginPath || malformedLegacyManifest {
                var provenanceDigest: String?
                do {
                    guard let descriptor, descriptor.file == legacyName(domain), try attributes(file) == nil else { throw HealthLocalFiles.Failure.invalid }
                    let bytes = try boundedData(originFile, limit: HealthLegacyRecoveryOrigin.envelopeLimit, control: control)
                    provenanceDigest = digest(bytes)
                    guard provenanceDigest == descriptor.sha256,
                          try HealthLegacyRecoveryOrigin.Value.decode(bytes, control: control).domain == domain else { throw HealthLocalFiles.Failure.invalid }
                } catch is CancellationError { throw CancellationError() }
                catch { legacyComplete = false }
                observations.append(.init(domain: domain, state: .unavailable, recordCount: nil, digest: provenanceDigest, photos: []))
                continue
            }
            do {
                guard try attributes(file) != nil else {
                    observations.append(.init(domain: domain, state: .notIncluded, recordCount: nil, digest: nil, photos: [])); continue
                }
                let data = try boundedData(file, limit: HealthLocalFiles.limit, control: control)
                let fileDigest = digest(data)
                do {
                    try HealthLocalFiles.validateCurrentData(data, domain: domain, control: control)
                    let count: Int
                    var photos: [PhotoPreview] = []
                    switch domain {
                    case .water: count = try decoder.decode([HydrationLog].self, from: data).count
                    case .workouts: count = try decoder.decode([Workout].self, from: data).count
                    case .meals:
                        let meals = try decoder.decode([Meal].self, from: data); count = meals.count
                        for photoID in Set(meals.compactMap(\.photoID)).sorted() {
                            try control.checkCancellation()
                            let folder = directory.appendingPathComponent("photos")
                            do {
                                guard try attributes(folder) != nil else {
                                    photos.append(.init(id: photoID, state: .missing, digest: nil)); continue
                                }
                                try realDirectory(folder)
                                let file = folder.appendingPathComponent(photoID + ".jpg")
                                guard try attributes(file) != nil else {
                                    photos.append(.init(id: photoID, state: .missing, digest: nil)); continue
                                }
                                let bytes = try boundedData(file, limit: BackupArchive.maxPhotoBytes, control: control)
                                guard !bytes.isEmpty else { throw HealthLocalFiles.Failure.invalid }
                                photos.append(.init(id: photoID, state: .readable, digest: digest(bytes)))
                            } catch { try control.checkCancellation(); photos.append(.init(id: photoID, state: .unavailable, digest: nil)) }
                        }
                    case .goals, .today: count = 1
                    }
                    observations.append(.init(domain: domain, state: .readable, recordCount: count, digest: fileDigest, photos: photos))
                } catch {
                    try control.checkCancellation()
                    observations.append(.init(domain: domain, state: .unavailable, recordCount: nil, digest: fileDigest, photos: []))
                }
            } catch {
                try control.checkCancellation()
                observations.append(.init(domain: domain, state: .unavailable, recordCount: nil, digest: nil, photos: []))
            }
        }
        // A manifest does not make missing or extra payload files trustworthy.
        let actualDomains = observations.filter { $0.state != .notIncluded }.map { $0.domain.rawValue }.sorted()
        let complete = manifest.map { $0.domains.sorted() == actualDomains } == true && legacyComplete && !id.hasPrefix("pending-")
        let provenance = (try? attributes(directory.appendingPathComponent(intentProvenanceName))) != nil
        try control.checkCancellation()
        return Preview(id: id, createdAt: manifest?.createdAt, complete: complete, domains: observations,
                       hasIntentProvenance: provenance, manifestDigest: manifestData.map(digest))
    }

    private static func boundedData(_ file: URL, limit: Int, control: BackupOperationControl? = nil) throws -> Data {
        try HealthLocalFiles.readRegularData(file, limit: limit, control: control)
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Operates only inside an uninstalled transaction stage. Its existing
    /// raw paths move into a private copy before replacements are written.
    /// Any error discards that stage, leaving the source root untouched.
    @discardableResult
    static func preserveReplacedDomains(in stage: URL, domains: Set<HealthLocalFiles.Domain>,
                                       legacyOrigins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin] = [:],
                                       control: BackupOperationControl = .init()) throws -> LegacyRetention? {
        guard !domains.isEmpty else { return nil }
        try control.checkCancellation()
        try Task.checkCancellation()
        for domain in domains {
            try Task.checkCancellation()
            let file = stage.appendingPathComponent(domain.rawValue + ".json")
            if legacyOrigins[domain] != nil {
                guard try attributes(file) == nil else { throw HealthLocalFiles.Failure.changed }
                continue
            }
            guard try attributes(file) != nil else { throw HealthLocalFiles.Failure.changed }
            var readable = false
            do {
                let bytes = try boundedData(file, limit: HealthLocalFiles.limit)
                try HealthLocalFiles.validateCurrentData(bytes, domain: domain)
                readable = true
            } catch is CancellationError { throw CancellationError() }
            catch { /* Preserve the actual failed path; never use a default. */ }
            guard !readable else { throw HealthLocalFiles.Failure.changed }
        }
        return try preserveDomains(in: stage, domains: domains, legacyOrigins: legacyOrigins, control: control)
    }

    /// Cache replacement is an explicit, separate decision. A healthy cache
    /// may be replaced here; a truly absent cache has no raw path to retain.
    /// Keep the unavailable-record route's stricter guards above unchanged.
    static func preserveDailyCache(in stage: URL) throws {
        try Task.checkCancellation()
        guard try attributes(stage.appendingPathComponent("today.json")) != nil else { return }
        _ = try preserveDomains(in: stage, domains: [.today], deduplicating: true)
    }

    private static func preserveDomains(in stage: URL, domains: Set<HealthLocalFiles.Domain>, deduplicating: Bool = false,
                                        legacyOrigins: [HealthLocalFiles.Domain: HealthLegacyRecoveryOrigin] = [:],
                                        control: BackupOperationControl = .init()) throws -> LegacyRetention? {
        try control.checkCancellation()
        guard Set(legacyOrigins.keys).isSubset(of: domains), legacyOrigins.allSatisfy({ $0.key == $0.value.value.domain }),
              legacyOrigins.values.reduce(0, { $0 + $1.value.bytes.count }) <= HealthLegacyRecoveryOrigin.aggregateLimit else { throw HealthLocalFiles.Failure.invalid }
        let base = try privateDirectory(in: stage)
        let retained = base.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var descriptors: [String: LegacyDescriptor] = [:], exactFiles: [String: Data] = [:]
        for domain in domains {
            try control.checkCancellation()
            let name = domain.rawValue + ".json"
            if let origin = legacyOrigins[domain] {
                let name = legacyName(domain), bytes = try origin.value.encoded(control: control)
                try bytes.write(to: retained.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                descriptors[domain.rawValue] = LegacyDescriptor(file: name, sha256: digest(bytes)); exactFiles[name] = bytes
            } else {
                try FileManager.default.moveItem(at: stage.appendingPathComponent(name), to: retained.appendingPathComponent(name))
            }
        }
        let photos = stage.appendingPathComponent("photos")
        let hasPhotoPath = try attributes(photos) != nil
        let hasPhotos = domains.contains(.meals) && hasPhotoPath
        if hasPhotos { try FileManager.default.moveItem(at: photos, to: retained.appendingPathComponent("photos")) }
        let intent = stage.appendingPathComponent(HealthWriteFiles.name)
        let hasIntent = try attributes(intent) != nil
        if hasIntent { try linkTree(from: intent, to: retained.appendingPathComponent(intentProvenanceName)) }
        let manifest = Manifest(version: descriptors.isEmpty ? 1 : 2, createdAt: Date(), domains: domains.map(\.rawValue).sorted(), photos: hasPhotos, intent: hasIntent,
                                legacyOrigins: descriptors.isEmpty ? nil : descriptors)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let manifestBytes = try encoder.encode(manifest)
        try manifestBytes.write(to: retained.appendingPathComponent("manifest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try control.checkCancellation()
        // A quarantined directory must remain carryable by later transactions:
        // validate the same depth/type/entry limits used for private copies.
        guard try sameTree(retained, retained) else { throw HealthLocalFiles.Failure.invalid }
        if deduplicating, try hasCoveringCopy(for: retained, in: base) {
            try FileManager.default.removeItem(at: retained)
        }
        guard !descriptors.isEmpty else { return nil }
        exactFiles["manifest.json"] = manifestBytes
        return LegacyRetention(directory: retained.lastPathComponent, files: exactFiles)
    }

    static func completedErasure(in root: URL) throws -> Bool {
        let file = root.appendingPathComponent(erasureMarker)
        guard try attributes(file) != nil else { return false }
        try regularFile(file)
        guard try attributes(file)?[.size] as? NSNumber == NSNumber(value: erasureMarkerData.count) else { throw HealthLocalFiles.Failure.invalid }
        guard try boundedData(file, limit: erasureMarkerData.count) == erasureMarkerData else { throw HealthLocalFiles.Failure.invalid }
        return true
    }
    static func finishErasure(in root: URL) throws {
        if try completedErasure(in: root) { try FileManager.default.removeItem(at: root.appendingPathComponent(erasureMarker)) }
    }

    /// Called under the common directory-swap lock, before .previous retires.
    /// Do not treat a missing domain as corrupt: an intentional reset must not
    /// resurrect deleted records. Existing failed reads retain raw prior data.
    static func preservePrevious(in root: URL, from prior: URL? = nil, control: BackupOperationControl = .init(),
                                 recoveringLegacyDomains: Set<HealthLocalFiles.Domain> = []) throws {
        try control.checkCancellation()
        let previous = prior ?? root.appendingPathExtension("previous")
        guard try attributes(previous) != nil else { return }
        try realDirectory(previous)
        try carryPrivateCopies(from: previous, into: root)
        var domains: [HealthLocalFiles.Domain] = []
        for domain in HealthLocalFiles.Domain.allCases {
            try control.checkCancellation()
            let file = root.appendingPathComponent(domain.rawValue + ".json")
            var failed = false
            do {
                guard try attributes(file) != nil else {
                    // Only explicit failed-legacy recovery retains a selected
                    // prior path despite an absent current path. Never load it
                    // into live history or infer permission from absence alone.
                    if recoveringLegacyDomains.contains(domain),
                       try attributes(previous.appendingPathComponent(domain.rawValue + ".json")) != nil { domains.append(domain) }
                    continue
                }
                try regularFile(file)
                try HealthLocalFiles.validateCurrentData(boundedData(file, limit: HealthLocalFiles.limit), domain: domain)
            } catch is CancellationError { throw CancellationError() }
            catch { failed = true }
            if failed, try attributes(previous.appendingPathComponent(domain.rawValue + ".json")) != nil { domains.append(domain) }
        }
        let previousIntent = previous.appendingPathComponent(HealthWriteFiles.name)
        let hasPriorIntent = try attributes(previousIntent) != nil
        var failedIntent = false
        if try attributes(root.appendingPathComponent(HealthWriteFiles.name)) != nil {
            do { _ = try HealthWriteFiles.read(from: root) }
            catch is CancellationError { throw CancellationError() }
            catch { failedIntent = true }
        }
        guard !domains.isEmpty || (failedIntent && hasPriorIntent) else { return }
        let base = try privateDirectory(in: root)
        let stage = base.appendingPathComponent("pending-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var installed = false
        defer { if !installed { try? FileManager.default.removeItem(at: stage) } }
        for domain in domains {
            let file = domain.rawValue + ".json"
            try linkTree(from: previous.appendingPathComponent(file), to: stage.appendingPathComponent(file))
        }
        let photos = previous.appendingPathComponent("photos")
        let hasPhotos = try attributes(photos) != nil
        let retainPhotos = domains.contains(.meals) && hasPhotos
        if retainPhotos { try linkTree(from: photos, to: stage.appendingPathComponent("photos")) }
        if hasPriorIntent { try linkTree(from: previousIntent, to: stage.appendingPathComponent(intentProvenanceName)) }
        let manifest = Manifest(version: 1, createdAt: Date(), domains: domains.map(\.rawValue).sorted(), photos: retainPhotos, intent: hasPriorIntent)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: stage.appendingPathComponent("manifest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Compare actual payload trees; a matching name or manifest is not proof
        // that another copy remains intact. Unreadable data is kept, not deduped.
        if try hasCoveringCopy(for: stage, in: base, control: control) { return }
        try control.checkCancellation()
        try FileManager.default.moveItem(at: stage, to: base.appendingPathComponent(UUID().uuidString))
        installed = true
    }

    /// A prepared transaction may predate a newly preserved copy. Carry the
    /// latest private material into its stage again immediately before install.
    /// Hard links keep both the old root and stage recoverable on failure.
    static func carryPrivateCopies(from source: URL, into destination: URL) throws {
        let sourceBase = source.appendingPathComponent(name)
        guard try attributes(sourceBase) != nil else { return }
        try realDirectory(sourceBase)
        let destinationBase = try privateDirectory(in: destination)
        for entry in try children(sourceBase) {
            let target = destinationBase.appendingPathComponent(entry.lastPathComponent)
            let absent = try attributes(target) == nil
            if absent || (try? sameTree(entry, target)) != true {
                // Keep a different or unreadable copy as a sibling, never nest
                // another mirror of the recovery area inside a new archive.
                let retained = absent ? target : destinationBase.appendingPathComponent(UUID().uuidString)
                let pending = destinationBase.appendingPathComponent("pending-" + UUID().uuidString)
                var published = false
                defer { if !published { try? FileManager.default.removeItem(at: pending) } }
                try linkTree(from: entry, to: pending)
                try FileManager.default.moveItem(at: pending, to: retained)
                published = true
            }
        }
    }

    private static func matchingManifest(in directory: URL, _ wanted: Manifest) -> Bool {
        do {
            let saved = try readManifest(in: directory)
            return validManifestShape(saved) && saved.version == wanted.version && saved.domains == wanted.domains && saved.photos == wanted.photos && (saved.intent ?? false) == (wanted.intent ?? false) && saved.legacyOrigins == wanted.legacyOrigins
        } catch { return false }
    }

    private static func readManifest(in directory: URL) throws -> Manifest {
        try realDirectory(directory)
        let data = try boundedData(directory.appendingPathComponent("manifest.json"), limit: 64_000)
        try JSONFieldAudit.check(data, control: .init())
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Manifest.self, from: data)
        guard validManifestShape(manifest), try validManifestEncoding(data, manifest: manifest) else { throw HealthLocalFiles.Failure.invalid }
        return manifest
    }

    private static func validManifestEncoding(_ data: Data, manifest: Manifest) throws -> Bool {
        guard manifest.version == 2 else { return true }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "createdAt", "domains", "photos", "intent", "legacyOrigins"]),
              Set(["version", "createdAt", "domains", "photos", "legacyOrigins"]).isSubset(of: Set(object.keys)),
              let origins = object["legacyOrigins"] as? [String: Any] else { return false }
        return origins.values.allSatisfy { value in
            guard let row = value as? [String: Any] else { return false }
            return Set(row.keys) == ["file", "sha256"]
        }
    }

    private static func validManifestShape(_ manifest: Manifest) -> Bool {
        if manifest.version == 1 { return manifest.legacyOrigins == nil }
        guard manifest.version == 2, let origins = manifest.legacyOrigins, !origins.isEmpty, origins.count <= 3 else { return false }
        return origins.allSatisfy { key, descriptor in
            guard let domain = HealthLocalFiles.Domain(rawValue: key), domain.legacyKey != nil,
                  manifest.domains.contains(key), descriptor.file == legacyName(domain) else { return false }
            return descriptor.sha256.utf8.count == 64 && descriptor.sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }

    /// The candidate is disposable staging material. A superset manifest alone
    /// is insufficient: every requested payload tree and intent file must match.
    /// Invalid, missing, unreadable or linked-away copies cannot justify reuse.
    private static func hasCoveringCopy(for candidate: URL, in base: URL, control: BackupOperationControl = .init()) throws -> Bool {
        try control.checkCancellation()
        try Task.checkCancellation()
        let wanted = try readManifest(in: candidate)
        if wanted.version == 2 { guard try preview(candidate, control: control).complete else { return false } }
        let known = Set(HealthLocalFiles.Domain.allCases.map(\.rawValue))
        func paths(_ manifest: Manifest) -> Set<String>? {
            let domains = Set(manifest.domains)
            guard validManifestShape(manifest), domains.count == manifest.domains.count,
                  domains.isSubset(of: known), !manifest.photos || domains.contains("meals") else { return nil }
            var names = Set(domains.map { manifest.legacyOrigins?[$0]?.file ?? $0 + ".json" })
            if manifest.photos { names.insert("photos") }
            if manifest.intent ?? false { names.insert(intentProvenanceName) }
            return names
        }
        guard let required = paths(wanted),
              Set(try children(candidate).map(\.lastPathComponent)) == required.union(["manifest.json"]) else { return false }
        for existing in try children(base) where existing.lastPathComponent != candidate.lastPathComponent {
            do {
                try control.checkCancellation()
                try Task.checkCancellation()
                let saved = try readManifest(in: existing)
                if saved.version == 2 { guard try preview(existing, control: control).complete else { continue } }
                guard let included = paths(saved), Set(wanted.domains).isSubset(of: Set(saved.domains)),
                      (saved.intent ?? false) == (wanted.intent ?? false),
                      !wanted.domains.contains("meals") || saved.photos == wanted.photos,
                      Set(try children(existing).map(\.lastPathComponent)) == included.union(["manifest.json"]),
                      try sameTree(existing, existing) else { continue }
                var matches = true
                for name in required {
                    try control.checkCancellation()
                    try Task.checkCancellation()
                    if try !sameTree(candidate.appendingPathComponent(name), existing.appendingPathComponent(name)) {
                        matches = false; break
                    }
                }
                if matches { return true }
            } catch is CancellationError { throw CancellationError() }
            catch { /* Keep the candidate when another copy cannot be proved intact. */ }
        }
        return false
    }

    private static func privateDirectory(in root: URL) throws -> URL {
        try realDirectory(root)
        let base = root.appendingPathComponent(name)
        if try attributes(base) == nil {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        try realDirectory(base)
        return base
    }

    private static func attributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
    }
    private static func realDirectory(_ url: URL) throws {
        guard try attributes(url)?[.type] as? FileAttributeType == .typeDirectory else { throw HealthLocalFiles.Failure.invalid }
    }
    private static func regularFile(_ url: URL) throws {
        guard try attributes(url)?[.type] as? FileAttributeType == .typeRegular else { throw HealthLocalFiles.Failure.invalid }
    }
    private static func children(_ url: URL) throws -> [URL] {
        try realDirectory(url)
        let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        guard entries.count <= 200_000 else { throw HealthLocalFiles.Failure.invalid }
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private static func linkTree(from source: URL, to destination: URL, depth: Int = 0) throws {
        guard depth <= 8, let facts = try attributes(source) else { throw HealthLocalFiles.Failure.invalid }
        let type = facts[.type] as? FileAttributeType
        if type == .typeDirectory {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            for child in try children(source) { try linkTree(from: child, to: destination.appendingPathComponent(child.lastPathComponent), depth: depth + 1) }
        } else {
            guard type == .typeRegular else { throw HealthLocalFiles.Failure.invalid }
            try FileManager.default.linkItem(at: source, to: destination)
        }
    }
    private static func sameTree(_ a: URL, _ b: URL, ignoringManifest: Bool = false, depth: Int = 0) throws -> Bool {
        guard depth <= 8, let left = try attributes(a), let right = try attributes(b),
              let type = left[.type] as? FileAttributeType, type == right[.type] as? FileAttributeType else { return false }
        if type == .typeDirectory {
            let l = try children(a).filter { !ignoringManifest || $0.lastPathComponent != "manifest.json" }
            let r = try children(b).filter { !ignoringManifest || $0.lastPathComponent != "manifest.json" }
            guard l.map(\.lastPathComponent) == r.map(\.lastPathComponent) else { return false }
            for (x, y) in zip(l, r) { if try !sameTree(x, y, depth: depth + 1) { return false } }
            return true
        }
        guard type == .typeRegular, left[.size] as? NSNumber == right[.size] as? NSNumber else { return false }
        if let inode = left[.systemFileNumber] as? NSNumber, let device = left[.systemNumber] as? NSNumber,
           inode == right[.systemFileNumber] as? NSNumber, device == right[.systemNumber] as? NSNumber { return true }
        let x = try FileHandle(forReadingFrom: a), y = try FileHandle(forReadingFrom: b)
        defer { try? x.close(); try? y.close() }
        while true {
            let l = try x.read(upToCount: 1 << 20) ?? Data(), r = try y.read(upToCount: 1 << 20) ?? Data()
            if l != r { return false }
            if l.isEmpty { return true }
        }
    }
}
