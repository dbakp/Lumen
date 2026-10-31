import Foundation
import CryptoKit
import Darwin

/// Complete offline corpus/query encoder, separate from the live search budget.
@main struct EmbeddingCorpusProbe {
    struct Input: Decodable { var id: String; var documentID: String?; var text: String }
    enum Failure: Error { case arguments, duplicateID, invalidVector, outputExists }
    static func main() async {
        setbuf(stdout, nil)
        do { try await run() }
        catch { FileHandle.standardError.write(Data(("Corpus encoding failed: \(error)\n").utf8)); exit(1) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 6, ["passages", "queries"].contains(CommandLine.arguments[5]) else { throw Failure.arguments }
        let fm = FileManager.default, compiled = URL(fileURLWithPath: CommandLine.arguments[1]), inputURL = URL(fileURLWithPath: CommandLine.arguments[3]), output = URL(fileURLWithPath: CommandLine.arguments[4]), kind = CommandLine.arguments[5]
        guard !fm.fileExists(atPath: output.path) else { throw Failure.outputExists }
        let vocabulary = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])), input = try Data(contentsOf: inputURL)
        guard input.count <= 80_000_000, let text = String(data: input, encoding: .utf8) else { throw Failure.arguments }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var samples: [Input] = [], ids = Set<String>()
        for (position, line) in lines.enumerated() {
            if line.isEmpty && position == lines.count - 1 { continue }
            let sample = try JSONDecoder().decode(Input.self, from: Data(line.utf8))
            guard !sample.id.isEmpty, ids.insert(sample.id).inserted else { throw Failure.duplicateID }
            guard kind != "passages" || sample.documentID?.isEmpty == false else { throw Failure.arguments }
            samples.append(sample)
        }
        guard !samples.isEmpty, samples.count <= 30_000 else { throw Failure.arguments }
        let tokenizer = try SemanticModelPackage.tokenizer(vocabulary)
        let started = ProcessInfo.processInfo.systemUptime
        let encoder = try MiniLMEncoder(compiledModel: compiled, vocabulary: vocabulary)
        try fm.createDirectory(at: output, withIntermediateDirectories: false)
        let matrix = output.appendingPathComponent("vectors.f32le")
        guard fm.createFile(atPath: matrix.path, contents: nil) else { throw Failure.arguments }
        let handle = try FileHandle(forWritingTo: matrix); defer { try? handle.close() }
        var mapping: [[String: Any]] = [], count = 0, rejected = 0
        do {
            for (position, sample) in samples.enumerated() {
                var row: [String: Any] = ["id": sample.id, "offset": count]
                if let document = sample.documentID { row["documentID"] = document }
                let vectors: [[Float]]
                do {
                    if kind == "queries" { vectors = [try await encoder.queryVector(sample.text)] }
                    else { vectors = try await encoder.passageVectors(sample.text) }
                } catch MiniLMEncoder.EncoderError.queryTooLong where kind == "queries" {
                    row["status"] = "queryTooLong"; row["vectors"] = 0; mapping.append(row); rejected += 1; continue
                } catch MiniLMTokenizer.TokenError.inputLimit where kind == "queries" {
                    row["status"] = "inputLimit"; row["vectors"] = 0; mapping.append(row); rejected += 1; continue
                } catch MiniLMEncoder.EncoderError.empty where kind == "queries" {
                    row["status"] = "empty"; row["vectors"] = 0; mapping.append(row); rejected += 1; continue
                }
                let windows = try tokenizer.windows(sample.text)
                guard !vectors.isEmpty, vectors.count == windows.count else { throw Failure.invalidVector }
                var bytes = Data(capacity: vectors.count * SemanticModelPackage.dimension * 4)
                for vector in vectors {
                    guard vector.count == SemanticModelPackage.dimension, vector.allSatisfy(\.isFinite) else { throw Failure.invalidVector }
                    for value in vector { var bits = value.bitPattern.littleEndian; withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) } }
                }
                try handle.write(contentsOf: bytes)
                row["vectors"] = vectors.count; row["status"] = "used"; mapping.append(row); count += vectors.count
                if (position + 1) % 250 == 0 { print("Encoded \(position + 1)/\(samples.count) \(kind); \(count) complete vectors.") }
            }
            await encoder.stop()
            try handle.synchronize()
        } catch { await encoder.stop(); throw error }
        let matrixData = try Data(contentsOf: matrix, options: .mappedIfSafe)
        guard matrixData.count == count * SemanticModelPackage.dimension * 4 else { throw Failure.invalidVector }
        func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        var modelFiles: [[String: Any]] = []
        guard let enumerator = fm.enumerator(at: compiled, includingPropertiesForKeys: [.isRegularFileKey]) else { throw Failure.arguments }
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
                modelFiles.append(["path": String(file.path.dropFirst(compiled.path.count + 1)), "bytes": bytes.count, "sha256": sha(bytes)])
            }
        }
        modelFiles.sort { ($0["path"] as! String) < ($1["path"] as! String) }
        let report: [String: Any] = ["version": 1, "complete": true, "kind": kind, "samples": samples.count, "rejectedQueries": rejected, "vectors": count, "dimension": SemanticModelPackage.dimension, "dtype": "float32-little-endian", "inputSHA256": sha(input), "vocabularySHA256": sha(vocabulary), "matrixSHA256": sha(matrixData), "compiledModelFiles": modelFiles, "seconds": ProcessInfo.processInfo.systemUptime - started, "rows": mapping, "scope": "Actual production CPU encoder and tokenizer; every prepared passage window; no live search budget or keyword fusion; Mac timing only"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("complete.json"), options: .atomic)
        print("Complete: \(samples.count) \(kind), \(count) vectors, \(rejected) explicit query rejections.")
    }
}
