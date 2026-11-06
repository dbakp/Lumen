import Foundation

/// Shared by native persistence and process-restart verification. Missing is a
/// legacy installation; corrupt, unreadable or non-regular intent is an error,
/// never permission to replace it with an empty queue.
enum HealthWriteFiles {
    static let name = "health-write-intent.json"

    static func read(from directory: URL, owner: UUID? = nil) throws -> HealthWriteJournal {
        try BackupFiles.openDirectory(directory, createIfMissing: false)
        let file = directory.appendingPathComponent(name)
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: file.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return HealthWriteJournal(owner: owner ?? UUID())
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value >= 0,
              size.int64Value <= HealthWriteJournal.maxBytes else { throw HealthWriteJournal.Failure.invalid }
        let data: Data
        do { data = try HealthLocalFiles.readRegularData(file, limit: HealthWriteJournal.maxBytes) }
        catch is HealthLocalFiles.Failure { throw HealthWriteJournal.Failure.invalid }
        let journal = try HealthWriteJournal.decode(data)
        guard owner == nil || journal.owner == owner else { throw HealthWriteJournal.Failure.foreignOwner }
        return journal
    }

    static func prepare(_ files: [String: Data], journal: HealthWriteJournal,
                        into directory: URL) throws -> BackupFileTransaction {
        guard files[name] == nil else { throw HealthWriteJournal.Failure.invalid }
        var linked = files
        linked[name] = try journal.encoded()
        return try ConversationFiles.prepareLinkedChange(linked, into: directory)
    }

    static func prepareReset(into directory: URL, owner: UUID? = nil) throws -> BackupFileTransaction {
        // Account reset may discard foreign pending work, but cannot replay it.
        // A corrupt file still fails rather than masquerading as missing.
        var journal = try read(from: directory)
        if let owner, journal.owner != owner { journal = HealthWriteJournal(owner: owner) }
        journal.resetRetainingDeletions()
        return try ConversationFiles.prepareReplacement([name: journal.encoded(), HealthRecoveryCopies.erasureMarker: HealthRecoveryCopies.erasureMarkerData], into: directory)
    }

    static func prepareDeviceSetup(into directory: URL, owner: UUID) throws -> BackupFileTransaction {
        let previous = try read(from: directory)
        guard previous.owner != owner else { throw HealthWriteJournal.Failure.invalid }
        return try prepare([:], journal: HealthWriteJournal(owner: owner), into: directory)
    }
}
