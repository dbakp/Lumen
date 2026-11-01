import Foundation
import CryptoKit
import NaturalLanguage

/// Research-only replay. The app's index, fusion and final selector run unchanged;
/// verified offline vectors replace inference, without simulating its time budget.
enum RetrievalSelectionProbe {
    struct Input: Codable { var path: String; var sha256: String }
    struct Model: Decodable {
        var id: String; var scores: Input; var queryStatuses: [String]
    }
    struct Spot: Decodable {
        var model: String; var queryIndex: Int; var passageIndex: Int
        var queryVector: [Float]; var windows: [[Float]]
    }
    struct Configuration: Decodable {
        var version: Int; var split: String; var protocolFile: Input
        var corpus: Input; var queries: Input; var prepared: Input
        var sourceLabel: String; var expectedDocuments: Int; var expectedQueries: Int; var expectedPassages: Int
        var models: [Model]; var spots: [Spot]; var expectedSources: [String: [String]]
    }
    struct Document: Decodable { var _id: String; var title: String; var text: String }
    struct Question: Decodable { var id: String; var text: String }
    struct Prepared: Decodable {
        var id: String; var documentID: String; var ordinal: Int
        var start: Int; var end: Int; var sourceSHA256: String; var text: String
    }
    struct Identity: Hashable {
        var documentID: String; var start: Int; var end: Int; var fingerprint: String
        init(_ p: LibraryPassage) { documentID = p.documentID; start = p.start; end = p.end; fingerprint = p.textSHA256 }
        init(_ p: Prepared) { documentID = p.documentID; start = p.start; end = p.end; fingerprint = p.sourceSHA256 }
    }
    private struct Policy {
        var id: String; var model: String?; var cutoff: Double?
    }
    enum Failure: Error { case invalidInput(String), outputExists, mismatchedSource, incompleteIndex, oracle }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func read(_ input: Input, limit: Int = 80_000_000) throws -> Data {
        let url = URL(fileURLWithPath: input.path)
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw Failure.invalidInput("symlink") }
        let data = try Data(contentsOf: url)
        guard data.count <= limit, digest(data) == input.sha256 else { throw Failure.invalidInput("hash or size") }
        return data
    }
    private static func lines<T: Decodable>(_ type: T.Type, data: Data) throws -> [T] {
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalidInput("UTF8") }
        return try text.split(separator: "\n").map { try JSONDecoder().decode(type, from: Data($0.utf8)) }
    }
    static func run(input: URL, output: URL) throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure.outputExists }
        let configData = try Data(contentsOf: input)
        guard configData.count <= 2_000_000 else { throw Failure.invalidInput("config") }
        let config = try JSONDecoder().decode(Configuration.self, from: configData)
        guard config.version == 1, ["dev", "challenge"].contains(config.split), (1...5000).contains(config.expectedDocuments),
              (1...1000).contains(config.expectedQueries), (1...30000).contains(config.expectedPassages),
              Set(config.models.map(\.id)) == ["baseline", "candidate"], config.models.count == 2 else { throw Failure.invalidInput("configuration") }
        let protocolData = try read(config.protocolFile)
        guard let protocolObject = try JSONSerialization.jsonObject(with: protocolData) as? [String: Any],
              protocolObject["name"] as? String == "complete-selection-dev-replay",
              let declared = protocolObject["policies"] as? [[String: Any]], declared.count == 3,
              let cutoffs = declared[2]["cutoffs"] as? [Any], cutoffs.count == 10,
              (declared[1]["cutoff"] as? Double) == HybridLibrarySearch.minimumSimilarity else { throw Failure.invalidInput("protocol") }
        let expectedCutoffs: [Double?] = [nil, 0.42, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9]
        guard zip(cutoffs, expectedCutoffs).allSatisfy({ raw, expected in expected.map { (raw as? Double) == $0 } ?? (raw is NSNull) }) else { throw Failure.invalidInput("cutoff grid") }
        let rawDocuments = try lines(Document.self, data: read(config.corpus))
        let queries = try lines(Question.self, data: read(config.queries))
        let prepared = try lines(Prepared.self, data: read(config.prepared))
        guard rawDocuments.count == config.expectedDocuments, queries.count == config.expectedQueries, prepared.count == config.expectedPassages,
              Set(rawDocuments.map(\._id)).count == rawDocuments.count, Set(queries.map(\.id)).count == queries.count,
              prepared.enumerated().allSatisfy({ $1.id == String($0) }), Set(prepared.map(Identity.init)).count == prepared.count,
              config.expectedSources.keys.allSatisfy({ id in queries.contains { $0.id == id } }),
              config.expectedSources.values.allSatisfy({ Set($0).isSubset(of: Set(rawDocuments.map(\._id))) }) else { throw Failure.invalidInput("complete identities") }
        if config.split == "challenge" && config.expectedSources.count != queries.count { throw Failure.invalidInput("challenge labels") }
        if config.split == "dev" && !config.expectedSources.isEmpty { throw Failure.invalidInput("dev labels supplied to native replay") }
        let documents = rawDocuments.map { HealthDocument(id: $0._id, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), title: $0.title, kind: .record, body: $0.text, source: config.sourceLabel, includeInAssistant: true) }
        let positions = Dictionary(uniqueKeysWithValues: prepared.enumerated().map { (Identity($1), $0) })
        let universe = try RecordRetrieval.candidates(query: "retrieval evaluation", documents: documents, now: Date(timeIntervalSince1970: 0))
        guard !universe.context.limited, universe.context.searchedDocuments == documents.count, universe.rows.count == prepared.count else { throw Failure.incompleteIndex }
        for p in universe.rows.values {
            guard let position = positions[Identity(p)], prepared[position].ordinal == p.ordinal,
                  prepared[position].text == String(p.title.prefix(160)) + "\n" + p.excerpt else { throw Failure.mismatchedSource }
        }
        var scores: [String: [Double]] = [:]
        for model in config.models {
            let data = try read(model.scores)
            let count = queries.count * prepared.count
            guard data.count == count * 8, model.queryStatuses.count == queries.count,
                  model.queryStatuses.allSatisfy({ ["used", "empty", "queryTooLong", "inputLimit"].contains($0) }) else { throw Failure.invalidInput("score shape") }
            let values = data.withUnsafeBytes { raw in (0..<count).map { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) } }
            guard values.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { throw Failure.invalidInput("score values") }
            scores[model.id] = values
        }
        guard config.spots.count >= 18 else { throw Failure.invalidInput("missing native cosine spots") }
        for spot in config.spots {
            guard let values = scores[spot.model], queries.indices.contains(spot.queryIndex), prepared.indices.contains(spot.passageIndex), !spot.windows.isEmpty else { throw Failure.invalidInput("spot identity") }
            let similarities = spot.windows.compactMap { MiniLMEncoder.similarity(spot.queryVector, $0) }
            guard similarities.count == spot.windows.count, let maximum = similarities.max(),
                  abs(maximum - values[spot.queryIndex * prepared.count + spot.passageIndex]) <= 1e-12 else { throw Failure.oracle }
        }
        guard HybridLibrarySearch.fused(keyword: [9, 1, 2], related: [2, 3, 1]) == [9, 2, 1, 3] else { throw Failure.oracle }
        let policies = [Policy(id: "keyword", model: nil, cutoff: nil), Policy(id: "minilm-production-042", model: "baseline", cutoff: 0.42)] + expectedCutoffs.map { Policy(id: "medembed-instructed-" + ($0.map { String($0) } ?? "no-cutoff"), model: "candidate", cutoff: $0) }
        func selected(_ index: RecordSearchIndex, queryPosition: Int, policy: Policy, language: NLLanguage?) throws -> RecordReplyContext {
            var audit = MeaningSearchAudit(status: .off, indexedPassages: index.rows.count)
            var ranked = index.keywordRows, related = Set<Int>()
            if let model = policy.model {
                if index.rows.isEmpty { audit.status = .notNeeded }
                else if language != .english { audit.status = .unsupportedLanguage }
                else {
                    audit.modelID = model == "baseline" ? SemanticModelPackage.identifier : "research-medembed-instructed-r3"
                    let state = config.models.first { $0.id == model }!.queryStatuses[queryPosition]
                    if state != "used" { audit.status = state == "empty" ? .failed : .queryTooLong }
                    else {
                        audit.status = .used; audit.comparedPassages = index.rows.count
                        let base = queryPosition * prepared.count
                        let values = scores[model]!
                        var topics: [(row: Int, score: Double)] = []
                        for (row, passage) in index.rows {
                            guard let position = positions[Identity(passage)] else { throw Failure.mismatchedSource }
                            let score = values[base + position]
                            if policy.cutoff == nil || score >= policy.cutoff! { topics.append((row, score)) }
                        }
                        topics.sort { $0.score == $1.score ? $0.row < $1.row : $0.score > $1.score }
                        related = Set(topics.map(\.row))
                        ranked = HybridLibrarySearch.fused(keyword: index.keywordRows, related: topics.map(\.row))
                    }
                }
            }
            return try RecordRetrieval.selecting(index, rankedRows: ranked, relatedRows: related, audit: audit)
        }
        func packet(_ context: RecordReplyContext, documents current: [HealthDocument]) throws -> [[String: Any]] {
            guard context.isValid, context.passages.count <= 4, context.passages.allSatisfy({ $0.selection != nil && RecordRetrieval.isCurrent($0, documents: current) }) else { throw Failure.mismatchedSource }
            return context.passages.map { ["documentID": $0.documentID, "start": $0.start, "end": $0.end, "ordinal": $0.ordinal, "sourceSHA256": $0.textSHA256, "selection": $0.selection!.rawValue] }
        }
        let started = ProcessInfo.processInfo.systemUptime
        var cases: [[String: Any]] = [], keywordOracles = 0, ceilingOracles = 0, withdrawalChecks = 0, carryChecks = 0
        for (position, query) in queries.enumerated() {
            try Task.checkCancellation()
            let language = NLLanguageRecognizer.dominantLanguage(for: query.text)
            let index: RecordSearchIndex
            do { index = try RecordRetrieval.candidates(query: query.text, documents: documents, now: Date(timeIntervalSince1970: 0)) }
            catch let error as RecordRetrieval.SearchError {
                cases.append(["queryID": query.id, "language": language?.rawValue ?? "undetermined", "indexError": String(describing: error), "policies": policies.map { ["id": $0.id, "passages": []] as [String: Any] }]); continue
            }
            guard !index.context.limited, index.context.searchedDocuments == documents.count else { throw Failure.incompleteIndex }
            let keyword = try selected(index, queryPosition: position, policy: policies[0], language: language)
            let normal = try RecordRetrieval.search(query: query.text, documents: documents, now: Date(timeIntervalSince1970: 0))
            guard keyword.passages.map(Identity.init) == normal.passages.map(Identity.init) else { throw Failure.oracle }; keywordOracles += 1
            let ceiling = try selected(index, queryPosition: position, policy: Policy(id: "ceiling-control", model: "baseline", cutoff: 1.000001), language: language)
            guard ceiling.passages.map(Identity.init) == keyword.passages.map(Identity.init) else { throw Failure.oracle }; ceilingOracles += 1
            var results: [[String: Any]] = []
            for policy in policies {
                let context = try selected(index, queryPosition: position, policy: policy, language: language)
                let passages = try packet(context, documents: documents)
                var result: [String: Any] = ["id": policy.id, "passages": passages, "status": context.meaningSearch?.status.rawValue ?? "absent", "comparedPassages": context.meaningSearch?.comparedPassages ?? 0]
                if let expected = config.expectedSources[query.id], !expected.isEmpty {
                    var withdrawn = documents
                    for n in withdrawn.indices where expected.contains(withdrawn[n].id) { withdrawn[n].includeInAssistant = false }
                    let freshIndex = try RecordRetrieval.candidates(query: query.text, documents: withdrawn, now: Date(timeIntervalSince1970: 0))
                    let fresh = try selected(freshIndex, queryPosition: position, policy: policy, language: language)
                    _ = try packet(fresh, documents: withdrawn)
                    guard !fresh.passages.contains(where: { expected.contains($0.documentID) }) else { throw Failure.mismatchedSource }; withdrawalChecks += 1
                    let history = [ChatMessage(role: .user, text: query.text), ChatMessage(role: .coach, text: "Synthetic retained source", recordContext: context)]
                    let followup = try RecordRetrieval.candidates(query: "Tell me more", documents: withdrawn, history: history, now: Date(timeIntervalSince1970: 0))
                    guard !followup.carried.contains(where: { expected.contains($0.documentID) }) else { throw Failure.mismatchedSource }; carryChecks += 1
                    result["withdrawalAndCarriedExclusionChecked"] = true
                }
                results.append(result)
            }
            cases.append(["queryID": query.id, "language": language?.rawValue ?? "undetermined", "indexedPassages": index.rows.count, "keywordCandidates": index.keywordRows.count, "policies": results])
            if (position + 1) % 25 == 0 { print("Replayed \(position + 1)/\(queries.count) complete questions through \(policies.count) native policies.") }
        }
        let report: [String: Any] = ["version": 1, "complete": true, "split": config.split, "protocolSHA256": digest(protocolData), "configurationSHA256": digest(configData), "documents": documents.count, "preparedPassages": prepared.count, "queries": queries.count, "seconds": ProcessInfo.processInfo.systemUptime - started, "nativeCosineSpots": config.spots.count, "keywordSelectionOracles": keywordOracles, "noRelatedCeilingOracles": ceilingOracles, "withdrawalChecks": withdrawalChecks, "carriedExclusionChecks": carryChecks, "allSelectedSourcesCurrentAndValid": true, "scope": "Offline complete-vector replay through actual current native index, original-query language gate, RRF fusion and four-passage selector. No live inference/cache/budget/provider or iPhone timing claim.", "cases": cases]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        print("Completed \(queries.count) questions; \(policies.count) policies; all source and integrity checks passed.")
    }
}
