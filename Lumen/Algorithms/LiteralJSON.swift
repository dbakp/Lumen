import Foundation

/// Bounded structured JSON with original byte ranges. Numbers never pass through
/// floating point; source excerpts keep exact spelling, whitespace and escapes.
enum LiteralJSON {
    static let maxBytes = 2_000_000
    static let maxDepth = 64
    static let maxNodes = 100_000
    struct Member: Sendable {
        let name: String
        let value: Node
    }
    struct Node: Sendable {
        indirect enum Value: Sendable {
            case object([Member]), array([Node]), string(String), number(String), boolean(Bool), null
        }
        let value: Value
        let bytes: Range<Int>
        var members: [Member]? { if case .object(let fields) = value { return fields }; return nil }
        var elements: [Node]? { if case .array(let values) = value { return values }; return nil }
        var string: String? { if case .string(let text) = value { return text }; return nil }
        var number: String? { if case .number(let text) = value { return text }; return nil }
        subscript(_ key: String) -> Node? { members?.first { $0.name.utf8.elementsEqual(key.utf8) }?.value }
    }
    struct Document: Sendable {
        let source: Data
        let root: Node
        func text(_ node: Node) -> String {
            String(decoding: source[node.bytes], as: UTF8.self)
        }
    }
    enum Failure: LocalizedError, Equatable {
        case size, syntax(Int), duplicateKey(Int), depth, nodes, lines
        var errorDescription: String? {
            switch self {
            case .size: return "Choose a nonempty UTF-8 JSON file up to 2 MB."
            case .syntax(let byte): return "The JSON is invalid near byte \(byte + 1). Export a fresh file."
            case .duplicateKey(let byte): return "The JSON repeats a field near byte \(byte + 1). Export an unambiguous copy."
            case .depth: return "The JSON is nested too deeply. Export a smaller, simpler file."
            case .nodes: return "The JSON has too many fields and values. Split the export into smaller files."
            case .lines: return "This NDJSON file has more than 1,024 resource lines. Split the export."
            }
        }
    }
    static func parse(_ data: Data, control: BackupOperationControl = .init()) throws -> Document {
        try control.checkCancellation()
        guard !data.isEmpty, data.count <= maxBytes, String(data: data, encoding: .utf8) != nil else { throw Failure.size }
        var parser = Parser(bytes: Array(data), control: control)
        if data.starts(with: [239, 187, 191]) { parser.offset = 3 }
        let root = try parser.node(depth: 0)
        try parser.space()
        guard parser.offset == data.count else { throw Failure.syntax(parser.offset) }
        try control.checkCancellation()
        // A Data subsequence can retain a nonzero collection startIndex. Node
        // ranges are file-relative offsets into the zero-based parser bytes.
        return Document(source: Data(parser.bytes), root: root)
    }
    /// A review container, not a JSON array in the source file. Each child is
    /// exactly one physical line; every range remains relative to the complete
    /// original file. One parser shares the node budget across all lines.
    static func parseLines(_ data: Data, maxLines: Int, control: BackupOperationControl = .init()) throws -> Document {
        try control.checkCancellation()
        guard !data.isEmpty, data.count <= maxBytes, String(data: data, encoding: .utf8) != nil else { throw Failure.size }
        var parser = Parser(bytes: Array(data), control: control), roots: [Node] = []
        if data.starts(with: [239, 187, 191]) { parser.offset = 3 }
        while parser.offset < parser.bytes.count {
            try control.checkCancellation()
            guard roots.count < maxLines else { throw Failure.lines }
            let start = parser.offset
            let newline = parser.bytes[start...].firstIndex(of: 10) ?? parser.bytes.count
            let end = newline < parser.bytes.count && newline > start && parser.bytes[newline - 1] == 13 ? newline - 1 : newline
            // CR is part of a CRLF delimiter only. A bare CR would display as
            // another physical line while keeping the same /line/N identity.
            if let carriage = parser.bytes[start..<end].firstIndex(of: 13) { throw Failure.syntax(carriage) }
            // Restrict the parser itself, so a malformed line cannot consume
            // another resource as JSON whitespace or emit a cross-line token.
            parser.limit = end
            let node = try parser.node(depth: 0)
            try parser.space()
            guard parser.offset == end else { throw Failure.syntax(parser.offset) }
            roots.append(node)
            parser.offset = newline < parser.bytes.count ? newline + 1 : newline
        }
        guard !roots.isEmpty else { throw Failure.syntax(parser.offset) }
        try control.checkCancellation()
        return Document(source: Data(parser.bytes), root: Node(value: .array(roots), bytes: 0..<data.count))
    }
    private struct Parser {
        let bytes: [UInt8]
        let control: BackupOperationControl
        var offset = 0
        var nodes = 0
        var limit: Int? = nil
        var end: Int { limit ?? bytes.count }
        mutating func space() throws {
            while offset < end && [9, 10, 13, 32].contains(bytes[offset]) {
                if offset.isMultiple(of: 4096) { try control.checkCancellation() }
                offset += 1
            }
        }
        mutating func take(_ byte: UInt8) throws {
            try space()
            guard offset < end, bytes[offset] == byte else { throw Failure.syntax(offset) }
            offset += 1
        }
        mutating func string() throws -> String {
            try take(34); let start = offset - 1
            while offset < end {
                if offset.isMultiple(of: 4096) { try control.checkCancellation() }
                let byte = bytes[offset]; offset += 1
                if byte == 34 {
                    guard let value = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) else { throw Failure.syntax(start) }
                    return value
                }
                guard byte >= 32 else { throw Failure.syntax(offset - 1) }
                if byte == 92 {
                    guard offset < end else { throw Failure.syntax(offset) }
                    offset += 1 // JSONDecoder validates escapes and surrogate pairs.
                }
            }
            throw Failure.syntax(start)
        }
        mutating func node(depth: Int) throws -> Node {
            try control.checkCancellation(); try space()
            guard depth <= maxDepth else { throw Failure.depth }
            nodes += 1; guard nodes <= maxNodes else { throw Failure.nodes }
            guard offset < end else { throw Failure.syntax(offset) }
            let start = offset, value: Node.Value
            switch bytes[offset] {
            case 123:
                offset += 1; try space()
                var fields: [Member] = [], keys = Set<Data>()
                if offset < end, bytes[offset] == 125 { offset += 1; value = .object(fields); break }
                while true {
                    try space(); let keyStart = offset, key = try string()
                    // JSON escaped spellings decode to one key. Canonically
                    // equivalent but byte-distinct Unicode names stay distinct.
                    guard keys.insert(Data(key.utf8)).inserted else { throw Failure.duplicateKey(keyStart) }
                    try take(58)
                    fields.append(Member(name: key, value: try node(depth: depth + 1)))
                    try space(); guard offset < end else { throw Failure.syntax(offset) }
                    if bytes[offset] == 125 { offset += 1; break }
                    try take(44)
                }
                value = .object(fields)
            case 91:
                offset += 1; try space(); var values: [Node] = []
                if offset < end, bytes[offset] == 93 { offset += 1; value = .array(values); break }
                while true {
                    values.append(try node(depth: depth + 1)); try space()
                    guard offset < end else { throw Failure.syntax(offset) }
                    if bytes[offset] == 93 { offset += 1; break }
                    try take(44)
                }
                value = .array(values)
            case 34: value = .string(try string())
            default:
                while offset < end && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) {
                    if offset.isMultiple(of: 4096) { try control.checkCancellation() }
                    offset += 1
                }
                let token = String(decoding: bytes[start..<offset], as: UTF8.self)
                switch token {
                case "true": value = .boolean(true)
                case "false": value = .boolean(false)
                case "null": value = .null
                default:
                    guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { throw Failure.syntax(start) }
                    value = .number(token)
                }
            }
            return Node(value: value, bytes: start..<offset)
        }
    }
}
