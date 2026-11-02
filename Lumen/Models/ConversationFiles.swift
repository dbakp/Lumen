import Foundation

/// Read and stage the existing archive/mirror formats without treating a
/// deliberately empty archive or an unreadable file as missing history.
enum ConversationFiles {
    struct Selection: Codable, Sendable { let activeID: String? }
    struct Loaded {
        let conversations: [HealthConversation]
        let needsMigration: Bool
        let selection: Selection?
    }
    enum Failure: Error { case missingSelection, invalidFile }

    /// Shared preparation for linked local writes, including changes to other
    /// domains that preserve the conversation files in the staged directory.
    static func prepareLinkedChange(_ files: [String: Data], into directory: URL) throws -> BackupFileTransaction {
        try protectPreviousCopy(in: directory)
        return try BackupFileTransaction.prepare(files, photoFiles: [:], into: directory, preserveByLink: true)
    }

    static func prepareRestore(_ files: [String: Data], photoFiles: [String: URL], into directory: URL,
                               control: BackupOperationControl) throws -> BackupFileTransaction {
        try protectPreviousCopy(in: directory)
        return try BackupFileTransaction.prepare(files, photoFiles: photoFiles, into: directory, control: control)
    }

    private static func protectPreviousCopy(in directory: URL) throws {
        // Generic preparation retires .previous before staging. Only let it
        // discard that recovery copy after the current history can be read.
        // Attribute errors must propagate rather than masquerade as absence.
        let previous = directory.appendingPathExtension("previous")
        var hasPrevious = true
        do { _ = try FileManager.default.attributesOfItem(atPath: previous.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { hasPrevious = false }
        if hasPrevious { _ = try load(from: directory) }
    }

    static func load(from directory: URL, legacyDefaults: () throws -> [ChatMessage] = { [] }) throws -> Loaded {
        // Recover an interrupted directory swap before deciding files are absent.
        // Unlike transaction retirement this never deletes a surviving prior copy.
        try BackupFiles.openDirectory(directory, createIfMissing: false)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try readIfMissing(directory.appendingPathComponent("conversations.json")) {
            let conversations = try decoder.decode([HealthConversation].self, from: data)
            guard Set(conversations.map(\.id)).count == conversations.count,
                  conversations.allSatisfy({ Set($0.messages.map(\.id)).count == $0.messages.count }) else { throw Failure.invalidFile }
            let selection = try readIfMissing(directory.appendingPathComponent("conversation-selection.json")).map { try decoder.decode(Selection.self, from: $0) }
            if let id = selection?.activeID, !conversations.contains(where: { $0.id == id }) { throw Failure.missingSelection }
            return Loaded(conversations: conversations, needsMigration: false, selection: selection)
        }
        let legacy: [ChatMessage]
        if let data = try readIfMissing(directory.appendingPathComponent("chat.json")) {
            legacy = try decoder.decode([ChatMessage].self, from: data)
        } else { legacy = try legacyDefaults() }
        return Loaded(conversations: ConversationArchive.migrate(legacy: legacy, existing: []), needsMigration: true, selection: nil)
    }

    static func encoded(_ conversations: [HealthConversation], activeID: String?) throws -> [String: Data] {
        let messages: [ChatMessage]
        if let activeID {
            guard let selected = conversations.first(where: { $0.id == activeID }) else { throw Failure.missingSelection }
            messages = selected.messages
        } else { messages = [] }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return ["conversations.json": try encoder.encode(conversations), "chat.json": try encoder.encode(messages),
                "conversation-selection.json": try encoder.encode(Selection(activeID: activeID))]
    }

    private static func readIfMissing(_ url: URL) throws -> Data? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.invalidFile }
        // Once found, any read error (including disappearance) is a failed load,
        // not permission to migrate a potentially stale compatibility mirror.
        return try Data(contentsOf: url)
    }
}
