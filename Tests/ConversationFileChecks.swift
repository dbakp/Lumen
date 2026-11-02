import Foundation

enum ConversationFileChecks {
    static func run() throws {
        func check(_ value: Bool, _ label: String) { precondition(value, label); print("PASS: " + label) }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Lumen-conversation-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let legacy = [ChatMessage(role: .user, text: "Synthetic legacy question")]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let archive = root.appendingPathComponent("conversations.json"), mirror = root.appendingPathComponent("chat.json")
        try encoder.encode(legacy).write(to: mirror)
        let migrated = try ConversationFiles.load(from: root)
        check(migrated.needsMigration && migrated.conversations.first?.messages.first?.id == legacy.first?.id,
              "legacy-only conversation loading preserves original message identity and requires a checked migration")
        check(!fm.fileExists(atPath: archive.path), "reading legacy chat cannot silently write or claim a saved archive")
        try Data("[]".utf8).write(to: archive)
        let empty = try ConversationFiles.load(from: root)
        check(empty.conversations.isEmpty && !empty.needsMigration, "an existing empty archive cannot resurrect old legacy chat")
        let malformed = Data("{broken".utf8); try malformed.write(to: archive)
        do { _ = try ConversationFiles.load(from: root); preconditionFailure("corrupt archive accepted") }
        catch { check(try Data(contentsOf: archive) == malformed, "corrupt archive read throws without overwriting bytes or using legacy fallback") }
        try fm.removeItem(at: archive)
        try malformed.write(to: mirror)
        do { _ = try ConversationFiles.load(from: root); preconditionFailure("corrupt legacy accepted") }
        catch { check(try Data(contentsOf: mirror) == malformed, "malformed legacy chat is preserved for recovery rather than replaced by defaults") }
        let conversation = migrated.conversations[0]
        let files = try ConversationFiles.encoded([conversation], activeID: conversation.id)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        check(try decoder.decode([ChatMessage].self, from: files["chat.json"]!).first?.id == legacy.first?.id,
              "paired conversation encoding mirrors the selected archive messages with existing date and ID formats")
        do { _ = try ConversationFiles.encoded([conversation], activeID: "removed"); preconditionFailure("missing selection accepted") }
        catch ConversationFiles.Failure.missingSelection { check(true, "paired conversation encoding rejects a selection absent from its saved archive") }
        let deleted = try ConversationFiles.encoded([], activeID: nil)
        let stage = try BackupFileTransaction.prepare(deleted, photoFiles: [:], into: root, preserveByLink: true)
        try stage.commit()
        let reloaded = try ConversationFiles.load(from: root)
        let remainingMirror = try decoder.decode([ChatMessage].self, from: Data(contentsOf: mirror))
        check(reloaded.conversations.isEmpty && !reloaded.needsMigration && remainingMirror.isEmpty,
              "actual paired file transaction and relaunch reader keep final deletion empty in both archive and legacy mirror")
        check(reloaded.selection != nil && reloaded.selection?.activeID == nil,
              "saved unsent selection is explicit rather than mistaken for old metadata requiring a newest-chat fallback")

        let interrupted = root.appendingPathComponent("interrupted", isDirectory: true)
        let previous = interrupted.appendingPathExtension("previous")
        try fm.createDirectory(at: previous, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: previous.appendingPathComponent(name)) }
        let recovered = try ConversationFiles.load(from: interrupted)
        check(recovered.conversations.first?.id == conversation.id && !recovered.needsMigration
              && !fm.fileExists(atPath: previous.path),
              "startup restores a missing current directory from the interrupted swap before considering legacy defaults")
        check(recovered.selection?.activeID == conversation.id,
              "interrupted directory recovery retains selection alongside its exact archive and compatibility mirror")

