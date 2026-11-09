import Foundation

/// The enclosing Settings navigation container owns this lifetime boundary.
/// Closing the container retires a review even while a child is displayed.
final class HealthRetainedRecoveryReviewScope: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var session: HealthRetainedRecoveryReviewSession?
    func review(_ preview: HealthRecoveryCopies.Preview, in root: URL) throws -> HealthRetainedRecoveryReviewSession {
        lock.lock()
        guard !closed else { lock.unlock(); throw CancellationError() }
        let next = HealthRetainedRecoveryReviewSession(preview, in: root)
        let old = session; session = next
        lock.unlock()
        old?.close()
        return next
    }
    func close() {
        lock.lock(); closed = true; let old = session; session = nil; lock.unlock()
        old?.close()
    }
    deinit { close() }
}

/// Cached destinations keep this closable authority and display metadata.
/// Permanent retained copies remain on disk when the user leaves their review.
final class HealthRetainedRecoveryReviewSession: @unchecked Sendable {
    struct Summary: Sendable {
        let copyID: String
        let createdAt: Date?
        let domains: [HealthRecoveryCopies.DomainPreview]
        var readableDomains: Set<HealthLocalFiles.Domain> {
            Set(domains.filter { $0.state == .readable }.map(\.domain))
        }
    }
    let id = UUID()
    let summary: Summary
    private let sourceRoot: URL
    private let copy: BackupReviewLease<HealthRecoveryCopies.Preview>
    private let origins = HealthRecoveryOriginReviewLease()
    // Only lifetime flags and operation controls use this lock. Cancellation
    // callbacks run after unlocking; raw observations stay in the origin lease.
    private let lock = NSLock()
    private var closed = false
    private var operations: [UUID: BackupOperationControl] = [:]
    var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }
    var originMetadata: HealthLegacyRecoveryOrigin.ReviewMetadata? { isClosed ? nil : origins.metadata }
    var originState: HealthRecoveryOriginReviewLease.Phase { isClosed ? .closed : origins.state }

    /// Keep this registration through the entire recovery, including commit.
    /// Leaving review cancels its actual control even after payload preparation.
    func beginOperation(control: BackupOperationControl) throws -> UUID {
        try control.checkCancellation()
        lock.lock(); defer { lock.unlock() }
        guard !closed else { throw CancellationError() }
        let id = UUID(); operations[id] = control; return id
    }
    func endOperation(_ id: UUID) { lock.lock(); operations.removeValue(forKey: id); lock.unlock() }
    func checkOpen(control: BackupOperationControl) throws {
        try control.checkCancellation()
        guard !isClosed else { throw CancellationError() }
        try control.checkCancellation()
    }

    init(_ preview: HealthRecoveryCopies.Preview, in root: URL) {
        summary = Summary(copyID: preview.id, createdAt: preview.createdAt, domains: preview.domains)
        sourceRoot = root
        copy = BackupReviewLease(preview)
        #if DEBUG && targetEnvironment(simulator)
        note("opened")
        #endif
    }

    /// The detached caller returns Void, never a raw ReviewSnapshot result.
    func captureOrigins(control: BackupOperationControl,
                        capture: (Set<HealthLocalFiles.Domain>, BackupOperationControl) throws
                            -> HealthLegacyRecoveryOrigin.ReviewSnapshot) throws {
        let operation = try beginOperation(control: control)
        defer { endOperation(operation) }
        let reviewed = try copy.acquire(control: control)
        defer { withExtendedLifetime(reviewed) {} }
        try origins.begin(control)
        #if DEBUG && targetEnvironment(simulator)
        note("capture-started", operation: operation)
        #endif
        do {
            let snapshot = try capture(summary.readableDomains, control)
            #if DEBUG && targetEnvironment(simulator)
            try HealthRetainedReviewUIFixture.afterCapture(session: id, root: sourceRoot, operation: operation, control: control,
                closed: { self.isClosed }, metadata: { self.originMetadata != nil })
            #endif
            try origins.finish(snapshot, control: control)
            try checkOpen(control: control)
            #if DEBUG && targetEnvironment(simulator)
            note("capture-ready", operation: operation)
            #endif
        } catch {
            origins.suspend(control)
            #if DEBUG && targetEnvironment(simulator)
            note(error is CancellationError ? "capture-cancelled" : "capture-failed", operation: operation)
            #endif
            throw error
        }
    }

    func suspendOriginCapture(control: BackupOperationControl) { origins.suspend(control) }

    func records(domain: HealthLocalFiles.Domain, control: BackupOperationControl) throws -> Data {
        let operation = try beginOperation(control: control)
        defer { endOperation(operation) }
        let reviewed = try copy.acquire(control: control)
        defer { withExtendedLifetime(reviewed) {} }
        let data = try HealthRecoverySelection.records(reviewed, domain: domain, in: sourceRoot, control: control)
        try checkOpen(control: control)
        #if DEBUG && targetEnvironment(simulator)
        note("records-read", operation: operation)
        #endif
        return data
    }

    func photoData(_ id: String, control: BackupOperationControl) throws -> Data {
        let operation = try beginOperation(control: control)
        defer { endOperation(operation) }
        let reviewed = try copy.acquire(control: control)
        defer { withExtendedLifetime(reviewed) {} }
        let data = try HealthRecoverySelection.photoData(reviewed, id: id, in: sourceRoot, control: control)
        try checkOpen(control: control)
        #if DEBUG && targetEnvironment(simulator)
        note("photo-read", operation: operation)
        #endif
        return data
    }

    func payload(domains: Set<HealthLocalFiles.Domain>,
                 legacyDomains: Set<HealthLocalFiles.Domain>, omittingPhotos: Set<String>,
                 control: BackupOperationControl, validPhoto: (URL) -> Bool) throws -> HealthRecoverySelection.Payload {
        let operation = try beginOperation(control: control)
        defer { endOperation(operation) }
        try control.checkCancellation()
        guard !domains.isEmpty, domains.isSubset(of: summary.readableDomains),
              let metadata = origins.metadata,
              domains.isSubset(of: metadata.recoverableDomains),
              legacyDomains == domains.intersection(metadata.legacyDomains) else { throw BackupError.recordsChanged }
        let selectedOrigins = try origins.acquire(legacyDomains, control: control)
        let reviewed = try copy.acquire(control: control)
        defer { withExtendedLifetime(reviewed) {} }
        let payload = try HealthRecoverySelection.retained(reviewed, in: sourceRoot, domains: domains,
            omittingPhotos: omittingPhotos, control: control, validPhoto: validPhoto)
        try checkOpen(control: control)
        return try HealthRecoverySelection.bindingLegacyOrigins(selectedOrigins, to: payload)
    }

    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        let pending = Array(operations.values); operations.removeAll()
        lock.unlock()
        origins.close()
        copy.close()
        for control in pending { control.cancel() }
        #if DEBUG && targetEnvironment(simulator)
        note("closed")
        #endif
    }
    #if DEBUG && targetEnvironment(simulator)
    private func note(_ event: String, operation: UUID? = nil) {
        HealthRetainedReviewUIFixture.note(event, session: id, root: sourceRoot, operation: operation,
            closed: isClosed, metadata: originMetadata != nil)
    }
    #endif
}
