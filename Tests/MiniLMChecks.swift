import Foundation

enum MiniLMChecks {
    static func cacheChecks() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        let fm = FileManager.default, workspace = fm.temporaryDirectory.appendingPathComponent("LumenBatch19CacheCheck-" + UUID().uuidString)
        let root = workspace.appendingPathComponent("Application/com.apple.e5rt.e5bundlecache")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }
        precondition(MiniLMRuntimeCache.fingerprints.count == 8 && Set(MiniLMRuntimeCache.fingerprints).count == 8)
        func package(_ name: Character, patterns: [Data]) throws -> URL {
            let folder = root.appendingPathComponent("TESTBUILD/" + String(repeating: String(name), count: 64) + "/" + String(repeating: "c", count: 64) + ".bundle")
            let file = folder.appendingPathComponent("intel.bundle/main/main_bnns/bnns_program.bnnsir")
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: file.path, contents: nil) else { throw MiniLMRuntimeCache.CacheError.unsafe }
            let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
            // Sparse: a realistic bounded program length without allocating 45 MB.
            try handle.truncate(atOffset: 45_023_232)
            for (index, pattern) in patterns.enumerated() { try handle.seek(toOffset: UInt64(index * 4096)); try handle.write(contentsOf: pattern) }
            return folder
        }
        let owned = try package("a", patterns: MiniLMRuntimeCache.fingerprints)
        let decoy = try package("b", patterns: Array(MiniLMRuntimeCache.fingerprints.dropLast()))
        let outside = workspace.appendingPathComponent("outside"); try fm.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("unrelated sentinel".utf8).write(to: outside.appendingPathComponent("sentinel"))
        let link = root.appendingPathComponent("TESTBUILD/" + String(repeating: "d", count: 64))
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        let unrelatedEmpty = root.appendingPathComponent("TESTBUILD/" + String(repeating: "e", count: 64))
        try fm.createDirectory(at: unrelatedEmpty, withIntermediateDirectories: false)
        var continuation: AsyncStream<Void>.Continuation?
        let gate = AsyncStream<Void> { continuation = $0 }
        let stopped = Task { for await _ in gate { break }; return try MiniLMRuntimeCache.purge(at: root) }
        stopped.cancel(); continuation?.finish()
        var cancelled = false
        do { _ = try await stopped.value; preconditionFailure("cache cleanup ignored cancellation") }
        catch is CancellationError { cancelled = true }
        check(cancelled && fm.fileExists(atPath: owned.path), "already-cancelled cache cleanup throws and preserves its pending package")
        let removed = try MiniLMRuntimeCache.purge(at: root)
        check(removed.packages == 1 && removed.logicalBytes == 45_023_232 && !fm.fileExists(atPath: owned.path), "cleanup removes only the bounded package matching every pinned model fingerprint")
        check(fm.fileExists(atPath: decoy.path) && fm.fileExists(atPath: unrelatedEmpty.path) && fm.fileExists(atPath: outside.appendingPathComponent("sentinel").path) && (try? link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true, "partial-match, empty and symlinked unrelated caches remain untouched along with unrelated files")
        let again = try MiniLMRuntimeCache.purge(at: root)
        check(again.packages == 0 && again.logicalBytes == 0, "verified model-cache cleanup is idempotent")
    }
    private struct RetrievalFixture: Decodable {
        struct Document: Decodable { var id: String; var title: String; var body: String }
        struct Case: Decodable { var id: String; var question: String; var expected: [String] }
        var scope: String; var documents: [Document]; var cases: [Case]
    }
    static func benchmark(source: URL, compiled: URL, output: URL) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(RetrievalFixture.self, from: Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/MiniLMRetrieval.json")))
        let encoder = try MiniLMEncoder(compiledModel: compiled, vocabulary: Data(contentsOf: source.appendingPathComponent("tokenizer/vocab.txt")))
        let documents = fixture.documents.enumerated().map { offset, doc in
            HealthDocument(id: doc.id, createdAt: Date(timeIntervalSince1970: Double(offset)), updatedAt: Date(timeIntervalSince1970: Double(offset)), title: doc.title, kind: .record, body: doc.body, source: "Synthetic English diagnostic", includeInAssistant: true)
        }
        var rows: [[String: Any]] = []
        let start = ProcessInfo.processInfo.systemUptime
        do {
            for sample in fixture.cases {
                let literal = try RecordRetrieval.search(query: sample.question, documents: documents)
                let hybrid = try await HybridLibrarySearch.search(query: sample.question, documents: documents, encoder: encoder, enabled: true)
                let expected = Set(sample.expected), keyword = literal.passages.map(\.documentID), actual = hybrid.passages.map(\.documentID)
                rows.append(["id":sample.id,"question":sample.question,"expectedContext":sample.expected,"keywordSelections":keyword,"hybridSelections":actual,"expectedContextsFoundByKeyword":Set(keyword).intersection(expected).count,"expectedContextsFoundByHybrid":Set(actual).intersection(expected).count,"unexpectedSelectionsByKeyword":Set(keyword).subtracting(expected).sorted(),"unexpectedSelectionsByHybrid":Set(actual).subtracting(expected).sorted(),"comparedPassages":hybrid.meaningSearch?.comparedPassages ?? 0,"status":hybrid.meaningSearch?.status.rawValue ?? "none"])
            }
        } catch { await encoder.stop(); throw error }
        await encoder.stop()
        let report: [String: Any] = ["scope":fixture.scope,"modelID":SemanticModelPackage.identifier,"minimumSimilarity":HybridLibrarySearch.minimumSimilarity,"documentCount":documents.count,"queryCount":fixture.cases.count,"elapsedMacSeconds":ProcessInfo.processInfo.systemUptime-start,"cases":rows,"limits":["Nine hand-authored English cases, not an independent clinical benchmark.","A selected excerpt does not establish entailment, laterality, negation equivalence or medical truth.","All misses and unexpected selections are retained. No passing threshold is imposed on this diagnostic.","Mac CPU timings do not establish physical iPhone performance."]]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        print("Recorded \(rows.count) synthetic diagnostic queries with actual Core ML; all selections and misses retained.")
    }
    #if DEBUG
    static func lowSpace(destination: URL) async throws {
        let fm = FileManager.default, parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let free = (try fm.attributesOfFileSystem(forPath: parent.path)[.systemFreeSize] as! NSNumber).int64Value
        precondition(free < 250_000_000, "Use a separate, bounded low-capacity test volume, not the main disk")
        print("Actual free bytes on isolated test volume: \(free)")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let vocabulary = try Data(contentsOf: root.appendingPathComponent("Lumen/Resources/MiniLM-vocab.txt"))
        do {
            // An intentionally absent local fixture also guarantees that a bad
            // space guard cannot accidentally start an external download here.
            try await SemanticModelInstallation.prepare(at: destination, source: .fixture(parent.appendingPathComponent("absent-input"), delayNanoseconds: 0), vocabulary: vocabulary, installationID: UUID()) { _, _ in }
            preconditionFailure("installation accepted insufficient space")
        } catch SemanticModelInstallation.InstallError.space { print("PASS: actual low-capacity volume rejects model preparation before transfer or compilation") }
        let remaining = try fm.contentsOfDirectory(atPath: parent.path)
        precondition(remaining.isEmpty && !fm.fileExists(atPath: destination.path))
        print("PASS: insufficient-space rejection creates no partial model or installation stage")
    }
    private final class Observations: @unchecked Sendable {
        private let lock = NSLock()
        private var maximum = 0.0
        private var phases: Set<String> = []
        func record(_ phase: SemanticModelInstallation.Phase, _ bytes: Int64?) {
            lock.lock(); defer { lock.unlock() }
            if let bytes { maximum = max(maximum, Double(bytes) / Double(SemanticModelPackage.downloadBytes)) }
            phases.insert(String(describing: phase))
        }
        func snapshot() -> (Double, Set<String>) { lock.lock(); defer { lock.unlock() }; return (maximum, phases) }
    }
    static func install(source: URL) async throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        let fm = FileManager.default, workspace = fm.temporaryDirectory.appendingPathComponent("LumenBatch19InstallCheck-" + UUID().uuidString)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: workspace) }
        let vocabulary = try Data(contentsOf: source.appendingPathComponent("tokenizer/vocab.txt"))
        let cancelledURL = workspace.appendingPathComponent("cancelled"), observation = Observations()
        let copying = Task {
            try await SemanticModelInstallation.prepare(at: cancelledURL, source: .fixture(source, delayNanoseconds: 40_000_000), vocabulary: vocabulary, installationID: UUID()) { observation.record($0, $1) }
        }
        for _ in 0..<100 {
            if observation.snapshot().0 > 0.1 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        check(observation.snapshot().0 > 0.1 && observation.snapshot().0 < 1, "installation cancellation is exercised during real streamed model copying")
        copying.cancel()
        do { try await copying.value; preconditionFailure("cancelled installation completed") }
        catch is CancellationError { print("PASS: cancelled model preparation propagates cancellation") }
        let afterCancel = try fm.contentsOfDirectory(atPath: workspace.path)
        check(!fm.fileExists(atPath: cancelledURL.path) && afterCancel.isEmpty, "cancelled model installation removes its partial files after its worker stops")
        let destination = workspace.appendingPathComponent("installed"), ticket = UUID(), installedProgress = Observations()
        let interrupted = workspace.appendingPathComponent(".pending-" + UUID().uuidString)
        try fm.createDirectory(at: interrupted, withIntermediateDirectories: false)
        try Data([1, 2, 3]).write(to: interrupted.appendingPathComponent("partial-weight.bin"))
        try await SemanticModelInstallation.prepare(at: destination, source: .fixture(source, delayNanoseconds: 0), vocabulary: vocabulary, installationID: ticket) { installedProgress.record($0, $1) }
        check(!fm.fileExists(atPath: interrupted.path), "retry removes an owned interrupted stage before starting new model work")
        check(installedProgress.snapshot().0 == 1 && installedProgress.snapshot().1 == ["cleaning", "downloading", "checking", "preparing"], "installation reports actual copied bytes and separate cache/checking/preparing phases")
        let installedFiles = try fm.contentsOfDirectory(atPath: destination.path)
        check(Set(installedFiles) == [SemanticModelInstallation.compiledName, "installation.json"], "successful installation retains compiled weights and a receipt without a duplicate downloaded package")
        let encoder = try SemanticModelInstallation.load(at: destination, vocabulary: vocabulary)
        let original = try await encoder.queryVector("What did my saved notes say about tiredness?")
        await encoder.stop()
        let reopened = try SemanticModelInstallation.load(at: destination, vocabulary: vocabulary)
        let reloaded = try await reopened.queryVector("What did my saved notes say about tiredness?")
        check((MiniLMEncoder.similarity(original, reloaded) ?? 0) > 0.9999, "verified installed model reopens and performs matching real Core ML inference")
        await reopened.stop()
        do {
            try await SemanticModelInstallation.prepare(at: destination, source: .fixture(source, delayNanoseconds: 0), vocabulary: vocabulary, installationID: UUID()) { _, _ in }
            preconditionFailure("existing installation overwritten")
        } catch SemanticModelInstallation.InstallError.existing { print("PASS: preparation cannot replace an existing model installation") }
        try SemanticModelInstallation.removeNewInstallation(at: destination, installationID: UUID())
        check(fm.fileExists(atPath: destination.path), "late cancellation from another installation cannot remove the current model")
        let inventory = try SemanticModelInstallation.files(in: destination.appendingPathComponent(SemanticModelInstallation.compiledName))
        let victim = destination.appendingPathComponent(SemanticModelInstallation.compiledName).appendingPathComponent(inventory[0].path)
        let writer = try FileHandle(forWritingTo: victim); try writer.seekToEnd(); try writer.write(contentsOf: Data([0])); try writer.close()
        do { _ = try SemanticModelInstallation.load(at: destination, vocabulary: vocabulary); preconditionFailure("changed compiled asset accepted") }
        catch SemanticModelInstallation.InstallError.invalid { print("PASS: changed compiled model bytes are rejected before inference") }
        try SemanticModelInstallation.removeNewInstallation(at: destination, installationID: ticket)
        check(!fm.fileExists(atPath: destination.path), "checked removal deletes only the owned installation after encoders stop")
        let bad = workspace.appendingPathComponent("bad-input"), invalid = workspace.appendingPathComponent("invalid")
        let manifest = bad.appendingPathComponent(SemanticModelPackage.assets[0].path)
        try fm.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: manifest)
        do {
            try await SemanticModelInstallation.prepare(at: invalid, source: .fixture(bad, delayNanoseconds: 0), vocabulary: vocabulary, installationID: UUID()) { _, _ in }
            preconditionFailure("invalid source accepted")
        } catch SemanticModelPackage.PackageError.invalid { print("PASS: invalid pinned download is rejected before Core ML compilation") }
        let afterFailure = try fm.contentsOfDirectory(atPath: workspace.path)
        check(!fm.fileExists(atPath: invalid.path) && !afterFailure.contains(where: { $0.hasPrefix(".pending-") }), "failed model preparation leaves no install or pending weight copy")
        let link = workspace.appendingPathComponent("linked-model")
        try fm.createSymbolicLink(at: link, withDestinationURL: source)
        do { _ = try SemanticModelInstallation.files(in: link); preconditionFailure("symlinked model accepted") }
        catch SemanticModelInstallation.InstallError.invalid { print("PASS: model inventory rejects a symlinked root without following it") }
    }
    #endif
    static func model(source: URL, compiled: URL) async throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        for asset in SemanticModelPackage.assets { try SemanticModelPackage.validate(source.appendingPathComponent(asset.path), asset: asset) }
        let weights = try Data(contentsOf: source.appendingPathComponent(SemanticModelPackage.assets[2].path), options: .mappedIfSafe)
        check(zip(MiniLMRuntimeCache.sourceOffsets, MiniLMRuntimeCache.fingerprints).allSatisfy { offset, bytes in weights.subdata(in: offset..<(offset + 64)) == bytes }, "runtime cache fingerprints exactly match disjoint blocks of the fully verified pinned weights")
        let encoder = try MiniLMEncoder(compiledModel: compiled, vocabulary: Data(contentsOf: source.appendingPathComponent("tokenizer/vocab.txt")))
        let target = HealthDocument(id: "semantic-fatigue", title: "Consultation note", kind: .record, body: "Persistent tiredness and low energy over several weeks.", source: "Synthetic", includeInAssistant: true)
        let budget = HealthDocument(id: "semantic-budget", title: "Household budget", kind: .note, body: "The accountant prepared a summary of quarterly income and expenses.", source: "Synthetic", includeInAssistant: true)
        let lab = HealthDocument(id: "semantic-lab", title: "Laboratory report", kind: .record, body: "Ferritin 42 ug/L. Reference interval 20 to 200 ug/L.", source: "Synthetic", includeInAssistant: true)
        let secret = HealthDocument(id: "semantic-private", title: "Feeling exhausted", kind: .record, body: "PRIVATE-SEMANTIC-CANARY Feeling exhausted after exercise.", source: "Synthetic")
        let docs = [budget, lab, target, secret]
        let query = "What did my saved notes say about feeling exhausted?"
        let lexical = try RecordRetrieval.search(query: query, documents: docs)
        let result = try await HybridLibrarySearch.search(query: query, documents: docs, encoder: encoder, enabled: true)
        check(lexical.passages.isEmpty && result.passages.first?.documentID == target.id, "actual Core ML finds differently worded tiredness text when lexical search has no match")
        check(result.isValid && result.sharedDocuments == 3 && result.meaningSearch?.comparedPassages == 3 && result.passages.first?.selection == .relatedTopic, "actual hybrid search retains valid references and reports real comparison coverage and method")
        check(!RecordRetrieval.prompt(result).contains("PRIVATE-SEMANTIC-CANARY") && !result.passages.contains(where: { $0.documentID == secret.id }), "private documents do not enter actual semantic candidates or provider context")
        check(RecordRetrieval.prompt(result).contains("related-topic") && RecordRetrieval.localReply(result, query: query).0.contains("may not answer your question"), "related topics are explicitly distinguished from support for an answer")
        let again = try await HybridLibrarySearch.search(query: query, documents: docs, encoder: encoder, enabled: true)
        check(again.meaningSearch?.cachedPassages == 3 && again.passages.first?.id != result.passages.first?.id, "private RAM cache reuse preserves fresh request reference identities")
        var withdrawn = docs; withdrawn[2].includeInAssistant = false
        let after = try await HybridLibrarySearch.search(query: query, documents: withdrawn, encoder: encoder, enabled: true)
        check(!after.passages.contains(where: { $0.documentID == target.id }) && !RecordRetrieval.isCurrent(result.passages[0], documents: withdrawn), "sharing withdrawal removes semantic candidates and invalidates their earlier reference for future use")
        let unsupported = try await HybridLibrarySearch.search(query: "Hvad siger mine journaler om udmattelse?", documents: docs, encoder: encoder, enabled: true)
        check(unsupported.meaningSearch?.status == .unsupportedLanguage && unsupported.meaningSearch?.comparedPassages == 0, "unsupported-language questions explicitly retain keyword search instead of claiming English model coverage")
        let long = try await HybridLibrarySearch.search(query: String(repeating: "Please find my saved record about persistent tiredness. ", count: 100), documents: docs, encoder: encoder, enabled: true)
        check(long.meaningSearch?.status == .queryTooLong && long.passages.allSatisfy({ $0.selection == .keyword }), "overlong model questions fall back to literal search without silently clipping the question")
        let timed = try await HybridLibrarySearch.search(query: query, documents: docs, encoder: encoder, enabled: true, timeBudget: 0)
        check(timed.meaningSearch?.limited == true && timed.meaningSearch?.comparedPassages == 0 && timed.passages.isEmpty, "exhausted meaning-search budget is visible and cannot fabricate a result")
        let coded = HealthDocument(title: "Sample code", kind: .record, body: "LAB-42 ferritin 12.5 mg/L, not 125 mg/L.", source: "Synthetic", includeInAssistant: true)
        let code = try await HybridLibrarySearch.search(query: "What did my record say about LAB-42?", documents: [coded] + docs, encoder: encoder, enabled: true)
        check(code.passages.first?.documentID == coded.id && code.passages.first?.excerpt.contains("12.5 mg/L, not 125 mg/L") == true, "leading lexical identifiers and exact units/numeric negation survive actual hybrid ranking")
        let restored = try JSONDecoder().decode(RecordReplyContext.self, from: JSONEncoder().encode(result))
        check(restored.isValid && restored.meaningSearch?.modelID == SemanticModelPackage.identifier && restored.passages[0].selection == .relatedTopic, "actual selected model provenance and topic method round-trip with the source snapshot")
        let lookup = RecordRetrieval.localReply(result, query: query)
        let message = ChatMessage(role: .coach, text: lookup.0, provider: "Synthetic actual-model check", recordContext: lookup.1)
        let saved = RecordRetrieval.savedDocument(from: message, history: [ChatMessage(role: .user, text: query), message])
        check(saved.markdown.contains("English related topics on this iPhone") && saved.markdown.contains("Selection: Related topic") && saved.markdown.contains("Topic matches may not answer the question."), "shared Markdown retains the topic method and its limits beside exact referenced text")
        let snapshot = BackupSnapshot(profile: .default, goals: .init(), habits: [], sleep: [], meals: [], workouts: [], water: [], conversations: [HealthConversation(title: "Synthetic model source", messages: [message])], symptoms: [], checkIns: [], documents: [saved], importedDays: [], imports: [], personalContext: .init(), photos: [:])
        let archive = try BackupArchive.read(BackupArchive.make(snapshot)).1
        check(archive.conversations[0].messages[0].recordContext?.meaningSearch?.status == .used && archive.documents[0].recordContext?.passages[0].selection == .relatedTopic, "version-one backups retain actual topic-search method and source selection metadata")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumenBatch19Compatibility-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let encrypted = folder.appendingPathComponent("sources.lumenbackup")
        try BackupPackage.write(snapshot, photos: [:], password: "Synthetic model test passphrase", to: encrypted)
        let package = try BackupPackage.read(encrypted, password: "Synthetic model test passphrase", temporaryRoot: folder)
        defer { package.removeTemporaryFiles() }
        check(package.snapshot.documents[0].recordContext?.meaningSearch?.modelID == SemanticModelPackage.identifier && package.snapshot.documents[0].recordContext?.passages[0].excerpt == result.passages[0].excerpt, "actual encrypted streamed backups retain topic model identity and exact excerpts")
        let readable = folder.appendingPathComponent("sources.json")
        try ReadableExport.write(snapshot, to: readable)
        let recovered = try ReadableExport.read(Data(contentsOf: readable))
        check(recovered.snapshot.documents[0].recordContext?.isValid == true && recovered.snapshot.documents[0].recordContext?.meaningSearch?.comparedPassages == 3 && recovered.snapshot.documents[0].recordContext?.passages[0].selection == .relatedTopic, "actual readable export and recovery retain valid topic coverage and selection methods")
        var historical = result; historical.meaningSearch?.modelID = "previous-general-retrieval-v1"
        let olderIdentity = try JSONDecoder().decode(RecordReplyContext.self, from: JSONEncoder().encode(historical))
        check(olderIdentity.isValid && olderIdentity.meaningSearch?.modelID == "previous-general-retrieval-v1", "historical model identities remain readable without authorizing a different executable model")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        legacy.removeValue(forKey: "meaningSearch")
        var legacyPassages = legacy["passages"] as! [[String: Any]]
        for index in legacyPassages.indices { legacyPassages[index].removeValue(forKey: "selection") }
        legacy["passages"] = legacyPassages
        let legacyContext = try JSONDecoder().decode(RecordReplyContext.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(legacyContext.isValid && legacyContext.meaningSearch == nil && legacyContext.passages[0].selection == nil, "older source snapshots decode without invented topic-search history")
        let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let diagnostic = try JSONDecoder().decode(RetrievalFixture.self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("Tests/Fixtures/MiniLMRetrieval.json")))
        let corpus = diagnostic.documents.enumerated().map { index, doc in
            HealthDocument(id: doc.id, createdAt: Date(timeIntervalSince1970: Double(index)), updatedAt: Date(timeIntervalSince1970: Double(index)), title: doc.title, kind: .record, body: doc.body, source: "Synthetic English diagnostic", includeInAssistant: true)
        }
        let swelling = try await HybridLibrarySearch.search(query: "Which notes describe swelling in both feet?", documents: corpus, encoder: encoder, enabled: true)
        let literal = RecordRetrieval.localReply(swelling, query: "Which notes describe swelling in both feet?")
        check(swelling.passages.count == 4 && swelling.passages.last?.documentID == "edema" && literal.1.passages.count == 4 && literal.1.isValid && literal.0.contains("Bilateral pedal edema") && literal.1.passages.allSatisfy(\.referenced), "local lookup preserves a real related-topic result after three keyword candidates instead of hiding it")
        let task = Task { try await HybridLibrarySearch.search(query: query, documents: docs, encoder: encoder, enabled: true) }; task.cancel()
        do { _ = try await task.value; preconditionFailure("cancelled semantic search returned") } catch is CancellationError { print("PASS: cancelled semantic search discards its result") }
        await encoder.stop()
        let stopped = try await HybridLibrarySearch.search(query: "What did my saved record say about ferritin?", documents: docs, encoder: encoder, enabled: true)
        check(stopped.meaningSearch?.status == .failed && stopped.passages.first?.documentID == lab.id && stopped.passages.allSatisfy({ $0.selection == .keyword }), "stopping the encoder prevents future inference and preserves genuine keyword fallback")
    }
    struct Golden: Decodable { var text: String; var ids: [Int32] }
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let vocabulary = try Data(contentsOf: root.appendingPathComponent("Lumen/Resources/MiniLM-vocab.txt"))
        let tokenizer = try SemanticModelPackage.tokenizer(vocabulary)
        let golden = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/MiniLMTokenization.json")))
        for (index, sample) in golden.enumerated() {
            let actual = try tokenizer.tokenIDs(sample.text)
            check(actual == sample.ids, "production WordPiece matches independent tokenizer reference case \(index + 1)")
        }
        let empty = try tokenizer.windows(" \n\t")
        check(empty.isEmpty, "empty text has no fabricated semantic embedding window")
        let short = try tokenizer.windows("Hello world.")[0]
        check(short.ids.count == 256 && short.mask.count == 256 && short.types.count == 256 && short.ids.prefix(5) == [101, 7592, 2088, 1012, 102] && short.ids.dropFirst(5).allSatisfy({ $0 == 0 }), "model inputs have exact boundary tokens and fixed 256-token padding")
        check(short.mask.prefix(5).allSatisfy({ $0 == 1 }) && short.mask.dropFirst(5).allSatisfy({ $0 == 0 }) && short.types.allSatisfy({ $0 == 0 }), "attention and segment masks retain real tokens and exclude padding")
        let text = String(repeating: "hello ", count: 600) + "final"
        let tokens = try tokenizer.tokenIDs(text), windows = try tokenizer.windows(text)
        var reconstructed: [Int32] = []
        for (index, window) in windows.enumerated() {
            let body = Array(window.ids.dropFirst().prefix(window.mask.filter({ $0 == 1 }).count - 2))
            reconstructed += index == 0 ? body : Array(body.dropFirst(32))
        }
        check(windows.count == 3 && reconstructed == tokens, "overlapping model windows preserve every original token through the final word")
        do { _ = try tokenizer.tokenIDs(String(repeating: "a", count: 8001)); preconditionFailure("input bound missing") }
        catch MiniLMTokenizer.TokenError.inputLimit { print("PASS: over-limit tokenizer input is rejected without truncation") }
        var altered = vocabulary; altered[0] ^= 1
        do { _ = try SemanticModelPackage.tokenizer(altered); preconditionFailure("altered vocabulary accepted") }
        catch SemanticModelPackage.PackageError.invalid { print("PASS: pinned vocabulary hash rejects modified tokenizer bytes") }
        do { _ = try MiniLMTokenizer(vocabularyText: "[PAD]\n[UNK]\n"); preconditionFailure("incompatible vocabulary accepted") }
        catch MiniLMTokenizer.TokenError.vocabulary { print("PASS: incompatible vocabulary layout is rejected") }
        let axis = [Float](repeating: 1, count: 384)
        check(abs((MiniLMEncoder.similarity(axis, axis) ?? 0) - 1) < 0.00001, "semantic ranking normalizes actual vectors instead of assuming a distance scale")
        check(MiniLMEncoder.similarity(axis, [Float](repeating: 0, count: 384)) == nil && MiniLMEncoder.similarity(axis, [Float](repeating: .nan, count: 384)) == nil && MiniLMEncoder.similarity(axis, [1]) == nil, "invalid zero nonfinite and wrong-dimension vectors cannot become ranking scores")
        check(SemanticModelPackage.downloadBytes == 45_012_149 && Set(SemanticModelPackage.assets.map(\.path)).count == 3 && SemanticModelPackage.assets.allSatisfy { $0.url.scheme == "https" && $0.url.host == "huggingface.co" && $0.url.path.contains(SemanticModelPackage.revision) }, "model assets have a bounded fixed total and immutable revision URLs")
        check(HybridLibrarySearch.fused(keyword: [1, 2, 3], related: [4, 2, 5]).first == 1 && HybridLibrarySearch.fused(keyword: [1, 2, 3], related: [4, 2, 5])[1] == 2, "hybrid ranking preserves the leading keyword hit and promotes agreement between independent rankings")
        check(HybridLibrarySearch.fused(keyword: [], related: [9, 8]) == [9, 8], "meaning-only candidates remain eligible when no exact keywords match")
        let invalidAudit = MeaningSearchAudit(status: .used, modelID: SemanticModelPackage.identifier, indexedPassages: 2, comparedPassages: 3)
        check(!invalidAudit.isValid && !MeaningSearchAudit(status: .used, indexedPassages: 2).isValid, "meaning-search metadata rejects impossible coverage and missing model identity")
    }
}
