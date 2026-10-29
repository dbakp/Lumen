import Foundation
import ZIPFoundation

enum ZIPImportChecks {
    static func run(in directory: URL) throws {
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            print("PASS: " + message)
        }
        let xml = Data("""
        <HealthData>
        <Record type="HKQuantityTypeIdentifierStepCount" value="8421" unit="count" startDate="2026-01-01 10:00:00 +0000" endDate="2026-01-01 10:00:00 +0000" sourceName="ZIP test Watch"/>
        <Record type="HKQuantityTypeIdentifierDietaryWater" value="0.25" unit="L" startDate="2026-01-01 11:00:00 +0000" endDate="2026-01-01 11:00:00 +0000" sourceName="ZIP test bottle"/>
        </HealthData>
        """.utf8)
        func make(_ name: String, _ entries: [(String, Data, Entry.EntryType)], method: CompressionMethod = .deflate) throws -> URL {
            let url = directory.appendingPathComponent(name + ".zip")
            let archive = try Archive(url: url, accessMode: .create)
            for (path, bytes, type) in entries {
                try archive.addEntry(with: path, type: type, uncompressedSize: Int64(bytes.count), compressionMethod: method) { position, size in
                    bytes.subdata(in: Int(position)..<(Int(position) + size))
                }
            }
            return url
        }
        let standard = try make("apple-health", [("apple_health_export/export.xml", xml, .file), ("apple_health_export/export_cda.xml", Data("ignored clinical file".utf8), .file), ("apple_health_export/workout-routes/route.gpx", Data("ignored route".utf8), .file)])
        let control = HealthImportControl()
        let preview = try HealthImportService.parse(url: standard, control: control)
        check(preview.samples == 2 && preview.days.count == 1 && preview.days[0].values["steps"] == 8421 && preview.days[0].values["water"] == 250, "Apple Health ZIP produces the same canonical daily preview as XML")
        check(preview.sourceNames == ["ZIP test Watch", "ZIP test bottle"], "ZIP preview preserves original measurement sources")
        check(control.recordsProcessed == 2 && control.progress.extractedBytes == Int64(xml.count), "ZIP extraction and record-reading progress use actual byte and record counts")
        var extractedURL: URL?
        let onlyXML = try HealthZIPArchive.withXML(in: standard, control: HealthImportControl()) { url in
            extractedURL = url
            return try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        }
        check(onlyXML == ["export.xml"], "ZIP import extracts only health XML to a fixed filename")
        check(!FileManager.default.fileExists(atPath: extractedURL!.path), "temporary XML is removed after a successful preview")
        let rootExport = try make("root-export", [("export.xml", xml, .file)], method: .none)
        let storedPreview = try HealthImportService.parse(url: rootExport)
        check(storedPreview.samples == 2, "stored ZIP entries and root-level export.xml are supported")
        func rejects(_ url: URL, as expected: HealthZIPError, _ message: String) throws {
            do { _ = try HealthImportService.parse(url: url); fatalError(message) }
            catch let actual as HealthZIPError { check(actual == expected, message) }
        }
        try rejects(make("missing-export", [("export_cda.xml", xml, .file)]), as: .missingXML, "ZIPs without export.xml are rejected before adding history")
        try rejects(make("ambiguous-export", [("export.xml", xml, .file), ("another/export.xml", xml, .file)]), as: .ambiguousXML, "multiple health exports require an explicit choice outside the ZIP")
        try rejects(make("unsafe-export", [("../export.xml", xml, .file)]), as: .unsafeEntry, "ZIP path traversal is rejected")
        try rejects(make("absolute-export", [("/export.xml", xml, .file)]), as: .unsafeEntry, "absolute ZIP paths are rejected")
        try rejects(make("backslash-export", [("folder\\export.xml", xml, .file)]), as: .unsafeEntry, "backslash ZIP paths are rejected")
        try rejects(make("linked-export", [("export.xml", Data("outside.xml".utf8), .symlink)]), as: .unsafeEntry, "symbolic-link exports are rejected")
        let invalid = directory.appendingPathComponent("invalid.zip")
        try Data("not an archive".utf8).write(to: invalid)
        try rejects(invalid, as: .invalid, "malformed ZIP containers are rejected")
        var damaged = try Data(contentsOf: rootExport)
        let payload = damaged.range(of: xml)!
        damaged[payload.lowerBound] ^= 1
        let corrupt = directory.appendingPathComponent("corrupt.zip"); try damaged.write(to: corrupt)
        try rejects(corrupt, as: .checksum, "corrupt XML payload fails CRC before parsing")
        let deflatedSize = try make("size-base", [("export.xml", xml, .file)])
        var expanded = try Data(contentsOf: deflatedSize)
        let local = expanded.range(of: Data([0x50, 0x4b, 0x03, 0x04]))!.lowerBound
        let central = expanded.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        func write32(_ value: UInt32, at offset: Int, in bytes: inout Data) {
            for i in 0..<4 { bytes[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        }
        write32(UInt32(HealthZIPArchive.maxExpandedBytes + 1), at: local + 22, in: &expanded)
        write32(UInt32(HealthZIPArchive.maxExpandedBytes + 1), at: central + 24, in: &expanded)
        let oversized = directory.appendingPathComponent("oversized.zip"); try expanded.write(to: oversized)
        try rejects(oversized, as: .expandedTooLarge, "declared expanded XML size is checked before extraction")
        var understated = try Data(contentsOf: deflatedSize)
        let understatedLocal = understated.range(of: Data([0x50, 0x4b, 0x03, 0x04]))!.lowerBound
        let understatedCentral = understated.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        write32(1, at: understatedLocal + 22, in: &understated)
        write32(1, at: understatedCentral + 24, in: &understated)
        let understatedURL = directory.appendingPathComponent("understated.zip"); try understated.write(to: understatedURL)
        try rejects(understatedURL, as: .checksum, "actual extraction bytes cannot exceed a declared XML size")
        let emptyXML = try make("empty-xml", [("export.xml", Data(), .file)], method: .none)
        do { _ = try HealthImportService.parse(url: emptyXML); fatalError("empty archived XML accepted") }
        catch HealthImportError.empty { print("PASS: empty archived XML reports missing measurements rather than a size error") }
        // Build small ZIP64 directory fixtures; no large files or allocations are required.
        let original = try Data(contentsOf: rootExport)
        let originalEnd = original.range(of: Data([0x50, 0x4b, 0x05, 0x06]))!.lowerBound
        let originalCentral = original.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        func number(_ value: UInt64, width: Int) -> Data {
            Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        func write64(_ value: UInt64, at offset: Int, in bytes: inout Data) {
            bytes.replaceSubrange(offset..<(offset + 8), with: number(value, width: 8))
        }
        var zip64 = original.subdata(in: 0..<originalEnd)
        let recordOffset = zip64.count
        zip64.append(number(0x06064b50, width: 4)); zip64.append(number(44, width: 8))
        zip64.append(number(45, width: 2)); zip64.append(number(45, width: 2))
        zip64.append(number(0, width: 4)); zip64.append(number(0, width: 4))
        zip64.append(number(1, width: 8)); zip64.append(number(1, width: 8))
        zip64.append(number(UInt64(originalEnd - originalCentral), width: 8)); zip64.append(number(UInt64(originalCentral), width: 8))
        zip64.append(number(0x07064b50, width: 4)); zip64.append(number(0, width: 4))
        zip64.append(number(UInt64(recordOffset), width: 8)); zip64.append(number(1, width: 4))
        var zip64End = original.subdata(in: originalEnd..<original.count)
        zip64End.replaceSubrange(8..<12, with: Data(repeating: 0xff, count: 4))
        zip64End.replaceSubrange(12..<20, with: Data(repeating: 0xff, count: 8))
        zip64.append(zip64End)
        let zip64URL = directory.appendingPathComponent("zip64.zip"); try zip64.write(to: zip64URL)
        let zip64Preview = try HealthImportService.parse(url: zip64URL)
        check(zip64Preview.samples == 2, "standard bounded ZIP64 directories remain readable")
        var invalidOffset = zip64
        write64(UInt64.max, at: recordOffset + 48, in: &invalidOffset)
        let invalidOffsetURL = directory.appendingPathComponent("zip64-overflow.zip"); try invalidOffset.write(to: invalidOffsetURL)
        try rejects(invalidOffsetURL, as: .invalid, "ZIP64 directory offset overflow is rejected before library access")
        var excessiveCount = zip64
        write64(100001, at: recordOffset + 24, in: &excessiveCount)
        write64(100001, at: recordOffset + 32, in: &excessiveCount)
        let excessiveCountURL = directory.appendingPathComponent("zip64-count.zip"); try excessiveCount.write(to: excessiveCountURL)
        try rejects(excessiveCountURL, as: .tooManyEntries, "ZIP entry count is bounded before directory iteration")
        func localOffsetArchive(_ value: UInt64) -> Data {
            var header = original.subdata(in: originalCentral..<(originalCentral + 46))
            header.replaceSubrange(30..<32, with: number(12, width: 2))
            header.replaceSubrange(42..<46, with: number(UInt64(UInt32.max), width: 4))
            var result = original.subdata(in: 0..<originalCentral)
            result.append(header); result.append(Data("export.xml".utf8))
            result.append(number(1, width: 2)); result.append(number(8, width: 2)); result.append(number(value, width: 8))
            var end = original.subdata(in: originalEnd..<original.count)
            write32(UInt32(originalEnd - originalCentral + 12), at: 12, in: &end)
            result.append(end); return result
        }
        let boundedLocalURL = directory.appendingPathComponent("zip64-local.zip"); try localOffsetArchive(0).write(to: boundedLocalURL)
        let boundedLocalPreview = try HealthImportService.parse(url: boundedLocalURL)
        check(boundedLocalPreview.samples == 2, "ZIP64 entry offsets within the file remain supported")
        let originalAfterImport = try Data(contentsOf: boundedLocalURL)
        check(originalAfterImport == localOffsetArchive(0), "ZIP64 normalization never changes the user's original export")
        let overflowLocalURL = directory.appendingPathComponent("zip64-local-overflow.zip"); try localOffsetArchive(UInt64.max).write(to: overflowLocalURL)
        try rejects(overflowLocalURL, as: .invalid, "ZIP64 local-header offset overflow is rejected before seeking")
        var encrypted = original
        encrypted.replaceSubrange(6..<8, with: number(0x801, width: 2))
        encrypted.replaceSubrange((originalCentral + 8)..<(originalCentral + 10), with: number(0x801, width: 2))
        let encryptedURL = directory.appendingPathComponent("encrypted.zip"); try encrypted.write(to: encryptedURL)
        try rejects(encryptedURL, as: .invalid, "encrypted ZIP entries require an original unencrypted export")
        let truncatedURL = directory.appendingPathComponent("truncated.zip"); try original.dropLast(5).write(to: truncatedURL)
        try rejects(truncatedURL, as: .invalid, "truncated ZIP directory metadata is rejected")
        var mismatchedName = original; mismatchedName[originalCentral + 46] ^= 1
        let mismatchURL = directory.appendingPathComponent("mismatched.zip"); try mismatchedName.write(to: mismatchURL)
        try rejects(mismatchURL, as: .invalid, "mismatched local and central file names are rejected")
        let before = (try? FileManager.default.contentsOfDirectory(atPath: HealthZIPArchive.temporaryRoot.path)) ?? []
        let cancelled = HealthImportControl()
        do {
            _ = try HealthZIPArchive.withXML(in: standard, control: cancelled, extracted: { _ in cancelled.cancel() }) { _ in fatalError("cancelled extraction yielded XML") }
            fatalError("extraction ignored cancellation")
        } catch is CancellationError { print("PASS: cancellation during extraction discards its partial XML") }
        let after = (try? FileManager.default.contentsOfDirectory(atPath: HealthZIPArchive.temporaryRoot.path)) ?? []
        check(Set(before) == Set(after), "cancelled extraction removes its temporary directory")
        let cancelledBefore = HealthImportControl(); cancelledBefore.cancel()
        do { _ = try HealthImportService.parse(url: standard, control: cancelledBefore); fatalError("cancelled ZIP started") }
        catch is CancellationError { print("PASS: cancelled ZIP imports stop before opening the archive") }
        var failingBodyURL: URL?
        do {
            let _: Void = try HealthZIPArchive.withXML(in: standard, control: HealthImportControl()) { url in
                failingBodyURL = url; throw HealthImportError.empty
            }
        } catch HealthImportError.empty { }
        check(failingBodyURL != nil && !FileManager.default.fileExists(atPath: failingBodyURL!.path), "temporary XML is removed when preview parsing fails")
        let badXML = try make("bad-xml", [("export.xml", Data("<HealthData><Record>".utf8), .file)])
        do { _ = try HealthImportService.parse(url: badXML); fatalError("malformed archived XML accepted") }
        catch HealthImportError.malformed { print("PASS: malformed archived XML retains a useful import error") }
        let stale = HealthZIPArchive.temporaryRoot.appendingPathComponent("interrupted-session")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("stale sensitive XML".utf8).write(to: stale.appendingPathComponent("export.xml"))
        HealthZIPArchive.clearTemporaryFiles()
        check(!FileManager.default.fileExists(atPath: stale.path), "launch cleanup removes temporary data from interrupted imports")
    }
}
