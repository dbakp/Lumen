import Foundation
import CryptoKit

/// Reads Lumen's historical plain JSON exports without treating them as backups.
/// Missing domains remain absent; present malformed data never becomes a default.
enum ReadableExport {
    static let maxBytes = BackupArchive.maxBytes
    /// Keep every saved character; prefer a nearby paragraph or word boundary.
    /// A single unbroken token can still cross the bounded reader pages.
    static func reviewSections(_ text: String, length: Int = 2000) -> [Substring] {
        precondition(length > 0)
        var result: [Substring] = [], start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
            var cut = end
            if end < text.endIndex {
                let lower = text.index(start, offsetBy: max(0, length - min(300, length / 2)))
                let tail = text[lower..<end]
                if let paragraph = tail.range(of: "\n\n", options: .backwards) { cut = paragraph.upperBound }
                else if let space = tail.lastIndex(where: \.isWhitespace) { cut = text.index(after: space) }
            }
            result.append(text[start..<cut]); start = cut
        }
        return result.isEmpty ? [text[...]] : result
    }
    enum Domain: String, CaseIterable, Sendable, Identifiable {
        case sleep, meals, workouts, water, conversations, symptoms
        case checkIns = "check-ins", documents, importedDays = "imported-days", imports = "import-receipts"
        case profile, goals, habits, personalContext = "personal-context"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sleep: return "Sleep entries"
            case .meals: return "Meals"
            case .workouts: return "Workouts"
            case .water: return "Water entries"
            case .conversations: return "Conversations"
            case .symptoms: return "Symptom entries"
            case .checkIns: return "Check-ins"
            case .documents: return "Library documents"
            case .importedDays: return "Imported health days"
            case .imports: return "Import receipts"
            case .profile: return "Name & sleep settings"
            case .goals: return "Body & activity goals"
            case .habits: return "Sleep routines"
            case .personalContext: return "Personal notes"
            }
        }
        var preference: BackupPreferenceSelection {
            switch self {
            case .profile: return .profile
            case .goals: return .goals
            case .habits: return .habits
            case .personalContext: return .personalContext
            default: return []
            }
        }
    }
    struct Conversion: Sendable {
        let snapshot: BackupSnapshot
        let exportedAt: Date
        let sha256: String
        let present: Set<Domain>
        let omittedKeys: [String]
        let missingPhotos: Int
        let mirroredMessages: Int
        let recoveredChat: Bool
        let omittedSampleMeals: Int
        let omittedSampleWorkouts: Int
        func count(_ domain: Domain) -> Int {
            switch domain {
            case .sleep: return snapshot.sleep.count
            case .meals: return snapshot.meals.count
            case .workouts: return snapshot.workouts.count
            case .water: return snapshot.water.count
            case .conversations: return snapshot.conversations.count
            case .symptoms: return snapshot.symptoms.count
            case .checkIns: return snapshot.checkIns.count
            case .documents: return snapshot.documents.count
            case .importedDays: return snapshot.importedDays.count
            case .imports: return snapshot.imports.count
            case .habits: return snapshot.habits.count
            default: return present.contains(domain) ? 1 : 0
            }
        }
        var defaultSelection: Set<Domain> { Set(present.filter { $0.preference.isEmpty && count($0) > 0 }) }
        func selected(_ domains: Set<Domain>) throws -> (BackupSnapshot, BackupPreferenceSelection) {
            guard domains.isSubset(of: present) else { throw Failure.invalidSelection }
            var value = snapshot
            if !domains.contains(.sleep) { value.sleep = [] }
            if !domains.contains(.meals) { value.meals = [] }
            if !domains.contains(.workouts) { value.workouts = [] }
            if !domains.contains(.water) { value.water = [] }
            if !domains.contains(.conversations) { value.conversations = [] }
            if !domains.contains(.symptoms) { value.symptoms = [] }
            if !domains.contains(.checkIns) { value.checkIns = [] }
            if !domains.contains(.documents) { value.documents = [] }
            if !domains.contains(.importedDays) { value.importedDays = [] }
            if !domains.contains(.imports) { value.imports = [] }
            return (value, domains.reduce(into: BackupPreferenceSelection()) { $0.formUnion($1.preference) })
        }
    }
    enum Failure: LocalizedError {
        case format, version, tooLarge, malformed(String), ambiguous, invalidSelection, empty, destination, recordsChanged
        var errorDescription: String? {
            switch self {
            case .format: return "Choose a readable Lumen JSON file made with Export my data. Use Backup & restore for backup files."
            case .version: return "This readable export needs a newer version of Lumen. Keep the file and update the app."
            case .tooLarge: return "Readable exports support up to 100 MB. Use an encrypted backup for a larger transfer."
            case .malformed(let domain): return "The \(domain) section couldn't be converted. No data was added. Keep the original file and check its contents."
            case .ambiguous: return "This file contains conflicting or repeated fields. No data was added. Keep the original and choose an unedited export."
            case .invalidSelection: return "A selected section isn't available in this file. Review your selection again."
            case .empty: return "No saved data sections were found in this export. Choose another Lumen export."
            case .recordsChanged: return "Saved data changed while this export was being created. Try again to include the latest data."
            case .destination: return "The export file couldn't be saved. Try creating it again."
            }
        }
    }
    private static let controlKey = CodingUserInfoKey(rawValue: "readable-control")!
    private static let domainKey = CodingUserInfoKey(rawValue: "readable-domain")!
    private struct Records<Value: Decodable>: Decodable {
        let values: [Value]
        init(from decoder: Decoder) throws {
            let control = decoder.userInfo[ReadableExport.controlKey] as? BackupOperationControl
            let domain = decoder.userInfo[ReadableExport.domainKey] as? String
            var container = try decoder.unkeyedContainer(), values: [Value] = []
            while !container.isAtEnd {
                try control?.checkCancellation()
                guard values.count < 200_000 else { throw Failure.malformed(domain ?? "saved data") }
                values.append(try container.decode(Value.self))
                if values.count % 128 == 0 { control?.update(.reading, completed: values.count, total: container.count ?? 0, detail: domain) }
            }
            self.values = values
        }
    }
    static func decoder(control: BackupOperationControl? = nil) -> JSONDecoder {
        let decoder = JSONDecoder()
        let standard = ISO8601DateFormatter(), fractional = ISO8601DateFormatter()
        fractional.formatOptions.insert(.withFractionalSeconds)
        decoder.userInfo[controlKey] = control
        decoder.dateDecodingStrategy = .custom { decoder in
            try control?.checkCancellation()
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = standard.date(from: text) ?? fractional.date(from: text) else { throw Failure.format }
            return date
        }
        return decoder
    }
    static func read(_ data: Data, control: BackupOperationControl = .init()) throws -> Conversion {
        try control.checkCancellation()
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        guard !data.isEmpty else { throw Failure.format }
        do { try JSONFieldAudit.check(data, control: control) }
        catch is CancellationError { throw CancellationError() }
        catch let error as Failure { throw error }
        catch { throw Failure.format }
        let object: [String: Any]
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root.count <= 64 else { throw Failure.format }
            object = root
        } catch let error as Failure { throw error } catch { throw Failure.format }
        struct Header: Decodable { let app: String; let exportedAt: Date; let readableVersion: Int? }
        let header: Header
        guard let app = object["app"] as? String, app.utf8.count <= 64,
              let date = object["exportedAt"] as? String, date.utf8.count <= 100,
              !(object["readableVersion"] is NSNull) else { throw Failure.format }
        let metadata = object.filter { ["app", "exportedAt", "readableVersion"].contains($0.key) }
        do { header = try decoder(control: control).decode(Header.self, from: JSONSerialization.data(withJSONObject: metadata)) }
        catch is CancellationError { throw CancellationError() }
        catch { throw Failure.format }
        guard header.app == "Lumen", header.exportedAt.timeIntervalSince1970.isFinite else { throw Failure.format }
        guard header.readableVersion == nil || header.readableVersion == 1 else { throw Failure.version }
        let total = object.keys.filter { Domain(rawValue: $0) != nil || $0 == "chat" }.count
        var present = Set<Domain>(), completed = 0
        func decode<T: Decodable>(_ key: String, _ type: T.Type) throws -> T? {
            try control.checkCancellation()
            guard let raw = object[key] else { return nil }
            do {
                let bytes = try JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed, .sortedKeys])
                let decoder = decoder(control: control)
                decoder.userInfo[domainKey] = Domain(rawValue: key)?.title ?? "Active conversation"
                let result = try decoder.decode(type, from: bytes)
                completed += 1; control.update(.reading, completed: completed, total: total, bytes: Int64(data.count), detail: "Sections")
                if let domain = Domain(rawValue: key) { present.insert(domain) }
                return result
            } catch is CancellationError { throw CancellationError() }
            catch { throw Failure.malformed(Domain(rawValue: key)?.title ?? "active conversation") }
        }
        var snapshot = BackupSnapshot(profile: try decode("profile", UserProfile.self) ?? .default,
                                      goals: try decode("goals", HealthGoals.self) ?? .init(),
                                      habits: try decode("habits", Records<SleepHabit>.self)?.values ?? [],
                                      sleep: try decode("sleep", Records<SleepEpisode>.self)?.values ?? [],
                                      meals: try decode("meals", Records<Meal>.self)?.values ?? [],
                                      workouts: try decode("workouts", Records<Workout>.self)?.values ?? [],
                                      water: try decode("water", Records<HydrationLog>.self)?.values ?? [],
                                      conversations: try decode("conversations", Records<HealthConversation>.self)?.values ?? [],
                                      symptoms: try decode("symptoms", Records<SymptomEntry>.self)?.values ?? [],
                                      checkIns: try decode("check-ins", Records<WellbeingCheckIn>.self)?.values ?? [],
                                      documents: try decode("documents", Records<HealthDocument>.self)?.values ?? [],
                                      importedDays: try decode("imported-days", Records<ImportedHealthDay>.self)?.values ?? [],
                                      imports: try decode("import-receipts", Records<ImportReceipt>.self)?.values ?? [],
                                      personalContext: try decode("personal-context", PersonalHealthContext.self) ?? .init(), photos: [:])
        let chat = try decode("chat", Records<ChatMessage>.self)?.values ?? []
        guard Set(chat.map(\.id)).count == chat.count else { throw Failure.malformed("active conversation") }
        let encoder = BackupArchive.encoder()
        var archived: [String: Data] = [:]
        for conversation in snapshot.conversations {
            for message in conversation.messages {
                try control.checkCancellation()
                let bytes = try encoder.encode(message)
                if let prior = archived[message.id], prior != bytes { throw Failure.ambiguous }
                archived[message.id] = bytes
            }
        }
        var mirrored = 0
        for message in chat {
            try control.checkCancellation()
            if let stored = archived[message.id] {
                guard stored == (try encoder.encode(message)) else { throw Failure.ambiguous }
                mirrored += 1
            }
        }
        let recovered = chat.count > mirrored
        if recovered {
            let bytes = try encoder.encode(chat)
            let id = "readable-chat-" + BackupArchive.digest(bytes)
            guard !snapshot.conversations.contains(where: { $0.id == id }) else { throw Failure.ambiguous }
            snapshot.conversations.append(HealthConversation(id: id, title: snapshot.conversations.isEmpty ? ConversationArchive.suggestedTitle(chat) : "Recovered active conversation",
                                                            createdAt: chat.first?.date ?? header.exportedAt, updatedAt: chat.last?.date ?? header.exportedAt, messages: chat))
            present.insert(.conversations)
        }
        let sampleMeals = snapshot.meals.filter { $0.source == .sample }.count
        snapshot.meals.removeAll { $0.source == .sample }
        let sampleWorkouts = snapshot.workouts.filter { $0.source == .sample }.count
        snapshot.workouts.removeAll { $0.source == .sample }
        var missingPhotos = 0
        for index in snapshot.meals.indices {
            try control.checkCancellation()
            if let id = snapshot.meals[index].photoID {
                guard BackupArchive.safePhotoID(id) else { throw Failure.malformed("Meals") }
                missingPhotos += 1; snapshot.meals[index].photoID = nil
            }
        }
        guard !present.isEmpty else { throw Failure.empty }
        if present.contains(.profile) {
            guard snapshot.profile.wakeGoal.hour.map({ (0...23).contains($0) }) ?? true,
                  snapshot.profile.wakeGoal.minute.map({ (0...59).contains($0) }) ?? true else { throw Failure.malformed(Domain.profile.title) }
        }
        do { try BackupArchive.validate(snapshot) } catch { throw Failure.malformed("saved data") }
        try control.checkCancellation()
        let known = Set(Domain.allCases.map(\.rawValue)).union(["chat", "app", "exportedAt", "readableVersion"])
        return Conversion(snapshot: snapshot, exportedAt: header.exportedAt, sha256: BackupArchive.digest(data), present: present,
                          omittedKeys: object.keys.filter { !known.contains($0) }.sorted(), missingPhotos: missingPhotos,
                          mirroredMessages: mirrored, recoveredChat: recovered, omittedSampleMeals: sampleMeals, omittedSampleWorkouts: sampleWorkouts)
    }
    /// Streams typed records to plain JSON; no photo bytes or runtime cache enter it.
    static func write(_ snapshot: BackupSnapshot, reminders: ReminderPreferences? = nil, to destination: URL, now: Date = Date(), control: BackupOperationControl = .init()) throws {
        try control.checkCancellation()
        guard snapshot.photos.isEmpty, now.timeIntervalSince1970.isFinite else { throw Failure.format }
        do { try BackupArchive.validate(snapshot, availablePhotoIDs: Set(snapshot.meals.compactMap(\.photoID))) }
        catch { throw Failure.malformed("saved data on this iPhone") }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw Failure.destination }
        let partial = destination.deletingLastPathComponent().appendingPathComponent("readable-" + UUID().uuidString + ".partial")
        try Data().write(to: partial, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        defer { try? fm.removeItem(at: partial) }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: partial.path)
        let output = try FileHandle(forWritingTo: partial); defer { try? output.close() }
        var written = 0, completed = 0
        let total = snapshot.recordCount + snapshot.habits.count + 3 + (reminders == nil ? 0 : 1), encoder = BackupArchive.encoder()
        func append(_ bytes: Data) throws {
            try control.checkCancellation()
            guard bytes.count <= maxBytes - written else { throw Failure.tooLarge }
            try output.write(contentsOf: bytes); written += bytes.count
        }
        func raw(_ value: String) throws { try append(Data(value.utf8)) }
        func value<T: Encodable>(_ value: T) throws {
            let data = try encoder.encode(value)
            guard data.count <= BackupPackage.maxRecordBytes else { throw Failure.tooLarge }
            try append(data); completed += 1; control.update(.writing, completed: completed, total: total, bytes: Int64(written))
        }
        func field<T: Encodable>(_ name: String, _ item: T) throws { try raw(",\"\(name)\":"); try value(item) }
        func array<T: Encodable>(_ name: String, _ items: [T]) throws {
            try raw(",\"\(name)\":[")
            for (index, item) in items.enumerated() { if index > 0 { try raw(",") }; try value(item) }
            try raw("]")
        }
        try raw("{\"app\":\"Lumen\",\"readableVersion\":1,\"exportedAt\":")
        try append(encoder.encode(ISO8601DateFormatter().string(from: now)))
        try field("profile", snapshot.profile); try field("goals", snapshot.goals); try field("personal-context", snapshot.personalContext)
        try array("habits", snapshot.habits); try array("sleep", snapshot.sleep); try array("meals", snapshot.meals)
        try array("workouts", snapshot.workouts); try array("water", snapshot.water); try array("conversations", snapshot.conversations)
        try array("symptoms", snapshot.symptoms); try array("check-ins", snapshot.checkIns); try array("documents", snapshot.documents)
        try array("imported-days", snapshot.importedDays); try array("import-receipts", snapshot.imports)
        if let reminders { try field("reminder-preferences", reminders) }
        try raw("}"); try output.close(); try control.checkCancellation()
        try fm.moveItem(at: partial, to: destination)
    }
}
