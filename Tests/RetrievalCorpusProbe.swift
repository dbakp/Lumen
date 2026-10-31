import Foundation
import CryptoKit

/// Offline research only. Uses the complete production passage preparation;
/// never changes app bounds or silently evaluates an accepted corpus prefix.
enum RetrievalCorpusProbe {
    private struct Row: Decodable { var _id: String; var title: String; var text: String }
    private enum Failure: Error { case invalidInput, incompleteIndex, outputExists, mismatchedSource }
    static func prepare(input: URL, output: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: output.path) else { throw Failure.outputExists }
        let bytes = try Data(contentsOf: input)
        guard bytes.count <= 80_000_000, let text = String(data: bytes, encoding: .utf8) else { throw Failure.invalidInput }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var documents: [HealthDocument] = [], ids = Set<String>()
        for (position, line) in lines.enumerated() {
            if line.isEmpty && position == lines.count - 1 { continue }
            let row = try JSONDecoder().decode(Row.self, from: Data(line.utf8))
            guard !row._id.isEmpty, ids.insert(row._id).inserted else { throw Failure.invalidInput }
            documents.append(HealthDocument(id: row._id, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), title: row.title, kind: .record, body: row.text, source: "BEIR NFCorpus public research", includeInAssistant: true))
        }
        guard !documents.isEmpty else { throw Failure.invalidInput }
        let started = ProcessInfo.processInfo.systemUptime
        let index = try RecordRetrieval.candidates(query: "retrieval evaluation", documents: documents, now: Date(timeIntervalSince1970: 0))
        let represented = Set(index.rows.values.map(\.documentID))
        let missing = ids.subtracting(represented).sorted()
        let base: [String: Any] = ["version": 1, "inputSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "documents": documents.count, "searchedDocuments": index.context.searchedDocuments, "passages": index.rows.count, "limited": index.context.limited, "unrepresentedDocumentIDs": missing, "seconds": ProcessInfo.processInfo.systemUptime - started, "scope": "Actual RecordRetrieval.candidates complete corpus; title.prefix(160) + LF + exact prepared excerpt; offline model-only diagnostic, not live keyword fusion"]
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
