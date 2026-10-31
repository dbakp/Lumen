import Foundation

/// Only NSFileCoordinator's documented any-thread cancellation crosses threads.
private final class LabFileCoordinatorCancellation: @unchecked Sendable {
    let coordinator: NSFileCoordinator
    init(_ coordinator: NSFileCoordinator) { self.coordinator = coordinator }
    func cancel() { coordinator.cancel() }
}

enum LabFileImportService {
    struct Input: Sendable {
        let data: Data
        let filename: String
        let readAt: Date
        func parse(separator: String? = nil, control: BackupOperationControl) throws -> LabTable {
            try LabTable.parse(data, filename: filename, separator: separator, control: control, now: readAt)
        }
    }
    enum Failure: LocalizedError {
        case file, fhirFormat
        var errorDescription: String? {
            switch self {
            case .file: return "Choose a nonempty supported data file. Shortcuts, folders and symbolic links aren't supported."
            case .fhirFormat: return "Choose a FHIR JSON or NDJSON file. Keep bulk-export manifests and companion files separate."
            }
        }
    }
    static func read(_ url: URL, control: BackupOperationControl, fhir: Bool = false) throws -> Input {
        try control.checkCancellation()
        guard (fhir ? ["json", "ndjson"] : ["csv", "tsv", "json"]).contains(url.pathExtension.lowercased()) else {
            if fhir { throw Failure.fhirFormat }
            throw LabTable.Failure.format
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.file }
        let coordinator = NSFileCoordinator()
        let bridge = LabFileCoordinatorCancellation(coordinator)
        control.setCancellationHandler { bridge.cancel() }
        defer { control.setCancellationHandler(nil) }
        var failure: NSError?, result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &failure) { path in
            result = Result {
                try control.checkCancellation()
                let info = try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true, let size = info.fileSize, size > 0 else { throw Failure.file }
                guard size <= LabTable.maxBytes else { throw LabTable.Failure.tooLarge }
                let handle = try FileHandle(forReadingFrom: path)
                defer { try? handle.close() }
                var data = Data()
                while true {
                    try control.checkCancellation()
                    let bytes = try handle.read(upToCount: min(64 * 1024, LabTable.maxBytes + 1 - data.count)) ?? Data()
                    if bytes.isEmpty { break }
                    data.append(bytes)
                    guard data.count <= LabTable.maxBytes else { throw LabTable.Failure.tooLarge }
                }
                guard !data.isEmpty else { throw Failure.file }
                return data
            }
        }
        try control.checkCancellation()
        if let failure { throw failure }
        guard let result else { throw Failure.file }
        return try Input(data: result.get(), filename: url.lastPathComponent, readAt: Date())
    }
}
