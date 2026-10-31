import Foundation

/// Local resource identity graph for a reviewed FHIR R4 JSON/NDJSON import. This never
/// follows a URL, treats a display name as an identifier, or infers a subject
/// across report/observation relationships. It is not a FHIR profile validator.
struct FHIRResourceArchive: Sendable {
    struct Resource: Identifiable, Sendable {
        let id: String // JSON pointer, or /line/N plus within-line path; never a clinical ID.
        let node: LiteralJSON.Node
        let type: String
        let logicalID: String?
        let fullURL: String?
        let container: String?
        var version: String? { node["meta"]?["versionId"]?.string }
    }
    struct Entry: Sendable {
        let path: String
        let resourcePath: String?
        let requestMethod: String?
    }
    enum Resolution: Sendable, Equatable {
        case found(String), missing, ambiguous([String]), unsupported, invalid, wrongType(String)
    }
    enum Failure: LocalizedError {
        case root, resource(String), limit, contained(String), lineType(Int)
        var errorDescription: String? {
            switch self {
            case .root: return "Choose a FHIR JSON resource or Bundle. A flat JSON table uses the table import."
            case .resource(let path): return "Check the resource identity or structure at \(path.isEmpty ? "the file root" : path)."
            case .limit: return "This file has more than 1,024 resources or bundle entries. Split the export."
            case .contained(let path): return "Nested contained resources at \(path) aren't supported by FHIR R4. Export a fresh copy."
            case .lineType(let line): return "Each NDJSON line must contain one resource of the same type. Check line \(line); Bundles and mixed resource types need a JSON Bundle export."
            }
        }
    }
    static let maxResources = 1024
    let json: LiteralJSON.Document
    let filename: String
    let sha256: String
    let readAt: Date
    let format: FHIRInputFormat
    let bundleType: String?
    let entries: [Entry]
    let resources: [Resource]
    let hasNextPage: Bool
    private let byPath: [String: Int]
    private let byFullURL: [Data: [Int]]

