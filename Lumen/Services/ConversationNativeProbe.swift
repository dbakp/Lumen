#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI
import CryptoKit

/// Dedicated synthetic integration checks against the actual actor/store/file
/// boundary. These do not replace visible UI or delayed network verification.
@MainActor final class ConversationNativeProbe: ObservableObject {
    static let shared = ConversationNativeProbe()
    static var requested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetForUITests") && args.contains("-conversation-native-probe")
    }
    @Published private(set) var status = "Checking synthetic conversations…"
    private var started = false
    private struct Check: Codable { let name: String; let passed: Bool }
    private struct Failure: LocalizedError {
        let name: String
        var errorDescription: String? { name }
    }
    func run() async {
        guard Self.requested, !started else { return }; started = true
        var checks: [Check] = []
        func check(_ passed: Bool, _ name: String) throws {
            checks.append(.init(name: name, passed: passed))
            if !passed { throw Failure(name: name) }
        }
        func rejects(_ name: String, _ action: () async throws -> Void) async throws {
            var rejected = false
            do { try await action() } catch { rejected = true }
            try check(rejected, name)
        }
        let health = HealthStore.shared, companion = CompanionStore.shared
        let fm = FileManager.default
        var phase = "conversation stores"
        let archiveControl = BackupOperationControl()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        do {
            for _ in 0..<300 where !health.conversationReady && health.conversationStorageIssue == nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            try check(health.conversationReady && health.conversations.isEmpty, "fresh app finishes checked empty startup migration")
            let root = try LocalStore.checkedDirectory()
            func disk() throws -> [String: Data] {
                try Dictionary(uniqueKeysWithValues: ["conversations.json", "chat.json", "conversation-selection.json"].map {
                    ($0, try Data(contentsOf: root.appendingPathComponent($0)))
                })
            }
            let first = try await health.sendUserMessageChecked(.init(role: .user, text: "Synthetic ferritin question\nLiteral second line"), expectedConversationID: nil)
            var firstCancelled = false
            try check(health.registerConversationReplyCancellation(first.owner, cancel: { firstCancelled = true }), "actual first request registers cancellation with its store owner")
            var record = HealthDocument(title: "Synthetic ferritin record", kind: .record, body: "Synthetic ferritin was 12.5 mg/L. This is a test record.", source: "Synthetic integration fixture")
            record.includeInAssistant = true
            try companion.saveChecked(record)
            let context = try RecordRetrieval.search(query: "ferritin", documents: companion.documents)
            let (text, references) = RecordRetrieval.localReply(context, query: "ferritin")
            try check(references.isValid && !references.passages.isEmpty && references.passages.allSatisfy(\.referenced), "production retrieval creates a valid nonempty exact reference packet")
            let reply = ChatMessage(role: .coach, text: text, provider: "Synthetic integration provider", recordContext: references)
            guard let pendingID = health.retainConversationReply(reply, owner: first.owner, savePlan: false) else { throw Failure(name: "reply ownership missing") }
            let beforeReply = try disk()
            try await rejects("real reply file-preparation failure reaches the checked caller") { _ = try await health.savePendingConversationReply(pendingID) }
            let pendingBytes = try encoder.encode(health.pendingConversationReplies.first?.message)
            let originalBytes = try encoder.encode(Optional(reply))
            let afterReplyFailure = try disk()
            try check(pendingBytes == originalBytes && afterReplyFailure == beforeReply && health.chat.count == 1,
                      "failed reply retains exact text/provider/references and leaves all three saved files unchanged")
            _ = try await health.savePendingConversationReply(pendingID)
            let loadedReply = try LocalStore.loadConversationsChecked().conversations.first?.messages.last
            try check(try encoder.encode(loadedReply) == originalBytes && health.pendingConversationReplies.isEmpty,
                      "storage-only retry saves the identical reference-rich packet once")
            let copy = RecordRetrieval.savedDocument(from: reply, history: health.chat)
            try companion.saveChecked(copy)
            let origin = HealthLogOrigin(conversationID: first.owner.conversationID, messageID: first.owner.questionID,
                                         statement: "Synthetic ferritin question\nLiteral second line", preparedBy: "Synthetic manual review", confirmedAt: Date())
            var receipt = WellbeingCheckIn(energy: 3, mood: 3, stress: 2, note: "Synthetic confirmed entry")
            receipt.logOrigin = origin
            try companion.confirmCheckIn(receipt)
            let beforeNew = try disk()
            try await rejects("real New-conversation preparation failure reaches the checked caller") { try await health.newConversation() }
            let afterNew = try disk()
            try check(afterNew == beforeNew && health.activeConversationID == first.owner.conversationID && health.chat.count == 2,
                      "failed New preserves live selection, messages and all saved conversation files")
            try await health.newConversation()
            let second = try await health.sendUserMessageChecked(.init(role: .user, text: "Synthetic second conversation"), expectedConversationID: nil)
            var secondCancelled = false
            try check(health.registerConversationReplyCancellation(second.owner, cancel: { secondCancelled = true }), "actual inactive request registers cancellation with its store owner")
            let beforeSelect = try disk()
            try await rejects("real selection preparation failure reaches the checked caller") { try await health.selectConversation(first.owner.conversationID) }
            let afterSelect = try disk()
            try check(afterSelect == beforeSelect && health.activeConversationID == second.owner.conversationID,
                      "failed selection retains original active conversation and exact saved files")
            try await health.selectConversation(first.owner.conversationID)
            try check(!firstCancelled && !secondCancelled, "New and selection preserve requests to intact origins")
            let secondReply = ChatMessage(role: .coach, text: reply.text, provider: reply.provider, recordContext: reply.recordContext)
            guard let secondPending = health.retainConversationReply(secondReply, owner: second.owner, savePlan: false) else { throw Failure(name: "inactive origin ownership missing") }
            _ = try await health.savePendingConversationReply(secondPending)
            let inactiveSaved = try LocalStore.loadConversationsChecked()
            try check(inactiveSaved.selection?.activeID == first.owner.conversationID && health.chat.last?.id == reply.id
                      && inactiveSaved.conversations.first(where: { $0.id == second.owner.conversationID })?.messages.last?.id == secondReply.id,
                      "inactive reply saves to its intact origin while preserving the current selection and mirror")
            phase = "encrypted export"
            let backup = try await BackupService.export(password: "Synthetic backup passphrase 42", sleep: SleepStore.shared, health: health, control: archiveControl)
            defer { backup.cleanup() }
            phase = "encrypted selection"
            let backupSource = try await Task.detached { try BackupService.select(backup.url, control: .init()) }.value
            defer { backupSource.cleanup() }
            phase = "encrypted read"
            let preview = try await Task.detached { try BackupService.read(backupSource, password: "Synthetic backup passphrase 42", control: .init()) }.value
            let archivedReply = preview.snapshot.conversations.first(where: { $0.id == first.owner.conversationID })?.messages.last
            try check(try encoder.encode(archivedReply) == originalBytes, "actual encrypted backup round trip retains the exact reply/provider/reference packet")
            // The live snapshot can remain valid after a file becomes unreadable.
            // A failed restore preparation must still preserve the prior copy.
            phase = "failed restore preserves recovery copy"
            let currentArchive = root.appendingPathComponent("conversations.json")
            let originalArchive = try Data(contentsOf: currentArchive)
            let previousRoot = root.appendingPathExtension("previous")
            let blockedFile = root.appendingPathComponent("synthetic-restore-unreadable.bin")
            let malformedArchive = Data("{SYNTHETIC-RESTORE-CORRUPTION-39".utf8)
            guard !fm.fileExists(atPath: previousRoot.path) else { throw Failure(name: "unexpected prior fixture directory") }
            try LocalStore.performWrite {
                try fm.copyItem(at: root, to: previousRoot)
                try malformedArchive.write(to: currentArchive, options: .atomic)
                try Data("SYNTHETIC-UNREADABLE-RESTORE-39".utf8).write(to: blockedFile)
                try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blockedFile.path)
            }
            do {
                defer {
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: blockedFile.path)
                    try? fm.removeItem(at: blockedFile)
                    try? originalArchive.write(to: currentArchive, options: .atomic)
                    // Only this reset-created synthetic duplicate is retired.
                    try? fm.removeItem(at: previousRoot)
                }
                try await rejects("actual restore rejects a failed preparation with corrupt current history") {
                    try await BackupService.restore(preview, preferences: false, sleep: SleepStore.shared, health: health, control: .init())
                }
                let currentAfterFailure = try Data(contentsOf: currentArchive)
                let previousAfterFailure = try? Data(contentsOf: previousRoot.appendingPathComponent("conversations.json"))
                try check(currentAfterFailure == malformedArchive && previousAfterFailure == originalArchive,
                          "failed actual restore keeps exact corrupt current and recoverable prior archive bytes")
            }
            phase = "clear/delete/restore"
            try await health.clearConversationChecked()
            try check(firstCancelled && !health.ownsReply(first.owner) && health.retainConversationReply(reply, owner: first.owner, savePlan: false) == nil,
                      "clear changes origin lifetime and rejects its late returned reply")
            try await health.deleteConversation(second.owner.conversationID)
            try check(secondCancelled && !health.ownsReply(second.owner) && health.retainConversationReply(reply, owner: second.owner, savePlan: false) == nil,
                      "delete rejects its late returned reply without recreating removed history")
            var rejectedOwnerCancelled = false
            let acceptedOldOwner = health.registerConversationReplyCancellation(second.owner, cancel: { rejectedOwnerCancelled = true })
            try check(!acceptedOldOwner && rejectedOwnerCancelled, "an already obsolete origin cancels before starting a provider")
            try check(companion.documents.contains(where: { $0.id == copy.id }) && companion.checkIns.contains(where: { $0.id == receipt.id && $0.logOrigin?.messageID == first.owner.questionID }),
                      "clear and delete retain independent Library copy and confirmed-entry origin receipt")
            try await health.deleteConversation(first.owner.conversationID)
            let beforeRestore = try await health.sendUserMessageChecked(.init(role: .user, text: "Synthetic in-flight restore owner"), expectedConversationID: nil)
            var restoreCancelled = false
            try check(health.registerConversationReplyCancellation(beforeRestore.owner, cancel: { restoreCancelled = true }), "actual pre-restore request registers cancellation")
            _ = health.retainConversationReply(reply, owner: beforeRestore.owner, savePlan: false)
            try await BackupService.restore(preview, preferences: false, sleep: SleepStore.shared, health: health, control: .init())
            let afterRestore = try LocalStore.loadConversationsChecked()
            try check(afterRestore.selection != nil && afterRestore.selection?.activeID == nil && health.chat.isEmpty
                      && restoreCancelled && !health.ownsReply(beforeRestore.owner) && health.pendingConversationReplies.isEmpty,
                      "actual restore installs archive/mirror/unsent selection together and invalidates old pending ownership")
            let restoredReply = afterRestore.conversations.first(where: { $0.id == first.owner.conversationID })?.messages.last
            try check(try encoder.encode(restoredReply) == originalBytes, "actual restore recovers missing conversation with its original message and reference identities")
            let readable = try await BackupService.exportReadable(sleep: SleepStore.shared, health: health, control: .init())
            defer { readable.cleanup() }
            let readableSource = try await Task.detached { try BackupService.selectReadable(readable.url, control: .init()) }.value
            defer { readableSource.cleanup() }
            let conversion = try await Task.detached { try BackupService.convertReadable(readableSource, control: .init()) }.value
            try await health.deleteConversation(first.owner.conversationID)
            try await BackupService.restoreReadable(conversion, domains: [.conversations], sleep: SleepStore.shared, health: health, control: .init())
            let readableReload = try LocalStore.loadConversationsChecked()
            let readableReply = readableReload.conversations.first(where: { $0.id == first.owner.conversationID })?.messages.last
            try check(try encoder.encode(readableReply) == originalBytes && readableReload.selection?.activeID == nil && health.chat.isEmpty,
                      "actual readable export and selected recovery preserve the packet and coherent unsent selection")
            try check(companion.documents.contains(where: { $0.id == copy.id }) && companion.checkIns.contains(where: { $0.id == receipt.id && $0.logOrigin?.messageID == first.owner.questionID }),
                      "backup and readable recovery keep independent Library copy and confirmed-entry receipt")
            let archive = root.appendingPathComponent("conversations.json")
            let saved = try Data(contentsOf: archive), corrupt = Data("{synthetic malformed archive".utf8)
            try LocalStore.performWrite { try corrupt.write(to: archive, options: .atomic) }
            await health.openConversationsChecked()
            let preserved = try Data(contentsOf: archive)
            try check(!health.conversationReady && health.conversationStorageIssue != nil && preserved == corrupt,
                      "actual app reopening reports corrupt history and preserves exact unreadable bytes")
            var refusedBackup = false
            do { _ = try BackupService.snapshot(sleep: SleepStore.shared, health: health) } catch { refusedBackup = true }
            try check(refusedBackup, "backup capture refuses unavailable conversation history")
            try LocalStore.performWrite { try saved.write(to: archive, options: .atomic) }
            await health.openConversationsChecked()
            try check(health.conversationReady && health.chat.isEmpty, "retry opening installs repaired history and retains explicit unsent selection")
            phase = "stale rename and prepared transactions"
            guard let renameTarget = health.conversations.first else { throw Failure(name: "missing stale-rename fixture") }
            try await health.renameConversation(renameTarget.id, title: "Synthetic newer title")
            let beforeStaleRename = try disk()
            try await rejects("actual stale rename rejects its previously reviewed title") {
                try await health.renameConversation(renameTarget.id, title: "Synthetic retained stale draft", expectedTitle: renameTarget.title)
            }
            let afterStaleRename = try disk()
            try check(afterStaleRename == beforeStaleRename && health.conversations.first(where: { $0.id == renameTarget.id })?.title == "Synthetic newer title",
                      "stale rename preserves the newer saved title and every exact conversation file")

            func preparedSnapshot() throws -> [String: Data] {
                var files: [String: Data] = [:]
                for name in ["conversations.json", "chat.json", "conversation-selection.json", "water.json"] {
                    let url = root.appendingPathComponent(name)
                    if fm.fileExists(atPath: url.path) { files[name] = try Data(contentsOf: url) }
                }
                return files
            }
            func preparedRace(_ label: String, mutation: () async throws -> Void) async throws {
                let before = try preparedSnapshot(), target = health.activeConversationID
                let question = ChatMessage(role: .user, text: "Synthetic obsolete prepared question · " + label)
                ConversationPreparedWriteFixture.arm()
                let worker = Task { try await health.sendUserMessageChecked(question, expectedConversationID: target) }
                do {
                    try await ConversationPreparedWriteFixture.waitUntilHeld()
                    let staged = try preparedSnapshot()
                    let stages = try fm.contentsOfDirectory(at: root.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                        .filter { $0.lastPathComponent.hasPrefix(root.lastPathComponent + ".restore-") }
                    var stagedQuestion = false
                    if let stage = stages.first {
                        let loaded = try ConversationFiles.load(from: stage)
                        stagedQuestion = loaded.conversations.flatMap(\.messages).contains { $0.id == question.id }
                    }
                    try check(health.isConversationSaving && staged == before && stages.count == 1 && stagedQuestion,
                              label + ": actual prepared directory exists before any live or saved question installation")
                    try await mutation()
                    let afterMutation = try preparedSnapshot()
                    ConversationPreparedWriteFixture.release()
                    var rejected = false
                    do { _ = try await worker.value } catch { rejected = true }
                    try check(rejected, label + ": obsolete actual prepared conversation commit is rejected")
                    let final = try preparedSnapshot()
                    try check(final == afterMutation && !health.conversations.flatMap(\.messages).contains(where: { $0.id == question.id }),
                              label + ": newer files and live history survive without the obsolete question")
                    var abandoned = true
                    for _ in 0..<300 {
                        abandoned = try fm.contentsOfDirectory(at: root.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                            .contains { $0.lastPathComponent.hasPrefix(root.lastPathComponent + ".restore-") }
                        if !abandoned { break }
                        try await Task.sleep(for: .milliseconds(10))
                    }
                    try check(!abandoned, label + ": rejected transaction releases its own prepared directory")
                } catch {
                    worker.cancel(); ConversationPreparedWriteFixture.release()
                    _ = try? await worker.value
                    throw error
                }
            }
            try await preparedRace("Newer health write") { try health.addWater(ml: 250) }
            let savedWater = LocalStore.load([HydrationLog].self, from: "water") ?? []
            try check(savedWater.contains(where: { $0.ml == 250 }) && savedWater.map(\.id) == health.waterLogs.map(\.id),
                      "newer actual checked water entry survives the rejected conversation stage")
            try await preparedRace("Restore generation") {
                try await BackupService.restore(preview, preferences: false, sleep: SleepStore.shared, health: health, control: .init())
            }
            try await preparedRace("Account reset") { LocalStore.eraseAll(); health.resetAll() }
            let pendingAtReset = try await health.sendUserMessageChecked(.init(role: .user, text: "Synthetic reset ownership"), expectedConversationID: health.activeConversationID)
            var resetCancelled = false
            try check(health.registerConversationReplyCancellation(pendingAtReset.owner, cancel: { resetCancelled = true }), "actual pre-reset request registers cancellation")
            LocalStore.eraseAll(); health.resetAll()
            try check(resetCancelled && !health.ownsReply(pendingAtReset.owner) && health.retainConversationReply(reply, owner: pendingAtReset.owner, savePlan: false) == nil,
                      "account-reset generation rejects a prior callback without claiming cross-domain erase durability")
            phase = "startup migration competing write"
            ConversationPreparedWriteFixture.arm()
            let opening = Task { @MainActor in await health.openConversationsChecked() }
            do {
                try await ConversationPreparedWriteFixture.waitUntilHeld()
                try check(health.isConversationSaving && !health.conversationReady, "actual empty-startup migration pauses with a prepared directory")
                try health.addWater(ml: 250)
                ConversationPreparedWriteFixture.release()
                await opening.value
            } catch {
                opening.cancel(); ConversationPreparedWriteFixture.release()
                await opening.value
                throw error
            }
            try check(LocalStore.load([HydrationLog].self, from: "water")?.map(\.id) == health.waterLogs.map(\.id),
                      "concurrent startup water write remains saved")
            try check(health.conversationReady && health.conversationStorageIssue == nil,
                      "fresh startup retries a competing storage revision without reporting unavailable history")
            let opened = try LocalStore.loadConversationsChecked()
            try check(!opened.needsMigration && opened.conversations.isEmpty && opened.selection?.activeID == nil,
                      "retried startup installs an empty archive and explicit unsent selection")
            status = "Conversation checks passed"
        } catch {
            let progress = archiveControl.progress
            status = "Conversation checks failed: \(phase), \(progress.stage) \(progress.completed)/\(progress.total), \(progress.bytes) bytes: " + error.localizedDescription
        }
        struct Report: Codable { let status: String; let checks: [Check]; let scope: String }
        let report = Report(status: status, checks: checks, scope: "Synthetic actual iOS HealthStore, LocalStore, linked Foundation files, retrieval/reference integration and encrypted/readable BackupService round trips. Fixed launch fault counts 3,5,8. Direct callback ownership checks; no delayed transport, visible startup UI, power-loss, disk-exhaustion, physical-device, live-provider or clinical claim.")
        do { try encoder.encode(report).write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Lumen-conversation-native-report.json"), options: .atomic) }
        catch { status = "Conversation checks failed: report could not be saved" }
    }
}

