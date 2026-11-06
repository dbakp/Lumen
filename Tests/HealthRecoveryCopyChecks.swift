import Foundation
import Darwin

enum HealthRecoveryCopyChecks {
    static func run(output: URL? = nil) throws {
        let fm = FileManager.default
        let outer = fm.temporaryDirectory.appendingPathComponent("Lumen-recovery-copies-" + UUID().uuidString)
        try fm.createDirectory(at: outer, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outer) }
        let encoder = BackupArchive.encoder(), conversations = try ConversationFiles.encoded([], activeID: nil)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let baseline = try JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent("Design/native/health-write-order/local-values-baseline-r1-report.json"))) as? [String: Any]
        guard let previousFixture = baseline?["previousCopy"] as? [String: Any],
              let goodEncoded = previousFixture["goodPreviousWaterBytes"] as? String, let good = Data(base64Encoded: goodEncoded),
              let badEncoded = previousFixture["damagedCurrentWaterBytes"] as? String, let bad = Data(base64Encoded: badEncoded) else { throw HealthLocalFiles.Failure.invalid }
        let goals = try encoder.encode(HealthGoals())
        var nextGoals = HealthGoals(); nextGoals.weightKg = 80
        let replacement = try encoder.encode(nextGoals)
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks.append(label); print("PASS: " + label) }
        func rejects(_ label: String, _ work: () throws -> Void) {
            var failed = false; do { try work() } catch { failed = true }; check(failed, label)
        }
        func seed(_ root: URL) throws {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for (name, data) in conversations { try data.write(to: root.appendingPathComponent(name)) }
            try good.write(to: root.appendingPathComponent("water.json"))
            try goals.write(to: root.appendingPathComponent("goals.json"))
        }
        func pair(_ name: String) throws -> (URL, URL) {
            let root = outer.appendingPathComponent(name), previous = root.appendingPathExtension("previous")
            try seed(root); try seed(previous); return (root, previous)
        }
        func copies(_ root: URL) throws -> [URL] {
            let base = root.appendingPathComponent(HealthRecoveryCopies.name)
            guard fm.fileExists(atPath: base.path) else { return [] }
            return try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix("pending-") }
        }
        func retained(_ root: URL, _ data: Data, file: String = "water.json") throws -> Bool {
            try copies(root).contains { (try? Data(contentsOf: $0.appendingPathComponent(file))) == data }
        }
        let (immediate, immediatePrevious) = try pair("immediate-discovery")
        try bad.write(to: immediate.appendingPathComponent("water.json"), options: .atomic)
        // Match the product's initial open/catalog path, before any linked write
        // calls generic prior retirement. A previous copy must already be usable.
        try BackupFiles.openDirectory(immediate, createIfMissing: true)
        let immediateChoices = try HealthRecoveryCopies.discover(in: immediate)
        check(immediateChoices.contains { $0.complete && $0.domains.contains { $0.domain == .water && $0.state == .readable && $0.recordCount == 1 } },
              "a good previous water copy is discoverable immediately without an unrelated save")
        check(try Data(contentsOf: immediate.appendingPathComponent("water.json")) == bad && Data(contentsOf: immediatePrevious.appendingPathComponent("water.json")) == good,
              "immediate discovery retains exact damaged current and good previous water")
        let immediateAgain = try HealthRecoveryCopies.discover(in: immediate)
        check(immediateAgain.map(\.id) == immediateChoices.map(\.id) && immediateAgain.count == 1,
              "repeated discovery reuses the same actual linked incident without growing copies")
        let (discoveryLockRoot, _) = try pair("discovery-validation-lock")
        try bad.write(to: discoveryLockRoot.appendingPathComponent("water.json"), options: .atomic)
        let discoveryLock = try HealthRecoveryCopies.captureDiscovery(in: discoveryLockRoot)!
        let discoveryHeld = DispatchSemaphore(value: 0), discoveryRelease = DispatchSemaphore(value: 0), discoveryDone = DispatchSemaphore(value: 0)
        let discoveryResult = CancellationResult()
        DispatchQueue.global().async { HealthRecoveryCopies.serialized { discoveryHeld.signal(); discoveryRelease.wait() } }
        discoveryHeld.wait()
        DispatchQueue.global().async {
            do { try discoveryLock.prepare(); discoveryResult.set(true) } catch { }
            discoveryDone.signal()
        }
        let outsideLock = discoveryDone.wait(timeout: .now() + 2) == .success
        discoveryRelease.signal(); if !outsideLock { discoveryDone.wait() }
        check(outsideLock && discoveryResult.get(), "discovery validation finishes while another worker holds the directory swap lock")
        try discoveryLock.publish()
        check(try retained(discoveryLockRoot, good), "validated immutable discovery publishes the exact previous bytes")
        for changed in ["current", "previous", "missing-domain", "reset", "cancel"] {
            let (candidate, old) = try pair("discovery-changed-" + changed)
            try bad.write(to: candidate.appendingPathComponent("water.json"), options: .atomic)
            let discovery = try HealthRecoveryCopies.captureDiscovery(in: candidate)!
            try discovery.prepare()
            let operation = BackupOperationControl()
            switch changed {
            case "current": try Data("[]".utf8).write(to: candidate.appendingPathComponent("water.json"), options: .atomic)
            case "previous": try Data("[]".utf8).write(to: old.appendingPathComponent("water.json"), options: .atomic)
            case "missing-domain": try Data("[]".utf8).write(to: candidate.appendingPathComponent("meals.json"), options: .atomic)
            case "reset": try HealthRecoveryCopies.erasureMarkerData.write(to: candidate.appendingPathComponent(HealthRecoveryCopies.erasureMarker), options: .atomic)
            default: operation.cancel()
            }
            rejects("discovery rejects " + changed + " before publishing stale private history") { try discovery.publish(control: operation) }
            check(try copies(candidate).isEmpty, "rejected " + changed + " discovery leaves no published private incident")
        }
        let (erasedDiscovery, _) = try pair("discovery-erased")
        try bad.write(to: erasedDiscovery.appendingPathComponent("water.json"), options: .atomic)
        try HealthRecoveryCopies.erasureMarkerData.write(to: erasedDiscovery.appendingPathComponent(HealthRecoveryCopies.erasureMarker), options: .atomic)
        check(try HealthRecoveryCopies.discover(in: erasedDiscovery).isEmpty && copies(erasedDiscovery).isEmpty,
              "completed erasure never discovers prior history")
        try fm.copyItem(at: immediate.appendingPathComponent(HealthRecoveryCopies.name), to: erasedDiscovery.appendingPathComponent(HealthRecoveryCopies.name))
        check(try HealthRecoveryCopies.discover(in: erasedDiscovery).isEmpty,
              "completed erasure also hides any leftover private copies instead of offering erased history")
        let lateDiscovery = outer.appendingPathComponent("discovery-after-transaction")
        try seed(lateDiscovery); try bad.write(to: lateDiscovery.appendingPathComponent("water.json"), options: .atomic)
        let beforeDiscovery = try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: lateDiscovery)
        try seed(lateDiscovery.appendingPathExtension("previous"))
        _ = try HealthRecoveryCopies.discover(in: lateDiscovery)
        do { try beforeDiscovery.commit() }
        catch {
            if let output {
                let expected = Mirror(reflecting: beforeDiscovery).children.first { $0.label == "sourceSnapshot" }.map { String(describing: $0.value) } ?? "missing"
                let entries = fm.enumerator(at: lateDiscovery, includingPropertiesForKeys: nil)!
                var observed: [String: String] = [:]
                for case let entry as URL in entries {
                    observed[entry.path] = String(describing: try fm.attributesOfItem(atPath: entry.path))
                }
                let diagnostic: [String: Any] = ["error": String(describing: error), "root": lateDiscovery.path, "expected": expected, "observed": observed]
                try JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys, .prettyPrinted]).write(to: output.appendingPathExtension("stage-failure.json"))
            }
            throw error
        }
        check(try retained(lateDiscovery, good) && Data(contentsOf: lateDiscovery.appendingPathComponent("water.json")) == bad,
              "an already prepared transaction carries later discovery without replacing damaged live history")
        let (privateDiscovery, privateDiscoveryPrevious) = try pair("discovery-prior-private")
        try fm.copyItem(at: immediate.appendingPathComponent(HealthRecoveryCopies.name), to: privateDiscoveryPrevious.appendingPathComponent(HealthRecoveryCopies.name))
        let privateChoices = try HealthRecoveryCopies.discover(in: privateDiscovery)
        let privateDiscoveryRetained = try retained(privateDiscovery, good)
        check(privateChoices.count == 1 && privateDiscoveryRetained, "discovery carries a private copy found only in previous even when current water is healthy")
        check(try HealthRecoveryCopies.discover(in: privateDiscovery).map(\.id) == privateChoices.map(\.id), "prior-only private discovery does not create recursive mirrors or duplicate choices")
        let (intentDiscovery, intentDiscoveryPrevious) = try pair("discovery-intent")
        try bad.write(to: intentDiscovery.appendingPathComponent("water.json"), options: .atomic)
        let liveIntent = try HealthWriteJournal().encoded(), oldIntent = try HealthWriteJournal().encoded()
        try liveIntent.write(to: intentDiscovery.appendingPathComponent(HealthWriteFiles.name))
        try oldIntent.write(to: intentDiscoveryPrevious.appendingPathComponent(HealthWriteFiles.name))
        let intentChoices = try HealthRecoveryCopies.discover(in: intentDiscovery)
        check(intentChoices.count == 1 && intentChoices[0].hasIntentProvenance, "discovery retains prior intent only as private provenance")
        check(try Data(contentsOf: intentDiscovery.appendingPathComponent(HealthWriteFiles.name)) == liveIntent,
              "discovery never changes or rotates the current device intent")
        let (inPlaceDiscovery, inPlacePrevious) = try pair("discovery-in-place")
        try bad.write(to: inPlaceDiscovery.appendingPathComponent("water.json"), options: .atomic)
        let inPlace = try HealthRecoveryCopies.captureDiscovery(in: inPlaceDiscovery)!
        try inPlace.prepare()
        let changedHandle = try FileHandle(forWritingTo: inPlacePrevious.appendingPathComponent("water.json"))
        try changedHandle.write(contentsOf: Data("[]".utf8)); try changedHandle.truncate(atOffset: 2); try changedHandle.close()
        rejects("in-place mutation of a captured prior inode rejects publication") { try inPlace.publish() }
        check(try copies(inPlaceDiscovery).isEmpty && Data(contentsOf: inPlaceDiscovery.appendingPathComponent("water.json")) == bad,
              "in-place source rejection retains the damaged current original")
        let (unsafeDiscovery, unsafePrevious) = try pair("discovery-symlink")
        try bad.write(to: unsafeDiscovery.appendingPathComponent("water.json"), options: .atomic)
        let untouched = outer.appendingPathComponent("discovery-untouched-water.json")
        try good.write(to: untouched)
        try fm.removeItem(at: unsafePrevious.appendingPathComponent("water.json"))
        try fm.createSymbolicLink(at: unsafePrevious.appendingPathComponent("water.json"), withDestinationURL: untouched)
        rejects("discovery refuses a prior symlink instead of following its target") { _ = try HealthRecoveryCopies.discover(in: unsafeDiscovery) }
        check(try Data(contentsOf: untouched) == good && copies(unsafeDiscovery).isEmpty, "unsafe prior discovery leaves referenced user bytes untouched and publishes nothing")
        let (cancelDiscovery, _) = try pair("discovery-cancel-prepare")
        try bad.write(to: cancelDiscovery.appendingPathComponent("water.json"), options: .atomic)
        var discardedDiscovery = try HealthRecoveryCopies.captureDiscovery(in: cancelDiscovery)
        let stopDiscovery = BackupOperationControl(); stopDiscovery.cancel()
        rejects("explicit cancellation stops discovery before snapshot validation") { try discardedDiscovery!.prepare(control: stopDiscovery) }
        discardedDiscovery = nil
        let discoveryLeftovers = try fm.contentsOfDirectory(at: outer, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(cancelDiscovery.lastPathComponent + ".discovery-") }
        let cancelledPublishedCopies = try copies(cancelDiscovery)
        check(discoveryLeftovers.isEmpty && cancelledPublishedCopies.isEmpty, "discarded discovery removes only its own snapshot and publishes no incident")

        let (root, previous) = try pair("baseline")
        try bad.write(to: root.appendingPathComponent("water.json"), options: .atomic)
        let prepared = try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: root)
        check(try retained(root, good), "exact baseline good previous water survives unrelated preparation")
        check(try Data(contentsOf: root.appendingPathComponent("water.json")) == bad, "preparation retains exact damaged current water")
        check(try Data(contentsOf: root.appendingPathComponent("goals.json")) == goals, "private-copy preparation does not publish the proposed goal")
        prepared.discard()
        check(try retained(root, good), "discarding the new transaction retains the recovered previous bytes")
        try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: root).commit()
        check(try retained(root, good), "unrelated successful commit carries the good private copy into the new root")
        check(try Data(contentsOf: root.appendingPathComponent("water.json")) == bad, "successful unrelated change does not silently restore damaged history")
        check(try Data(contentsOf: root.appendingPathComponent("goals.json")) == replacement, "healthy unrelated goal change remains usable")
        check(try copies(root).count == 1, "one preservation incident creates one complete private copy")
        for _ in 0..<3 {
            try fm.copyItem(at: root, to: previous)
            try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: root).commit()
        }
        check(try copies(root).count == 2 && retained(root, good) && retained(root, bad), "repeated prior trees reuse exact payload copies while retaining raw damaged prior data")
        check(try copies(root).allSatisfy { !fm.fileExists(atPath: $0.appendingPathComponent(HealthRecoveryCopies.name).path) }, "private copies never recursively mirror the recovery area")

        let catalog = try HealthRecoveryCopies.previews(in: root)
        check(catalog.count == 2 && catalog.allSatisfy(\.complete), "catalog observes both published prior incidents without merging their histories")
        let healthyPreview = catalog.first { $0.domains.contains { $0.domain == .water && $0.state == .readable } }!
        let damagedPreview = catalog.first { $0.domains.contains { $0.domain == .water && $0.state == .unavailable } }!
        check(healthyPreview.domains.first { $0.domain == .water }?.recordCount == 1, "exact baseline retained water is a one-record recovery choice")
        check(damagedPreview.domains.first { $0.domain == .water }?.recordCount == nil, "damaged raw prior water is unavailable rather than an empty history")
        check(healthyPreview.domains.first { $0.domain == .meals }?.state == .notIncluded, "absent retained domains are explicitly not included")
        try HealthRecoveryCopies.verify(healthyPreview, in: root)
        check(try retained(root, good) && retained(root, bad), "preview and reviewed-source verification retain both exact good and damaged originals")
        let reviewedFile = root.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(healthyPreview.id).appendingPathComponent("water.json")
        try Data("[]".utf8).write(to: reviewedFile, options: .atomic)
        rejects("reviewed source verification rejects a valid but different same-domain payload") { try HealthRecoveryCopies.verify(healthyPreview, in: root) }
        let emptyPreview = try HealthRecoveryCopies.previews(in: root).first { $0.id == healthyPreview.id }!
        check(emptyPreview.domains.first { $0.domain == .water }?.recordCount == 0 && emptyPreview.domains.first { $0.domain == .water }?.state == .readable,
              "valid empty retained history is readable with zero records rather than unavailable")
        try good.write(to: reviewedFile, options: .atomic)
        try HealthRecoveryCopies.verify(healthyPreview, in: root)
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("catalog cancellation is not converted to an unavailable-copy observation") { _ = try HealthRecoveryCopies.previews(in: root, control: cancelled) }
        let held = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), observed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { HealthRecoveryCopies.serialized { held.signal(); release.wait() } }
        held.wait()
        DispatchQueue.global().async {
            _ = try? HealthRecoveryCopies.previews(in: root)
            try? HealthRecoveryCopies.verify(healthyPreview, in: root)
            observed.signal()
        }
        let nonblocking = observed.wait(timeout: .now() + 2) == .success
        release.signal(); if !nonblocking { observed.wait() }
        check(nonblocking, "preview and reviewed-source reads complete while another worker holds the directory write lock")
        rejects("raw damaged copy cannot become a selected replacement") {
            _ = try HealthRecoverySelection.retained(damagedPreview, in: root, domains: [.water], validPhoto: { _ in false })
        }
        let selectedWater = try HealthRecoverySelection.retained(healthyPreview, in: root, domains: [.water], validPhoto: { _ in false })
        let (cancelRoot, cancelPrevious) = try pair("cancelled-preservation")
        let cancelResult = CancellationResult(), cancelDone = DispatchSemaphore(value: 0)
        Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var cancelled = false
            do { try HealthRecoveryCopies.serialized { try HealthRecoveryCopies.preservePrevious(in: cancelRoot) } }
            catch is CancellationError { cancelled = true }
            catch { }
            cancelResult.set(cancelled); cancelDone.signal()
        }
        let cancelledCompleted = cancelDone.wait(timeout: .now() + 5) == .success
        check(cancelledCompleted && cancelResult.get(), "cancelled preservation stays cancellation instead of classifying healthy data as corrupt")
        check(try Data(contentsOf: cancelPrevious.appendingPathComponent("water.json")) == good && !fm.fileExists(atPath: cancelRoot.appendingPathComponent(HealthRecoveryCopies.name).path),
              "cancelled read leaves the healthy prior copy in place without publishing a false recovery incident")
        let bounded = outer.appendingPathComponent("bounded-reader")
        try Data().write(to: bounded)
        check(try HealthLocalFiles.readRegularData(bounded, limit: 0).isEmpty, "bounded reader accepts an empty regular file at a zero-byte ceiling")
        let boundaryBytes = Data(repeating: 32, count: 128)
        try boundaryBytes.write(to: bounded, options: .atomic)
        check(try HealthLocalFiles.readRegularData(bounded, limit: 128) == boundaryBytes, "bounded descriptor reader accepts the exact byte ceiling")
        try (boundaryBytes + Data([32])).write(to: bounded, options: .atomic)
        rejects("bounded descriptor reader rejects one byte above its ceiling") { _ = try HealthLocalFiles.readRegularData(bounded, limit: 128) }
        let boundedAlias = outer.appendingPathComponent("bounded-alias")
        try fm.createSymbolicLink(at: boundedAlias, withDestinationURL: bounded)
        rejects("bounded descriptor reader refuses a leaf symlink without reading its target") { _ = try HealthLocalFiles.readRegularData(boundedAlias, limit: 1024) }
        check(try Data(contentsOf: bounded).count == 129, "refusing a symlink leaves its referenced bytes untouched")
        let fifo = outer.appendingPathComponent("bounded-fifo")
        guard mkfifo(fifo.path, mode_t(0o600)) == 0 else { throw HealthLocalFiles.Failure.invalid }
        rejects("nonblocking descriptor open rejects a real FIFO without waiting for a writer") { _ = try HealthLocalFiles.readRegularData(fifo, limit: 128) }
        try fm.removeItem(at: fifo)
        rejects("bounded descriptor reader rejects a directory") { _ = try HealthLocalFiles.readRegularData(root, limit: 128) }

        let (capacity, capacityPrevious) = try pair("sparse-current-capacity")
        let hugeWater = capacity.appendingPathComponent("water.json")
        let hugeLength = UInt64(HealthLocalFiles.limit + 1)
        let hugeHandle = try FileHandle(forWritingTo: hugeWater)
        try hugeHandle.truncate(atOffset: hugeLength); try hugeHandle.close()
        let originalHugeInode = try fm.attributesOfItem(atPath: hugeWater.path)[.systemFileNumber] as? NSNumber
        let healthyMeal = try encoder.encode([Meal(id: "unselected-healthy-meal", type: .lunch, items: [], photoID: "keep")])
        try healthyMeal.write(to: capacity.appendingPathComponent("meals.json"))
        let healthyPhotos = capacity.appendingPathComponent("photos")
        try fm.createDirectory(at: healthyPhotos, withIntermediateDirectories: false)
        let unselectedPhoto = Data("unselected healthy photo bytes".utf8)
        try unselectedPhoto.write(to: healthyPhotos.appendingPathComponent("keep.jpg"))
        try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: capacity).commit()
        check(try retained(capacity, good) && !fm.fileExists(atPath: capacityPrevious.path), "oversized current water is rejected before allocation while its good prior copy survives unrelated commit")
        check(try fm.attributesOfItem(atPath: hugeWater.path)[.size] as? NSNumber == NSNumber(value: hugeLength), "capacity rejection leaves the exact sparse current file length intact")
        try HealthRecoverySelection.prepare(selectedWater, into: capacity, owner: UUID()).commit()
        let privateHuge = try copies(capacity).map { $0.appendingPathComponent("water.json") }.first {
            (try? fm.attributesOfItem(atPath: $0.path)[.size] as? NSNumber) == NSNumber(value: hugeLength)
        }!
        check(try fm.attributesOfItem(atPath: privateHuge.path)[.systemFileNumber] as? NSNumber == originalHugeInode && Data(contentsOf: hugeWater) == good,
              "explicit recovery keeps the oversized original inode privately and installs the exact reviewed small records")
        check(try Data(contentsOf: capacity.appendingPathComponent("meals.json")) == healthyMeal && Data(contentsOf: healthyPhotos.appendingPathComponent("keep.jpg")) == unselectedPhoto,
              "water-only replacement keeps healthy unselected meal metadata and photo bytes live")
        check(try !retained(capacity, unselectedPhoto, file: "photos/keep.jpg"), "unselected healthy photos stay live rather than moving into private replaced data")
        check(try HealthRecoveryCopies.previews(in: capacity).contains { $0.domains.contains { $0.domain == .water && $0.state == .unavailable && $0.digest == nil } },
              "catalog marks oversized raw copies unavailable without allocating their contents")
        try fm.removeItem(at: capacity)

        let oversizedIntent = outer.appendingPathComponent("sparse-intent-capacity")
        try seed(oversizedIntent)
        let intentPath = oversizedIntent.appendingPathComponent(HealthWriteFiles.name)
        try Data().write(to: intentPath)
        let intentHandle = try FileHandle(forWritingTo: intentPath)
        try intentHandle.truncate(atOffset: UInt64(HealthWriteJournal.maxBytes + 1)); try intentHandle.close()
        var journalCapacityRejected = false
        do { _ = try HealthWriteFiles.read(from: oversizedIntent) }
        catch HealthWriteJournal.Failure.invalid { journalCapacityRejected = true }
        check(journalCapacityRejected, "live journal reader rejects a sparse file above its shared decoder ceiling before allocation")
        rejects("recovery selection uses the same journal ceiling and cannot replace oversized intent with an empty queue") {
            _ = try HealthRecoverySelection.prepare(selectedWater, into: oversizedIntent, owner: UUID())
        }
        check(try fm.attributesOfItem(atPath: intentPath.path)[.size] as? NSNumber == NSNumber(value: HealthWriteJournal.maxBytes + 1), "oversized intent rejection retains the original sparse file")
        try fm.removeItem(at: oversizedIntent)
        check(try HealthRecoverySelection.records(healthyPreview, domain: .water, in: root) == good,
              "record review opens the exact validated baseline bytes before selection")
        rejects("record review cannot show damaged retained bytes as valid history") {
            _ = try HealthRecoverySelection.records(damagedPreview, domain: .water, in: root)
        }
        let recovery = outer.appendingPathComponent("explicit-water")
        try seed(recovery); try bad.write(to: recovery.appendingPathComponent("water.json"), options: .atomic)
        let recoveryOwner = UUID()
        func cancellationTarget(_ name: String) throws -> URL {
            let target = outer.appendingPathComponent(name)
            try seed(target); try bad.write(to: target.appendingPathComponent("water.json"))
            try HealthWriteJournal(owner: recoveryOwner).encoded().write(to: target.appendingPathComponent(HealthWriteFiles.name))
            return target
        }
        func cancellationFiles(_ target: URL) throws -> [String: Data] {
            var saved: [String: Data] = [:]
            let entries = fm.enumerator(at: target, includingPropertiesForKeys: [.isDirectoryKey])!
            for case let file as URL in entries {
                let relative = String(file.path.dropFirst(target.path.count + 1))
                if try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { saved[relative + "/"] = Data() }
                else { saved[relative] = try Data(contentsOf: file) }
            }
            return saved
        }
        let cancelledTarget = try cancellationTarget("cancel-before-commit")
        let cancelledBefore = try cancellationFiles(cancelledTarget)
        let cancelledControl = BackupOperationControl()
        let cancelledStage = try HealthRecoverySelection.prepare(selectedWater, into: cancelledTarget, owner: recoveryOwner, control: cancelledControl)
        cancelledControl.cancel()
        var rejectedCancellation = false
        do { try cancelledStage.commit(control: cancelledControl) } catch is CancellationError { rejectedCancellation = true }
        check(rejectedCancellation, "cancelling a fully prepared recovery rejects installation with CancellationError")
        check(try cancellationFiles(cancelledTarget) == cancelledBefore, "cancelled prepared commit retains exact damaged/current files and intent without a receipt")
        cancelledStage.discard()

        let queuedTarget = try cancellationTarget("cancel-waiting-commit")
        let queuedBefore = try cancellationFiles(queuedTarget)
        let queuedControl = BackupOperationControl()
        let queuedStage = try HealthRecoverySelection.prepare(selectedWater, into: queuedTarget, owner: recoveryOwner, control: queuedControl)
        let commitStarted = DispatchSemaphore(value: 0), commitEnded = DispatchSemaphore(value: 0)
        let queuedResult = CancellationResult()
        let queuedStarted = HealthRecoveryCopies.serialized {
            DispatchQueue.global().async {
                commitStarted.signal()
                do { try queuedStage.commit(control: queuedControl); queuedResult.set(false) }
                catch is CancellationError { queuedResult.set(true) }
                catch { queuedResult.set(false) }
                commitEnded.signal()
            }
            let started = commitStarted.wait(timeout: .now() + 5) == .success
            queuedControl.cancel()
            return started
        }
        check(queuedStarted, "commit worker starts while the common directory commit lock is held")
        check(commitEnded.wait(timeout: .now() + 5) == .success, "cancelled queued commit finishes after the common lock releases")
        check(queuedResult.get(), "queued commit rechecks cancellation after acquiring the directory lock")
        check(try cancellationFiles(queuedTarget) == queuedBefore, "cancellation during the commit-lock wait preserves every original byte and creates no receipt")
        queuedStage.discard()
        var recoveryJournal = HealthWriteJournal(owner: recoveryOwner)
        try recoveryJournal.append(domain: .water, localID: "old-unstarted-water", components: [.init(metric: .water, value: 100, date: Date())])
        try recoveryJournal.requestDeletion(domain: .water, localID: "older-owned-removal")
        let originalIntent = try recoveryJournal.encoded()
        try originalIntent.write(to: recovery.appendingPathComponent(HealthWriteFiles.name))
        let staleRecovery = try HealthRecoverySelection.prepare(selectedWater, into: recovery, owner: recoveryOwner)
        try good.write(to: recovery.appendingPathComponent("water.json"), options: .atomic)
        rejects("source replacement during recovery staging rejects installation") { try staleRecovery.commit() }
        staleRecovery.discard()
        check(try Data(contentsOf: recovery.appendingPathComponent("water.json")) == good && Data(contentsOf: recovery.appendingPathComponent(HealthWriteFiles.name)) == originalIntent,
              "rejected recovery preserves the newly healthy target and original device intent")
        rejects("explicit recovery cannot replace an already readable current domain") { _ = try HealthRecoverySelection.prepare(selectedWater, into: recovery, owner: recoveryOwner) }
        try bad.write(to: recovery.appendingPathComponent("water.json"), options: .atomic)
        rejects("recovery cannot adopt foreign live device intent") { _ = try HealthRecoverySelection.prepare(selectedWater, into: recovery, owner: UUID()) }
        var changedIntent = recoveryJournal
        try changedIntent.append(domain: .water, localID: "new-concurrent-intent", components: [.init(metric: .water, value: 200, date: Date())])
        let changedIntentBytes = try changedIntent.encoded(), intentFile = recovery.appendingPathComponent(HealthWriteFiles.name)
        let changingIntent = BackupOperationControl { progress in
            if progress.stage == .restoring && progress.completed == 0 { try? changedIntentBytes.write(to: intentFile, options: .atomic) }
        }
        rejects("intent changed during recovery preparation rejects before returning a transaction") {
            _ = try HealthRecoverySelection.prepare(selectedWater, into: recovery, owner: recoveryOwner, control: changingIntent)
        }
        check(try Data(contentsOf: intentFile) == changedIntentBytes && Data(contentsOf: recovery.appendingPathComponent("water.json")) == bad,
              "recovery preparation retains concurrent device work and the unchanged damaged target")
        try originalIntent.write(to: intentFile, options: .atomic)
        let failedInstall = try HealthRecoverySelection.prepare(selectedWater, into: recovery, owner: recoveryOwner)
        for folder in try fm.contentsOfDirectory(at: outer, includingPropertiesForKeys: nil) where folder.lastPathComponent.hasPrefix(recovery.lastPathComponent + ".restore-") { try fm.removeItem(at: folder) }
        rejects("actual missing-stage installation failure cannot publish explicit recovery") { try failedInstall.commit() }
        check(try Data(contentsOf: recovery.appendingPathComponent("water.json")) == bad && Data(contentsOf: intentFile) == originalIntent,
              "failed explicit recovery installation restores the damaged current root and its original intent")
        let install = try HealthRecoverySelection.prepare(selectedWater, into: recovery, owner: recoveryOwner)
        check(try Data(contentsOf: recovery.appendingPathComponent("water.json")) == bad, "preparing explicit recovery does not publish its replacement")
        try install.commit()
        check(try Data(contentsOf: recovery.appendingPathComponent("water.json")) == good && retained(recovery, bad), "explicit replacement installs exact reviewed records and privately retains exact damaged originals")
        check(try Data(contentsOf: recovery.appendingPathComponent("goals.json")) == goals, "explicit water recovery leaves unrelated healthy goals unchanged")
        check(try retained(recovery, originalIntent, file: HealthRecoveryCopies.intentProvenanceName), "recovery retains the exact old live intent as non-live provenance")
        let recoveredIntent = try HealthWriteFiles.read(from: recovery, owner: recoveryOwner)
        check(recoveredIntent.owner == recoveryOwner && recoveredIntent.lifecycle != recoveryJournal.lifecycle && recoveredIntent.events == recoveryJournal.events,
              "recovery rotates this device lifecycle while retaining exact event identities and pending removal")
        check(recoveredIntent.next()?.action == .delete, "withdrawn old save is not replayed and pending owned deletion remains eligible")

        let directoryRecovery = outer.appendingPathComponent("directory-replacement")
        try seed(directoryRecovery); try fm.removeItem(at: directoryRecovery.appendingPathComponent("water.json"))
        try fm.createDirectory(at: directoryRecovery.appendingPathComponent("water.json"), withIntermediateDirectories: false)
        try bad.write(to: directoryRecovery.appendingPathComponent("water.json/raw-original"))
        try HealthRecoverySelection.prepare(selectedWater, into: directoryRecovery, owner: recoveryOwner).commit()
        check(try Data(contentsOf: directoryRecovery.appendingPathComponent("water.json")) == good && retained(directoryRecovery, bad, file: "water.json/raw-original"),
              "non-regular directory target is replaced only after its complete raw tree is retained privately")
        let (conversationFailure, conversationPrevious) = try pair("recovery-protects-conversations")
        try bad.write(to: conversationFailure.appendingPathComponent("water.json"), options: .atomic)
        try bad.write(to: conversationFailure.appendingPathComponent("conversations.json"), options: .atomic)
        rejects("health recovery rejects before retiring a good prior conversation copy when current conversations cannot open") {
            _ = try HealthRecoverySelection.prepare(selectedWater, into: conversationFailure, owner: recoveryOwner)
        }
        check(try Data(contentsOf: conversationPrevious.appendingPathComponent("conversations.json")) == conversations["conversations.json"] && Data(contentsOf: conversationFailure.appendingPathComponent("water.json")) == bad,
              "failed targeted recovery retains the exact previous conversations and damaged current water")

        let (allDomains, allPrevious) = try pair("all-preview-domains")
        let allPayloads: [String: Data] = ["water": good, "meals": Data("[]".utf8), "workouts": Data("[]".utf8), "goals": goals, "today": try encoder.encode(DayMetrics.empty)]
        for (name, data) in allPayloads {
            try data.write(to: allPrevious.appendingPathComponent(name + ".json"))
            try bad.write(to: allDomains.appendingPathComponent(name + ".json"))
        }
        try BackupFiles.recover(allDomains)
        let allPreview = try HealthRecoveryCopies.previews(in: allDomains).first!
        check(allPreview.complete && allPreview.domains.allSatisfy { $0.state == .readable }, "one retained incident previews all five validated health domains")
        let allSelected = try HealthRecoverySelection.retained(allPreview, in: allDomains, domains: Set(HealthLocalFiles.Domain.allCases), validPhoto: { _ in false })
        let allTarget = outer.appendingPathComponent("replace-all-health-domains")
        try seed(allTarget)
        for name in allPayloads.keys { try bad.write(to: allTarget.appendingPathComponent(name + ".json"), options: .atomic) }
        try HealthRecoverySelection.prepare(allSelected, into: allTarget, owner: recoveryOwner).commit()
        var allExact = true
        for (name, bytes) in allPayloads {
            if try Data(contentsOf: allTarget.appendingPathComponent(name + ".json")) != bytes { allExact = false }
        }
        check(allExact, "one linked explicit replacement recovers all five reviewed domains including the retained daily cache")
        check(try copies(allTarget).count == 1 && retained(allTarget, bad, file: "today.json"), "all-domain replacement retains one incident with the exact damaged daily-cache original")
        check(allPreview.domains.first { $0.domain == .goals }?.recordCount == 1 && allPreview.domains.first { $0.domain == .today }?.recordCount == 1,
              "retained goals and daily cache each preview as one saved snapshot")
        check(allPreview.domains.first { $0.domain == .workouts }?.recordCount == 0 && allPreview.domains.first { $0.domain == .meals }?.recordCount == 0,
              "valid empty workout and meal histories remain explicitly empty")
        let allCopy = allDomains.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(allPreview.id)
        var invalidRetainedGoals = HealthGoals(); invalidRetainedGoals.weightKg = -1
        let invalidRetainedGoalData = try encoder.encode(invalidRetainedGoals)
        _ = try JSONDecoder().decode(HealthGoals.self, from: invalidRetainedGoalData)
        try invalidRetainedGoalData.write(to: allCopy.appendingPathComponent("goals.json"), options: .atomic)
        let invalidGoals = try HealthRecoveryCopies.previews(in: allDomains).first!
        check(invalidGoals.domains.first { $0.domain == .goals }?.state == .unavailable && invalidGoals.domains.first { $0.domain == .water }?.state == .readable,
              "semantically invalid retained goals do not hide readable water in the same incident")
        try fm.removeItem(at: allCopy.appendingPathComponent("today.json"))
        check(try HealthRecoveryCopies.previews(in: allDomains).first?.complete == false,
              "a missing declared domain prevents a complete recovery choice")

        let (late, latePrevious) = try pair("late-copy")
        try fm.removeItem(at: latePrevious)
        try bad.write(to: late.appendingPathComponent("water.json"), options: .atomic)
        let lateStage = try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: late)
        try seed(latePrevious)
        try lateStage.commit()
        check(try retained(late, good), "a good prior copy discovered after preparation is carried into the installed stage")
        check(try Data(contentsOf: late.appendingPathComponent("water.json")) == bad, "late preservation retains the unchanged damaged source")

        let (changed, changedPrevious) = try pair("changed-source")
        try fm.removeItem(at: changedPrevious)
        let stale = try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: changed)
        try bad.write(to: changed.appendingPathComponent("water.json"), options: .atomic)
        try seed(changedPrevious)
        rejects("external source replacement during preparation rejects installation") { try stale.commit() }
        check(try Data(contentsOf: changed.appendingPathComponent("water.json")) == bad && Data(contentsOf: changedPrevious.appendingPathComponent("water.json")) == good,
              "source-change rejection precedes retirement and retains both original current and prior files")
        stale.discard()

        let (privateRoot, privatePrevious) = try pair("private-only")
        let priorPrivate = privatePrevious.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: priorPrivate, withIntermediateDirectories: true)
        try good.write(to: priorPrivate.appendingPathComponent("water.json"))
        try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: privateRoot).commit()
        check(try retained(privateRoot, good), "a private copy present only in previous is retained even when live domains are healthy")
        try fm.copyItem(at: privateRoot, to: privatePrevious)
        let sameName = try copies(privateRoot)[0].lastPathComponent
        let different = try encoder.encode([HydrationLog(id: "different-prior", ml: 444)])
        try different.write(to: privatePrevious.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(sameName).appendingPathComponent("water.json"), options: .atomic)
        try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: privateRoot).commit()
        check(try retained(privateRoot, good) && retained(privateRoot, different), "same-name but different private copies are both retained after byte comparison")

        let (missing, _) = try pair("missing-domain")
        try fm.removeItem(at: missing.appendingPathComponent("water.json"))
        try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: missing).commit()
        let missingCopies = try copies(missing)
        check(!fm.fileExists(atPath: missing.appendingPathComponent("water.json").path) && missingCopies.isEmpty,
              "a genuinely absent current domain does not resurrect intentionally missing records")
        let (interrupted, interruptedPrevious) = try pair("interrupted")
        try fm.removeItem(at: interrupted)
        try BackupFiles.recover(interrupted)
        check(try Data(contentsOf: interrupted.appendingPathComponent("water.json")) == good && !fm.fileExists(atPath: interruptedPrevious.path), "missing-root recovery still restores the complete previous directory")

        let (meals, mealsPrevious) = try pair("meal-photos")
        let mealData = try encoder.encode([Meal(id: "shared-a", type: .lunch, items: [], photoID: "shared"), Meal(id: "shared-b", type: .dinner, items: [], photoID: "shared")])
        try bad.write(to: meals.appendingPathComponent("meals.json"))
        try mealData.write(to: mealsPrevious.appendingPathComponent("meals.json"))
        let photos = mealsPrevious.appendingPathComponent("photos")
        try fm.createDirectory(at: photos, withIntermediateDirectories: false)
        let photo = Data("synthetic exact owned photo bytes".utf8)
        try photo.write(to: photos.appendingPathComponent("shared.jpg"))
        try Data("old private intent must not replay".utf8).write(to: mealsPrevious.appendingPathComponent(HealthWriteFiles.name))
        try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: meals).commit()
        check(try retained(meals, mealData, file: "meals.json") && retained(meals, photo, file: "photos/shared.jpg"), "meal recovery keeps exact records and a shared photo once")
        check(try copies(meals).allSatisfy { !fm.fileExists(atPath: $0.appendingPathComponent(HealthWriteFiles.name).path) }, "private operation provenance never occupies the live journal filename")
        check(try retained(meals, Data("old private intent must not replay".utf8), file: HealthRecoveryCopies.intentProvenanceName), "raw prior operation provenance is retained under a non-live filename")
        check(!fm.fileExists(atPath: meals.appendingPathComponent("photos/shared.jpg").path), "retained meal photos are not silently installed as live photos")

        let mealPreview = try HealthRecoveryCopies.previews(in: meals).first!
        let mealObservation = mealPreview.domains.first { $0.domain == .meals }!
        check(mealObservation.state == .readable && mealObservation.recordCount == 2 && mealObservation.photos.count == 1,
              "two retained meals review as two records with one shared photo dependency")
        check(mealObservation.photos[0].state == .readable && mealObservation.photos[0].digest != nil,
              "photo preview fingerprints readable bytes without claiming JPEG decoding")
        check(mealPreview.hasIntentProvenance && mealPreview.domains.count == 5,
              "private device intent is provenance only and never a sixth recoverable domain")
        let mealCopy = meals.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(mealPreview.id)
        let retainedPhoto = mealCopy.appendingPathComponent("photos/shared.jpg")
        try fm.removeItem(at: retainedPhoto)
        let missingPhotoPreview = try HealthRecoveryCopies.previews(in: meals).first!
        check(missingPhotoPreview.domains.first { $0.domain == .meals }!.photos.first?.state == .missing,
              "missing photo remains visible beside readable retained meal records")
        rejects("a removed photo invalidates the exact reviewed source") { try HealthRecoveryCopies.verify(mealPreview, in: meals) }
        try fm.createSymbolicLink(at: retainedPhoto, withDestinationURL: referencePhoto(outer, data: photo))
        let linkedPhotoPreview = try HealthRecoveryCopies.previews(in: meals).first!
        check(linkedPhotoPreview.domains.first { $0.domain == .meals }!.photos.first?.state == .unavailable,
              "a symlink photo is unavailable and never followed for recovery preview")
        try fm.removeItem(at: retainedPhoto); try photo.write(to: retainedPhoto)
        try HealthRecoveryCopies.verify(mealPreview, in: meals)

        let catalogBase = meals.appendingPathComponent(HealthRecoveryCopies.name)
        let pendingCopy = catalogBase.appendingPathComponent("pending-synthetic")
        try fm.copyItem(at: mealCopy, to: pendingCopy)
        check(try HealthRecoveryCopies.previews(in: meals).first { $0.id == "pending-synthetic" }?.complete == false,
              "an interrupted unpublished stage is visible but not a complete recovery choice")
        try fm.removeItem(at: pendingCopy)
        let manifestFile = mealCopy.appendingPathComponent("manifest.json")
        let originalManifest = try Data(contentsOf: manifestFile)
        try bad.write(to: manifestFile, options: .atomic)
        let invalidManifestPreview = try HealthRecoveryCopies.previews(in: meals).first!
        check(!invalidManifestPreview.complete && invalidManifestPreview.domains.first { $0.domain == .meals }?.recordCount == 2,
              "invalid manifest retains visible raw records without authorizing a complete recovery choice")
        rejects("an incomplete reviewed copy cannot pass source verification") { try HealthRecoveryCopies.verify(invalidManifestPreview, in: meals) }
        try originalManifest.write(to: manifestFile, options: .atomic)
        let alias = catalogBase.appendingPathComponent("copy-alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: mealCopy)
        let aliasPreview = try HealthRecoveryCopies.previews(in: meals).first { $0.id == "copy-alias" }!
        check(!aliasPreview.complete && aliasPreview.domains.isEmpty, "catalog never follows an alias into another recovery copy")
        try fm.removeItem(at: alias)
        check(try Data(contentsOf: meals.appendingPathComponent("meals.json")) == bad && Data(contentsOf: mealCopy.appendingPathComponent("meals.json")) == mealData,
              "all recovery preview failures preserve current damage and retained original records")

        rejects("meal recovery requires explicit omission of a missing photo") {
            try fm.removeItem(at: retainedPhoto)
            let missing = try HealthRecoveryCopies.previews(in: meals).first!
            _ = try HealthRecoverySelection.retained(missing, in: meals, domains: [.meals], validPhoto: { _ in true })
        }
        let withoutPhoto = try HealthRecoverySelection.retained(HealthRecoveryCopies.previews(in: meals).first!, in: meals, domains: [.meals], omittingPhotos: ["shared"], validPhoto: { _ in false })
        let mealTarget = outer.appendingPathComponent("explicit-meals")
        try seed(mealTarget); try bad.write(to: mealTarget.appendingPathComponent("meals.json"))
        try HealthRecoverySelection.prepare(withoutPhoto, into: mealTarget, owner: recoveryOwner).commit()
        let decodedWithout = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: mealTarget.appendingPathComponent("meals.json")))
        check(decodedWithout.count == 2 && decodedWithout.allSatisfy { $0.photoID == nil }, "explicit omission recovers both meal records without dangling missing-photo references")
        try photo.write(to: retainedPhoto)
        rejects("platform photo-validation failure rejects selected photo bytes") {
            _ = try HealthRecoverySelection.retained(mealPreview, in: meals, domains: [.meals], validPhoto: { _ in false })
        }
        let withPhoto = try HealthRecoverySelection.retained(mealPreview, in: meals, domains: [.meals], validPhoto: { _ in true })
        try bad.write(to: mealTarget.appendingPathComponent("meals.json"), options: .atomic)
        let oldPhotos = mealTarget.appendingPathComponent("photos")
        try fm.createDirectory(at: oldPhotos, withIntermediateDirectories: true)
        let oldPhoto = Data("damaged history photo original".utf8)
        try oldPhoto.write(to: oldPhotos.appendingPathComponent("shared.jpg"))
        try Data("changed selected source photo".utf8).write(to: retainedPhoto, options: .atomic)
        rejects("selected photo changed before copy rejects staging rather than importing different bytes") { _ = try HealthRecoverySelection.prepare(withPhoto, into: mealTarget, owner: recoveryOwner) }
        check(try Data(contentsOf: mealTarget.appendingPathComponent("meals.json")) == bad && Data(contentsOf: oldPhotos.appendingPathComponent("shared.jpg")) == oldPhoto,
              "photo staging failure preserves exact damaged current metadata and photos")
        try photo.write(to: retainedPhoto, options: .atomic)
        try HealthRecoverySelection.prepare(withPhoto, into: mealTarget, owner: recoveryOwner).commit()
        let recoveredMeals = try BackupArchive.decoder().decode([Meal].self, from: Data(contentsOf: mealTarget.appendingPathComponent("meals.json")))
        let restoredPhotoID = recoveredMeals[0].photoID!
        check(recoveredMeals.count == 2 && recoveredMeals.allSatisfy { $0.photoID == restoredPhotoID } && restoredPhotoID != "shared", "shared recovered photo receives one fresh identity without reusing a current photo path")
        check(try Data(contentsOf: mealTarget.appendingPathComponent("photos/" + restoredPhotoID + ".jpg")) == photo && retained(mealTarget, oldPhoto, file: "photos/shared.jpg"),
              "recovered photo bytes match review while original current photos remain private")

        var backup = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        backup.water = try BackupArchive.decoder().decode([HydrationLog].self, from: good)
        let encryptedURL = outer.appendingPathComponent("recovery-test.lumenbackup"), password = "Synthetic recovery passphrase 43"
        try BackupPackage.write(backup, photos: [:], password: password, to: encryptedURL)
        let contents = try BackupPackage.read(encryptedURL, password: password, temporaryRoot: outer)
        let encryptedSelection = try HealthRecoverySelection.backup(contents.snapshot, photos: contents.photos, domains: [.water], validPhoto: { _ in false })
        try bad.write(to: recovery.appendingPathComponent("water.json"), options: .atomic)
        try HealthRecoverySelection.prepare(encryptedSelection, into: recovery, owner: recoveryOwner).commit()
        let archiveWater = try encoder.encode(backup.water)
        check(try Data(contentsOf: recovery.appendingPathComponent("water.json")) == archiveWater, "actual encrypted archive installs the exact canonical selected water payload")
        let readableURL = outer.appendingPathComponent("recovery-readable.json")
        try ReadableExport.write(backup, to: readableURL)
        let readable = try ReadableExport.read(Data(contentsOf: readableURL))
        let readableSelection = try HealthRecoverySelection.backup(readable.snapshot, photos: [:], domains: [.water], validPhoto: { _ in false })
        try bad.write(to: recovery.appendingPathComponent("water.json"), options: .atomic)
        try HealthRecoverySelection.prepare(readableSelection, into: recovery, owner: recoveryOwner).commit()
        check(try Data(contentsOf: recovery.appendingPathComponent("water.json")) == archiveWater, "actual readable export installs the exact canonical payload without a live snapshot of damaged data")
        rejects("backup without today cache cannot claim to recover daily readings") { _ = try HealthRecoverySelection.backup(backup, photos: [:], domains: [.today], validPhoto: { _ in false }) }

        // Bind actual decoded inputs to their original file, through installation.
        let legacyBytes = try BackupArchive.make(backup)
        for format in [BackupSourceIdentity.Format.encryptedBackup, .legacyJSONBackup, .readableExport] {
            let workspace = try BackupWorkspace(base: outer)
            let file = workspace.directory.appendingPathComponent("selected-backup")
            let bytes: Data
            let decoded: BackupSnapshot
            switch format {
            case .encryptedBackup: bytes = try Data(contentsOf: encryptedURL); decoded = contents.snapshot
            case .legacyJSONBackup: bytes = legacyBytes; decoded = try BackupArchive.read(bytes).1
            case .readableExport: bytes = try Data(contentsOf: readableURL); decoded = readable.snapshot
            }
            try bytes.write(to: file)
            let identity = try BackupSourceIdentity.measure(file, named: "Original selected file.json", format: format, limit: Int64(bytes.count))
            let source = BackupRecoverySource(lease: BackupSourceLease(file: file, identity: identity, workspace: workspace), photoWorkspace: nil, contents: nil)
            let selectedFile = try HealthRecoverySelection.backup(decoded, photos: [:], domains: [.water], source: source, validPhoto: { _ in false })
            let target = outer.appendingPathComponent("bound-" + format.rawValue)
            try seed(target); try bad.write(to: target.appendingPathComponent("water.json"))
            let prepared = try HealthRecoverySelection.prepare(selectedFile, into: target, owner: recoveryOwner)
            try prepared.commit()
            check(try Data(contentsOf: target.appendingPathComponent("water.json")) == archiveWater && retained(target, bad), "bound \(format.rawValue) installs selected records and preserves damaged originals")
            let receipts = try fm.contentsOfDirectory(at: target.appendingPathComponent(".health-recovery-history"), includingPropertiesForKeys: nil)
            let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: receipts[0])) as! [String: Any]
            let recorded = try JSONDecoder().decode(BackupSourceIdentity.self, from: JSONSerialization.data(withJSONObject: receipt["fileSource"]!))
            check(recorded == identity && receipt["source"] as? String == "selected-file:" + identity.sha256 && receipt["omittedPhotoCount"] as? Int == 0,
                  "bound \(format.rawValue) receipt retains original name, format, byte count, hash and omission count")
            try bad.write(to: target.appendingPathComponent("water.json"), options: .atomic)
            let pending = try HealthRecoverySelection.prepare(selectedFile, into: target, owner: recoveryOwner)
            let before = try cancellationFiles(target)
            var changed = bytes; changed[changed.startIndex] ^= 1
            try changed.write(to: file, options: .atomic)
            rejects("bound \(format.rawValue) source replacement after prepare rejects at installation") { try pending.commit() }
            check(try cancellationFiles(target) == before, "bound \(format.rawValue) changed-source rejection preserves every current byte and receipt")
            rejects("bound \(format.rawValue) changed source cannot prepare another transaction") { _ = try HealthRecoverySelection.prepare(selectedFile, into: target, owner: recoveryOwner) }
            pending.discard()
        }

        let (intentRoot, intentPrevious) = try pair("intent-only")
        var intent = HealthWriteJournal(); try intent.requestDeletion(domain: .water, localID: "synthetic-owned-removal")
        let intentBytes = try intent.encoded()
        try intentBytes.write(to: intentPrevious.appendingPathComponent(HealthWriteFiles.name))
        try bad.write(to: intentRoot.appendingPathComponent(HealthWriteFiles.name))
        try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: intentRoot).commit()
        check(try retained(intentRoot, intentBytes, file: HealthRecoveryCopies.intentProvenanceName), "failed current intent preserves exact prior ownership and removal provenance privately")
        rejects("private prior intent is never adopted or replayed as the live journal") { _ = try HealthWriteFiles.read(from: intentRoot) }

        let (blocked, blockedPrevious) = try pair("blocked-private")
        try bad.write(to: blocked.appendingPathComponent("water.json"))
        try Data("blocked".utf8).write(to: blocked.appendingPathComponent(HealthRecoveryCopies.name))
        rejects("actual private destination failure rejects preparation before prior retirement") { _ = try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: blocked) }
        check(try Data(contentsOf: blockedPrevious.appendingPathComponent("water.json")) == good && Data(contentsOf: blocked.appendingPathComponent("water.json")) == bad, "failed preservation retains both exact prior and damaged current bytes")
        let (linked, linkedPrevious) = try pair("linked-prior")
        let reference = outer.appendingPathComponent("untouched-reference.json")
        try good.write(to: reference); try bad.write(to: linked.appendingPathComponent("water.json"))
        try fm.removeItem(at: linkedPrevious.appendingPathComponent("water.json"))
        try fm.createSymbolicLink(at: linkedPrevious.appendingPathComponent("water.json"), withDestinationURL: reference)
        rejects("prior symlink is rejected without following or retiring it") { _ = try ConversationFiles.prepareLinkedChange(["goals.json": replacement], into: linked) }
        check(try Data(contentsOf: reference) == good && fm.fileExists(atPath: linkedPrevious.path), "symlink failure leaves the referenced data and previous tree untouched")

        let resetRoot = root
        let failedReset = try HealthWriteFiles.prepareReset(into: resetRoot)
        for folder in try fm.contentsOfDirectory(at: outer, includingPropertiesForKeys: nil) where folder.lastPathComponent.hasPrefix(resetRoot.lastPathComponent + ".restore-") { try fm.removeItem(at: folder) }
        rejects("actual reset installation failure reaches the caller") { try failedReset.commit() }
        check(try retained(resetRoot, good) && Data(contentsOf: resetRoot.appendingPathComponent("water.json")) == bad,
              "failed checked reset keeps damaged current data and its private recovery copy")
        check(!fm.fileExists(atPath: resetRoot.appendingPathComponent(HealthRecoveryCopies.erasureMarker).path), "failed reset cannot publish a completed-erasure marker")
        var journal = HealthWriteJournal(); try journal.requestDeletion(domain: .water, localID: "synthetic-pending-delete")
        try journal.encoded().write(to: resetRoot.appendingPathComponent(HealthWriteFiles.name), options: .atomic)
        try HealthWriteFiles.prepareReset(into: resetRoot, owner: journal.owner).commit()
        check(!fm.fileExists(atPath: resetRoot.appendingPathComponent(HealthRecoveryCopies.name).path) && !fm.fileExists(atPath: resetRoot.appendingPathComponent("water.json").path), "successful explicit reset erases live history and private copies together")
        let minimal = try HealthWriteFiles.read(from: resetRoot, owner: journal.owner)
        check(minimal.events.count == 1 && minimal.events[0].action == .delete && minimal.events[0].components.allSatisfy { $0.value == 0 }, "reset retains only minimal same-owner pending deletion intent")
        let oldPrevious = resetRoot.appendingPathExtension("previous")
        try seed(oldPrevious)
        let oldCopy = oldPrevious.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: oldCopy, withIntermediateDirectories: true); try good.write(to: oldCopy.appendingPathComponent("water.json"))
        try HealthRecoveryCopies.erasureMarkerData.write(to: resetRoot.appendingPathComponent(HealthRecoveryCopies.erasureMarker))
        try BackupFiles.recover(resetRoot)
        check(!fm.fileExists(atPath: oldPrevious.path) && !fm.fileExists(atPath: resetRoot.appendingPathComponent(HealthRecoveryCopies.name).path), "restart after committed reset retires old private data without resurrecting it")
        check(!fm.fileExists(atPath: resetRoot.appendingPathComponent(HealthRecoveryCopies.erasureMarker).path), "erasure marker clears only after the old prior path has been retired")
        try seed(oldPrevious); try bad.write(to: resetRoot.appendingPathComponent(HealthRecoveryCopies.erasureMarker))
        rejects("corrupt erasure marker is not permission to delete a previous copy") { try BackupFiles.recover(resetRoot) }
        check(try Data(contentsOf: oldPrevious.appendingPathComponent("water.json")) == good, "corrupt marker retains the exact previous health file")

        if let output {
            let report: [String: Any] = ["status": "passed", "count": checks.count, "checks": checks,
                                        "baselineGoodWaterBytes": good.base64EncodedString(), "baselineDamagedWaterBytes": bad.base64EncodedString(),
                                        "scope": "Actual Foundation production preparation/install/recovery and real file/link/rename failures. No native UI, process interruption, failing device filesystem or explicit recovery selection acceptance."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }

    private static func referencePhoto(_ outer: URL, data: Data) throws -> URL {
        let file = outer.appendingPathComponent("untouched-preview-photo.jpg")
        try data.write(to: file); return file
    }
    private final class CancellationResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set(_ value: Bool) { lock.lock(); self.value = value; lock.unlock() }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
}
