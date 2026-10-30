import Foundation

/// BERT uncased WordPiece preprocessing for the pinned MiniLM search model.
/// Text stays literal in references; normalization is only for model input.
struct MiniLMTokenizer: Sendable {
    static let sequenceLength = 256
    private let vocabulary: [String: Int32]
    private let special = ["[PAD]", "[UNK]", "[CLS]", "[SEP]", "[MASK]"]
    enum TokenError: Error { case vocabulary, inputLimit }

    init(vocabularyText: String) throws {
        var lines = vocabularyText.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard lines.count == 30_522, Set(lines).count == lines.count,
              lines[0] == "[PAD]", lines[100] == "[UNK]", lines[101] == "[CLS]",
              lines[102] == "[SEP]", lines[103] == "[MASK]" else { throw TokenError.vocabulary }
        vocabulary = Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($0.element, Int32($0.offset)) })
    }

    struct Input: Sendable {
        var ids: [Int32]
        var mask: [Int32]
        var types: [Int32] { Array(repeating: 0, count: ids.count) }
    }

    /// Overlapping windows preserve all input tokens, including the final words.
    /// Padding and boundary tokens match the model's fixed 1×256 input.
    func windows(_ text: String) throws -> [Input] {
        let tokens = try tokenIDs(text)
        guard !tokens.isEmpty else { return [] }
        var result: [Input] = [], start = 0
        while start < tokens.count {
            let end = min(tokens.count, start + Self.sequenceLength - 2)
            let ids = [Int32(101)] + tokens[start..<end] + [Int32(102)]
            result.append(Input(ids: ids + Array(repeating: 0, count: Self.sequenceLength - ids.count),
                                mask: Array(repeating: 1, count: ids.count) + Array(repeating: 0, count: Self.sequenceLength - ids.count)))
            if end == tokens.count { break }
            start = end - 32
        }
        return result
    }

    func tokenIDs(_ text: String) throws -> [Int32] {
        guard text.utf8.count <= 32_000, text.unicodeScalars.count <= 8_000 else { throw TokenError.inputLimit }
        var output: [Int32] = [], start = text.startIndex
        while start < text.endIndex {
            // Added special tokens are matched before lowercasing, as in the
            // pinned tokenizer. Their presence never grants text any authority.
            let next = special.compactMap { token -> (String, Range<String.Index>)? in
                text.range(of: token, range: start..<text.endIndex).map { (token, $0) }
            }.min { $0.1.lowerBound < $1.1.lowerBound }
            let end = next?.1.lowerBound ?? text.endIndex
            for word in basicTokens(String(text[start..<end])) { output += wordPieces(word) }
            guard let next else { break }
            output.append(vocabulary[next.0]!); start = next.1.upperBound
        }
        return output
    }

    private func basicTokens(_ text: String) -> [String] {
        var clean = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value, category = scalar.properties.generalCategory
            if value == 0 || value == 0xfffd { continue }
            if [9, 10, 13, 32].contains(value) || category == .spaceSeparator { clean.append(" "); continue }
            if [.control, .format, .surrogate, .privateUse, .unassigned].contains(category) { continue }
            if Self.chinese(value) { clean.append(" "); clean.append(scalar); clean.append(" ") }
            else { clean.append(scalar) }
        }
        let normalized = String(clean).lowercased().decomposedStringWithCanonicalMapping
        var words: [String] = [], current = String.UnicodeScalarView()
        func flush() { if !current.isEmpty { words.append(String(current)); current = .init() } }
        for scalar in normalized.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            if scalar.properties.isWhitespace { flush(); continue }
            let value = scalar.value, category = scalar.properties.generalCategory
            let punctuation = (33...47).contains(value) || (58...64).contains(value) || (91...96).contains(value) || (123...126).contains(value) ||
                [.connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation, .otherPunctuation].contains(category)
            if punctuation { flush(); words.append(String(scalar)) } else { current.append(scalar) }
        }
        flush(); return words
    }

    private func wordPieces(_ word: String) -> [Int32] {
        let scalars = Array(word.unicodeScalars)
        guard scalars.count <= 100 else { return [100] }
        var result: [Int32] = [], start = 0
        while start < scalars.count {
            var end = scalars.count, match: Int32?
            while end > start {
                let token = (start == 0 ? "" : "##") + String(String.UnicodeScalarView(scalars[start..<end]))
                if let id = vocabulary[token] { match = id; break }
                end -= 1
            }
            guard let match else { return [100] }
            result.append(match); start = end
        }
        return result
    }

    private static func chinese(_ value: UInt32) -> Bool {
        [(0x4e00, 0x9fff), (0x3400, 0x4dbf), (0x20000, 0x2a6df), (0x2a700, 0x2b73f),
         (0x2b740, 0x2b81f), (0x2b820, 0x2ceaf), (0xf900, 0xfaff), (0x2f800, 0x2fa1f)].contains { $0.0...$0.1 ~= Int(value) }
    }
}
