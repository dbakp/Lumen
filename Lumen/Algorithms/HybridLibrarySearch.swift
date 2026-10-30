import Foundation
import NaturalLanguage

public struct MeaningSearchAudit: Codable, Sendable {
    public enum Status: String, Codable, Sendable { case off, unavailable, unsupportedLanguage, queryTooLong, used, failed, notNeeded }
    public var status: Status
    public var modelID: String? = nil
    public var indexedPassages: Int
    public var comparedPassages = 0
    public var cachedPassages = 0
    public var limited = false
    public var isValid: Bool {
        (0...RecordRetrieval.maxPassages).contains(indexedPassages) && (0...indexedPassages).contains(comparedPassages) &&
        (0...comparedPassages).contains(cachedPassages) && (modelID.map { $0.range(of: #"^[a-z0-9][a-z0-9._-]{0,159}$"#, options: .regularExpression) != nil } ?? true) &&
        (status != .used || (modelID != nil && comparedPassages > 0))
    }
}

enum HybridLibrarySearch {
    // Topic matching is not entailment, a diagnosis or a confidence estimate.
    static let minimumSimilarity = 0.42

    static func search(query: String, documents: [HealthDocument], history: [ChatMessage] = [], encoder: MiniLMEncoder?, enabled: Bool,
                       timeBudget: TimeInterval = 12) async throws -> RecordReplyContext {
        let index = try RecordRetrieval.candidates(query: query, documents: documents, history: history)
        var audit = MeaningSearchAudit(status: enabled ? .unavailable : .off, indexedPassages: index.rows.count)
        func keyword() throws -> RecordReplyContext { try RecordRetrieval.selecting(index, rankedRows: index.keywordRows, audit: audit) }
        guard enabled, let encoder else { return try keyword() }
        func key(_ passage: LibraryPassage) -> String { "\(passage.textSHA256):\(passage.start):\(passage.end)" }
        await encoder.retainCache(keys: Set(index.rows.values.map(key)))
        guard !index.rows.isEmpty, index.carried.count < 4 else { audit.status = .notNeeded; return try keyword() }
        let input: String
        if RecordRetrieval.followup(query), let previous = history.last(where: { $0.role == .user && !RecordRetrieval.words($0.text).isEmpty }) {
            input = previous.text + "\n" + query
        } else { input = query }
        guard NLLanguageRecognizer.dominantLanguage(for: input) == .english else { audit.status = .unsupportedLanguage; return try keyword() }
        audit.modelID = SemanticModelPackage.identifier
        let queryVector: [Float]
        do { queryVector = try await encoder.queryVector(input) }
        catch is CancellationError { throw CancellationError() }
        catch MiniLMEncoder.EncoderError.queryTooLong { audit.status = .queryTooLong; return try keyword() }
        catch MiniLMTokenizer.TokenError.inputLimit { audit.status = .queryTooLong; return try keyword() }
        catch { audit.status = .failed; return try keyword() }
        // Round-robin by within-document ordinal: one long/new record cannot
        // consume the entire meaning-search budget before other records begin.
        let order = index.rows.keys.sorted {
            let a = index.rows[$0]!.ordinal, b = index.rows[$1]!.ordinal
            return a == b ? $0 < $1 : a < b
        }
        let started = ProcessInfo.processInfo.systemUptime
        let budget = timeBudget.isFinite ? min(12, max(0, timeBudget)) : 0
        var related: [(Int, Double)] = []
        for row in order {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.systemUptime - started >= budget { audit.limited = true; break }
            let passage = index.rows[row]!
            do {
                let encoded = try await encoder.passageVectors(String(passage.title.prefix(160)) + "\n" + passage.excerpt, key: key(passage))
                let score = encoded.vectors.compactMap { MiniLMEncoder.similarity(queryVector, $0) }.max()
                guard let score else { audit.status = .failed; return try keyword() }
                audit.comparedPassages += 1
                if encoded.cached { audit.cachedPassages += 1 }
                if score >= minimumSimilarity { related.append((row, score)) }
            } catch is CancellationError { throw CancellationError() }
            catch MiniLMTokenizer.TokenError.inputLimit { audit.limited = true; continue }
            catch MiniLMEncoder.EncoderError.empty { audit.limited = true; continue }
            catch { audit.status = .failed; return try keyword() }
        }
        guard audit.comparedPassages > 0 else { audit.status = .notNeeded; return try keyword() }
        audit.status = .used
        related.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        let ranked = fused(keyword: index.keywordRows, related: related.map(\.0))
        return try RecordRetrieval.selecting(index, rankedRows: ranked, relatedRows: Set(related.map(\.0)), audit: audit)
    }

    static func fused(keyword: [Int], related: [Int]) -> [Int] {
        var scores: [Int: Double] = [:], keywordRanks: [Int: Int] = [:]
        for (rank, row) in keyword.enumerated() { scores[row, default: 0] += 1 / Double(60 + rank + 1); keywordRanks[row] = rank }
        for (rank, row) in related.enumerated() { scores[row, default: 0] += 1 / Double(60 + rank + 1) }
        let result = scores.keys.sorted {
            if scores[$0] != scores[$1] { return scores[$0]! > scores[$1]! }
            if keywordRanks[$0] != keywordRanks[$1] { return (keywordRanks[$0] ?? .max) < (keywordRanks[$1] ?? .max) }
            return $0 < $1
        }
        // Retain the leading literal match; related-topic results supplement it.
        guard let first = keyword.first else { return result }
        return [first] + result.filter { $0 != first }
    }
}
