import Foundation
import PDFKit
import Vision
import ImageIO
import CryptoKit
import CoreGraphics
import UniformTypeIdentifiers

final class RecordWorkspace: Sendable {
    let directory: URL
    private static let cleanup: Void = {
        let fm = FileManager.default
        let old = ((try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("LumenRecordWork-") }
        for path in old { try? fm.removeItem(at: path) }
    }()
    init() throws {
        _ = Self.cleanup
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LumenRecordWork-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    deinit { let path = directory; DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: path) } }
}

// Only the documented any-thread cancel operations cross threads. Configuration
// and perform/coordinated reading remain on their owning worker.
private final class RecordCoordinatorCancellation: @unchecked Sendable {
    let coordinator: NSFileCoordinator
    init(_ value: NSFileCoordinator) { coordinator = value }
    func cancel() { coordinator.cancel() }
}
private final class RecordVisionCancellation: @unchecked Sendable {
    let request: VNRecognizeTextRequest
    init(_ value: VNRecognizeTextRequest) { request = value }
    func cancel() { request.cancel() }
}

enum RecordImportService {
    static let maxBytes = 20_000_000
    static let maxPages = 100
    static let maxPreviewBytes = 150_000_000
    struct Preview: Sendable {
        var pages: [RecordPageDraft]
        let filename: String
        let sha256: String
        let readAt: Date
        let originalURL: URL
        let workspace: RecordWorkspace
    }
    static func read(_ url: URL, control: RecordImportControl) throws -> Preview {
        try control.check()
        let workspace = try RecordWorkspace()
        let suffix = url.pathExtension.lowercased()
        let original = workspace.directory.appendingPathComponent("Original." + (suffix.isEmpty ? "txt" : suffix))
        let fingerprint = try select(url, to: original, control: control)
        let date = Date()
        var pages: [RecordPageDraft] = []
        if suffix == "pdf" {
            guard let document = PDFDocument(url: original) else { throw RecordImportError.invalid }
            guard !document.isLocked else { throw RecordImportError.locked }
            guard document.pageCount > 0 else { throw RecordImportError.invalid }
            guard document.pageCount <= maxPages else { throw RecordImportError.pageLimit }
            var previewBytes = 0
            for index in 0..<document.pageCount {
                try control.check()
                let page: RecordPageDraft = try autoreleasepool {
                    guard let page = document.page(at: index), let cg = page.pageRef else { throw RecordImportError.invalid }
                    // Widgets can contain values that aren't in page text/content streams.
                    // Require a flattened readable copy rather than silently dropping them.
                    guard !page.annotations.contains(where: { $0.type == PDFAnnotationSubtype.widget.rawValue }) else { throw RecordImportError.form }
                    control.update("Reading page", page: index + 1, total: document.pageCount)
                    let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard embedded.count <= RecordReview.maxCharacters else { throw RecordImportError.textLimit }
                    let image = try render(cg)
                    let thumbnail = try savePreview(image, number: index + 1, workspace: workspace)
                    previewBytes += try thumbnail.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard previewBytes <= maxPreviewBytes else { throw RecordImportError.imageSize }
                    var recognized = "", uncertain = 0, unavailable = false
                    do { (recognized, uncertain) = try recognize(image, page: index + 1, total: document.pageCount, control: control) }
                    catch {
                        try control.check()
                        if case RecordImportError.textLimit = error { throw error }
                        guard !embedded.isEmpty else { throw RecordImportError.recognition }
                        unavailable = true
                    }
                    // A raster page may also contain a selectable header/old OCR layer.
                    // Recognize the whole visible page so a hybrid's image isn't omitted.
                    let useOCR = embedded.isEmpty || (hasImage(cg.dictionary, depth: 0) && !recognized.isEmpty)
                    return .init(number: index + 1, selectable: embedded, recognized: recognized, method: useOCR ? .textRecognition : .selectableText,
                                 text: useOCR ? recognized : embedded, lowConfidenceLines: uncertain, recognitionUnavailable: unavailable, imageURL: thumbnail)
                }
                pages.append(page)
                try checkTextLimit(pages)
            }
        } else if ["jpg", "jpeg", "png", "heic", "heif"].contains(suffix) {
            control.update("Reading image", page: 1, total: 1)
            let image = try image(original)
            let thumbnail = try savePreview(image, number: 1, workspace: workspace)
            let (text, uncertain) = try recognize(image, page: 1, total: 1, control: control)
            pages = [.init(number: 1, selectable: "", recognized: text, method: .textRecognition, text: text, lowConfidenceLines: uncertain, imageURL: thumbnail)]
        } else if ["txt", "md", "text", ""].contains(suffix) || UTType(filenameExtension: suffix)?.conforms(to: .plainText) == true {
            control.update("Reading text", page: 1, total: 1)
            let text = try String(contentsOf: original, encoding: .utf8)
            guard text.count <= RecordReview.maxCharacters else { throw RecordImportError.textLimit }
            pages = [.init(number: 1, selectable: text, recognized: "", method: .plainText, text: text)]
        } else { throw RecordImportError.invalid }
        try control.check(); try checkTextLimit(pages)
        control.update("Ready to review", page: pages.count, total: pages.count, fraction: 1)
        return Preview(pages: pages, filename: String(url.lastPathComponent.prefix(500)), sha256: fingerprint, readAt: date, originalURL: original, workspace: workspace)
    }
    private static func select(_ url: URL, to original: URL, control: RecordImportControl) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        // Use a single coordinator for both operations and cancellation.
        let bridge = RecordCoordinatorCancellation(coordinator)
        control.setCancellationHandler { bridge.cancel() }
        var error: NSError?, copied: Result<String, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { path in
            copied = Result { try copy(path, to: original, control: control) }
        }
        control.setCancellationHandler(nil)
        try control.check()
        if let error { throw error }
        guard let copied else { throw RecordImportError.invalid }
        return try copied.get()
    }
    private static func checkTextLimit(_ pages: [RecordPageDraft]) throws {
        guard pages.reduce(0, { $0 + max($1.selectable.count, $1.recognized.count) }) <= RecordReview.maxCharacters else { throw RecordImportError.textLimit }
    }
    private static func copy(_ url: URL, to target: URL, control: RecordImportControl) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RecordImportError.invalid }
        guard let size = values.fileSize, size > 0 else { throw RecordImportError.invalid }
        guard size <= maxBytes else { throw RecordImportError.tooLarge }
        _ = FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600])
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
        #endif
        let input = try FileHandle(forReadingFrom: url), output = try FileHandle(forWritingTo: target)
        defer { try? input.close(); try? output.close() }
        var hash = SHA256(), count = 0
        while true {
            try control.check()
            let bytes = try input.read(upToCount: 64 * 1024) ?? Data()
            if bytes.isEmpty { break }
            count += bytes.count; guard count <= maxBytes else { throw RecordImportError.tooLarge }
            hash.update(data: bytes); try output.write(contentsOf: bytes)
        }
        guard count == size else { throw RecordImportError.invalid }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func render(_ page: CGPDFPage) throws -> CGImage {
        let box = page.getBoxRect(.cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0, max(box.width, box.height) <= 10_000_000 else { throw RecordImportError.imageSize }
        let rotated = abs(page.rotationAngle) % 180 == 90
        let width = rotated ? box.height : box.width, height = rotated ? box.width : box.height
        let scale = min(3, 2400 / max(width, height))
        let w = max(1, Int(ceil(width * scale))), h = max(1, Int(ceil(height * scale)))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RecordImportError.imageSize }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: w, height: h), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw RecordImportError.imageSize }; return image
    }
    private static func image(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 100_000_000 / height,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw RecordImportError.imageSize }
        return image
    }
    private static func savePreview(_ image: CGImage, number: Int, workspace: RecordWorkspace) throws -> URL {
        let path = workspace.directory.appendingPathComponent("page-\(number).jpg")
        guard let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw RecordImportError.invalid }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RecordImportError.invalid }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path.path)
        #endif
        return path
    }
    private static func recognize(_ image: CGImage, page: Int, total: Int, control: RecordImportControl) throws -> (String, Int) {
        try control.check()
        control.update("Recognizing text", page: page, total: total)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // Preserve raw candidates; never auto-correct names, numbers or units.
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.005
        let supported = try request.supportedRecognitionLanguages()
        let desired = Locale.preferredLanguages + ["en-US"]
        let languages = desired.compactMap { language in supported.first { $0 == language || $0.split(separator: "-").first == language.split(separator: "-").first } }
        request.recognitionLanguages = Array(NSOrderedSet(array: languages).array as? [String] ?? ["en-US"])
        let bridge = RecordVisionCancellation(request)
        control.setCancellationHandler { bridge.cancel() }
        defer { control.setCancellationHandler(nil) }
        request.progressHandler = { _, fraction, _ in control.update("Recognizing text", page: page, total: total, fraction: fraction) }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try control.check()
        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n")
        guard text.count <= RecordReview.maxCharacters else { throw RecordImportError.textLimit }
        return (text, candidates.filter { $0.confidence < 0.7 }.count)
    }
    private static func hasImage(_ dictionary: CGPDFDictionaryRef?, depth: Int) -> Bool {
        guard let dictionary, depth < 8 else { return false }
        var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return false }
        let found = ImageProbe(depth: depth)
        CGPDFDictionaryApplyFunction(objects, { _, object, info in
            guard let info else { return }
            let probe = Unmanaged<ImageProbe>.fromOpaque(info).takeUnretainedValue()
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let data = CGPDFStreamGetDictionary(stream) else { return }
            var name: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(data, "Subtype", &name), let name, String(cString: name) == "Image" { probe.found = true }
            else if RecordImportService.hasImage(data, depth: probe.depth + 1) { probe.found = true }
        }, Unmanaged.passUnretained(found).toOpaque())
        return found.found
    }
    private final class ImageProbe { var found = false; let depth: Int; init(depth: Int) { self.depth = depth } }
}
