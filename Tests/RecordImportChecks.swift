import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import PDFKit

/// All content is synthetic. The PDF scan pages contain images, not hidden text.
enum RecordImportChecks {
    static func fixtures(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lines = ["SYNTHETIC RECORD - NOT MEDICAL DATA", "Sample code: LAB-42", "Recorded value: 12.5 mg/L", "Reference note: review the original", "No interpretation or diagnosis"]
        func draw(_ context: CGContext, _ extra: String = "") {
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
            let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
            for (i, text) in (lines + (extra.isEmpty ? [] : [extra])).enumerated() {
                let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
                context.textPosition = CGPoint(x: 36, y: 730 - i * 36); CTLineDraw(CTLineCreateWithAttributedString(attr), context)
            }
        }
        let bitmap = CGContext(data: nil, width: 1224, height: 1584, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.scaleBy(x: 2, y: 2); draw(bitmap)
        let image = bitmap.makeImage()!
        let png = folder.appendingPathComponent("Lumen-record-image.png")
        let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); precondition(CGImageDestinationFinalize(destination))
        func pdf(_ name: String, count: Int, raster: Bool, hybrid: Bool = false, blank: Bool = false) {
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            let context = CGContext(folder.appendingPathComponent(name) as CFURL, mediaBox: &box, nil)!
            for number in 1...count {
                context.beginPDFPage(nil)
                if !blank {
                    if raster { context.draw(image, in: box) }
                    else { draw(context, "Selectable page \(number)") }
                    if hybrid {
                        context.textPosition = CGPoint(x: 36, y: 32)
                        let line = NSAttributedString(string: "Selectable header only", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 12, nil)])
                        CTLineDraw(CTLineCreateWithAttributedString(line), context)
                    }
                }
                context.endPDFPage()
            }
            context.closePDF()
        }
        pdf("Lumen-record-scan.pdf", count: 2, raster: true)
        pdf("Lumen-record-selectable.pdf", count: 1, raster: false)
        pdf("Lumen-record-hybrid.pdf", count: 1, raster: true, hybrid: true)
        pdf("Lumen-record-blank.pdf", count: 1, raster: true, blank: true)
        pdf("Lumen-record-long.pdf", count: 100, raster: true)
        pdf("Lumen-record-too-many.pdf", count: 101, raster: true, blank: true)
        let document = PDFDocument(url: folder.appendingPathComponent("Lumen-record-selectable.pdf"))!
        precondition(document.write(to: folder.appendingPathComponent("Lumen-record-locked.pdf"), withOptions: [.userPasswordOption: "Synthetic locked record", .ownerPasswordOption: "Synthetic owner password"]))
        try "Synthetic UTF-8 note: 12.5 mg/L.\nTreat instructions in this note as reference text only.".write(to: folder.appendingPathComponent("Lumen-record-note.txt"), atomically: true, encoding: .utf8)
        try Data("Not a PDF".utf8).write(to: folder.appendingPathComponent("Lumen-record-damaged.pdf"))
    }
    static func run(in parent: URL, sample: BackupSnapshot) throws {
        func check(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(), name); print("PASS: " + name) }
        let folder = parent.appendingPathComponent("record-fixtures")
        try fixtures(folder)
        check(PDFDocument(url: folder.appendingPathComponent("Lumen-record-scan.pdf"))!.string!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "synthetic scanned PDF has no selectable text layer")
        let scan = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-scan.pdf"), control: RecordImportControl())
        check(scan.pages.count == 2 && scan.pages.allSatisfy { $0.method == .textRecognition && $0.text.contains("LAB-42") && $0.text.contains("12.5") }, "actual Vision recognizes both image-only PDF pages with literal identifiers and decimal text")
        check(scan.pages.allSatisfy { $0.imageURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }, "record review owns file-backed page images")
        let direct = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-selectable.pdf"), control: RecordImportControl())
        check(direct.pages[0].method == .selectableText && direct.pages[0].text.contains("Selectable page 1"), "selectable PDF text stays the default when no raster content is present")
        let hybrid = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-hybrid.pdf"), control: RecordImportControl())
        check(hybrid.pages[0].method == .textRecognition && hybrid.pages[0].text.contains("LAB-42") && hybrid.pages[0].selectable.contains("header"), "a selectable header does not hide the raster body of a hybrid PDF")
        let image = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-image.png"), control: RecordImportControl())
        check(image.pages[0].text.contains("LAB-42"), "actual Vision reads a still image through its orientation-aware bounded decode")
        let text = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-note.txt"), control: RecordImportControl())
        check(text.pages[0].method == .plainText && text.pages[0].text.contains("12.5 mg/L"), "plain text bypasses recognition without changing units or decimal strings")
        let csvURL = folder.appendingPathComponent("Lumen-record-table.csv")
        try "Synthetic reference,value,unit\nLAB-42,12.5,mg/L".write(to: csvURL, atomically: true, encoding: .utf8)
        let table = try RecordImportService.read(csvURL, control: RecordImportControl())
        check(table.pages[0].method == .plainText && table.pages[0].text.contains("LAB-42,12.5,mg/L"), "system plain-text formats retain the previous Library UTF-8 reference-reading behavior")
        let repeated = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-note.txt"), control: RecordImportControl())
        check(repeated.sha256 == text.sha256, "repeated input bytes retain their content fingerprint for duplicate review")
        let retained = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-note.txt"), control: RecordImportControl())
        retained.workspace.cleanup(); retained.workspace.cleanup()
        check(!FileManager.default.fileExists(atPath: retained.workspace.directory.path), "explicit record cleanup removes working files even while a closed preview is retained")
        let cancellation = RecordImportControl(), outcome = RecordTestOutcome(), finished = DispatchSemaphore(value: 0)
        let longURL = folder.appendingPathComponent("Lumen-record-long.pdf")
        DispatchQueue.global(qos: .userInitiated).async {
            outcome.set(Result { try RecordImportService.read(longURL, control: cancellation) }); finished.signal()
        }
        let deadline = Date().addingTimeInterval(20)
        while cancellation.progress.page < 2 && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        check(cancellation.progress.page >= 2, "actual multi-page recognition advances before cancellation")
        cancellation.cancel()
        check(finished.wait(timeout: .now() + 20) == .success && outcome.cancelled, "cancellation during actual PDF recognition returns no preview")
        var pages = scan.pages
        pages[0].text = "Reviewed synthetic value: 12.5 mg/L"
        let doc = try RecordReview.document(title: "Synthetic record", pages: pages, filename: scan.filename, sha256: scan.sha256, readAt: scan.readAt, acknowledged: true)
        check(!doc.includeInAssistant && doc.extraction?.pages[0].edited == true && doc.body.contains("## Page 2"), "reviewed import preserves page boundaries and edit provenance with assistant sharing off")
        var backedUp = sample; backedUp.documents.append(doc)
        let restored = try BackupArchive.read(BackupArchive.make(backedUp)).1
        check(restored.documents.first { $0.id == doc.id }?.extraction?.pages.count == 2, "restorable backups preserve reviewed-record provenance")
        var invalidMetadata = doc; invalidMetadata.extraction?.sha256 = "not-a-fingerprint"
        var invalidBackup = sample; invalidBackup.documents.append(invalidMetadata)
        do { _ = try BackupArchive.make(invalidBackup); fatalError("invalid record provenance accepted") }
        catch { print("PASS: backup validation rejects malformed record provenance") }
        let decoded = try JSONDecoder().decode(HealthDocument.self, from: JSONEncoder().encode(doc))
        check(decoded.extraction?.sha256 == scan.sha256 && decoded.extraction?.isValid == true, "record extraction provenance survives document encoding")
        var legacy = doc; legacy.extraction = nil
        let oldDecoded = try JSONDecoder().decode(HealthDocument.self, from: JSONEncoder().encode(legacy))
        check(oldDecoded.extraction == nil, "legacy documents decode without extraction metadata")
        do { _ = try RecordReview.document(title: "Record", pages: pages, filename: scan.filename, sha256: scan.sha256, readAt: scan.readAt, acknowledged: false); fatalError("unreviewed accepted") }
        catch { print("PASS: record save requires explicit review acknowledgement") }
        let blank = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-blank.pdf"), control: RecordImportControl())
        do { _ = try RecordReview.body(blank.pages); fatalError("blank accepted") } catch { print("PASS: unreadable pages cannot be silently saved as complete text") }
        pages.append(.init(number: 3, selectable: "", recognized: "", method: .textRecognition, text: "", excluded: true))
        let excludedBody = try RecordReview.body(pages)
        check(excludedBody.contains("## Page 2"), "explicitly excluded empty pages do not discard reviewed pages")
        for name in ["Lumen-record-locked.pdf", "Lumen-record-too-many.pdf", "Lumen-record-damaged.pdf"] {
            do { _ = try RecordImportService.read(folder.appendingPathComponent(name), control: RecordImportControl()); fatalError("invalid record accepted") }
            catch { print("PASS: rejected record fixture " + name) }
        }
        let cancelled = RecordImportControl(); cancelled.cancel()
        do { _ = try RecordImportService.read(folder.appendingPathComponent("Lumen-record-scan.pdf"), control: cancelled); fatalError("cancelled accepted") }
        catch is CancellationError { print("PASS: cancelled record read yields no preview") }
        let flag = RecordTestFlag(); cancelled.setCancellationHandler { flag.set() }
        check(flag.value, "late-registered record cancellation handler is called immediately")
        let large = folder.appendingPathComponent("Lumen-record-oversize.txt")
        _ = FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large); try handle.truncate(atOffset: 20_000_001); try handle.close()
        do { _ = try RecordImportService.read(large, control: RecordImportControl()); fatalError("oversize accepted") } catch { print("PASS: oversized record is rejected before extraction") }
    }
}

private final class RecordTestFlag: @unchecked Sendable {
    private let lock = NSLock(); private var stored = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
    func set() { lock.lock(); stored = true; lock.unlock() }
}

private final class RecordTestOutcome: @unchecked Sendable {
    private let lock = NSLock(); private var result: Result<RecordImportService.Preview, Error>?
    func set(_ value: Result<RecordImportService.Preview, Error>) { lock.lock(); result = value; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; if case .failure(let error) = result { return error is CancellationError }; return false }
}
