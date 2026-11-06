import Foundation

/// Device-local intent and receipts. This file is deliberately absent from
/// BackupArchive/ReadableExport: importing records is never permission to send
/// another device's pending Health operations.
struct HealthWriteJournal: Codable, Equatable, Sendable {
    static let maxBytes = 100 * 1024 * 1024
    enum Failure: Error { case invalid, unsupportedVersion, duplicateRecord, staleClaim, foreignOwner }
    enum Domain: String, Codable, Sendable { case water, meal, weight }
    enum Metric: String, Codable, CaseIterable, Sendable {
        case water, calories, protein, carbs, fat, fiber, weight
        var domain: Domain {
            switch self { case .water: return .water; case .weight: return .weight; default: return .meal }
        }
    }
    enum Action: String, Codable, Sendable { case save, delete }
    enum Identity: String, Codable, Sendable { case sync, legacyDeletion }
    enum Issue: String, Codable, Sendable { case unavailable, permission, operation, receipt }
    struct Component: Codable, Equatable, Sendable {
        let metric: Metric
        let value: Double
        let date: Date
    }
    struct Event: Codable, Equatable, Sendable {
        let id: UUID
        let lifecycle: UUID
        let domain: Domain
        let localID: String
        let identity: Identity
        let components: [Component]
        fileprivate(set) var generation: UUID
        fileprivate(set) var requestedAt: Date
        fileprivate(set) var action: Action
        fileprivate(set) var acknowledged: Set<Metric>
        fileprivate(set) var issue: Issue?
        var complete: Bool { acknowledged == Set(components.map(\.metric)) }
    }
    /// An immutable operation snapshot. A late receipt must match this exact
    /// owner/event/generation/action/component; it cannot acknowledge a deletion
    /// or a replacement lifecycle on behalf of an earlier save.
    struct Claim: Equatable, Sendable {
        let owner: UUID
        let event: UUID
        let lifecycle: UUID
        let generation: UUID
        let domain: Domain
        let localID: String
        let identity: Identity
        let action: Action
        let component: Component
        var syncIdentifier: String {
            "com.dbakp.lumen.health.v1.\(owner.uuidString).\(event.uuidString).\(component.metric.rawValue)"
        }
        let syncVersion = 1
    }

    let version: Int
    let owner: UUID
    private(set) var lifecycle: UUID
    private(set) var events: [Event]

    init(owner: UUID = UUID(), lifecycle: UUID = UUID()) {
        version = 1; self.owner = owner; self.lifecycle = lifecycle; events = []
    }

    mutating func append(domain: Domain, localID: String, components: [Component]) throws {
        guard !events.contains(where: { $0.domain == domain && $0.localID == localID }) else { throw Failure.duplicateRecord }
        let event = Event(id: UUID(), lifecycle: lifecycle, domain: domain, localID: localID,
                          identity: .sync, components: components, generation: UUID(), requestedAt: Date(), action: .save,
                          acknowledged: [], issue: nil)
        try Self.validate(event)
        events.append(event)
    }

    /// An explicit delete keeps the same external identities and payload. Even
    /// acknowledged save components need their own deletion acknowledgement.
    /// Missing legacy receipts allow deletion only, never manufacture a save.
    mutating func requestDeletion(domain: Domain, localID: String) throws {
        guard domain != .weight else { throw Failure.invalid } // no weight deletion UI exists
        if let index = events.firstIndex(where: { $0.domain == domain && $0.localID == localID }) {
            guard events[index].action != .delete else { return }
            events[index].action = .delete; events[index].generation = UUID()
            events[index].requestedAt = Date()
            events[index].acknowledged = []; events[index].issue = nil
        } else {
            let metrics: [Metric] = domain == .water ? [.water] : [.calories, .protein, .carbs, .fat, .fiber]
            let event = Event(id: UUID(), lifecycle: lifecycle, domain: domain, localID: localID, identity: .legacyDeletion,
                              components: metrics.map { Component(metric: $0, value: 0, date: Date(timeIntervalSince1970: 0)) },
                              generation: UUID(), requestedAt: Date(), action: .delete, acknowledged: [], issue: nil)
            try Self.validate(event); events.append(event)
        }
    }

