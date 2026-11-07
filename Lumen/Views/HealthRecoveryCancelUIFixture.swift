#if DEBUG && targetEnvironment(simulator)
import SwiftUI

@MainActor final class HealthRecoveryCancelUIState: ObservableObject {
    static let shared = HealthRecoveryCancelUIState()
    @Published var phase = "preparing"
}

/// A dedicated synthetic test barrier inside actual transaction preparation.
/// It observes the worker's real control; it never substitutes or cancels it.
enum HealthRecoveryCancelUIFixture {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-health-recovery-cancel-ui") }
    private static let bridge = Bridge()
    private static let checkpointName = "Lumen-health-cancel-checkpoint.json"
    private static let releaseName = "Lumen-health-cancel-release.json"
    enum Failure: Error { case invalidFixture, timeout }

    @MainActor static func reset(in root: URL) throws {
        guard requested else { return }
        for name in [checkpointName, releaseName] {
            let file = root.deletingLastPathComponent().appendingPathComponent(name)
            do {
                let facts = try FileManager.default.attributesOfItem(atPath: file.path)
                guard facts[.type] as? FileAttributeType == .typeRegular else { throw Failure.invalidFixture }
                try FileManager.default.removeItem(at: file)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { }
        }
        bridge.reset(); HealthRecoveryCancelUIState.shared.phase = "preparing"
    }

    @MainActor static func makeControl() -> BackupOperationControl {
        let control = BackupOperationControl()
        if requested { bridge.register(control); HealthRecoveryCancelUIState.shared.phase = "preparing" }
        return control
    }

    static func pause(control: BackupOperationControl, stage: URL, root: URL) throws {
        guard requested else { return }
        let context = try bridge.begin(worker: control, stage: stage, root: root)
        Task { @MainActor in HealthRecoveryCancelUIState.shared.phase = "held-\(context.ordinal)" }
        let deadline = Date().addingTimeInterval(30)
        var notedUICancel = false
        var notedHostObservation = false
        while true {
            do { try control.checkCancellation() }
            catch {
                try bridge.update(context, phase: "cancelled", uiCancelled: true)
                Task { @MainActor in HealthRecoveryCancelUIState.shared.phase = "cancelled-\(context.ordinal)" }
                throw error
            }
            let uiCancelled: Bool
            do { try context.uiControl.checkCancellation(); uiCancelled = false }
            catch { uiCancelled = true }
            if uiCancelled && !notedUICancel {
                try bridge.update(context, phase: "held-after-ui-cancel", uiCancelled: true)
                notedUICancel = true
            }
            let file = root.deletingLastPathComponent().appendingPathComponent(releaseName)
            if let bytes = try? HealthLocalFiles.readRegularData(file, limit: 1024),
               let release = try? JSONDecoder().decode(Release.self, from: bytes),
               release.nonce == context.nonce {
                if release.acknowledgementOnly == true {
                    if !notedHostObservation {
                        notedHostObservation = true
                        Task { @MainActor in HealthRecoveryCancelUIState.shared.phase = "observed-\(context.ordinal)" }
                    }
                } else {
                try bridge.update(context, phase: "released", uiCancelled: uiCancelled)
                return
                }
            }
            guard Date() < deadline else {
                try bridge.update(context, phase: "timed-out", uiCancelled: uiCancelled)
                throw Failure.timeout
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
    }

    private struct Release: Codable { let nonce: UUID; let acknowledgementOnly: Bool? }
    private struct Record: Codable {
        let ordinal: Int; let nonce: UUID; let stage: String
        let workerControlMatchesUI: Bool; let originals: [String: Data]
        var phase: String; var uiCancelled: Bool
    }
    private struct Snapshot: Codable { let attempts: [Record] }
    private struct Context {
        let ordinal: Int; let nonce: UUID; let uiControl: BackupOperationControl; let root: URL
    }
    private final class Bridge: @unchecked Sendable {
        private let lock = NSLock()
        private var current: BackupOperationControl?
        private var ordinal = 0
        private var records: [Record] = []
        func reset() { lock.lock(); defer { lock.unlock() }; current = nil; ordinal = 0; records = [] }
        func register(_ control: BackupOperationControl) {
            lock.lock(); defer { lock.unlock() }; current = control; ordinal += 1
        }
        func begin(worker: BackupOperationControl, stage: URL, root: URL) throws -> Context {
            lock.lock(); defer { lock.unlock() }
            guard let uiControl = current, ordinal > 0,
                  stage.deletingLastPathComponent() == root.deletingLastPathComponent(),
                  stage.lastPathComponent.hasPrefix(root.lastPathComponent + ".restore-") else { throw Failure.invalidFixture }
            var originals: [String: Data] = [:]
            for name in HealthLocalFiles.Domain.allCases.map({ $0.rawValue + ".json" }) + [HealthWriteFiles.name] {
                if name == "today.json", ProcessInfo.processInfo.arguments.contains("-health-daily-cache-directory-ui") {
                    let directory = root.appendingPathComponent(name)
                    let facts = try FileManager.default.attributesOfItem(atPath: directory.path)
                    guard facts[.type] as? FileAttributeType == .typeDirectory else { throw Failure.invalidFixture }
                    for child in ["nested/raw-a.bin", "raw-b.txt"] {
                        originals[name + "/" + child] = try HealthLocalFiles.readRegularData(directory.appendingPathComponent(child), limit: 256 * 1024)
                    }
                    continue
                }
                originals[name] = try HealthLocalFiles.readRegularData(root.appendingPathComponent(name), limit: 256 * 1024)
            }
            guard originals["water.json"] == Data("{\"syntheticUnavailableWater\":".utf8) else { throw Failure.invalidFixture }
            let nonce = UUID()
            records.append(.init(ordinal: ordinal, nonce: nonce, stage: stage.lastPathComponent,
                                 workerControlMatchesUI: worker === uiControl, originals: originals,
                                 phase: "held", uiCancelled: false))
            try save(root)
            return .init(ordinal: ordinal, nonce: nonce, uiControl: uiControl, root: root)
        }
        func update(_ context: Context, phase: String, uiCancelled: Bool) throws {
            lock.lock(); defer { lock.unlock() }
            guard let index = records.firstIndex(where: { $0.nonce == context.nonce }) else { throw Failure.invalidFixture }
            records[index].phase = phase; records[index].uiCancelled = uiCancelled
            try save(context.root)
        }
        private func save(_ root: URL) throws {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let file = root.deletingLastPathComponent().appendingPathComponent(checkpointName)
            try encoder.encode(Snapshot(attempts: records)).write(to: file, options: .atomic)
        }
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
import Darwin
import SwiftUI
@MainActor final class HealthReadUIState: ObservableObject {
    static let shared = HealthReadUIState()
    @Published var phase = "idle"
}

@MainActor
struct HealthImportReadUIProbe: View {
    @ObservedObject private var state = HealthReadUIState.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        if HealthReadUIFixture.importRequested {
            Text("Import read check").accessibilityIdentifier("healthImportReadState").accessibilityValue(state.phase)
                .accessibilityLabel("Import read check; appearance=\(colorScheme == .dark ? "dark" : "light"); type=\(dynamicTypeSize == .accessibility5 ? "accessibility5" : dynamicTypeSize == .large ? "large" : "other")")
        }
    }
}

/// Observes an actual bounded read on the dedicated synthetic simulator root.
/// Acknowledgements never release a hold. Back tests leave the first hold for
/// real UI cancellation; source-change tests explicitly release after mutation.
enum HealthReadUIFixture {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-health-read-ui") }
    static var importRequested: Bool { requested && requestedScope == "selected-import" }
    private static var requestedScope: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-health-read-scope"), arguments.indices.contains(index + 1) else { return "retained-record" }
        return arguments[index + 1]
    }
    private static let bridge = Bridge()
    private static let checkpoint = "Lumen-health-read-checkpoint.json"
    private static let release = "Lumen-health-read-release.json"
    enum Failure: Error { case invalidFixture, timeout }

    @MainActor static func reset(in root: URL) throws {
        guard requested else { return }
        for name in [checkpoint, release] {
            let file = root.deletingLastPathComponent().appendingPathComponent(name)
            do {
                let facts = try FileManager.default.attributesOfItem(atPath: file.path)
                guard facts[.type] as? FileAttributeType == .typeRegular else { throw Failure.invalidFixture }
                try FileManager.default.removeItem(at: file)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { }
        }
        bridge.reset(root); HealthReadUIState.shared.phase = "idle"
    }
    @MainActor static func register(_ control: BackupOperationControl, scope: String) {
        guard requested, scope == requestedScope else { return }
        bridge.register(control, scope: scope); HealthReadUIState.shared.phase = "preparing"
    }
    static func willReadPhotoPayload(control: BackupOperationControl) {
        guard requested else { return }
        bridge.markPayload(control)
    }
    static func willReadSelectedPhoto(control: BackupOperationControl, source: URL, photo: URL) {
        guard requested, requestedScope == "selected-photo" else { return }
        bridge.markSelectedPhoto(control, source: source, photo: photo)
    }
    static func willReadOriginalPayload(control: BackupOperationControl) {
        guard requested, ProcessInfo.processInfo.arguments.contains("-health-read-original-payload") else { return }
        bridge.markPayload(control)
    }
    static func pause(control: BackupOperationControl, file: URL, descriptor: Int32, bytesRead: Int,
                      copyTarget: URL? = nil, outputDescriptor: Int32? = nil,
                      encryptedRecordKind: String? = nil, recordOffset: Int? = nil,
                      recordLength: Int? = nil, extractedDirectory: URL? = nil, unlocking: Bool = false) throws {
        guard requested, let context = try bridge.begin(control, file: file, descriptor: descriptor, bytesRead: bytesRead,
                                                        copyTarget: copyTarget, outputDescriptor: outputDescriptor,
                                                        encryptedRecordKind: encryptedRecordKind, recordOffset: recordOffset,
                                                        recordLength: recordLength, extractedDirectory: extractedDirectory, unlocking: unlocking) else { return }
        Task { @MainActor in HealthReadUIState.shared.phase = "held-\(context.ordinal)" }
        let deadline = Date().addingTimeInterval(60)
        var acknowledged = false
        while true {
            do { try control.checkCancellation() }
            catch {
                try bridge.update(context, phase: "cancelled", cancelled: true)
                if context.ordinal == 1, requestedScope == "selected-record" || requestedScope == "selected-photo",
                   ProcessInfo.processInfo.arguments.contains("-health-read-owner-unwind") {
                    // Keep the actual cancelled reader's stack and descriptor
                    // alive while the UI releases its review owner. Only the
                    // dedicated host audit releases this finite test hold.
                    try bridge.update(context, phase: "cancelled-worker-held", cancelled: true)
                    Task { @MainActor in HealthReadUIState.shared.phase = "unwinding-\(context.ordinal)" }
                    let unwindDeadline = Date().addingTimeInterval(60)
                    var released = false
                    while Date() < unwindDeadline {
                        if let data = try? HealthLocalFiles.readRegularData(context.root.deletingLastPathComponent().appendingPathComponent(release), limit: 1024),
                           let message = try? JSONDecoder().decode(Message.self, from: data),
                           message.nonce == context.nonce, message.acknowledgementOnly != true {
                            released = true; break
                        }
                        Thread.sleep(forTimeInterval: 0.025)
                    }
                    guard released else { throw Failure.timeout }
                    try bridge.update(context, phase: "cancelled-worker-released", cancelled: true)
                }
                throw error
            }
            if let data = try? HealthLocalFiles.readRegularData(context.root.deletingLastPathComponent().appendingPathComponent(release), limit: 1024),
               let message = try? JSONDecoder().decode(Message.self, from: data), message.nonce == context.nonce {
                if message.acknowledgementOnly == true {
                    if !acknowledged {
                        acknowledged = true
                        Task { @MainActor in HealthReadUIState.shared.phase = "observed-\(context.ordinal)" }
                    }
                } else {
                    try bridge.update(context, phase: "released", cancelled: false)
                    return
                }
            }
            guard Date() < deadline else {
                try bridge.update(context, phase: "timed-out", cancelled: false)
                throw Failure.timeout
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
    }
    static func didClose(control: BackupOperationControl, descriptor: Int32, succeeded: Bool) {
        guard requested, let ordinal = try? bridge.closed(control, descriptor: descriptor, succeeded: succeeded) else { return }
        Task { @MainActor in HealthReadUIState.shared.phase = "closed-\(ordinal)" }
    }
    static func didCloseDecrypted(control: BackupOperationControl, descriptor: Int32, error: String?) {
        guard requested else { return }
        try? bridge.closedDecrypted(control, descriptor: descriptor, error: error)
    }
    static func willProcessPassword(control: BackupOperationControl, descriptor: Int32) {
        guard requested else { return }
        try? bridge.encryptedUpdate(control, descriptor: descriptor, passwordStarted: true)
    }
    static func didCreateDecrypted(control: BackupOperationControl, descriptor: Int32) {
        guard requested else { return }
        try? bridge.encryptedUpdate(control, descriptor: descriptor, streamCreated: true)
    }
    static func didCreateExtraction(control: BackupOperationControl, descriptor: Int32, directory: URL) {
        guard requested else { return }
        try? bridge.encryptedUpdate(control, descriptor: descriptor, directory: directory)
    }
    static func didEndReview(file: URL) {
        guard requested else { return }
        try? bridge.endedReview(file)
    }
    private struct Message: Codable { let nonce: UUID; let acknowledgementOnly: Bool? }
    private struct Context { let root: URL; let nonce: UUID; let ordinal: Int }
    private struct Record: Codable {
        let ordinal: Int; let nonce: UUID; let scope: String; let file: String
        let descriptor: Int32; let pid: Int32; let inode: UInt64; let size: Int64; let bytesRead: Int
        let workerControlMatchesUI: Bool
        let readBoundary: String
        let copyTarget: String?; let outputDescriptor: Int32?
        var outputDescriptorCloseSucceeded: Bool?
        let encryptedRecordKind: String?; let recordOffset: Int?; let recordLength: Int?
        var extractedDirectory: String?
        var passwordSetStarted: Bool?; var decryptedStreamCreated: Bool?
        var reviewOwnerClosed: Bool?
        let reviewSourceFile: String?
        var decryptedCloseAttempts: Int?; var decryptedCloseSucceeded: Bool?; var decryptedCloseError: String?
        var phase: String; var uiCancelled: Bool; var descriptorCloseSucceeded: Bool?
    }
    private struct Snapshot: Codable { let root: String; let attempts: [Record] }
    private final class Bridge: @unchecked Sendable {
        private let lock = NSLock()
        private var root: URL?
        private var current: BackupOperationControl?
        private var scope = ""
        private var ordinal = 0
        private var records: [Record] = []
        private var workers: [UUID: BackupOperationControl] = [:]
        private var payloadWorker: BackupOperationControl?
        private var selectedPhoto: (worker: BackupOperationControl, source: URL, photo: URL)?
        func reset(_ root: URL) {
            lock.lock(); defer { lock.unlock() }
            self.root = root; current = nil; scope = ""; ordinal = 0; records = []; workers = [:]; payloadWorker = nil
            selectedPhoto = nil
        }
        func register(_ control: BackupOperationControl, scope: String) {
            lock.lock(); defer { lock.unlock() }
            current = control; self.scope = scope; ordinal += 1; payloadWorker = nil
            selectedPhoto = nil
        }
        func markPayload(_ worker: BackupOperationControl) {
            lock.lock(); defer { lock.unlock() }
            payloadWorker = worker
        }
        func markSelectedPhoto(_ worker: BackupOperationControl, source: URL, photo: URL) {
            lock.lock(); defer { lock.unlock() }
            selectedPhoto = (worker, source, photo); payloadWorker = worker
        }
        func begin(_ worker: BackupOperationControl, file: URL, descriptor: Int32, bytesRead: Int,
                   copyTarget: URL?, outputDescriptor: Int32?, encryptedRecordKind: String?,
                   recordOffset: Int?, recordLength: Int?, extractedDirectory: URL?, unlocking: Bool) throws -> Context? {
            lock.lock(); defer { lock.unlock() }
            guard let root, let current, !records.contains(where: { $0.ordinal == ordinal }) else { return nil }
            let retained = file.path.hasPrefix(root.appendingPathComponent(HealthRecoveryCopies.name).path + "/")
            let copying = ProcessInfo.processInfo.arguments.contains("-health-read-original-copy")
            guard copying == (copyTarget != nil), !copying || outputDescriptor != nil else { return nil }
            let decrypting = ProcessInfo.processInfo.arguments.contains("-health-read-encrypted-record")
            guard decrypting == (encryptedRecordKind != nil) else { return nil }
            guard ProcessInfo.processInfo.arguments.contains("-health-read-encrypted-unlock") == unlocking else { return nil }
            if decrypting {
                guard encryptedRecordKind == "personalContext", recordOffset == 65_536,
                      let recordLength, recordLength > 65_536, let extractedDirectory,
                      extractedDirectory.lastPathComponent.hasPrefix("LumenBackupPreview-"),
                      extractedDirectory.deletingLastPathComponent().resolvingSymlinksInPath().path == file.deletingLastPathComponent().resolvingSymlinksInPath().path
                else { throw Failure.invalidFixture }
            }
            let selectedFile = copyTarget ?? file
            let workspace = selectedFile.deletingLastPathComponent()
            let selected = selectedFile.lastPathComponent == "selected-backup"
                && workspace.lastPathComponent.hasPrefix("LumenBackupWork-v1-")
                && workspace.deletingLastPathComponent().resolvingSymlinksInPath().path == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
            var photoWorkspace = file.deletingLastPathComponent()
            let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            for _ in 0..<6 where photoWorkspace.deletingLastPathComponent().resolvingSymlinksInPath() != temporary {
                photoWorkspace.deleteLastPathComponent()
            }
            let selectedPhotoMatches = scope == "selected-photo" && selectedPhoto?.worker === worker
                && selectedPhoto?.photo == file && selectedPhoto?.source.lastPathComponent == "selected-backup"
                && file.pathExtension.lowercased() == "jpg"
                && photoWorkspace.lastPathComponent.hasPrefix("LumenBackupWork-v1-\(getpid())-")
                && photoWorkspace.deletingLastPathComponent().resolvingSymlinksInPath() == temporary
            guard ((scope == "retained-record" || (scope == "retained-photo" && file.pathExtension.lowercased() == "jpg")) && retained)
                    || ((scope == "selected-record" || scope == "selected-import") && selected) || selectedPhotoMatches else { return nil }
            guard !ProcessInfo.processInfo.arguments.contains("-health-read-photo-payload") || payloadWorker === worker else { return nil }
            let originalPayload = ProcessInfo.processInfo.arguments.contains("-health-read-original-payload")
            guard !originalPayload || payloadWorker === worker else { return nil }
            var facts = stat()
            guard fstat(descriptor, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  bytesRead >= (unlocking ? 0 : 1), bytesRead <= 64 * 1024,
                  !unlocking || (bytesRead == 0 && extractedDirectory == nil) else { throw Failure.invalidFixture }
            let nonce = UUID()
            records.append(.init(ordinal: ordinal, nonce: nonce, scope: scope, file: file.path,
                                 descriptor: descriptor, pid: getpid(), inode: UInt64(facts.st_ino), size: facts.st_size,
                                 bytesRead: bytesRead, workerControlMatchesUI: worker === current,
                                 readBoundary: unlocking ? "encrypted-unlock" : decrypting ? "encrypted-record" : copying ? "original-copy" : originalPayload ? "original-payload" : (scope == "selected-record" || scope == "selected-import") ? "selected-source" : payloadWorker === worker ? "photo-payload" : "verification",
                                 copyTarget: copyTarget?.path, outputDescriptor: outputDescriptor, outputDescriptorCloseSucceeded: nil,
                                 encryptedRecordKind: encryptedRecordKind, recordOffset: recordOffset, recordLength: recordLength,
                                 extractedDirectory: extractedDirectory?.path,
                                 passwordSetStarted: decrypting ? true : unlocking ? false : nil,
                                 decryptedStreamCreated: decrypting ? true : unlocking ? false : nil,
                                 reviewOwnerClosed: nil,
                                 reviewSourceFile: selectedPhotoMatches ? selectedPhoto?.source.path : nil,
                                 decryptedCloseAttempts: nil, decryptedCloseSucceeded: nil, decryptedCloseError: nil,
                                 phase: "held", uiCancelled: false, descriptorCloseSucceeded: nil))
            workers[nonce] = worker; try save()
            return .init(root: root, nonce: nonce, ordinal: ordinal)
        }
        func update(_ context: Context, phase: String, cancelled: Bool) throws {
            lock.lock(); defer { lock.unlock() }
            guard let i = records.firstIndex(where: { $0.nonce == context.nonce }) else { throw Failure.invalidFixture }
            records[i].phase = phase; records[i].uiCancelled = cancelled; try save()
        }
        func closed(_ control: BackupOperationControl, descriptor: Int32, succeeded: Bool) throws -> Int? {
            lock.lock(); defer { lock.unlock() }
            if let i = records.firstIndex(where: { $0.outputDescriptor == descriptor && $0.outputDescriptorCloseSucceeded == nil && workers[$0.nonce] === control }) {
                records[i].outputDescriptorCloseSucceeded = succeeded; try save()
                return records[i].descriptorCloseSucceeded == true && succeeded ? records[i].ordinal : nil
            }
            guard let i = records.firstIndex(where: { $0.descriptor == descriptor && $0.descriptorCloseSucceeded == nil && workers[$0.nonce] === control }) else { return nil }
            records[i].descriptorCloseSucceeded = succeeded; try save()
            return records[i].outputDescriptor == nil || records[i].outputDescriptorCloseSucceeded == true ? records[i].ordinal : nil
        }
        func closedDecrypted(_ control: BackupOperationControl, descriptor: Int32, error: String?) throws {
            lock.lock(); defer { lock.unlock() }
            guard let i = records.firstIndex(where: { $0.descriptor == descriptor && workers[$0.nonce] === control }) else { return }
            records[i].decryptedCloseAttempts = (records[i].decryptedCloseAttempts ?? 0) + 1
            records[i].decryptedCloseSucceeded = error == nil
            records[i].decryptedCloseError = error
            try save()
        }
        func encryptedUpdate(_ control: BackupOperationControl, descriptor: Int32, passwordStarted: Bool? = nil,
                             streamCreated: Bool? = nil, directory: URL? = nil) throws {
            lock.lock(); defer { lock.unlock() }
            guard let i = records.firstIndex(where: { $0.descriptor == descriptor && workers[$0.nonce] === control }) else { return }
            if let passwordStarted { records[i].passwordSetStarted = passwordStarted }
            if let streamCreated { records[i].decryptedStreamCreated = streamCreated }
            if let directory { records[i].extractedDirectory = directory.path }
            try save()
        }
        func endedReview(_ file: URL) throws {
            lock.lock(); defer { lock.unlock() }
            for i in records.indices where records[i].file == file.path || records[i].reviewSourceFile == file.path { records[i].reviewOwnerClosed = true }
            try save()
        }
        private func save() throws {
            guard let root else { throw Failure.invalidFixture }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Snapshot(root: root.path, attempts: records)).write(to: root.deletingLastPathComponent().appendingPathComponent(checkpoint), options: .atomic)
        }
    }
}
#endif