/// Pause only an explicitly armed synthetic native probe, after the production
/// directory preparation and before its real revision/ownership commit checks.
@MainActor enum ConversationPreparedWriteFixture {
    private(set) static var armed = false
    private static var holding = false
    private static var continuation: CheckedContinuation<Void, Never>?
    private static var requestedUI: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetForUITests") && args.contains("-conversation-preparation-ui-hold")
    }
    static func arm() {
        precondition((ConversationNativeProbe.requested || requestedUI) && !armed && !holding)
        armed = true
    }
    static func pauseIfArmed() async throws {
        guard (ConversationNativeProbe.requested || requestedUI), armed else { return }
        armed = false
        if requestedUI {
            holding = true; defer { holding = false }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 90
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            do {
                let (_, response) = try await session.data(from: URL(string: "http://127.0.0.1:48731/prepared-hold")!)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            } catch { try Task.checkCancellation(); throw error }
            return
        }
        await withCheckedContinuation { waiting in continuation = waiting; holding = true }
    }
    static func waitUntilHeld() async throws {
        for _ in 0..<300 {
            if holding { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Synthetic prepared-write barrier did not open"])
    }
    static func release() {
        armed = false; holding = false
        let waiting = continuation; continuation = nil; waiting?.resume()
    }
}

/// Seed only this reset, synthetic simulator launch before any store loads.
/// Keep original bytes beside the fixture for independent host read-back.
enum ConversationNativeFixtures {
    private static var titleChanged = false
    static var restoreRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-resetForUITests"), let index = args.firstIndex(of: "-conversation-startup-fixture"), args.indices.contains(index + 1) else { return false }
        return args[index + 1] == "restore"
    }
    static var restoreFixtureURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumen-synthetic-held-restore-39.lumenbackup")
    }
    @MainActor static func changeTitleIfRequested(health: HealthStore, id: String) async throws {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-resetForUITests"), args.contains("-conversation-rename-change"), !titleChanged else { return }
        titleChanged = true
        try await health.renameConversation(id, title: "Synthetic external title change")
    }
    @MainActor static func prepareStartupIfRequested() throws {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-resetForUITests"), let index = args.firstIndex(of: "-conversation-startup-fixture"),
              args.indices.contains(index + 1) else { return }
        let mode = args[index + 1]
        guard ["legacy", "empty", "corrupt", "unreadable", "saved", "references", "restore", "counts"].contains(mode) else { throw BackupError.invalid }
        let root = try LocalStore.checkedDirectory(), encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let message = ChatMessage(id: "synthetic-startup-message-39", role: .user,
                                  text: "Synthetic saved question\nCafé · 12,5 µg/L", date: date)
        var conversation = HealthConversation(id: "synthetic-startup-conversation-39", title: "Synthetic saved conversation",
                                              createdAt: date, updatedAt: date, messages: [message])
        var countFixture: Int?
        if mode == "counts" {
            guard let countIndex = args.firstIndex(of: "-conversation-count"), args.indices.contains(countIndex + 1),
                  let count = Int(args[countIndex + 1]), (0...2).contains(count) else { throw BackupError.invalid }
            countFixture = count
            conversation.messages = (0..<count).map {
                ChatMessage(id: "synthetic-count-message-39-\($0)", role: .user, text: "Synthetic count question \($0 + 1)", date: date)
            }
        }
        let baseline = try ConversationFiles.encoded([conversation], activeID: conversation.id)
        try LocalStore.performWrite {
            for (name, data) in baseline { try data.write(to: root.appendingPathComponent(name), options: .atomic) }
            if let count = countFixture {
                let documents = (0..<count).map { index in
                    var document = HealthDocument(id: "synthetic-count-document-39-\(index)", title: "Synthetic count record \(index + 1)",
                                                  kind: .record, body: "Synthetic count fixture. No personal health data.", source: "Synthetic verification")
                    document.includeInAssistant = true
                    return document
                }
                try encoder.encode(documents).write(to: root.appendingPathComponent("documents.json"), options: .atomic)
            }
            let archive = root.appendingPathComponent("conversations.json")
            let selection = root.appendingPathComponent("conversation-selection.json")
            if mode == "legacy" {
                try FileManager.default.removeItem(at: archive); try FileManager.default.removeItem(at: selection)
            } else if mode == "empty" {
                try Data("[]".utf8).write(to: archive, options: .atomic)
                try encoder.encode(ConversationFiles.Selection(activeID: nil)).write(to: selection, options: .atomic)
            } else if mode == "corrupt" {
                try Data("{SYNTHETIC-CORRUPT-ARCHIVE-39".utf8).write(to: archive, options: .atomic)
            }
            let original = mode == "legacy" ? root.appendingPathComponent("chat.json") : archive
            try Data(contentsOf: original).write(to: root.appendingPathComponent("conversation-fixture-original.bin"), options: .atomic)
            try encoder.encode(["mode": mode]).write(to: root.appendingPathComponent("conversation-fixture-mode.json"), options: .atomic)
            if mode == "references" {
                var document = HealthDocument(id: "synthetic-conversation-source-39", createdAt: date, updatedAt: date,
                                              title: "Synthetic ferritin record", kind: .record,
                                              body: "Synthetic ferritin was 12.5 mg/L. This is a test record.", source: "Synthetic integration fixture")
                document.includeInAssistant = true
                try encoder.encode([document]).write(to: root.appendingPathComponent("documents.json"), options: .atomic)
                let origin = HealthLogOrigin(conversationID: conversation.id, messageID: message.id, statement: message.text,
                                             preparedBy: "Synthetic confirmed manual review", confirmedAt: date)
                let checkIn = WellbeingCheckIn(logOrigin: origin, id: "synthetic-conversation-receipt-39", date: date,
                                              energy: 3, mood: 3, stress: 2, note: "Synthetic independently confirmed entry")
                try encoder.encode([checkIn]).write(to: root.appendingPathComponent("check-ins.json"), options: .atomic)
            }
            if mode == "unreadable" { try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: archive.path) }
        }
        if args.contains("-conversation-preparation-ui-hold") { ConversationPreparedWriteFixture.arm() }
        if mode == "restore" {
            let file = restoreFixtureURL, marker = restoreFixtureURL.appendingPathExtension("fixture.json")
            let fm = FileManager.default
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            func digest(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }
            var ownedMarker: [String: String]?
            if fm.fileExists(atPath: marker.path) {
                guard try fm.attributesOfItem(atPath: marker.path)[.type] as? FileAttributeType == .typeRegular else { throw BackupError.invalid }
                ownedMarker = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: marker))
                guard ownedMarker?["creator"] == "LumenBatch39SyntheticRestore", ownedMarker?["name"] == file.lastPathComponent else { throw BackupError.invalid }
            }
            if fm.fileExists(atPath: file.path) {
                guard try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType == .typeRegular,
                      try ownedMarker?["sha256"] == digest(file) else { throw BackupError.invalid }
                try fm.removeItem(at: file)
            }
            let missing = HealthConversation(id: "synthetic-restore-missing-39", title: "Synthetic missing conversation", createdAt: date, updatedAt: date,
                messages: [.init(id: "synthetic-restore-missing-message-39", role: .user, text: "Synthetic missing conversation record", date: date)])
            let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [],
                conversations: [conversation, missing], symptoms: [], checkIns: [], documents: [], importedDays: [], imports: [], personalContext: .init(), photos: [:])
            try BackupPackage.write(snapshot, photos: [:], password: "Synthetic backup passphrase 42", to: file, now: date)
            try encoder.encode(["creator": "LumenBatch39SyntheticRestore", "name": file.lastPathComponent, "sha256": try digest(file)]).write(to: marker, options: .atomic)
        }
    }
}
#endif
