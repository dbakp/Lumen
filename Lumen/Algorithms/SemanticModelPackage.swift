import Foundation
import CryptoKit

/// Fixed, independently hashed public assets. No health text is sent to these
/// URLs, and no remote manifest can add paths or change the installed model.
enum SemanticModelPackage {
    static let repository = "haihengh/all-MiniLM-L6-v2-coreml"
    static let revision = "c683f20435a63c9884472f5de9f56865e865fd99"
    static let identifier = "minilm-l6-v2-fp16-" + revision
    static let vocabularySHA256 = "07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3"
    static let dimension = 384
    struct Asset: Sendable {
        let path: String
        let bytes: Int64
        let sha256: String
        var url: URL { URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)")! }
    }
    static let assets: [Asset] = [
        .init(path: "all-minilm-l6-v2.mlpackage/Manifest.json", bytes: 617, sha256: "550e4c51f2dcb47dfd58d2249663c379dc4ceb633be6cc7355fe4f56f369cec7"),
        .init(path: "all-minilm-l6-v2.mlpackage/Data/com.apple.CoreML/model.mlmodel", bytes: 70_860, sha256: "6201aeebdc5d31966147fc286890a7c4eb9cff31bce925b683dc5a6ac62497c7"),
        .init(path: "all-minilm-l6-v2.mlpackage/Data/com.apple.CoreML/weights/weight.bin", bytes: 44_940_672, sha256: "84cbd97f75e18368c9ba9566bb51614f8f7d56f659c171124bf4447cc2145bde")
    ]
    static var downloadBytes: Int64 { assets.reduce(0) { $0 + $1.bytes } }
    enum PackageError: Error { case invalid }

    static func validate(_ file: URL, asset: Asset) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == asset.bytes else { throw PackageError.invalid }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation(); digest.update(data: data)
        }
        guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == asset.sha256 else { throw PackageError.invalid }
    }
    static func tokenizer(_ data: Data) throws -> MiniLMTokenizer {
        guard data.count == 231_508,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == vocabularySHA256,
              let text = String(data: data, encoding: .utf8) else { throw PackageError.invalid }
        return try MiniLMTokenizer(vocabularyText: text)
    }
}