    init(data: Data, filename: String, control: BackupOperationControl = .init(), now: Date = Date()) throws {
        guard LabReport.bounded(filename, limit: 500, required: true, multiline: false),
              !filename.contains("/"), !filename.contains("\\"), now.timeIntervalSince1970.isFinite else { throw Failure.root }
        let format: FHIRInputFormat = URL(fileURLWithPath: filename).pathExtension.lowercased() == "ndjson" ? .ndjson : .json
        let json = try format == .ndjson ? LiteralJSON.parseLines(data, maxLines: Self.maxResources, control: control) : LiteralJSON.parse(data, control: control)
        let rootType: String
        if format == .json {
            guard json.root.members != nil, let type = json.root["resourceType"]?.string, Self.validType(type) else { throw Failure.root }
            rootType = type
        } else { rootType = "NDJSON" }
        var resources: [Resource] = [], entries: [Entry] = []
        func add(_ node: LiteralJSON.Node, path: String, url: String?, container: String?) throws {
            try control.checkCancellation()
            guard resources.count < Self.maxResources else { throw Failure.limit }
            guard node.members != nil, let type = node["resourceType"]?.string, Self.validType(type) else { throw Failure.resource(path) }
            if let id = node["id"] { guard let text = id.string, Self.validID(text) else { throw Failure.resource(path) } }
            if let url {
                guard Self.isAbsolute(url), !url.contains("/_history/") else { throw Failure.resource(path) }
            }
            if let meta = node["meta"] {
                guard meta.members != nil else { throw Failure.resource(path) }
                if let version = meta["versionId"] { guard version.string.map(Self.validID) == true else { throw Failure.resource(path) } }
            }
            resources.append(.init(id: path, node: node, type: type, logicalID: node["id"]?.string, fullURL: url, container: container))
            if let contained = node["contained"] {
                guard container == nil else { throw Failure.contained(path) }
                guard let children = contained.elements else { throw Failure.resource(path + "/contained") }
                for (index, child) in children.enumerated() {
                    guard child["id"]?.string.map(Self.validID) == true else { throw Failure.resource(path + "/contained/\(index)") }
                    try add(child, path: path + "/contained/\(index)", url: nil, container: path)
                }
            }
        }
        if format == .ndjson {
            bundleType = nil
            var type: String?
            for (index, node) in (json.root.elements ?? []).enumerated() {
                guard let current = node["resourceType"]?.string, Self.validType(current), current != "Bundle", type == nil || type == current else { throw Failure.lineType(index + 1) }
                type = current
                let path = "/line/\(index + 1)"
                try add(node, path: path, url: nil, container: nil)
                entries.append(.init(path: path, resourcePath: path, requestMethod: nil))
            }
        } else if rootType == "Bundle" {
            guard let type = json.root["type"]?.string,
                  ["document", "message", "transaction", "transaction-response", "batch", "batch-response", "history", "searchset", "collection"].contains(type) else { throw Failure.root }
            bundleType = type
            let nodes: [LiteralJSON.Node]
            if let value = json.root["entry"] { guard let array = value.elements else { throw Failure.root }; nodes = array }
            else { nodes = [] }
            guard nodes.count <= Self.maxResources else { throw Failure.limit }
            for (index, entry) in nodes.enumerated() {
                try control.checkCancellation()
                let path = "/entry/\(index)"
                guard entry.members != nil else { throw Failure.resource(path) }
                let url: String?
                if let full = entry["fullUrl"] { guard let value = full.string else { throw Failure.resource(path) }; url = value }
                else { url = nil }
                if let resource = entry["resource"] {
                    let resourcePath = path + "/resource"
                    try add(resource, path: resourcePath, url: url, container: nil)
                    entries.append(.init(path: path, resourcePath: resourcePath, requestMethod: entry["request"]?["method"]?.string))
                } else {
                    // Request/response-only entries are retained in coverage.
                    // They must never disappear as if every entry had a result.
                    guard entry["request"]?.members != nil || entry["response"]?.members != nil else { throw Failure.resource(path) }
                    entries.append(.init(path: path, resourcePath: nil, requestMethod: entry["request"]?["method"]?.string))
                }
            }
        } else {
            bundleType = nil
            try add(json.root, path: "", url: nil, container: nil)
            entries.append(.init(path: "", resourcePath: "", requestMethod: nil))
        }
        self.json = json; self.filename = filename; sha256 = BackupArchive.digest(data); readAt = now; self.format = format
        self.resources = resources; self.entries = entries
        hasNextPage = rootType == "Bundle" && (json.root["link"]?.elements?.contains { $0["relation"]?.string == "next" } ?? false)
        byPath = Dictionary(uniqueKeysWithValues: resources.enumerated().map { ($0.element.id, $0.offset) })
        var urls: [Data: [Int]] = [:]
        for (index, resource) in resources.enumerated() { if let url = resource.fullURL { urls[Data(url.utf8), default: []].append(index) } }
        byFullURL = urls
        try control.checkCancellation()
    }
    func resource(at path: String) -> Resource? { byPath[path].map { resources[$0] } }
    func identity(of resource: Resource) -> String? {
        if let full = resource.fullURL { return full }
        if let container = resource.container, let parent = self.resource(at: container), let full = identity(of: parent), let id = resource.logicalID { return full + "#" + id }
        if format == .ndjson, resource.container == nil, let id = resource.logicalID { return "urn:lumen:ndjson:" + sha256 + ":" + resource.type + "/" + id }
        return nil
    }
    private func owner(_ resource: Resource) -> Resource { resource.container.flatMap { self.resource(at: $0) } ?? resource }
    /// Literal identity without fetching or claiming the target is present.
    /// Patient versions can share this identity while retaining distinct source
    /// versions. Fragments keep their containing-resource namespace.
    func literalIdentity(_ reference: LiteralJSON.Node, from source: Resource) -> String? {
        guard let literal = reference["reference"]?.string, !literal.isEmpty else { return nil }
        if literal.hasPrefix("#") {
            guard literal != "#" || source.container != nil else { return nil }
            let parent = owner(source)
            return (parent.fullURL ?? ("file-resource:" + parent.id)) + literal
        }
        guard let parsed = Self.versioned(literal) else { return nil }
        if Self.isAbsolute(parsed.url) { return parsed.url }
        // An NDJSON file supplies no server base. Retain a relative literal
        // identity only inside this exact file, never invent an absolute URL or
        // merge it with an absolute reference ending in the same Type/id.
        if format == .ndjson, Self.relativeIdentity(parsed.url) { return "urn:lumen:ndjson:" + sha256 + ":" + parsed.url }
        guard Self.relativeIdentity(parsed.url), let full = owner(source).fullURL, let base = Self.restBase(full) else { return nil }
        return base + parsed.url
    }
    func resolve(_ reference: LiteralJSON.Node, from source: Resource, expectedTypes: Set<String> = []) -> Resolution {
        guard reference.members != nil else { return .invalid }
        var declaredType: String?
        if let node = reference["type"] {
            guard let text = node.string else { return .invalid }
            let prefix = "http://hl7.org/fhir/StructureDefinition/"
            let type = text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
            guard Self.validType(type) else { return .unsupported }; declaredType = type
        }
        let candidates: [Resource]
        if let value = reference["reference"] {
            guard let literal = value.string, !literal.isEmpty else { return .invalid }
            if literal == "#" {
                guard source.container != nil else { return .unsupported }
                candidates = [owner(source)]
            }
            else if literal.hasPrefix("#") {
                let id = String(literal.dropFirst())
                guard Self.validID(id) else { return .invalid }
                candidates = resources.filter { $0.container == owner(source).id && $0.logicalID.map { Self.exact($0, id) } == true }
            } else {
                guard let parsed = Self.versioned(literal) else { return .unsupported }
                if format == .ndjson, Self.relativeIdentity(parsed.url) {
                    let pieces = parsed.url.split(separator: "/").map(String.init)
                    candidates = resources.filter { resource in
                        resource.container == nil && Self.exact(resource.type, pieces[0]) &&
                        resource.logicalID.map { Self.exact($0, pieces[1]) } == true &&
                        (parsed.version.map { wanted in resource.version.map { Self.exact($0, wanted) } == true } ?? true)
                    }
                } else {
                    let absolute: String
                    if Self.isAbsolute(parsed.url) { absolute = parsed.url }
                    else {
                        guard Self.relativeIdentity(parsed.url), let full = owner(source).fullURL, let base = Self.restBase(full) else { return .unsupported }
                        absolute = base + parsed.url
                    }
                    candidates = (byFullURL[Data(absolute.utf8)] ?? []).map { resources[$0] }.filter { resource in
                        parsed.version.map { wanted in resource.version.map { Self.exact($0, wanted) } == true } ?? true
                    }
                }
            }
        } else if let identifier = reference["identifier"] {
            guard identifier.members != nil, let system = identifier["system"]?.string, !system.isEmpty,
                  let value = identifier["value"]?.string, !value.isEmpty else { return .unsupported }
            let identified = resources.filter { resource in
                guard resource.container == nil || resource.container == owner(source).id else { return false }
                return resource.node["identifier"]?.elements?.contains { id in
                    id["system"]?.string.map { Self.exact($0, system) } == true && id["value"]?.string.map { Self.exact($0, value) } == true
                } ?? false
            }
            // A logical identifier can belong to a Patient and a Practitioner
            // representing the same person. The declared/schema target type is
            // part of that lookup; it does not disambiguate duplicate fullUrls.
            let typed = identified.filter { resource in
                (declaredType.map { Self.exact($0, resource.type) } ?? true) && (expectedTypes.isEmpty || expectedTypes.contains(resource.type))
            }
            candidates = typed.isEmpty ? identified : typed
        } else { return .unsupported } // Display alone never establishes identity.
        guard !candidates.isEmpty else { return .missing }
        guard candidates.count == 1 else { return .ambiguous(candidates.map(\.id)) }
        let match = candidates[0]
        guard (declaredType.map { Self.exact($0, match.type) } ?? true), expectedTypes.isEmpty || expectedTypes.contains(match.type) else { return .wrongType(match.id) }
        return .found(match.id)
    }
    /// These semantics cannot safely be ignored when proposing result fields.
    func hasUninterpretedRules(_ resource: Resource) -> Bool {
        if bundleType != nil, json.root["implicitRules"] != nil { return true }
        func visit(_ node: LiteralJSON.Node) -> Bool {
            if let members = node.members {
                return members.contains { field in
                    field.name == "modifierExtension" || field.name == "implicitRules" || visit(field.value)
                }
            }
            return node.elements?.contains(where: visit) ?? false
        }
        return visit(owner(resource).node)
    }
    private static func exact(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    private static func validID(_ value: String) -> Bool { value.range(of: #"^[A-Za-z0-9.-]{1,64}$"#, options: .regularExpression) != nil }
    private static func validType(_ value: String) -> Bool { value.range(of: #"^[A-Z][A-Za-z0-9]{0,63}$"#, options: .regularExpression) != nil }
    static func isAbsolute(_ value: String) -> Bool {
        guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let parts = URLComponents(string: value), let scheme = parts.scheme, !scheme.isEmpty else { return false }
        return !["http", "https"].contains(scheme.lowercased()) || (parts.host?.isEmpty == false && parts.user == nil && parts.password == nil)
    }
    private static func relativeIdentity(_ value: String) -> Bool {
        let pieces = value.split(separator: "/", omittingEmptySubsequences: false)
        return pieces.count == 2 && validType(String(pieces[0])) && validID(String(pieces[1]))
    }
    private static func restBase(_ url: String) -> String? {
        guard let parts = URLComponents(string: url), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil,
              parts.query == nil, parts.fragment == nil, parts.user == nil, parts.password == nil else { return nil }
        let pieces = url.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count >= 5, relativeIdentity(pieces.suffix(2).joined(separator: "/")) else { return nil }
        return pieces.dropLast(2).joined(separator: "/") + "/"
    }
    private static func versioned(_ value: String) -> (url: String, version: String?)? {
        guard let range = value.range(of: "/_history/", options: .backwards) else { return (value, nil) }
        let base = String(value[..<range.lowerBound]), version = String(value[range.upperBound...])
        guard validID(version), !base.contains("/_history/") else { return nil }
        return (base, version)
    }
}
