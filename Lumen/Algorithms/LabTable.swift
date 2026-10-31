import Foundation

enum LabColumn: String, CaseIterable, Sendable {
    case test, result, unit, reference, flag, timing, status, laboratory, specimen, method, subject
    var label: String {
        switch self {
        case .test: return "Test name"
        case .result: return "Reported result"
        case .unit: return "Unit"
        case .reference: return "Reference wording"
        case .flag: return "Reported flag"
        case .timing: return "Reported collection wording"
        case .status: return "Reported status"
        case .laboratory: return "Laboratory"
        case .specimen: return "Specimen"
        case .method: return "Method"
        case .subject: return "Subject column"
        }
    }
    var aliases: Set<String> {
        switch self {
        case .test: return ["test", "testname", "analyte", "component"]
        case .result: return ["result", "value", "reportedresult", "yourvalue"]
        case .unit: return ["unit", "units"]
        case .reference: return ["reference", "referencerange", "standardrange"]
        case .flag: return ["flag", "reportedflag"]
        case .timing: return ["collectedon", "collectiondate", "collectiontime", "date", "timing", "reportedtiming"]
        case .status: return ["status", "reportedstatus"]
        case .laboratory: return ["laboratory", "lab"]
        case .specimen: return ["specimen", "sampletype"]
        case .method: return ["method"]
        case .subject: return ["subject", "patient", "patientname", "patientid"]
        }
    }
}

