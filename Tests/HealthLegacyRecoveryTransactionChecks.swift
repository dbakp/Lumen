import Foundation
import CryptoKit
import ImageIO

/// Actual checked backend transactions with isolated defaults. Product review
/// ownership, LocalStore locking and native standard-defaults routes are later.
enum HealthLegacyRecoveryTransactionChecks {
    static func run(output: URL) throws {
        typealias Origin = HealthLegacyRecoveryOrigin
        let fm = FileManager.default, encoder = BackupArchive.encoder()
        let area = fm.temporaryDirectory.appendingPathComponent("Lumen-legacy-transaction-" + UUID().uuidString)
        try fm.createDirectory(at: area, withIntermediateDirectories: false)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let photoA = repo.appendingPathComponent("Design/native/health-write-order/health-backup-photo-original-r1.jpg")
        let photoB = repo.appendingPathComponent("Design/native/health-write-order/health-backup-photo-changed-r1.jpg")
        var mealA = Meal(id: "legacy-replacement-a", type: .lunch, items: [])
        var mealB = Meal(id: "legacy-replacement-b", type: .snack, items: [])
        mealA.photoID = "one"; mealB.photoID = "two"
        var goals = HealthGoals(); goals.stepGoal = 6543; goals.weightKg = 88.5
        var replacementGoals = goals; replacementGoals.stepGoal = 321
        let snapshot = BackupSnapshot(profile: .default, goals: replacementGoals, habits: [], sleep: [], meals: [mealA, mealB], workouts: [], water: [], conversations: [], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        let water = try encoder.encode([HydrationLog(id: "legacy-healthy-water", date: Date(timeIntervalSince1970: 1_700_000_000), ml: 137)])
        let malformed = Data("{synthetic failed legacy transaction".utf8)
        var checks: [[String: Any]] = [], cases: [[String: Any]] = []
        var completed = false
        print("Retained legacy transaction root: " + area.path)
        defer {
            let report: [String: Any] = ["status": completed ? "PASS actual backend legacy recovery transactions" : "FAILED backend trial; inspect partial checks/raw log",
                                         "checks": checks, "retainedRoot": area.path, "cases": cases,
                                         "scope": "Isolated defaults/direct production selection+transaction+private catalog. Actual LocalStore.standard/write lock/UI review/native/signed/runtime origin routes unimplemented/unverified. Fixtures and suites retained through independent audit/exact backup; no allrace/allmetadata/allrawprior claim."]
            // Preserve partial fixture identities even when a check throws.
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output) }
            catch { print("Failed retaining transaction report: " + String(reflecting: error)) }
        }
        func check(_ name: String, _ condition: @autoclosure () throws -> Bool) throws {
            let passed = try condition(); checks.append(["name": name, "passed": passed])
            guard passed else { throw HealthLocalFiles.Failure.invalid }
        }
        func rejected(_ work: () throws -> Void) -> Bool { do { try work(); return false } catch { return true } }
        func currentValues(_ defaults: UserDefaults, keys: [String]) -> [String: [String: String]] {
            var result: [String: [String: String]] = [:]
            for key in keys {
                if let data = defaults.object(forKey: key) as? Data { result[key] = ["type": "Data", "base64": data.base64EncodedString()] }
                else if let string = defaults.object(forKey: key) as? String, let bytes = string.data(using: .utf16LittleEndian) {
                    result[key] = ["type": "StringUTF16LE", "base64": bytes.base64EncodedString()]
                }
            }
            return result
        }
        func files(_ root: URL) throws -> [String: String] {
            var result: [String: String] = [:]
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { throw HealthLocalFiles.Failure.invalid }
            for case let file as URL in iterator {
                let attributes = try fm.attributesOfItem(atPath: file.path)
                if attributes[.type] as? FileAttributeType == .typeRegular {
                    result[String(file.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: file).base64EncodedString()
                }
            }
            return result
        }
        func seed(_ root: URL, owner: UUID, missing: Set<HealthLocalFiles.Domain>) throws {
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            for (name, value) in try ConversationFiles.encoded([], activeID: nil) { try value.write(to: root.appendingPathComponent(name)) }
            try water.write(to: root.appendingPathComponent("water.json"))
            for domain in [HealthLocalFiles.Domain.meals, .workouts, .goals] where !missing.contains(domain) {
                let value = domain == .goals ? try encoder.encode(goals) : Data("[]".utf8)
                try value.write(to: root.appendingPathComponent(domain.rawValue + ".json"))
            }
            try HealthWriteJournal(owner: owner).encoded().write(to: root.appendingPathComponent(HealthWriteFiles.name))
        }
        func payload(_ selected: Set<HealthLocalFiles.Domain>, origins: [HealthLocalFiles.Domain: Origin]) throws -> HealthRecoverySelection.Payload {
            let raw = try HealthRecoverySelection.backup(snapshot, photos: ["one": photoA, "two": photoB], domains: selected, validPhoto: { url in
                guard let image = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
                return CGImageSourceCreateImageAtIndex(image, 0, nil) != nil
            })
            return try HealthRecoverySelection.bindingLegacyOrigins(origins, to: raw)
        }
        for domain in [HealthLocalFiles.Domain.meals, .workouts, .goals] {
          for string in [false, true] {
            let label = domain.rawValue + (string ? "-String" : "-Data"), root = area.appendingPathComponent(domain.rawValue + (string ? "-String" : "-Data"))
            let owner = UUID(), previous = root.appendingPathExtension("previous")
            try seed(root, owner: owner, missing: [domain]); try seed(previous, owner: owner, missing: [])
            let previousSelected = try Data(contentsOf: previous.appendingPathComponent(domain.rawValue + ".json"))
            let suiteName = "com.dbakp.lumen.synthetic.legacy-transaction." + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suiteName), let key = domain.legacyKey else { throw HealthLocalFiles.Failure.invalid }
            let caseIndex = cases.count
            cases.append(["label": label, "root": root.path, "suite": suiteName, "key": key, "phase": "fixture created before capture"])
            if string { defaults.set("synthetic failed older value e\u{301}", forKey: key) } else { defaults.set(malformed, forKey: key) }
            let legacy: @Sendable (String) throws -> Any? = { defaults.object(forKey: $0) }
            guard let origin = try Origin.capture(domain, in: root, legacy: legacy) else { throw HealthLocalFiles.Failure.invalid }
            let bound = try payload([domain], origins: [domain: origin])
            let before = try files(root)
            let transaction = try HealthRecoverySelection.prepare(bound, into: root, owner: owner, legacy: legacy)
            try transaction.commit()
            try check(label + " legacy key unchanged after actual installation", Origin.capture(domain, in: root, legacy: legacy) == nil)
            if string { try check(label + " exact actual String key retained", (defaults.object(forKey: key) as? String)?.utf16.elementsEqual("synthetic failed older value e\u{301}".utf16) == true) }
            else { try check(label + " exact actual Data key retained", defaults.object(forKey: key) as? Data == malformed) }
            try check(label + " healthy water bytes preserved", Data(contentsOf: root.appendingPathComponent("water.json")) == water)
            if domain != .goals { try check(label + " unselected healthy goals preserved", Data(contentsOf: root.appendingPathComponent("goals.json")) == encoder.encode(goals)) }
            let installed = try HealthLocalFiles.readRegularData(root.appendingPathComponent(domain.rawValue + ".json"), limit: HealthLocalFiles.limit)
            try HealthLocalFiles.validateCurrentData(installed, domain: domain)
            let previews = try HealthRecoveryCopies.previews(in: root)
            guard let copy = previews.first(where: { item in item.complete && item.domains.contains { $0.domain == domain && $0.state == .unavailable && $0.digest != nil } }) else { throw HealthLocalFiles.Failure.invalid }
            try check(label + " failed legacy catalog unavailable/count unknown", copy.domains.first { $0.domain == domain }?.recordCount == nil)
            try check(label + " failed legacy cannot export records", rejected { _ = try HealthRecoverySelection.records(copy, domain: domain, in: root) })
            let privateRoot = root.appendingPathComponent(HealthRecoveryCopies.name)
            let envelopeFile = privateRoot.appendingPathComponent(copy.id).appendingPathComponent("legacy-origin-" + domain.rawValue + ".json")
            let exactEnvelope = try Data(contentsOf: envelopeFile)
            try check(label + " private typed raw exactly retained", Origin.Value.decode(exactEnvelope) == origin.value)
            let names = try fm.contentsOfDirectory(at: privateRoot, includingPropertiesForKeys: nil)
            try check(label + " selected prior raw kept privately", names.contains { (try? Data(contentsOf: $0.appendingPathComponent(domain.rawValue + ".json"))) == previousSelected })
            let receipts = try fm.contentsOfDirectory(at: root.appendingPathComponent(".health-recovery-history"), includingPropertiesForKeys: nil)
            try check(label + " actual receipt recorded once", receipts.count == 1)
            let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: receipts[0])) as! [String: Any]
            try check(label + " receipt exact selected domain", receipt["domains"] as? [String] == [domain.rawValue])
            if domain == .meals {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let meals = try decoder.decode([Meal].self, from: installed)
                let ids = Set(meals.compactMap(\.photoID))
                try check(label + " two fresh photos and distinct identifiers installed", ids.count == 2 && ids.isDisjoint(with: ["one", "two"]))
                let actual = try ids.map { try Data(contentsOf: root.appendingPathComponent("photos/" + $0 + ".jpg")) }
                try check(label + " both exact photo byte payloads installed", Set(actual) == Set([try Data(contentsOf: photoA), try Data(contentsOf: photoB)]))
            }
            let journal = try HealthWriteFiles.read(from: root)
            try check(label + " same device owner/no replay events", journal.owner == owner && journal.events.isEmpty)
            // A later normal write must carry version2 provenance byte-for-byte.
            try ConversationFiles.prepareLinkedChange(["synthetic-linked-marker.json": Data("true".utf8)], into: root).commit()
            try check(label + " version2 copy carried through linked write", Data(contentsOf: envelopeFile) == exactEnvelope)
            try check(label + " original review remains verifiable after carry", { try HealthRecoveryCopies.verify(copy, in: root); return true }())
            // Corruption/dual representation/extra provenance must never become a readable fallback.
            let copyDirectory = envelopeFile.deletingLastPathComponent()
            try Data("{}".utf8).write(to: envelopeFile, options: .atomic)
            try check(label + " corrupt envelope incomplete", HealthRecoveryCopies.previews(in: root).first { $0.id == copy.id }?.complete == false)
            try exactEnvelope.write(to: envelopeFile, options: .atomic)
            let fabricated = copyDirectory.appendingPathComponent(domain.rawValue + ".json")
            try installed.write(to: fabricated)
            try check(label + " dual raw/provenance authority incomplete", HealthRecoveryCopies.previews(in: root).first { $0.id == copy.id }?.complete == false)
            try fm.removeItem(at: fabricated)
            let extra = copyDirectory.appendingPathComponent("legacy-origin-unexpected.json")
            try Data("{}".utf8).write(to: extra)
            try check(label + " unexpected provenance file incomplete", HealthRecoveryCopies.previews(in: root).first { $0.id == copy.id }?.complete == false)
            try fm.removeItem(at: extra)
            cases[caseIndex] = ["label": label, "root": root.path, "suite": suiteName, "key": key,
                          "originEnvelope": exactEnvelope.base64EncodedString(), "before": before, "after": try files(root),
                          "currentDefaults": currentValues(defaults, keys: [key]),
                          "synchronized": defaults.synchronize()]
          }
        }
        do {
            let root = area.appendingPathComponent("mixed-three-domains"), owner = UUID()
            try seed(root, owner: owner, missing: [.meals, .goals])
            try seed(root.appendingPathExtension("previous"), owner: owner, missing: [])
            try malformed.write(to: root.appendingPathComponent("workouts.json"))
            let suite = "com.dbakp.lumen.synthetic.legacy-transaction." + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suite) else { throw HealthLocalFiles.Failure.invalid }
            let keys = [HealthLocalFiles.Domain.meals.legacyKey!, HealthLocalFiles.Domain.goals.legacyKey!]
            let index = cases.count
            cases.append(["label": "mixed-three-domains", "root": root.path, "suite": suite, "keys": keys, "phase": "fixture created"])
            defaults.set(malformed, forKey: keys[0]); defaults.set("synthetic failed mixed goals", forKey: keys[1])
            let legacy: @Sendable (String) throws -> Any? = { defaults.object(forKey: $0) }
            guard let mealOrigin = try Origin.capture(.meals, in: root, legacy: legacy),
                  let goalOrigin = try Origin.capture(.goals, in: root, legacy: legacy) else { throw HealthLocalFiles.Failure.invalid }
            let before = try files(root), prior = try files(root.appendingPathExtension("previous"))
            let unbound = try payload([.meals, .workouts, .goals], origins: [:])
            try check("mixed absent targets require explicit origin observations", rejected { _ = try HealthRecoverySelection.prepare(unbound, into: root, owner: owner, legacy: legacy) })
            try check("mixed unsupported preparation preserves current/prior bytes", files(root) == before && files(root.appendingPathExtension("previous")) == prior)
            try check("wrong domain cannot borrow another origin token", rejected { _ = try HealthRecoverySelection.bindingLegacyOrigins([.workouts: mealOrigin], to: unbound) })
            let selected = try HealthRecoverySelection.bindingLegacyOrigins([.meals: mealOrigin, .goals: goalOrigin], to: unbound)
            try HealthRecoverySelection.prepare(selected, into: root, owner: owner, legacy: legacy).commit()
            let choices = try HealthRecoveryCopies.previews(in: root)
            guard let mixed = choices.first(where: { $0.complete && $0.domains.filter { $0.state == .unavailable }.count == 3 }) else { throw HealthLocalFiles.Failure.invalid }
            let directory = root.appendingPathComponent(HealthRecoveryCopies.name).appendingPathComponent(mixed.id)
            try check("mixed two legacy values and failed regular file retained", Data(contentsOf: directory.appendingPathComponent("workouts.json")) == malformed)
            try check("mixed Data provenance exact", Origin.Value.decode(Data(contentsOf: directory.appendingPathComponent("legacy-origin-meals.json"))) == mealOrigin.value)
            try check("mixed String provenance exact", Origin.Value.decode(Data(contentsOf: directory.appendingPathComponent("legacy-origin-goals.json"))) == goalOrigin.value)
            try check("mixed healthy water and defaults unchanged", Data(contentsOf: root.appendingPathComponent("water.json")) == water && defaults.object(forKey: keys[0]) as? Data == malformed && defaults.object(forKey: keys[1]) as? String == "synthetic failed mixed goals")
            cases[index] = ["label": "mixed-three-domains", "root": root.path, "suite": suite, "keys": keys,
                            "before": before, "after": try files(root), "currentDefaults": currentValues(defaults, keys: keys),
                            "synchronized": defaults.synchronize()]
        }
        // Deterministic review/prepare/final-boundary rejections use actual keys.
        for fault in ["before-prepare", "after-prepare", "stage-envelope", "stage-manifest", "cancel", "operational"] {
            let root = area.appendingPathComponent("reject-" + fault), owner = UUID()
            try seed(root, owner: owner, missing: [.meals])
            let suite = "com.dbakp.lumen.synthetic.legacy-transaction." + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suite) else { throw HealthLocalFiles.Failure.invalid }
            let key = HealthLocalFiles.Domain.meals.legacyKey!; defaults.set(malformed, forKey: key)
            let caseIndex = cases.count
            cases.append(["label": "reject-" + fault, "root": root.path, "suite": suite, "key": key, "phase": "fixture created before capture"])
            final class Reader: @unchecked Sendable {
                let defaults: UserDefaults; var operational = false
                init(_ defaults: UserDefaults) { self.defaults = defaults }
                func read(_ key: String) throws -> Any? { if operational { throw NSError(domain: NSPOSIXErrorDomain, code: 13) }; return defaults.object(forKey: key) }
            }
            let reader = Reader(defaults), legacy: @Sendable (String) throws -> Any? = { try reader.read($0) }
            guard let origin = try Origin.capture(.meals, in: root, legacy: legacy) else { throw HealthLocalFiles.Failure.invalid }
            let bound = try payload([.meals], origins: [.meals: origin]), control = BackupOperationControl()
            let before = try files(root)
            if fault == "before-prepare" {
                defaults.set(Data("{changed before preparation".utf8), forKey: key)
                try check(fault + " rejects without live replacement", rejected { _ = try HealthRecoverySelection.prepare(bound, into: root, owner: owner, legacy: legacy) })
            } else {
                let transaction = try HealthRecoverySelection.prepare(bound, into: root, owner: owner, control: control, legacy: legacy)
                if fault == "after-prepare" { defaults.set(Data("{changed after preparation".utf8), forKey: key) }
                if fault == "operational" { reader.operational = true }
                if fault == "cancel" { control.cancel() }
                if fault.hasPrefix("stage-") {
                    let stages = try fm.contentsOfDirectory(at: area, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(root.lastPathComponent + ".restore-") }
                    guard stages.count == 1 else { throw HealthLocalFiles.Failure.invalid }
                    let copies = try fm.contentsOfDirectory(at: stages[0].appendingPathComponent(HealthRecoveryCopies.name), includingPropertiesForKeys: nil)
                    guard let copy = copies.first else { throw HealthLocalFiles.Failure.invalid }
                    let name = fault == "stage-envelope" ? "legacy-origin-meals.json" : "manifest.json"
                    try Data("{}".utf8).write(to: copy.appendingPathComponent(name), options: .atomic)
                }
                try check(fault + " actual commit rejects", rejected { try transaction.commit(control: control) })
                transaction.discard()
            }
            try check(fault + " current bytes/no receipt unchanged", files(root) == before)
            cases[caseIndex] = ["label": "reject-" + fault, "root": root.path, "suite": suite, "key": key,
                               "before": before, "after": try files(root), "currentDefaults": currentValues(defaults, keys: [key]), "synchronized": defaults.synchronize()]
        }
        completed = true
        print("PASS: \(checks.count) failed-legacy backend transaction checks; native product integration pending")
    }
}
