import Foundation

public struct RecordExtraction: Codable, Sendable {
    public enum Method: String, Codable, Sendable { case selectableText, textRecognition, plainText, excluded }
    public struct Page: Codable, Sendable {
        public var number: Int
        public var method: Method
        public var edited: Bool
        public var lowConfidenceLines: Int
    }
    public var version = 1
    public var filename: String
    public var sha256: String
    public var readAt: Date
    public var reviewedAt: Date
    public var pages: [Page]
    public var laterEditedAt: Date? = nil
    public var isValid: Bool {
        version == 1 && !filename.isEmpty && filename.count <= 500 && sha256.count == 64 && sha256.allSatisfy { $0.isHexDigit && $0.isASCII } &&
        !pages.isEmpty && pages.count <= 100 && pages.enumerated().allSatisfy { $0.element.number == $0.offset + 1 && (0...100_000).contains($0.element.lowConfidenceLines) } &&
        readAt.timeIntervalSince1970.isFinite && reviewedAt >= readAt && (laterEditedAt.map { $0 >= reviewedAt } ?? true)
    }
    public var recognizedPages: Int { pages.filter { $0.method == .textRecognition }.count }
}

struct RecordPageDraft: Identifiable, Sendable {
    var id: Int { number }
    var number: Int
    var selectable: String
    var recognized: String
    var method: RecordExtraction.Method
    var text: String
    var excluded = false
    var lowConfidenceLines = 0
    var recognitionUnavailable = false
    var imageURL: URL?
    var initialText: String { method == .selectableText || method == .plainText ? selectable : recognized }
    var edited: Bool { text != initialText }
    mutating func select(_ method: RecordExtraction.Method) {
        self.method = method; text = initialText
    }
}

enum RecordReview {
    /// Either import route can hold the same original-file fingerprint. Titles,
    /// reviewed wording and patient identities never establish a file match.
    static func hasDuplicate(sha256: String, in documents: [HealthDocument]) -> Bool {
        let hash = sha256.lowercased()
        return documents.contains { $0.originalLabImport?.sha256.lowercased() == hash || $0.fhirLabImport?.sha256.lowercased() == hash || $0.extraction?.sha256.lowercased() == hash }
    }
    static let maxCharacters = 200_000
    static func body(_ pages: [RecordPageDraft]) throws -> String {
        guard !pages.isEmpty, pages.count <= 100, pages.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 }) else { throw RecordImportError.invalid }
        guard pages.allSatisfy({ $0.excluded || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw RecordImportError.emptyPage }
        let included = pages.filter { !$0.excluded }
        guard !included.isEmpty else { throw RecordImportError.noText }
        let body = included.map { "## Page \($0.number)\n\n\($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n\n")
        guard body.count <= maxCharacters else { throw RecordImportError.textLimit }
        return body
    }
    static func document(title: String, pages: [RecordPageDraft], filename: String, sha256: String, readAt: Date, acknowledged: Bool, now: Date = Date()) throws -> HealthDocument {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 500, acknowledged else { throw RecordImportError.review }
        let text = try body(pages)
        let metadata = RecordExtraction(filename: String(filename.prefix(500)), sha256: sha256, readAt: readAt, reviewedAt: max(now, readAt), pages: pages.map {
            .init(number: $0.number, method: $0.excluded ? .excluded : $0.method, edited: $0.edited, lowConfidenceLines: $0.lowConfidenceLines)
        })
        guard metadata.isValid else { throw RecordImportError.invalid }
        var document = HealthDocument(title: title, kind: .record, body: text, source: "Imported · " + metadata.filename)
        document.extraction = metadata
        return document
    }
}

enum RecordImportError: LocalizedError {
    case tooLarge, pageLimit, textLimit, invalid, locked, form, imageSize, noText, emptyPage, review, recognition
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a file up to 20 MB. Split a larger record into smaller files."
        case .pageLimit: return "This record has more than 100 pages. Split it into smaller files."
        case .textLimit: return "The text exceeds 200,000 characters. Split the record into smaller files."
        case .invalid: return "This file couldn't be read. Choose a PDF, UTF-8 text file, or a still JPEG, PNG or HEIC image."
        case .locked: return "This PDF is locked. Choose an unlocked copy, then try again."
        case .form: return "This PDF has form fields. Export a flattened readable copy so field values are included, then try again."
        case .imageSize: return "A page or image is too large to read safely. Export a smaller copy and try again."
        case .noText: return "No text is available to save. Choose a clearer scan or another file."
        case .emptyPage: return "A page has no text. Add its text or explicitly exclude it before saving."
        case .review: return "Add a title and confirm that you checked the text before saving."
        case .recognition: return "Text recognition couldn't read this page. Try a clearer image or a smaller PDF."
        }
    }
}

final class RecordImportControl: @unchecked Sendable {
    struct Progress: Sendable {
        var title = "Opening record"
        var page = 0
        var total = 0
        var fraction = 0.0
    }
    private let lock = NSLock()
    private var cancelled = false
    private var handler: (@Sendable () -> Void)?
    private var state = Progress()
    var progress: Progress { lock.lock(); defer { lock.unlock() }; return state }
    func update(_ title: String, page: Int = 0, total: Int = 0, fraction: Double = 0) {
        lock.lock(); state = .init(title: title, page: page, total: total, fraction: fraction); lock.unlock()
    }
    func cancel() { lock.lock(); cancelled = true; let action = handler; lock.unlock(); action?() }
    func check() throws { lock.lock(); let value = cancelled; lock.unlock(); if value { throw CancellationError() } }
    func setCancellationHandler(_ action: (@Sendable () -> Void)?) {
        lock.lock(); handler = action; let call = cancelled ? action : nil; lock.unlock(); call?()
    }
}
