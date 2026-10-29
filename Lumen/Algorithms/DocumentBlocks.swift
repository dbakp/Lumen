import Foundation

public struct DocumentBlock: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case heading(Int), paragraph, listItem(String), code }
    public var id: Int
    public var kind: Kind
    public var text: String
}

public enum DocumentBlocks {
    /// Preserve the portable Markdown source while rendering block structure natively.
    public static func parse(_ text: String) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = [], paragraph: [String] = [], code: [String] = []
        var fenced = false
        func add(_ kind: DocumentBlock.Kind, _ text: String) { blocks.append(DocumentBlock(id: blocks.count, kind: kind, text: text)) }
        func flush() { if !paragraph.isEmpty { add(.paragraph, paragraph.joined(separator: "\n")); paragraph = [] } }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                if fenced { add(.code, code.joined(separator: "\n")); code = [] }
                fenced.toggle(); continue
            }
            if fenced { code.append(line); continue }
            if trimmed.isEmpty { flush(); continue }
            if let range = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush(); let marker = String(trimmed[..<range.upperBound])
                add(.heading(marker.filter { $0 == "#" }.count), String(trimmed[range.upperBound...])); continue
            }
            if let range = trimmed.range(of: #"^(?:[-*•]|\d+[.)])\s+"#, options: .regularExpression) {
                flush(); let marker = String(trimmed[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
                add(.listItem(marker == "-" || marker == "*" ? "•" : marker), String(trimmed[range.upperBound...])); continue
            }
            paragraph.append(line)
        }
        flush(); if !code.isEmpty { add(.code, code.joined(separator: "\n")) }
        return blocks
    }
}