        try fm.createDirectory(at: previous, withIntermediateDirectories: true)
        try files["conversations.json"]!.write(to: previous.appendingPathComponent("conversations.json"))
        let interruptedArchive = interrupted.appendingPathComponent("conversations.json")
        try malformed.write(to: interruptedArchive)
        do { _ = try ConversationFiles.load(from: interrupted); preconditionFailure("corrupt current directory accepted") }
        catch {
            check(try Data(contentsOf: previous.appendingPathComponent("conversations.json")) == files["conversations.json"]!
                  && Data(contentsOf: interruptedArchive) == malformed,
                  "a corrupt current archive leaves both exact current bytes and the surviving previous archive available")
        }
        try BackupFiles.openDirectory(interrupted, createIfMissing: true)
        check(fm.fileExists(atPath: previous.path), "opening an existing storage folder never retires its previous copy")

        let badPreviousRoot = root.appendingPathComponent("bad-previous", isDirectory: true)
        let badPrevious = badPreviousRoot.appendingPathExtension("previous")
        try malformed.write(to: badPrevious)
        do { try BackupFiles.openDirectory(badPreviousRoot, createIfMissing: true); preconditionFailure("invalid previous accepted") }
        catch {
            let original = try Data(contentsOf: badPrevious)
            check(!fm.fileExists(atPath: badPreviousRoot.path) && original == malformed,
                  "failed recovery from a non-directory previous path cannot initialize an empty replacement")
        }

        let link = root.appendingPathComponent("linked-root")
        try fm.createSymbolicLink(at: link, withDestinationURL: interrupted)
        do { _ = try ConversationFiles.load(from: link); preconditionFailure("linked current accepted") }
        catch { check(try Data(contentsOf: interruptedArchive) == malformed, "startup refuses a symbolic-link storage root without changing its target") }
        let linkedPreviousRoot = root.appendingPathComponent("linked-previous")
        try fm.createSymbolicLink(at: linkedPreviousRoot.appendingPathExtension("previous"), withDestinationURL: interrupted)
        do { try BackupFiles.openDirectory(linkedPreviousRoot, createIfMissing: true); preconditionFailure("linked previous accepted") }
        catch { check(!fm.fileExists(atPath: linkedPreviousRoot.path), "symbolic-link previous storage cannot be moved or treated as fresh installation") }

        let linkedArchiveRoot = root.appendingPathComponent("linked-archive", isDirectory: true)
        try fm.createDirectory(at: linkedArchiveRoot, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linkedArchiveRoot.appendingPathComponent("conversations.json"), withDestinationURL: archive)
        do { _ = try ConversationFiles.load(from: linkedArchiveRoot); preconditionFailure("linked archive accepted") }
        catch ConversationFiles.Failure.invalidFile {
            check(try Data(contentsOf: archive) == deleted["conversations.json"]!, "conversation loading refuses a symbolic-link archive and preserves target bytes")
        }

        let firstInstall = root.appendingPathComponent("first-install", isDirectory: true)
        var legacyCalls = 0
        let fresh = try ConversationFiles.load(from: firstInstall, legacyDefaults: { legacyCalls += 1; return [] })
        check(fresh.needsMigration && fresh.conversations.isEmpty && legacyCalls == 1 && !fm.fileExists(atPath: firstInstall.path),
              "a truly absent installation can read legacy defaults without creating storage or claiming a completed save")
        try BackupFiles.openDirectory(firstInstall, createIfMissing: true)
        check(try fm.attributesOfItem(atPath: firstInstall.path)[.type] as? FileAttributeType == .typeDirectory,
              "checked storage creation makes a real directory only after confirming both current and previous paths are absent")