    /// Restore/reset withdraw unstarted saves from the old lifecycle. Explicit
    /// pending deletions and their source-owned identities remain recoverable.
    /// Old receipts remain as ownership evidence; no imported record is queued.
    mutating func rotateLifecycle() { lifecycle = UUID() }

    mutating func resetRetainingDeletions() {
        lifecycle = UUID()
        events = events.filter { $0.action == .delete && !$0.complete }.map { old in
            Event(id: old.id, lifecycle: old.lifecycle, domain: old.domain, localID: old.localID,
                  identity: old.identity,
                  components: old.components.map { Component(metric: $0.metric, value: 0, date: Date(timeIntervalSince1970: 0)) },
                  generation: UUID(), requestedAt: old.requestedAt, action: .delete, acknowledged: old.acknowledged, issue: old.issue)
        }
    }

    func next(excluding active: Set<UUID> = []) -> Claim? {
        for event in events where !active.contains(event.id) && !event.complete {
            guard event.action == .delete || event.lifecycle == lifecycle else { continue }
            if let component = event.components.first(where: { !event.acknowledged.contains($0.metric) }) {
                return Claim(owner: owner, event: event.id, lifecycle: event.lifecycle, generation: event.generation,
                             domain: event.domain, localID: event.localID, identity: event.identity,
                             action: event.action, component: component)
            }
        }
        return nil
    }

    func contains(_ claim: Claim) -> Bool {
        guard claim.owner == owner, let event = events.first(where: { $0.id == claim.event }),
              event.lifecycle == claim.lifecycle, event.generation == claim.generation,
              event.domain == claim.domain, event.localID == claim.localID, event.identity == claim.identity,
              event.action == claim.action, event.components.contains(claim.component),
              !event.acknowledged.contains(claim.component.metric) else { return false }
        return event.action == .delete || event.lifecycle == lifecycle
    }

    mutating func acknowledge(_ claim: Claim) throws {
        guard contains(claim), let index = events.firstIndex(where: { $0.id == claim.event }) else { throw Failure.staleClaim }
        events[index].acknowledged.insert(claim.component.metric); events[index].issue = nil
    }

    mutating func recordFailure(_ claim: Claim, issue: Issue) throws {
        guard contains(claim), let index = events.firstIndex(where: { $0.id == claim.event }) else { throw Failure.staleClaim }
        events[index].issue = issue
    }

    var pendingEvents: [Event] {
        events.filter { !$0.complete && ($0.action == .delete || $0.lifecycle == lifecycle) }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maxBytes else { throw Failure.invalid }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maxBytes else { throw Failure.invalid }
        try JSONFieldAudit.check(data, control: .init())
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    private func validate() throws {
        guard version == 1 else { throw Failure.unsupportedVersion }
        guard Set(events.map(\.id)).count == events.count else { throw Failure.duplicateRecord }
        var keys = Set<String>()
        for event in events {
            guard keys.insert(event.domain.rawValue + ":" + event.localID).inserted else { throw Failure.duplicateRecord }
            try Self.validate(event)
        }
    }
    private static func validate(_ event: Event) throws {
        guard !event.localID.isEmpty, event.localID.utf8.count <= 256,
              event.requestedAt.timeIntervalSince1970.isFinite,
              !event.localID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !event.components.isEmpty,
              Set(event.components.map(\.metric)).count == event.components.count,
              event.acknowledged.isSubset(of: Set(event.components.map(\.metric))),
              event.identity != .legacyDeletion || (event.action == .delete && event.domain != .weight) else { throw Failure.invalid }
        for component in event.components {
            guard component.metric.domain == event.domain, component.value.isFinite,
                  component.date.timeIntervalSince1970.isFinite,
                  component.value >= 0, event.action == .delete || component.value > 0 else { throw Failure.invalid }
        }
    }
}