struct LabTable: Sendable {
    struct Cell: Sendable { var value: String; var token: String }
    struct Row: Sendable, Identifiable { var id: Int; var cells: [String: Cell] }
    var filename: String
    var sha256: String
    var format: String
    var readAt: Date
    var headers: [String]
    var rows: [Row]
    var blankRows: Int
    var separator: String? = nil
    static let maxBytes = 2_000_000
    static let maxRows = 1024
    static let maxColumns = 64
    /// Preview only: retain a literal prefix without splitting a grapheme or
    /// sending a single huge combining sequence to native text layout. Storage
    /// and validation always use the untouched cell/source, never this prefix.
    static func displayPreview(_ value: String, maxCharacters: Int) -> (text: String, truncated: Bool) {
        guard maxCharacters > 0 else { return ("", !value.isEmpty) }
        var text = "", characters = 0, bytes = 0
        for character in value {
            let size = String(character).utf8.count
            guard characters < maxCharacters, bytes + size <= maxCharacters * 4 else { break }
            text.append(character); characters += 1; bytes += size
        }
        return (text, bytes < value.utf8.count)
    }
    enum Failure: LocalizedError {
        case format, tooLarge, rows, columns, header, cells
        var errorDescription: String? {
            switch self {
            case .format: return "Choose UTF-8 CSV or TSV with headers, or a JSON array of flat row objects. Export a fresh copy, then try again."
            case .tooLarge: return "Choose a lab file up to 2 MB. Split a larger export before importing."
            case .rows: return "This file has more than 1,024 data rows. Split it into smaller files."
            case .columns: return "Use a file with up to 64 columns."
            case .header: return "Give every column a unique, visible header of up to 200 characters."
            case .cells: return "Every CSV or TSV row must have the same number of cells as its header."
            }
        }
    }
    var suggestedMapping: [String: String] {
        var result: [String: String] = [:]
        for field in LabColumn.allCases {
            let matches = headers.filter { field.aliases.contains($0.lowercased().filter { $0.isLetter || $0.isNumber }) }
            if matches.count == 1 { result[field.rawValue] = matches[0] }
        }
        return result
    }
    func validates(_ mapping: [String: String]) -> Bool {
        mapping["test"] != nil && mapping["result"] != nil && Set(mapping.keys).isSubset(of: Set(LabColumn.allCases.map(\.rawValue))) &&
        Set(mapping.values).count == mapping.count && mapping.values.allSatisfy(headers.contains)
    }
    func subjects(mapping: [String: String]) -> [String] {
        guard let column = mapping["subject"] else { return [""] }
        var seen = Set<String>()
        return rows.compactMap { row in let value = row.cells[column]?.value ?? ""; return seen.insert(value).inserted ? value : nil }
    }
    static func parse(_ original: Data, filename: String, separator chosenSeparator: String? = nil, control: BackupOperationControl = .init(), now: Date = Date()) throws -> Self {
        try control.checkCancellation()
        guard original.count <= maxBytes else { throw Failure.tooLarge }
        guard LabReport.bounded(filename, limit: 500, required: true, multiline: false), !filename.contains("/"), !filename.contains("\\"), now.timeIntervalSince1970.isFinite else { throw Failure.format }
        let data = original.starts(with: [239, 187, 191]) ? Data(original.dropFirst(3)) : original
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { throw Failure.format }
        let format = URL(fileURLWithPath: filename).pathExtension.lowercased()
        var headers: [String] = [], rows: [Row] = [], blanks = 0
        switch format {
        case "csv", "tsv":
            let separator = chosenSeparator ?? (format == "csv" ? "," : "\t")
            guard [",", ";", "\t"].contains(separator) else { throw Failure.format }
            let parsed = try delimited(text, separator: Character(separator), control: control)
            guard let first = parsed.rows.first else { throw Failure.format }
            headers = first.map(\.value)
            try validateHeaders(headers)
            for cells in parsed.rows.dropFirst() {
                try control.checkCancellation()
                guard cells.count == headers.count else { throw Failure.cells }
                rows.append(.init(id: rows.count + 1, cells: Dictionary(uniqueKeysWithValues: zip(headers, cells))))
            }
            blanks = parsed.blanks
            guard !rows.isEmpty else { throw Failure.format }
            return .init(filename: filename, sha256: digest(original), format: separator == "\t" ? "tsv" : "csv", readAt: now, headers: headers, rows: rows, blankRows: blanks, separator: separator)
        case "json":
            guard chosenSeparator == nil else { throw Failure.format }
            var scanner = JSONRows(bytes: Array(data), control: control)
            let parsedRows = try scanner.read()
            var seen = Set<String>()
            for row in parsedRows { for key in row.order { if seen.insert(key).inserted { headers.append(key) } } }
            try validateHeaders(headers)
            return .init(filename: filename, sha256: digest(original), format: format, readAt: now, headers: headers, rows: parsedRows.map { .init(id: $0.number, cells: $0.cells) }, blankRows: 0)
        default: throw Failure.format
        }
    }
    private static func digest(_ data: Data) -> String { BackupArchive.digest(data) }
    private static func validateHeaders(_ headers: [String]) throws {
        guard !headers.isEmpty, headers.count <= maxColumns else { throw Failure.columns }
        guard Set(headers).count == headers.count, headers.allSatisfy({ LabReport.bounded($0, limit: 200, required: true) }) else { throw Failure.header }
    }
    private static func delimited(_ text: String, separator: Character, control: BackupOperationControl) throws -> (rows: [[Cell]], blanks: Int) {
        enum State { case start, plain, quoted, closed }
        var state = State.start, value = "", token = "", cells: [Cell] = [], rows: [[Cell]] = [], blanks = 0
        var pending = false, recordCR = false
        let delimiter = separator.unicodeScalars.first!
        func cell() { cells.append(.init(value: value, token: token)); value = ""; token = ""; state = .start }
        func row() throws {
            cell()
            if cells.count == 1 && cells[0].token.isEmpty { blanks += 1 }
            else { rows.append(cells); guard rows.count <= maxRows + 1 else { throw Failure.rows } }
            cells = []; pending = false
        }
        // CSV punctuation is scalar syntax. Extended graphemes can combine a
        // separator or opening quote with a leading mark in the next cell.
        // Preserve those marks, but never let them hide structural punctuation.
        for (index, char) in text.unicodeScalars.enumerated() {
            if index.isMultiple(of: 4096) { try control.checkCancellation() }
            if recordCR { recordCR = false; if char == "\n" { continue } }
            let newline = char == "\n" || char == "\r"
            if state == .quoted {
                token.unicodeScalars.append(char)
                if char == "\"" { state = .closed } else { value.unicodeScalars.append(char) }
            } else if state == .closed && char == "\"" {
                token.unicodeScalars.append(char); value.unicodeScalars.append(char); state = .quoted
            } else if char == delimiter {
                cell(); guard cells.count < maxColumns else { throw Failure.columns }; pending = true
            } else if newline { try row(); recordCR = char == "\r" }
            else {
                guard state != .closed else { throw Failure.format }
                if char == "\"" { guard state == .start else { throw Failure.format }; state = .quoted; token.unicodeScalars.append(char) }
                else { state = .plain; token.unicodeScalars.append(char); value.unicodeScalars.append(char) }
                pending = true
            }
        }
        guard state != .quoted else { throw Failure.format }
        if pending || !cells.isEmpty || !token.isEmpty { try row() }
        return (rows, blanks)
    }
    /// Small bounded grammar for flat JSON rows. Numeric lexemes never pass
    /// through NSNumber/Double, so 1.00 and 1e-9 keep their source spelling.
    private struct JSONRows {
        struct ParsedRow { var number: Int; var cells: [String: Cell]; var order: [String] }
        let bytes: [UInt8]
        let control: BackupOperationControl
        var offset = 0
        mutating func space() throws { while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { if offset.isMultiple(of: 4096) { try control.checkCancellation() }; offset += 1 } }
        mutating func take(_ byte: UInt8) throws { try space(); guard offset < bytes.count, bytes[offset] == byte else { throw Failure.format }; offset += 1 }
        mutating func string() throws -> Cell {
            try space(); let start = offset; try take(34)
            var escaped = false
            while offset < bytes.count {
                if offset.isMultiple(of: 4096) { try control.checkCancellation() }
                let char = bytes[offset]; offset += 1
                if char == 34 && !escaped {
                    let raw = Data(bytes[start..<offset])
                    guard let value = try? JSONDecoder().decode(String.self, from: raw), let token = String(data: raw, encoding: .utf8) else { throw Failure.format }
                    return .init(value: value, token: token)
                }
                if char == 92 && !escaped { escaped = true } else { escaped = false }
            }
            throw Failure.format
        }
        mutating func scalar() throws -> Cell {
            try space(); guard offset < bytes.count else { throw Failure.format }
            if bytes[offset] == 34 { return try string() }
            let start = offset
            while offset < bytes.count && ![9, 10, 13, 32, 44, 125].contains(bytes[offset]) {
                if offset.isMultiple(of: 4096) { try control.checkCancellation() }; offset += 1
            }
            let raw = String(decoding: bytes[start..<offset], as: UTF8.self)
            guard raw == "null" || raw == "true" || raw == "false" || raw.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { throw Failure.format }
            return .init(value: raw == "null" ? "" : raw, token: raw)
        }
        mutating func read() throws -> [ParsedRow] {
            try take(91); try space(); var rows: [ParsedRow] = []
            guard offset < bytes.count, bytes[offset] != 93 else { throw Failure.format }
            while true {
                try control.checkCancellation(); try take(123); var cells: [String: Cell] = [:], order: [String] = []
                try space(); guard offset < bytes.count, bytes[offset] != 125 else { throw Failure.header }
                while true {
                    let key = try string().value
                    guard cells[key] == nil else { throw Failure.header }
                    try take(58); cells[key] = try scalar(); order.append(key)
                    guard cells.count <= maxColumns else { throw Failure.columns }
                    try space(); guard offset < bytes.count else { throw Failure.format }
                    if bytes[offset] == 125 { offset += 1; break }; try take(44)
                }
                rows.append(.init(number: rows.count + 1, cells: cells, order: order)); guard rows.count <= maxRows else { throw Failure.rows }
                try space(); guard offset < bytes.count else { throw Failure.format }
                if bytes[offset] == 93 { offset += 1; break }; try take(44)
            }
            try space(); guard offset == bytes.count else { throw Failure.format }; return rows
        }
    }
}
