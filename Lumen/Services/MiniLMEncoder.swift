import Foundation
import CoreML
import CryptoKit

/// A model instance is confined to one actor; callers can cancel between native
/// predictions. Vectors are ranking inputs, never clinical confidence scores.
actor MiniLMEncoder {
    private var model: MLModel?
    private let tokenizer: MiniLMTokenizer
    private struct Cached {
        var vectors: [[Float]]
        var accessed: UInt64
        var inputSHA256: String
        var floats: Int { vectors.reduce(0) { $0 + $1.count } }
    }
    private var cache: [String: Cached] = [:]
    private var cachedFloats = 0
    private var clock: UInt64 = 0
    enum EncoderError: Error { case incompatible, empty, invalidOutput, queryTooLong, stopped }

    init(compiledModel: URL, vocabulary: Data) throws {
        tokenizer = try SemanticModelPackage.tokenizer(vocabulary)
        let configuration = MLModelConfiguration()
        // This pinned conversion's ANE compilation failed in the actual probe.
        // Use its measured CPU path rather than requesting a failing accelerator.
        configuration.computeUnits = .cpuOnly
        let loaded = try MLModel(contentsOf: compiledModel, configuration: configuration)
        model = loaded
        let inputs = loaded.modelDescription.inputDescriptionsByName
        guard Set(inputs.keys) == ["input_ids", "attention_mask", "token_type_ids"], inputs.values.allSatisfy({ description in
            description.type == .multiArray && description.multiArrayConstraint?.dataType == .int32 &&
            description.multiArrayConstraint?.shape.map(\.intValue) == [1, MiniLMTokenizer.sequenceLength]
        }), let output = loaded.modelDescription.outputDescriptionsByName["div_1"], output.type == .multiArray,
              output.multiArrayConstraint?.shape.map(\.intValue) == [1, SemanticModelPackage.dimension] else { throw EncoderError.incompatible }
    }

    func queryVector(_ text: String) throws -> [Float] {
        let inputs = try tokenizer.windows(text)
        guard inputs.count <= 1 else { throw EncoderError.queryTooLong }
        guard let input = inputs.first else { throw EncoderError.empty }
        return try predict(input)
    }

    /// Once this returns, no prediction is running and retained leases cannot
    /// start another prediction. The owner can safely remove model files.
    func stop() { model = nil; cache.removeAll(); cachedFloats = 0 }

    func retainCache(keys: Set<String>) {
        cache = cache.filter { keys.contains($0.key) }
        cachedFloats = cache.values.reduce(0) { $0 + $1.floats }
    }

    func passageVectors(_ text: String, key: String) throws -> (vectors: [[Float]], cached: Bool) {
        try Task.checkCancellation()
        guard model != nil else { throw EncoderError.stopped }
        clock &+= 1
        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        if var entry = cache[key], entry.inputSHA256 == digest {
            entry.accessed = clock; cache[key] = entry; return (entry.vectors, true)
        }
        if let replaced = cache.removeValue(forKey: key) { cachedFloats -= replaced.floats }
        let vectors = try passageVectors(text), cost = vectors.reduce(0) { $0 + $1.count }
        // Private RAM only: no duplicate text/vector index is written to disk.
        while !cache.isEmpty && (cache.count >= 8192 || cachedFloats + cost > 8_000_000) {
            guard let oldest = cache.min(by: { $0.value.accessed < $1.value.accessed }) else { break }
            cachedFloats -= oldest.value.floats; cache.removeValue(forKey: oldest.key)
        }
        if cost <= 8_000_000 { cache[key] = Cached(vectors: vectors, accessed: clock, inputSHA256: digest); cachedFloats += cost }
        return (vectors, false)
    }

    func passageVectors(_ text: String) throws -> [[Float]] {
        let inputs = try tokenizer.windows(text)
        guard !inputs.isEmpty else { throw EncoderError.empty }
        // Production passages are bounded before this call; retain every window.
        return try inputs.map { try predict($0) }
    }

    private func predict(_ input: MiniLMTokenizer.Input) throws -> [Float] {
        try Task.checkCancellation()
        guard let model else { throw EncoderError.stopped }
        func array(_ values: [Int32]) throws -> MLMultiArray {
            guard values.count == MiniLMTokenizer.sequenceLength else { throw EncoderError.incompatible }
            let result = try MLMultiArray(shape: [1, NSNumber(value: MiniLMTokenizer.sequenceLength)], dataType: .int32)
            for (index, value) in values.enumerated() { result[index] = NSNumber(value: value) }
            return result
        }
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": array(input.ids), "attention_mask": array(input.mask), "token_type_ids": array(input.types)
        ])
        let prediction = try model.prediction(from: features)
        try Task.checkCancellation()
        guard let value = prediction.featureValue(for: "div_1")?.multiArrayValue,
              value.shape.map(\.intValue) == [1, SemanticModelPackage.dimension] else { throw EncoderError.invalidOutput }
        let vector = (0..<SemanticModelPackage.dimension).map { value[$0].floatValue }
        guard vector.allSatisfy(\.isFinite) else { throw EncoderError.invalidOutput }
        let norm = sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard norm.isFinite, norm > 0 else { throw EncoderError.invalidOutput }
        return vector.map { Float(Double($0) / norm) }
    }

    static func similarity(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == SemanticModelPackage.dimension, b.count == a.count,
              a.allSatisfy(\.isFinite), b.allSatisfy(\.isFinite) else { return nil }
        let na = sqrt(a.reduce(0.0) { $0 + Double($1) * Double($1) }), nb = sqrt(b.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard na > 0, nb > 0, na.isFinite, nb.isFinite else { return nil }
        let dot = zip(a, b).reduce(0.0) { $0 + Double($1.0) * Double($1.1) } / (na * nb)
        return max(-1, min(1, dot))
    }
}
