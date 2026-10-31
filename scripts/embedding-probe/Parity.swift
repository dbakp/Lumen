import Foundation
import CryptoKit
import Darwin

/// Standalone diagnostic; compile with the actual production tokenizer/encoder.
/// It is excluded from app and package targets by the existing scripts exclusion.
@main struct EmbeddingParityProbe {
    struct Fixture: Decodable { struct Sample: Decodable { var id: String; var text: String }; var cases: [Sample] }
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data(("Embedding probe failed: \(error)\n").utf8)); exit(1) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 5 else { throw ProbeError.arguments }
        let compiled = URL(fileURLWithPath: CommandLine.arguments[1]), vocabulary = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        guard input.count <= 1_000_000 else { throw ProbeError.arguments }
        let fixture = try JSONDecoder().decode(Fixture.self, from: input)
        guard !fixture.cases.isEmpty, fixture.cases.count <= 256, Set(fixture.cases.map(\.id)).count == fixture.cases.count else { throw ProbeError.arguments }
        let tokenizer = try SemanticModelPackage.tokenizer(vocabulary)
        let encoder = try MiniLMEncoder(compiledModel: compiled, vocabulary: vocabulary)
        var rows: [[String: Any]] = [], unexpected = false
        func status(_ error: Error) -> String {
            switch error {
            case MiniLMTokenizer.TokenError.inputLimit: return "inputLimit"
            case MiniLMEncoder.EncoderError.queryTooLong: return "queryTooLong"
            case MiniLMEncoder.EncoderError.empty: return "empty"
            default: unexpected = true; return "failed: \(error)"
            }
        }
        for sample in fixture.cases {
            var row: [String: Any] = ["id": sample.id]
            do {
                row["tokenIDs"] = try tokenizer.tokenIDs(sample.text)
                let windows = try tokenizer.windows(sample.text)
                row["windowTokenIDs"] = windows.map(\.ids)
                row["windowMasks"] = windows.map(\.mask)
            }
            catch { row["tokenStatus"] = status(error) }
            do { row["queryVector"] = try await encoder.queryVector(sample.text); row["queryStatus"] = "used" }
            catch { row["queryStatus"] = status(error) }
            do { row["passageVectors"] = try await encoder.passageVectors(sample.text); row["passageStatus"] = "used" }
            catch { row["passageStatus"] = status(error) }
            rows.append(row)
        }
        await encoder.stop()
        let report: [String: Any] = ["scope": "Actual production Swift tokenizer and CPU Core ML encoder; synthetic compatibility diagnostic, not clinical/device validation", "windowProofVersion": 1, "fixtureSHA256": SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined(), "vocabularySHA256": SHA256.hash(data: vocabulary).map { String(format: "%02x", $0) }.joined(), "cases": rows]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[4]), options: .atomic)
        guard !unexpected else { throw ProbeError.prediction }
        print("Recorded \(rows.count) production tokenizer/query/passage cases.")
    }
    enum ProbeError: Error { case arguments, prediction }
}
