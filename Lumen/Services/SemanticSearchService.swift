import Foundation
import Combine

/// Owns generic model files and RAM-only source vectors. It never downloads in
/// response to a question. Every settings change invalidates outstanding leases.
@MainActor
final class SemanticSearchService: ObservableObject {
    static let shared = SemanticSearchService()
    enum Phase: Equatable { case idle, cleaning, downloading, checking, preparing, stopping, removing }
    struct Lease: Sendable { let encoder: MiniLMEncoder?; let enabled: Bool; let generation: UUID }
    @Published private(set) var enabled: Bool
    @Published private(set) var installed: Bool
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var problem: String?
    private var generation = UUID()
    private var encoder: MiniLMEncoder?
    private var loading: Task<MiniLMEncoder, Error>?
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    private static let enabledKey = "lumen.library.meaning.enabled"
    private static let removalKey = "lumen.library.meaning.pendingRemoval"
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LumenLocalSearch", isDirectory: true)
    }
    private static var modelDirectory: URL { directory.appendingPathComponent(SemanticModelPackage.identifier, isDirectory: true) }
    var busy: Bool { phase != .idle }
    var fraction: Double { Double(receivedBytes) / Double(SemanticModelPackage.downloadBytes) }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        installed = FileManager.default.fileExists(atPath: Self.modelDirectory.appendingPathComponent("installation.json").path)
        if UserDefaults.standard.bool(forKey: Self.removalKey) { removeModel() }
    }
    nonisolated private static func vocabulary() throws -> Data {
        guard let url = Bundle.main.url(forResource: "MiniLM-vocab", withExtension: "txt") else { throw SemanticModelInstallation.InstallError.invalid }
        return try Data(contentsOf: url)
    }
    func isCurrent(_ lease: Lease) -> Bool { lease.generation == generation }

    func lease() async -> Lease {
        let snapshot = generation, wanted = enabled
        guard wanted, !busy else { return Lease(encoder: nil, enabled: wanted, generation: snapshot) }
        if let encoder { return Lease(encoder: encoder, enabled: true, generation: snapshot) }
        let task: Task<MiniLMEncoder, Error>
        if let loading { task = loading }
        else {
            let directory = Self.modelDirectory
            task = Task.detached(priority: .userInitiated) { try Task.checkCancellation(); return try SemanticModelInstallation.load(at: directory, vocabulary: Self.vocabulary()) }
            loading = task
        }
        do {
            let loaded = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard generation == snapshot, enabled, !Task.isCancelled else {
                await loaded.stop()
                if generation == snapshot { loading = nil }
                return Lease(encoder: nil, enabled: wanted, generation: snapshot)
            }
            loading = nil; encoder = loaded; problem = nil
            return Lease(encoder: loaded, enabled: true, generation: snapshot)
        } catch {
            if generation == snapshot {
                loading = nil
                if !Task.isCancelled { problem = "The search model couldn't be opened. Keyword search still works. Delete the model and download it again to retry." }
            }
            return Lease(encoder: nil, enabled: wanted, generation: snapshot)
        }
    }

    func setEnabled(_ value: Bool) {
        guard !busy, value != enabled, !value || installed else { return }
        generation = UUID(); enabled = value; problem = nil
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        guard !value else { return }
        let oldEncoder = encoder, oldLoading = loading
        encoder = nil; loading = nil; oldLoading?.cancel()
        guard oldEncoder != nil || oldLoading != nil else { return }
        let id = UUID(); operationID = id; phase = .stopping
        operation = Task {
            await oldEncoder?.stop()
            if let loaded = try? await oldLoading?.value { await loaded.stop() }
            guard operationID == id else { return }
            phase = .idle; operation = nil; operationID = nil
        }
    }

    func downloadAndEnable() {
        guard !busy, !installed else { return }
        generation = UUID(); problem = nil; phase = .downloading; receivedBytes = 0
        let id = UUID(), destination = Self.modelDirectory
        operationID = id
        let source = Self.installationSource
        operation = Task {
            let worker = Task.detached(priority: .userInitiated) {
                try await SemanticModelInstallation.prepare(at: destination, source: source, vocabulary: Self.vocabulary(), installationID: id) { phase, bytes in
                    Task { @MainActor in
                        guard self.operationID == id, self.phase != .stopping else { return }
                        switch phase { case .cleaning: self.phase = .cleaning; case .downloading: self.phase = .downloading; case .checking: self.phase = .checking; case .preparing: self.phase = .preparing }
                        if let bytes { self.receivedBytes = bytes }
                    }
                }
                try Task.checkCancellation()
                return try SemanticModelInstallation.load(at: destination, vocabulary: Self.vocabulary())
            }
            do {
                let loaded = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, operationID == id else {
                    await loaded.stop()
                    try? await Self.purgeStoppedRuntimeCaches()
                    try? SemanticModelInstallation.removeNewInstallation(at: destination, installationID: id)
                    finishCancelled(id); return
                }
                generation = UUID(); encoder = loaded; installed = true; enabled = true
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
            } catch {
                // The awaited worker is terminal, including an uncancellable native
                // compilation. Its owned stage/encoder is no longer in use.
                try? await Self.purgeStoppedRuntimeCaches()
                try? SemanticModelInstallation.removeNewInstallation(at: destination, installationID: id)
                guard operationID == id else { return }
                if !Task.isCancelled {
                    if case SemanticModelInstallation.InstallError.space = error { problem = "Make at least 250 MB available to download and prepare this model. Keyword search still works." }
                    else { problem = "The model couldn't be prepared. Keyword search still works. Check your connection and available space, then try again." }
                }
            }
            finishCancelled(id)
        }
    }
    private func finishCancelled(_ id: UUID) {
        guard operationID == id else { return }
        installed = FileManager.default.fileExists(atPath: Self.modelDirectory.appendingPathComponent("installation.json").path)
        phase = .idle; operation = nil; operationID = nil
    }
    func cancelDownload() {
        guard [.cleaning, .downloading, .checking, .preparing].contains(phase) else { return }
        generation = UUID(); phase = .stopping; operation?.cancel()
    }

    /// Also called after the regular erase resets preferences. The pending flag
    /// survives termination so a later launch can finish generic-weight cleanup.
    func removeModel() {
        generation = UUID(); enabled = false; problem = nil
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        UserDefaults.standard.set(true, forKey: Self.removalKey)
        let oldWork = operation, oldLoading = loading, oldEncoder = encoder
        oldWork?.cancel(); oldLoading?.cancel(); loading = nil; encoder = nil
        let id = UUID(); operationID = id; phase = .removing
        operation = Task {
            await oldWork?.value
            if let loaded = try? await oldLoading?.value { await loaded.stop() }
            await oldEncoder?.stop()
            let directory = Self.directory
            let cleanup = Task.detached(priority: .utility) {
                try MiniLMRuntimeCache.purgeCurrentApp()
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            }
            do {
                try await cleanup.value
                guard operationID == id else { return }
                installed = false; UserDefaults.standard.removeObject(forKey: Self.removalKey)
            } catch {
                guard operationID == id else { return }
                problem = "The model is off, but its files couldn't be removed. Try Delete model again."
            }
            guard operationID == id else { return }
            phase = .idle; operation = nil; operationID = nil
        }
    }

    nonisolated private static func purgeStoppedRuntimeCaches() async throws {
        // Cleanup must finish even when the cancelled download's parent task
        // is cancelled; its awaited worker and any returned encoder are stopped.
        let cleanup = Task.detached(priority: .utility) { try MiniLMRuntimeCache.purgeCurrentApp() }
        _ = try await cleanup.value
    }

    #if DEBUG && targetEnvironment(simulator)
    static var usesFixture: Bool { ProcessInfo.processInfo.arguments.contains("-librarySearchUITestMode") }
    static var usesLocalReplyTest: Bool { usesFixture || ProcessInfo.processInfo.arguments.contains("-librarySearchRemoteUITestMode") }
    private static var fixtureDirectory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("LumenSemanticFixture", isDirectory: true) }
    private static var installationSource: SemanticModelInstallation.Source { usesFixture ? .fixture(fixtureDirectory, delayNanoseconds: 100_000_000) : .remote }
    static func resetForUITests() { try? FileManager.default.removeItem(at: directory) }
    #else
    private static var installationSource: SemanticModelInstallation.Source { .remote }
    #endif
}
