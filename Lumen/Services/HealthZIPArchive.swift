import Foundation
import ZIPFoundation

enum HealthZIPError: LocalizedError, Equatable {
    case invalid, missingXML, ambiguousXML, unsafeEntry, expandedTooLarge, tooManyEntries, checksum
    var errorDescription: String? {
        switch self {
        case .invalid: return "This ZIP couldn’t be read. Choose the original, unencrypted export from Apple Health."
        case .missingXML: return "This ZIP has no export.xml health history. Choose the export created by Apple Health."
        case .ambiguousXML: return "This ZIP contains more than one health export. Choose a ZIP with one export.xml, or select the XML file directly."
        case .unsafeEntry: return "This ZIP contains an unsafe file entry. Choose the original Apple Health export. Nothing was added."
        case .expandedTooLarge: return "The health history inside this ZIP exceeds the 500 MB limit. Keep the original export and import a smaller XML or metrics file."
        case .tooManyEntries: return "This ZIP contains too many files to review safely. Select its export.xml file directly."
        case .checksum: return "The health history failed its integrity check. Choose another copy of the export. Nothing was added."
        }
    }
}

/// Opens one bounded, regular XML entry at a fixed temporary filename. Other entries are never extracted.
enum HealthZIPArchive {
    static let maxExpandedBytes: Int64 = 500_000_000
    static let maxEntries = 100_000
    static var temporaryRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("LumenHealthImports", isDirectory: true) }

    static func safePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains("..") && !parts.contains(".") && !parts.dropLast().contains("")
    }

    static func withXML<T>(in url: URL, control: HealthImportControl,
                           extracted: (Int64) -> Void = { _ in }, body: (URL) throws -> T) throws -> T {
        try control.checkCancellation()
        let folder = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            // Snapshot an externally provided file before checking offsets, avoiding a changing-file race.
            let snapshot = folder.appendingPathComponent("source.zip")
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            let total = try input.seekToEnd()
            guard total <= UInt64(maxExpandedBytes) else { throw HealthImportError.tooLarge }
            try input.seek(toOffset: 0)
            try Data().write(to: snapshot, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let copy = try FileHandle(forWritingTo: snapshot)
            defer { try? copy.close() }
            var copied: Int64 = 0
            control.copyingArchive(bytes: 0, total: Int64(total))
            while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try control.checkCancellation()
                guard Int64(chunk.count) <= maxExpandedBytes - copied else { throw HealthImportError.tooLarge }
                copied += Int64(chunk.count)
                try copy.write(contentsOf: chunk)
                control.copyingArchive(bytes: copied, total: Int64(total))
            }
            try copy.close()
            guard copied == Int64(total) else { throw HealthZIPError.invalid }
            control.checkingArchive()
            let summary = try ZIPPreflight.validate(snapshot, control: control)
            if !summary.zeroOffsetFields.isEmpty {
                // ZIPFoundation 0.9.20 falls back to the 32-bit field when a ZIP64 offset is zero.
                // Normalize only this validated field in our private copy; original exports are untouched.
                let normalized = try FileHandle(forWritingTo: snapshot)
                defer { try? normalized.close() }
                for offset in summary.zeroOffsetFields {
                    try control.checkCancellation()
                    try normalized.seek(toOffset: offset)
                    try normalized.write(contentsOf: Data(repeating: 0, count: 4))
                }
                try normalized.close()
            }
            let archive = try Archive(url: snapshot, accessMode: .read)
            var selected: Entry?
            var count = 0
            for entry in archive {
                try control.checkCancellation()
                count += 1
                guard count <= maxEntries else { throw HealthZIPError.tooManyEntries }
                guard safePath(entry.path), entry.type != .symlink else { throw HealthZIPError.unsafeEntry }
                if entry.path.split(separator: "/").last?.lowercased() == "export.xml", entry.type != .directory {
                    guard selected == nil else { throw HealthZIPError.ambiguousXML }
                    guard entry.type == .file else { throw HealthZIPError.unsafeEntry }
                    selected = entry
                }
            }
            guard count == summary.entries else { throw HealthZIPError.invalid }
            guard let entry = selected else { throw HealthZIPError.missingXML }
            guard entry.uncompressedSize > 0 else { throw HealthImportError.empty }
            guard entry.uncompressedSize <= UInt64(maxExpandedBytes) else { throw HealthZIPError.expandedTooLarge }
            guard entry.compressedSize <= summary.fileBytes else { throw HealthZIPError.invalid }
            let target = folder.appendingPathComponent("export.xml")
            try Data().write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let output = try FileHandle(forWritingTo: target)
            defer { try? output.close() }
            var written: Int64 = 0
            control.extractingArchive(bytes: 0, total: Int64(entry.uncompressedSize))
            let crc = try archive.extract(entry, bufferSize: 64 * 1024, skipCRC32: false) { chunk in
                try control.checkCancellation()
                guard Int64(chunk.count) <= maxExpandedBytes - written else { throw HealthZIPError.expandedTooLarge }
                written += Int64(chunk.count)
                guard written <= Int64(entry.uncompressedSize) else { throw HealthZIPError.checksum }
                try output.write(contentsOf: chunk)
                control.extractingArchive(bytes: written, total: Int64(entry.uncompressedSize))
                extracted(written)
                try control.checkCancellation()
            }
            guard crc == entry.checksum, written == Int64(entry.uncompressedSize) else { throw HealthZIPError.checksum }
            try output.close()
            try control.checkCancellation()
            try FileManager.default.removeItem(at: snapshot)
            control.readingRecords()
            return try body(target)
        } catch {
            try control.checkCancellation()
            if error is HealthZIPError || error is HealthImportError || error is CocoaError { throw error }
            throw HealthZIPError.invalid
        }
    }

    /// Called once on process launch; interrupted imports never survive into a later session.
    static func clearTemporaryFiles() { try? FileManager.default.removeItem(at: temporaryRoot) }
}
