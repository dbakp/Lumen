import Foundation

/// Historical provenance for an explicitly reviewed flat-table import. This is
/// neither an original-file archive nor proof of clinical authorship/accuracy.
public struct LabImportOrigin: Codable, Sendable, Equatable {
    public var version = 1
    public var filename: String
    public var sha256: String
    public var format: String
    public var readAt: Date
    public var inputRows: Int
    public var blankRows: Int
    public var mapping: [String: String]
    public var selectedRows: [Int]
    public var subject: String?
    public var separator: String? = nil
    /// Original generated cell layout, retained when later source review changes.
    public var layoutSHA256: String? = nil
    public var isValid: Bool {
        let keys = Set(["test", "result", "unit", "reference", "flag", "timing", "status", "laboratory", "specimen", "method", "subject"])
        return version == 1 && LabReport.bounded(filename, limit: 500, required: true, multiline: false) &&
        !filename.contains("/") && !filename.contains("\\") &&
        sha256.count == 64 && sha256.allSatisfy { $0.isASCII && $0.isHexDigit } && ["csv", "tsv", "json"].contains(format) &&
        (format == "json" ? separator == nil : [",", ";", "\t"].contains(separator ?? "")) &&
        readAt.timeIntervalSince1970.isFinite && (1...1024).contains(inputRows) && (0...2_000_000).contains(blankRows) &&
        mapping["test"] != nil && mapping["result"] != nil && Set(mapping.keys).isSubset(of: keys) &&
        Set(mapping.values).count == mapping.count && mapping.values.allSatisfy { LabReport.bounded($0, limit: 200, required: true) } &&
        !selectedRows.isEmpty && selectedRows.count <= LabReport.maxObservations && Set(selectedRows).count == selectedRows.count &&
        selectedRows.allSatisfy { (1...inputRows).contains($0) } && selectedRows == selectedRows.sorted() &&
        (mapping["subject"] == nil ? subject == nil : subject != nil) && (subject.map(Self.validSubject) ?? true) &&
        (layoutSHA256.map { $0.count == 64 && $0.allSatisfy { $0.isASCII && $0.isHexDigit } } ?? true)
    }
    static func validSubject(_ value: String) -> Bool {
        value.count <= 500 && value.utf8.count <= 2000 && value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) || [9, 10, 13].contains($0.value)
        }
    }
    public var referenceText: String {
        let iso = ISO8601DateFormatter()
        let columns = mapping.keys.sorted().map { "\($0): \(mapping[$0] ?? "")" }.joined(separator: "\n")
        let delimiter = separator.map { "\nSeparator: " + ($0 == "\t" ? "Tab" : $0) } ?? ""
        let layout = layoutSHA256.map { "\nOriginal Lumen cell-layout SHA-256: " + $0 } ?? ""
        let rowUnit = inputRows == 1 ? "data row" : "data rows"
        return "Originally imported mapped cells: \(filename) (\(format.uppercased()))\(delimiter)\nRead: \(iso.string(from: readAt))\nInput SHA-256: \(sha256)\(layout)\nOriginal import selected \(selectedRows.count) of \(inputRows) \(rowUnit): \(selectedRows.map(String.init).joined(separator: ", ")). Physically blank rows skipped: \(blankRows). Other rows and unmapped columns were not retained.\nSubject: \(subject.map { $0.isEmpty ? "Blank source subject cell" : $0 } ?? "No subject column mapped; identity was checked during review")\nMapped columns:\n\(columns)\nOriginal cell values arranged by Lumen, not the original file layout. Keep the original file separately."
    }
}