        let blocked = root.appendingPathComponent("unreadable", isDirectory: true)
        try fm.createDirectory(at: blocked, withIntermediateDirectories: true)
        try files["conversations.json"]!.write(to: blocked.appendingPathComponent("conversations.json"))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }
        do { _ = try ConversationFiles.load(from: blocked, legacyDefaults: { preconditionFailure("unreadable history used defaults") }); preconditionFailure("unreadable archive accepted") }
        catch {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
            check(try Data(contentsOf: blocked.appendingPathComponent("conversations.json")) == files["conversations.json"]!,
                  "actual filesystem permission failure preserves saved history and never falls back to defaults")
        }

        let pairRoot = root.appendingPathComponent("pair", isDirectory: true)
        try fm.createDirectory(at: pairRoot, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: pairRoot.appendingPathComponent(name), options: .atomic) }
        let water = pairRoot.appendingPathComponent("water.json")
        try Data("old-water".utf8).write(to: water, options: .atomic)
        let revision = BackupStorageRevision(), captured = revision.current
        let stale = try BackupFileTransaction.prepare(deleted, photoFiles: [:], into: pairRoot, preserveByLink: true)
        try revision.write { try Data("new-water".utf8).write(to: water, options: .atomic) }
        do { try revision.commit(ifUnchanged: captured) { try stale.commit() }; preconditionFailure("stale conversation commit accepted") }
        catch BackupError.recordsChanged {
            check(try Data(contentsOf: pairRoot.appendingPathComponent("conversations.json")) == files["conversations.json"]!
                  && Data(contentsOf: pairRoot.appendingPathComponent("chat.json")) == files["chat.json"]!
                  && Data(contentsOf: water) == Data("new-water".utf8),
                  "a stale conversation preparation cannot replace either saved history file or a newer health record")
        }
        stale.discard()

        let failedInstall = try BackupFileTransaction.prepare(deleted, photoFiles: [:], into: pairRoot, preserveByLink: true)
        let prepared = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("pair.restore-") }
        check(prepared.count == 1, "conversation failure check identifies only its own one staged replacement")
        try fm.removeItem(at: prepared[0])
        do { try failedInstall.commit(); preconditionFailure("missing conversation stage accepted") }
        catch {
            check(try Data(contentsOf: pairRoot.appendingPathComponent("conversations.json")) == files["conversations.json"]!
                  && Data(contentsOf: pairRoot.appendingPathComponent("chat.json")) == files["chat.json"]!,
                  "failed directory installation restores the exact old archive and chat mirror together")
        }
        check(try ConversationFiles.load(from: pairRoot).conversations.first?.messages.first?.id == legacy.first?.id,
              "relaunch after a failed history installation reads the original message rather than the proposed deletion")

        for name in ["conversations.json", "chat.json"] {
            let blockedPair = root.appendingPathComponent("blocked-" + name, isDirectory: true)
            try fm.createDirectory(at: blockedPair, withIntermediateDirectories: true)
            let other = name == "chat.json" ? "conversations.json" : "chat.json"
            try files[other]!.write(to: blockedPair.appendingPathComponent(other))
            try fm.createDirectory(at: blockedPair.appendingPathComponent(name), withIntermediateDirectories: true)
            do { _ = try BackupFileTransaction.prepare(deleted, photoFiles: [:], into: blockedPair, preserveByLink: true); preconditionFailure("blocked conversation destination accepted") }
            catch {
                check(try Data(contentsOf: blockedPair.appendingPathComponent(other)) == files[other]!,
                      "actual staging failure at " + name + " leaves the other original history file unchanged")
            }
        }

        let selectionRoot = root.appendingPathComponent("selection", isDirectory: true)
        try fm.createDirectory(at: selectionRoot, withIntermediateDirectories: true)
        let unsent = try ConversationFiles.encoded([conversation], activeID: nil)
        for (name, data) in unsent { try data.write(to: selectionRoot.appendingPathComponent(name)) }
        let unsentReload = try ConversationFiles.load(from: selectionRoot)
        check(unsentReload.conversations.count == 1 && unsentReload.selection != nil && unsentReload.selection?.activeID == nil,
              "relaunch preserves an explicit unsent conversation even when older saved conversations exist")
        let badSelection = try encoder.encode(ConversationFiles.Selection(activeID: "deleted-conversation"))
        try badSelection.write(to: selectionRoot.appendingPathComponent("conversation-selection.json"))
        do { _ = try ConversationFiles.load(from: selectionRoot); preconditionFailure("dangling selection accepted") }
        catch ConversationFiles.Failure.missingSelection {
            check(try Data(contentsOf: selectionRoot.appendingPathComponent("conversations.json")) == unsent["conversations.json"]!,
                  "invalid selection is surfaced without replacing saved history or inventing a selected conversation")
        }
        try fm.removeItem(at: selectionRoot.appendingPathComponent("conversation-selection.json"))
        try encoder.encode([conversation, conversation]).write(to: selectionRoot.appendingPathComponent("conversations.json"))
        do { _ = try ConversationFiles.load(from: selectionRoot); preconditionFailure("duplicate conversation identity accepted") }
        catch ConversationFiles.Failure.invalidFile { check(true, "duplicate conversation identities are rejected before installing keyed live state") }

        // An unrelated linked settings write must not retire the surviving
        // previous history while the current archive cannot be read.
        let linkedWriteRoot = root.appendingPathComponent("linked-write", isDirectory: true)
        let linkedWritePrevious = linkedWriteRoot.appendingPathExtension("previous")
        for directory in [linkedWriteRoot, linkedWritePrevious] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, data) in files { try data.write(to: directory.appendingPathComponent(name)) }
        }
        let currentArchive = linkedWriteRoot.appendingPathComponent("conversations.json")
        let goalsFile = linkedWriteRoot.appendingPathComponent("goals.json")
        let originalGoals = Data("original-goals".utf8), replacementGoals = Data("replacement-goals".utf8)
        try malformed.write(to: currentArchive)
        try originalGoals.write(to: goalsFile)
        var rejectedCorruptHistory = false
        do {
            let transaction = try ConversationFiles.prepareLinkedChange(["goals.json": replacementGoals], into: linkedWriteRoot)
            transaction.discard()
        } catch { rejectedCorruptHistory = true }
        check(rejectedCorruptHistory && fm.fileExists(atPath: linkedWritePrevious.path),
              "unrelated linked preparation refuses corrupt history before retiring its surviving previous copy")
        let preservedArchive = try Data(contentsOf: currentArchive)
        let preservedGoals = try Data(contentsOf: goalsFile)
        let preservedPriorFiles = try files.allSatisfy { name, data in
            try Data(contentsOf: linkedWritePrevious.appendingPathComponent(name)) == data
        }
        check(preservedArchive == malformed && preservedGoals == originalGoals && preservedPriorFiles,
              "failed unrelated linked write preserves exact corrupt archive, original goals and every prior conversation file")
        do {
            _ = try ConversationFiles.prepareRestore(["goals.json": replacementGoals], photoFiles: [:], into: linkedWriteRoot, control: .init())
            preconditionFailure("restore accepted corrupt current history while retiring a valid prior copy")
        } catch {
            let priorArchive = try Data(contentsOf: linkedWritePrevious.appendingPathComponent("conversations.json"))
            let currentArchiveBytes = try Data(contentsOf: currentArchive)
            check(priorArchive == files["conversations.json"]! && currentArchiveBytes == malformed,
                  "restore preparation preserves the exact corrupt current and good prior archive before retiring recovery")
        }
        try files["conversations.json"]!.write(to: currentArchive)
        let repairedTransaction = try ConversationFiles.prepareLinkedChange(["goals.json": replacementGoals], into: linkedWriteRoot)
        try repairedTransaction.commit()
        let repairedHistory = try ConversationFiles.load(from: linkedWriteRoot)
        let repairedGoals = try Data(contentsOf: goalsFile)
        check(repairedGoals == replacementGoals && repairedHistory.selection?.activeID == conversation.id
              && repairedHistory.conversations.first?.messages.first?.id == legacy.first?.id,
              "valid current history permits an unrelated linked write while preserving conversation identity and selection")
        let validRestore = try ConversationFiles.prepareRestore(["goals.json": originalGoals], photoFiles: [:], into: linkedWriteRoot, control: .init())
        try validRestore.commit()
        let restoredGoals = try Data(contentsOf: goalsFile), restoredHistory = try ConversationFiles.load(from: linkedWriteRoot)
        check(restoredGoals == originalGoals && restoredHistory.selection?.activeID == conversation.id
              && restoredHistory.conversations.first?.messages.first?.id == legacy.first?.id,
              "valid current history permits restore preparation and preserves original conversation identities")
    }
}
