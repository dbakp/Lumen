import Foundation
import CryptoKit

/// Offline research only. Uses the complete production passage preparation;
/// never changes app bounds or silently evaluates an accepted corpus prefix.
enum RetrievalCorpusProbe {
    private struct Row: Decodable { var _id: String; var title: String; var text: String }
    private enum Failure: Error { case invalidInput, incompleteIndex, outputExists, mismatchedSource }
    static func keywordChallenge(input: URL, output: URL) throws {
        struct Fixture: Decodable {
            struct Document: Decodable { var id: String; var title: String; var body: String }
            struct Query: Decodable { var id: String; var text: String; var expectedDocumentIDs: [String] }
            var documents: [Document]; var queries: [Query]
        }
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure.outputExists }
        let data = try Data(contentsOf: input)
        guard data.count <= 1_000_000 else { throw Failure.invalidInput }
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        guard (1...100).contains(fixture.documents.count), (1...200).contains(fixture.queries.count), Set(fixture.documents.map(\.id)).count == fixture.documents.count,
              Set(fixture.queries.map(\.id)).count == fixture.queries.count,
              fixture.queries.allSatisfy({ Set($0.expectedDocumentIDs).isSubset(of: Set(fixture.documents.map(\.id))) }) else { throw Failure.invalidInput }
        let documents = fixture.documents.map { row in HealthDocument(id: row.id, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), title: row.title, kind: .record, body: row.body, source: "Synthetic retrieval development challenge; no personal data", includeInAssistant: true) }
        var rows: [[String: Any]] = []
        for query in fixture.queries {
            let context = try RecordRetrieval.search(query: query.text, documents: documents, now: Date(timeIntervalSince1970: 0))
            guard context.isValid, context.passages.allSatisfy({ RecordRetrieval.isCurrent($0, documents: documents) }) else { throw Failure.mismatchedSource }
            let selected = context.passages.map(\.documentID)
            var withdrawn = documents
            for index in withdrawn.indices where query.expectedDocumentIDs.contains(withdrawn[index].id) { withdrawn[index].includeInAssistant = false }
            let fresh = try RecordRetrieval.search(query: query.text, documents: withdrawn, now: Date(timeIntervalSince1970: 0))
            guard fresh.isValid, fresh.passages.allSatisfy({ RecordRetrieval.isCurrent($0, documents: withdrawn) }), !fresh.passages.contains(where: { query.expectedDocumentIDs.contains($0.documentID) }) else { throw Failure.mismatchedSource }
            rows.append(["queryID": query.id, "selectedDocumentIDs": selected, "expectedDocumentIDs": query.expectedDocumentIDs, "expectedInTop4": !Set(selected).isDisjoint(with: query.expectedDocumentIDs), "selectedCount": selected.count, "allPassagesCurrentAndValid": true, "sharingWithdrawalChecked": !query.expectedDocumentIDs.isEmpty, "localReply": RecordRetrieval.localReply(context, query: query.text).0])
        }
        let report: [String: Any] = ["fixtureSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "queries": rows, "scope": "Actual production keyword search, four-passage selection, source/current-sharing validation and literal local reply; not topic fusion or live provider correctness"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        print("Recorded \(rows.count) actual keyword/source/local-reply challenge cases.")
    }
    static func prepare(input: URL, output: URL, sourceLabel: String = "BEIR NFCorpus public research") throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: output.path) else { throw Failure.outputExists }
        guard !sourceLabel.isEmpty, sourceLabel.count <= 500, sourceLabel.utf8.count <= 4000 else { throw Failure.invalidInput }
        let bytes = try Data(contentsOf: input)
        guard bytes.count <= 80_000_000, let text = String(data: bytes, encoding: .utf8) else { throw Failure.invalidInput }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var documents: [HealthDocument] = [], ids = Set<String>()
        for (position, line) in lines.enumerated() {
            if line.isEmpty && position == lines.count - 1 { continue }
            let row = try JSONDecoder().decode(Row.self, from: Data(line.utf8))
            guard !row._id.isEmpty, ids.insert(row._id).inserted else { throw Failure.invalidInput }
            documents.append(HealthDocument(id: row._id, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), title: row.title, kind: .record, body: row.text, source: sourceLabel, includeInAssistant: true))
        }
        guard !documents.isEmpty else { throw Failure.invalidInput }
        let started = ProcessInfo.processInfo.systemUptime
        let index = try RecordRetrieval.candidates(query: "retrieval evaluation", documents: documents, now: Date(timeIntervalSince1970: 0))
        let represented = Set(index.rows.values.map(\.documentID))
        let missing = ids.subtracting(represented).sorted()
        let base: [String: Any] = ["version": 1, "sourceLabel": sourceLabel, "inputSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "documents": documents.count, "searchedDocuments": index.context.searchedDocuments, "passages": index.rows.count, "limited": index.context.limited, "unrepresentedDocumentIDs": missing, "seconds": ProcessInfo.processInfo.systemUptime - started, "scope": "Actual RecordRetrieval.candidates complete corpus; title.prefix(160) + LF + exact prepared excerpt; offline model-only diagnostic, not live keyword fusion"]
        guard !index.context.limited, index.context.searchedDocuments == documents.count, represented == ids else {
            // No passage output on exclusion. Caller retains this failure fact.
            FileHandle.standardError.write(try JSONSerialization.data(withJSONObject: base, options: [.prettyPrinted, .sortedKeys]))
            throw Failure.incompleteIndex
        }
        let originals = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        var data = Data()
        let rows = index.rows.values.sorted { $0.documentID == $1.documentID ? $0.ordinal < $1.ordinal : $0.documentID < $1.documentID }
        for (position, passage) in rows.enumerated() {
            guard let original = originals[passage.documentID], let canonical = RecordRetrieval.text(original), String(canonical.dropFirst(passage.start).prefix(passage.end - passage.start)) == passage.excerpt,
                  RecordRetrieval.fingerprint(original) == passage.textSHA256 else { throw Failure.mismatchedSource }
            let encoded: [String: Any] = ["id": String(position), "documentID": passage.documentID, "ordinal": passage.ordinal, "start": passage.start, "end": passage.end, "sourceSHA256": passage.textSHA256, "text": String(passage.title.prefix(160)) + "\n" + passage.excerpt]
            data.append(try JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys])); data.append(10)
        }
        try fm.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            try data.write(to: output.appendingPathComponent("passages.jsonl"), options: .atomic)
            var report = base
            report["preparedSHA256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("preparation.json"), options: .atomic)
        } catch { try? fm.removeItem(at: output); throw error }
        print("Prepared all \(documents.count) documents as \(rows.count) passages; no exclusions.")
    }
}
