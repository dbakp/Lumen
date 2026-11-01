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
    static func indexTiming(input: URL, protocolURL: URL, output: URL) throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure.outputExists }
        let configData = try Data(contentsOf: input), protocolData = try Data(contentsOf: protocolURL)
        let config = try JSONDecoder().decode(Configuration.self, from: configData)
        guard let policy = try JSONSerialization.jsonObject(with: protocolData) as? [String: Any],
              policy["name"] as? String == "per-search-title-key-performance",
              let ids = policy["queryIDs"] as? [String], ids.count == 7,
              config.split == "dev", config.expectedDocuments == 3633, config.expectedQueries == 324 else { throw Failure.invalidInput("timing protocol") }
        let queryData = try read(config.queries)
        guard digest(queryData) == policy["originalDevQueriesSHA256"] as? String else { throw Failure.invalidInput("timing queries") }
        let queries = try lines(Question.self, data: queryData)
        guard queries.count == config.expectedQueries,
              Array(queries.map(\.id).sorted { digest(Data($0.utf8)) < digest(Data($1.utf8)) }.prefix(7)) == ids else { throw Failure.invalidInput("timing selection") }
        let raw = try lines(Document.self, data: read(config.corpus))
        guard raw.count == config.expectedDocuments, Set(raw.map(\._id)).count == raw.count else { throw Failure.invalidInput("timing corpus") }
        let documents = raw.map { HealthDocument(id: $0._id, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), title: $0.title, kind: .record, body: $0.text, source: config.sourceLabel, includeInAssistant: true) }
        func signature(_ index: RecordSearchIndex) throws -> String {
            guard !index.context.limited, index.context.searchedDocuments == documents.count else { throw Failure.incompleteIndex }
            let rows: [[String: Any]] = index.rows.keys.sorted().map { row in
                let p = index.rows[row]!
                return ["row": row, "documentID": p.documentID, "title": p.title, "source": p.source, "start": p.start, "end": p.end, "ordinal": p.ordinal,
                        "page": p.page.map { $0 as Any } ?? NSNull(), "sourceSHA256": p.textSHA256, "excerptSHA256": digest(Data(p.excerpt.utf8))]
            }
            let object: [String: Any] = ["rows": rows, "keywordRows": index.keywordRows, "literalIdentifiers": index.literalIdentifiers.sorted(),
                                         "sharedDocuments": index.context.sharedDocuments, "searchedDocuments": index.context.searchedDocuments, "limited": index.context.limited]
            return digest(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        }
        var warmed: [String: String] = [:], measured: [[String: Any]] = []
        for id in ids {
            guard let query = queries.first(where: { $0.id == id }) else { throw Failure.invalidInput("timing ID") }
            warmed[id] = try signature(RecordRetrieval.candidates(query: query.text, documents: documents, now: Date(timeIntervalSince1970: 0)))
        }
        for id in ids {
            let query = queries.first { $0.id == id }!
            let started = ProcessInfo.processInfo.systemUptime
            let index = try RecordRetrieval.candidates(query: query.text, documents: documents, now: Date(timeIntervalSince1970: 0))
            let seconds = ProcessInfo.processInfo.systemUptime - started
            let hash = try signature(index)
            guard hash == warmed[id] else { throw Failure.oracle }
            measured.append(["queryID": id, "seconds": seconds, "indexSHA256": hash, "preparedPassages": index.rows.count, "keywordCandidates": index.keywordRows.count])
        }
        let report: [String: Any] = ["complete": true, "protocolSHA256": digest(protocolData), "configurationSHA256": digest(configData),
                                    "documents": documents.count, "queries": measured, "warmAndMeasuredSignaturesEqual": true,
                                    "scope": "Warmed Mac Release production candidates only; signature generation/input loading outside timer. No model/UI/provider/iPhone latency claim."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        print("Timed all seven predeclared questions; warm/measured full index signatures match.")
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

// Research-only joint reranking. The production app never loads these scores.
extension RetrievalSelectionProbe {
    struct RerankPassage: Codable, Equatable {
        var documentID: String; var start: Int; var end: Int; var ordinal: Int
        var sourceSHA256: String; var selection: String
        init(_ p: LibraryPassage) { documentID = p.documentID; start = p.start; end = p.end; ordinal = p.ordinal; sourceSHA256 = p.textSHA256; selection = p.selection?.rawValue ?? "absent" }
    }
    struct RerankRow: Codable, Equatable {
        var row: Int; var preparedID: String; var documentID: String; var start: Int; var end: Int
        var sourceSHA256: String; var text: String
    }
    struct RerankCase: Codable {
        var queryID: String; var query: String; var language: String; var baselineStatus: String
        var indexError: String?; var indexedPassages: Int; var baseline: [RerankPassage]; var pool: [RerankRow]
    }
    struct RerankPool: Codable {
        var version: Int; var split: String; var protocolSHA256: String; var configurationSHA256: String
        var preparedSHA256: String; var nativeCosineSpots: Int; var seconds: Double; var cases: [RerankCase]
    }
    struct RerankScore: Codable {
        var row: Int; var preparedID: String; var inputSHA256: String; var score: Double; var windows: Int
    }
    struct RerankScoresCase: Codable {
        var queryID: String; var status: String; var scores: [RerankScore]
    }
    struct RerankScores: Codable {
        var version: Int; var protocolSHA256: String; var poolSHA256: String
        var modelRevision: String; var weightsSHA256: String; var cases: [RerankScoresCase]
    }
    private struct RerankWorkspace {
        var config: Configuration; var configHash: String; var protocolHash: String
        var queries: [Question]; var documents: [HealthDocument]; var prepared: [Prepared]
        var positions: [Identity: Int]; var scores: [Double]; var statuses: [String]; var spots: Int
        init(input: URL, protocolURL: URL) throws {
            let data = try Data(contentsOf: input), policyData = try Data(contentsOf: protocolURL)
            guard data.count <= 2_000_000, policyData.count <= 100_000, digest(policyData) == "3551921b67fba043d21be0db174976633b144e2de0eecd64361e3108059ebd0c",
                  let policy = try JSONSerialization.jsonObject(with: policyData) as? [String: Any],
                  policy["name"] as? String == "question-passage-cross-encoder-dev",
                  let inputs = policy["inputs"] as? [String: String],
                  let pool = policy["candidatePool"] as? [String: Any], pool["limit"] as? Int == 64,
                  HybridLibrarySearch.minimumSimilarity == 0.42 else { throw Failure.invalidInput("rerank protocol") }
            config = try JSONDecoder().decode(Configuration.self, from: data)
            guard config.version == 1, ["dev", "challenge"].contains(config.split),
                  digest(data) == inputs[config.split + "ConfigurationSHA256"],
                  digest(try read(config.protocolFile)) == inputs["selectionProtocolSHA256"] else { throw Failure.invalidInput("rerank frozen input") }
            configHash = digest(data); protocolHash = digest(policyData)
            let raw = try lines(Document.self, data: read(config.corpus))
            queries = try lines(Question.self, data: read(config.queries))
            prepared = try lines(Prepared.self, data: read(config.prepared))
            guard raw.count == config.expectedDocuments, queries.count == config.expectedQueries, prepared.count == config.expectedPassages,
                  Set(raw.map(\._id)).count == raw.count, Set(queries.map(\.id)).count == queries.count,
                  prepared.enumerated().allSatisfy({ $1.id == String($0) }), Set(prepared.map(Identity.init)).count == prepared.count else { throw Failure.invalidInput("rerank complete identities") }
            let sourceLabel = config.sourceLabel
            documents = raw.map { HealthDocument(id: $0._id, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), title: $0.title, kind: .record, body: $0.text, source: sourceLabel, includeInAssistant: true) }
            positions = Dictionary(uniqueKeysWithValues: prepared.enumerated().map { (Identity($1), $0) })
            guard let baseline = config.models.first(where: { $0.id == "baseline" }), config.models.filter({ $0.id == "baseline" }).count == 1 else { throw Failure.invalidInput("rerank baseline") }
            let matrix = try read(baseline.scores), count = queries.count * prepared.count
            guard matrix.count == count * 8, baseline.queryStatuses.count == queries.count,
                  baseline.queryStatuses.allSatisfy({ ["used", "empty", "queryTooLong", "inputLimit"].contains($0) }) else { throw Failure.invalidInput("rerank score shape") }
            scores = matrix.withUnsafeBytes { raw in (0..<count).map { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) } }
            guard scores.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { throw Failure.invalidInput("rerank score values") }
            statuses = baseline.queryStatuses
            let controls = config.spots.filter { $0.model == "baseline" }; spots = controls.count
            guard spots >= 9 else { throw Failure.invalidInput("rerank native spots") }
            for spot in controls {
                guard queries.indices.contains(spot.queryIndex), prepared.indices.contains(spot.passageIndex), !spot.windows.isEmpty else { throw Failure.invalidInput("rerank spot identity") }
                let similarities = spot.windows.compactMap { MiniLMEncoder.similarity(spot.queryVector, $0) }
                guard similarities.count == spot.windows.count, let maximum = similarities.max(), abs(maximum - scores[spot.queryIndex * prepared.count + spot.passageIndex]) <= 1e-12 else { throw Failure.oracle }
            }
        }
        func index(_ q: Question, documents current: [HealthDocument]? = nil) throws -> RecordSearchIndex {
            let result = try RecordRetrieval.candidates(query: q.text, documents: current ?? documents, now: Date(timeIntervalSince1970: 0))
            guard !result.context.limited, result.context.searchedDocuments == (current ?? documents).filter(\.includeInAssistant).count else { throw Failure.incompleteIndex }
            for passage in result.rows.values {
                guard let position = positions[Identity(passage)], prepared[position].ordinal == passage.ordinal,
                      prepared[position].text == String(passage.title.prefix(160)) + "\n" + passage.excerpt else { throw Failure.mismatchedSource }
            }
            return result
        }
        func ranking(_ index: RecordSearchIndex, position: Int) throws -> (order: [Int], related: Set<Int>, audit: MeaningSearchAudit) {
            var audit = MeaningSearchAudit(status: .off, indexedPassages: index.rows.count)
            if index.rows.isEmpty { audit.status = .notNeeded; return (index.keywordRows, [], audit) }
            if NLLanguageRecognizer.dominantLanguage(for: queries[position].text) != .english { audit.status = .unsupportedLanguage; return (index.keywordRows, [], audit) }
            audit.modelID = SemanticModelPackage.identifier
            guard statuses[position] == "used" else { audit.status = statuses[position] == "empty" ? .failed : .queryTooLong; return (index.keywordRows, [], audit) }
            audit.status = .used; audit.comparedPassages = index.rows.count
            var topics: [(Int, Double)] = []
            for (row, passage) in index.rows {
                guard let p = positions[Identity(passage)] else { throw Failure.mismatchedSource }
                let value = scores[position * prepared.count + p]
                if value >= 0.42 { topics.append((row, value)) }
            }
            topics.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
            return (HybridLibrarySearch.fused(keyword: index.keywordRows, related: topics.map(\.0)), Set(topics.map(\.0)), audit)
        }
        func pool(_ index: RecordSearchIndex, order: [Int]) throws -> [RerankRow] {
            try order.prefix(64).map { row in
                guard let p = index.rows[row], let n = positions[Identity(p)] else { throw Failure.mismatchedSource }
                return RerankRow(row: row, preparedID: prepared[n].id, documentID: p.documentID, start: p.start, end: p.end, sourceSHA256: p.textSHA256, text: prepared[n].text)
            }
        }
    }
    private static func rerankPacket(_ context: RecordReplyContext, documents: [HealthDocument]) throws -> [RerankPassage] {
        guard context.isValid, context.passages.allSatisfy({ RecordRetrieval.isCurrent($0, documents: documents) }) else { throw Failure.mismatchedSource }
        return context.passages.map(RerankPassage.init)
    }
    static func rerankPools(input: URL, protocolURL: URL, output: URL) throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure.outputExists }
        let work = try RerankWorkspace(input: input, protocolURL: protocolURL), started = ProcessInfo.processInfo.systemUptime
        var cases: [RerankCase] = []
        for (position, query) in work.queries.enumerated() {
            try Task.checkCancellation()
            let language = NLLanguageRecognizer.dominantLanguage(for: query.text)?.rawValue ?? "undetermined"
            do {
                let index = try work.index(query), rank = try work.ranking(index, position: position)
                let baseline = try RecordRetrieval.selecting(index, rankedRows: rank.order, relatedRows: rank.related, audit: rank.audit)
                let pool = language == NLLanguage.english.rawValue ? try work.pool(index, order: rank.order) : []
                cases.append(RerankCase(queryID: query.id, query: query.text, language: language, baselineStatus: rank.audit.status.rawValue, indexedPassages: index.rows.count, baseline: try rerankPacket(baseline, documents: work.documents), pool: pool))
            } catch let error as RecordRetrieval.SearchError {
                cases.append(RerankCase(queryID: query.id, query: query.text, language: language, baselineStatus: "indexError", indexError: String(describing: error), indexedPassages: 0, baseline: [], pool: []))
            }
            if (position + 1) % 25 == 0 { print("Prepared rerank pool \(position + 1)/\(work.queries.count).") }
        }
        let report = RerankPool(version: 1, split: work.config.split, protocolSHA256: work.protocolHash, configurationSHA256: work.configHash, preparedSHA256: work.config.prepared.sha256, nativeCosineSpots: work.spots, seconds: ProcessInfo.processInfo.systemUptime - started, cases: cases)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(report).write(to: output, options: .atomic)
        print("Prepared all\(cases.count) original-query rerank pools; native source/currentness checks pass.")
    }
    static func rerankSelect(input: URL, protocolURL: URL, poolURL: URL, scoresURL: URL, output: URL) throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure.outputExists }
        let work = try RerankWorkspace(input: input, protocolURL: protocolURL)
        let poolData = try Data(contentsOf: poolURL), scoreData = try Data(contentsOf: scoresURL)
        guard poolData.count <= 80_000_000, scoreData.count <= 20_000_000 else { throw Failure.invalidInput("rerank result size") }
        let pool = try JSONDecoder().decode(RerankPool.self, from: poolData), scores = try JSONDecoder().decode(RerankScores.self, from: scoreData)
        guard pool.version == 1, scores.version == 1, pool.split == work.config.split,
              pool.protocolSHA256 == work.protocolHash, scores.protocolSHA256 == work.protocolHash,
              pool.configurationSHA256 == work.configHash, pool.preparedSHA256 == work.config.prepared.sha256, pool.nativeCosineSpots == work.spots,
              scores.poolSHA256 == digest(poolData), scores.modelRevision == "233902d25c440f23af6f7d6e94d2946bac0bee0a",
              scores.weightsSHA256 == "821d1aa69520101d6e0737f78a042ae25b19e5cb9160701909d10434f4aeb0ae",
              pool.cases.count == work.queries.count, scores.cases.count == pool.cases.count else { throw Failure.invalidInput("rerank result identity") }
        let cutoffs: [Double?] = [nil, -8, -6, -4, -2, 0, 2, 4, 6, 8]
        var cases: [[String: Any]] = [], withdrawal = 0, carried = 0
        for (position, query) in work.queries.enumerated() {
            let saved = pool.cases[position], scored = scores.cases[position]
            guard saved.queryID == query.id, saved.query == query.text, scored.queryID == query.id else { throw Failure.invalidInput("rerank query identity") }
            let index: RecordSearchIndex
            do { index = try work.index(query) }
            catch let error as RecordRetrieval.SearchError {
                guard saved.indexError == String(describing: error), saved.pool.isEmpty, saved.baseline.isEmpty,
                      scored.status == "indexError", scored.scores.isEmpty else { throw Failure.invalidInput("rerank errored query") }
                cases.append(["queryID": query.id, "indexError": String(describing: error), "policies": cutoffs.map { ["cutoff": $0 as Any? ?? NSNull(), "passages": []] }]); continue
            }
            let rank = try work.ranking(index, position: position)
            guard saved.indexError == nil, saved.language == (NLLanguageRecognizer.dominantLanguage(for: query.text)?.rawValue ?? "undetermined"),
                  saved.indexedPassages == index.rows.count, saved.baselineStatus == rank.audit.status.rawValue else { throw Failure.invalidInput("rerank live query status") }
            let current = try RecordRetrieval.selecting(index, rankedRows: rank.order, relatedRows: rank.related, audit: rank.audit)
            guard try rerankPacket(current, documents: work.documents) == saved.baseline else { throw Failure.oracle }
            let expectedPool = saved.language == NLLanguage.english.rawValue ? try work.pool(index, order: rank.order) : []
            guard expectedPool == saved.pool else { throw Failure.mismatchedSource }
            let allowed = ["scored", "unsupportedLanguage", "notNeeded", "inputLimit"]
            guard allowed.contains(scored.status), Set(scored.scores.map(\.row)).count == scored.scores.count else { throw Failure.invalidInput("rerank scores status") }
            if scored.status == "scored" {
                guard !saved.pool.isEmpty, scored.scores.count == saved.pool.count else { throw Failure.invalidInput("rerank missing pair") }
                for (row, value) in zip(saved.pool, scored.scores) {
                    guard row.row == value.row, row.preparedID == value.preparedID, value.windows > 0, value.score.isFinite,
                          value.inputSHA256 == digest(Data((query.text + "\0" + row.text).utf8)) else { throw Failure.invalidInput("rerank pair identity") }
                }
            } else {
                guard scored.scores.isEmpty,
                      scored.status == "unsupportedLanguage" && saved.language != NLLanguage.english.rawValue ||
                      scored.status == "notNeeded" && saved.pool.isEmpty ||
                      scored.status == "inputLimit" && saved.language == NLLanguage.english.rawValue else { throw Failure.invalidInput("rerank unsupported status") }
            }
            let identities = Dictionary(uniqueKeysWithValues: zip(saved.pool, scored.scores).map { (Identity(index.rows[$0.0.row]!), $0.1.score) })
            func select(_ currentIndex: RecordSearchIndex, currentRank: (order: [Int], related: Set<Int>, audit: MeaningSearchAudit), cutoff: Double?) throws -> RecordReplyContext {
                let ranked: [Int]
                if scored.status == "unsupportedLanguage" { ranked = currentRank.order }
                else if scored.status != "scored" { ranked = [] }
                else {
                    let freshPool = try work.pool(currentIndex, order: currentRank.order)
                    let scoredRows = try freshPool.enumerated().map { n, row -> (Int, Double, Int) in
                        guard let p = currentIndex.rows[row.row], let value = identities[Identity(p)] else { throw Failure.invalidInput("rerank unscored fresh pool") }
                        return (row.row, value, n)
                    }
                    ranked = scoredRows.filter { cutoff == nil || $0.1 >= cutoff! }.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 > $1.1 }.map(\.0)
                }
                return try RecordRetrieval.selecting(currentIndex, rankedRows: ranked, relatedRows: currentRank.related, audit: currentRank.audit)
            }
            func attempt(_ currentIndex: RecordSearchIndex, currentRank: (order: [Int], related: Set<Int>, audit: MeaningSearchAudit), cutoff: Double?) throws -> (context: RecordReplyContext, error: String?) {
                do { return (try select(currentIndex, currentRank: currentRank, cutoff: cutoff), nil) }
                catch let error as RecordRetrieval.SearchError {
                    var empty = currentIndex.context; empty.passages = []; empty.meaningSearch = currentRank.audit
                    return (empty, String(describing: error))
                }
            }
            var policies: [[String: Any]] = []
            for cutoff in cutoffs {
                let selected = try attempt(index, currentRank: rank, cutoff: cutoff)
                let packet = try rerankPacket(selected.context, documents: work.documents)
                var result: [String: Any] = ["cutoff": cutoff as Any? ?? NSNull(),
                    "passages": try JSONSerialization.jsonObject(with: JSONEncoder().encode(packet))]
                if let error = selected.error { result["selectionError"] = error }
                if let expected = work.config.expectedSources[query.id], !expected.isEmpty {
                    var withdrawn = work.documents
                    for n in withdrawn.indices where expected.contains(withdrawn[n].id) { withdrawn[n].includeInAssistant = false }
                    let freshIndex = try work.index(query, documents: withdrawn), freshRank = try work.ranking(freshIndex, position: position)
                    let fresh = try attempt(freshIndex, currentRank: freshRank, cutoff: cutoff)
                    _ = try rerankPacket(fresh.context, documents: withdrawn)
                    guard !fresh.context.passages.contains(where: { expected.contains($0.documentID) }) else { throw Failure.oracle }; withdrawal += 1
                    let previous = [ChatMessage(role: .user, text: query.text), ChatMessage(role: .coach, text: "Synthetic retained reference", recordContext: selected.context)]
                    let followup = try RecordRetrieval.candidates(query: "Tell me more", documents: withdrawn, history: previous, now: Date(timeIntervalSince1970: 0))
                    guard !followup.carried.contains(where: { expected.contains($0.documentID) }) else { throw Failure.oracle }; carried += 1
                    result["withdrawalAndCarriedExclusionChecked"] = true
                    if let error = fresh.error { result["withdrawalSelectionError"] = error }
                }
                policies.append(result)
            }
            cases.append(["queryID": query.id, "language": saved.language, "rerankStatus": scored.status, "poolSize": saved.pool.count,
                          "baseline": try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved.baseline)), "policies": policies])
            if (position + 1) % 25 == 0 { print("Selected rerank packets \(position + 1)/\(work.queries.count).") }
        }
        let report: [String: Any] = ["version": 1, "complete": true, "split": pool.split, "protocolSHA256": work.protocolHash,
            "poolSHA256": digest(poolData), "scoresSHA256": digest(scoreData), "queries": cases.count,
            "withdrawalChecks": withdrawal, "carriedExclusionChecks": carried, "cases": cases,
            "scope": "Upstream FP32 relevance logits over current eligible first-stage pools; actual native final selector/currentness. No CoreML conversion, app model change, provider/clinical support or physical-device timing claim."]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: output, options: .atomic)
        print("Selected all\(cases.count) complete rerank cases under\(cutoffs.count) frozen cutoffs.")
    }
}
