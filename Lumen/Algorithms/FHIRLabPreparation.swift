import Foundation

/// Temporary proposals from one bounded file. Nothing here is a confirmed
/// measurement, a saved document, or a clinical interpretation.
struct FHIRLabPreparation: Sendable {
    struct Field: Sendable, Equatable {
        let path: String
        let token: String
        let byteStart: Int
        let byteEnd: Int
    }
    struct Subject: Sendable, Equatable {
        let key: String
        let label: String
        let resourcePath: String?
        let suppliedIdentity: Bool
        let issues: [String]
    }
    struct Link: Sendable {
        let sourcePath: String
        let fieldPath: String
        let resolution: FHIRResourceArchive.Resolution
        let original: Field
    }
    struct Result: Identifiable, Sendable {
        let id: String
        let resourcePath: String
        let componentIndex: Int?
        let subject: Subject
        let valueKind: String
        let originalScalarToken: String?
        let test: String
        let result: String
        let unit: String
        let reference: String
        let flag: String
        let status: String
        let method: String
        let specimen: String
        let laboratory: String
        let effectiveWording: String
        let collectionWording: String
        let fields: [Field]
        let reportPaths: [String]
        let issues: [String]
        let warnings: [String]
        /// Original declared form/status only. This must survive corrections;
        /// a code/string/range must not become a scalar by looking numeric.
        var allowsNumericInterpretation: Bool {
            originalScalarToken != nil && issues.isEmpty && ["preliminary", "final", "amended", "corrected"].contains(status)
        }
        var sourceText: String {
            "Selected FHIR source fields · " + (id.isEmpty ? "file root" : id) + "\n" + fields.map { $0.path + ":\n" + $0.token }.joined(separator: "\n")
        }
        /// The existing transcription anchor can point at this own-result field;
        /// full related source context remains separately retained provenance.
        /// A whole linked report layout must not be crammed into a 2,000-char
        /// manual-transcription excerpt or silently shortened.
        var anchor: Field? {
            fields.first { $0.path == id + "/" + valueKind } ?? fields.first { $0.path == id + "/code" }
        }
    }
    struct Coverage: Sendable {
        let entries: Int
        let resources: Int
        let resourceTypes: [String: Int]
        let resultRows: Int
        let panelsWithoutOwnValue: [String]
        let requestResponseOnly: [String]
        let deletedEntries: [String]
        let links: [Link]
        let hasNextPage: Bool
        let omittedResourceFields: [String: [String]]
    }
    enum Failure: LocalizedError, Equatable {
        case results, relationships, content
        var errorDescription: String? {
            switch self {
            case .results: return "This file has more than 1,024 result proposals. Split the export; no partial list was prepared."
            case .relationships: return "This file has too many linked report/result relationships. Split the export; no partial list was prepared."
            case .content: return "The complete proposed source fields exceed the review size limit. Split the export; no partial list was prepared."
            }
        }
    }
    static let maxResults = 1024
    static let maxRelationships = 8192
    static let maxPreparedBytes = 8_000_000
    let archive: FHIRResourceArchive
    let results: [Result]
    let coverage: Coverage
    func capturedSource(for resultID: String) -> FHIRResultSource? {
        guard let result = results.first(where: { $0.id == resultID }), let resource = archive.resource(at: result.resourcePath), result.issues.isEmpty else { return nil }
        let source = FHIRResultSource(inputSHA256: archive.sha256, resourcePath: resource.id, fullURL: resource.fullURL, resourceIdentity: archive.identity(of: resource), resourceVersion: resource.version, componentIndex: result.componentIndex, valueKind: result.valueKind, fields: result.fields.map { .init(path: $0.path, token: $0.token, byteStart: $0.byteStart, byteEnd: $0.byteEnd) }, inputFormat: archive.format == .ndjson ? .ndjson : nil)
        return source.isValid ? source : nil
    }

    init(archive: FHIRResourceArchive, control: BackupOperationControl = .init()) throws {
        try control.checkCancellation()
        self.archive = archive
        typealias Resource = FHIRResourceArchive.Resource
        func field(_ node: LiteralJSON.Node, _ path: String) -> Field {
            .init(path: path, token: archive.json.text(node), byteStart: node.bytes.lowerBound, byteEnd: node.bytes.upperBound)
        }
        let observations = archive.resources.filter { $0.type == "Observation" }
        var links: [Link] = [], reportsByObservation: [String: [String]] = [:]
        for resource in archive.resources where resource.type == "DiagnosticReport" || resource.type == "Observation" {
            try control.checkCancellation()
            let key = resource.type == "DiagnosticReport" ? "result" : "hasMember"
            if let node = resource.node[key] {
                if let refs = node.elements {
                    for (index, reference) in refs.enumerated() {
                        try control.checkCancellation()
                        let resolution = archive.resolve(reference, from: resource, expectedTypes: ["Observation"])
                        let path = resource.id + "/" + key + "/\(index)"
                        links.append(.init(sourcePath: resource.id, fieldPath: path, resolution: resolution, original: field(reference, path)))
                    }
                } else { links.append(.init(sourcePath: resource.id, fieldPath: resource.id + "/" + key, resolution: .invalid, original: field(node, resource.id + "/" + key))) }
            }
        }
        // Traverse local panel membership once per report. Cycle/repeated edges
        // never manufacture extra result rows or recurse without a bound.
        let adjacency = Dictionary(grouping: links, by: \.sourcePath).mapValues { values in values.compactMap { link -> String? in if case .found(let path) = link.resolution { return path }; return nil } }
        var incoming: [String: [Link]] = [:]
        for link in links { if case .found(let path) = link.resolution { incoming[path, default: []].append(link) } }
        var associations = 0
        for report in archive.resources where report.type == "DiagnosticReport" {
            var queue = adjacency[report.id] ?? []
            var seen = Set<String>()
            while let path = queue.popLast() {
                try control.checkCancellation()
                guard seen.insert(path).inserted else { continue }
                associations += 1; guard associations <= Self.maxRelationships else { throw Failure.relationships }
                reportsByObservation[path, default: []].append(report.id)
                queue += adjacency[path] ?? []
            }
        }
        func exact(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
        func concept(_ node: LiteralJSON.Node?) -> String {
            guard let node else { return "" }
            if let text = node["text"]?.string, !text.isEmpty { return text }
            return node["coding"]?.elements?.compactMap { coding in coding["display"]?.string ?? coding["code"]?.string }.joined(separator: "; ") ?? ""
        }
        func subject(_ resource: Resource) -> Subject {
            guard let reference = resource.node["subject"] else {
                return .init(key: LabHistory.key([archive.sha256, "unreported", resource.id]), label: "Person not reported for this observation", resourcePath: nil, suppliedIdentity: false, issues: [])
            }
            let resolution = archive.resolve(reference, from: resource, expectedTypes: ["Patient"])
            if case .found(let path) = resolution, let patient = archive.resource(at: path) {
                let name = reference["display"]?.string ?? patient.node["name"]?.elements?.first.flatMap { name in
                    name["text"]?.string ?? ([name["given"]?.elements?.compactMap(\.string).joined(separator: " "), name["family"]?.string].compactMap { $0 }.joined(separator: " "))
                }
                let identity = patient.fullURL ?? ("file-resource:" + path)
                return .init(key: LabHistory.key([archive.sha256, "person-ref", identity]), label: name?.isEmpty == false ? name! : "Patient reference: " + (patient.fullURL ?? patient.logicalID ?? path), resourcePath: path, suppliedIdentity: true, issues: archive.hasUninterpretedRules(patient) ? ["The Patient resource has unknown interpretation rules."] : [])
            }
            var issues: [String] = []
            switch resolution {
            case .wrongType: issues.append("This observation refers to a group, device or another resource type, not a patient.")
            case .ambiguous: issues.append("The observation's person reference matches multiple resources. Resolve the ambiguity in the export.")
            case .invalid: issues.append("The observation's person reference is malformed.")
            default: break
            }
            if let type = reference["type"]?.string, !["Patient", "http://hl7.org/fhir/StructureDefinition/Patient"].contains(type) { issues.append("The subject is declared as another resource type, not a patient.") }
            let literal = reference["reference"]?.string ?? reference["identifier"].map { archive.json.text($0) }
            let label = literal.map { "Unresolved person reference: " + $0 } ?? "Person label only: " + (reference["display"]?.string ?? "not reported")
            // Even unresolved references keep their own literal identity. A
            // display-only label is scoped to this observation, never merged.
            let identity: String, supplied: Bool
            if let absolute = archive.literalIdentity(reference, from: resource) { identity = absolute; supplied = true }
            else if reference["reference"] == nil, let system = reference["identifier"]?["system"]?.string, let value = reference["identifier"]?["value"]?.string, !system.isEmpty, !value.isEmpty {
                identity = LabHistory.key(["identifier", reference["type"]?.string ?? "undeclared", system, value]); supplied = true
            } else { identity = "unidentified:" + resource.id; supplied = false }
            return .init(key: LabHistory.key([archive.sha256, "person-ref", identity]), label: label, resourcePath: nil, suppliedIdentity: supplied, issues: issues)
        }
        var rows: [Result] = [], panels: [String] = [], omitted: [String: [String]] = [:], preparedBytes = 0
        let valueKeys = Set(["valueQuantity", "valueCodeableConcept", "valueString", "valueBoolean", "valueInteger", "valueRange", "valueRatio", "valueSampledData", "valueTime", "valueDateTime", "valuePeriod"])
        let statuses = Set(["registered", "preliminary", "final", "amended", "corrected", "cancelled", "entered-in-error", "unknown"])
        for observation in observations {
            try control.checkCancellation()
            let person = subject(observation), status = observation.node["status"]?.string ?? ""
            var sharedIssues = person.issues, sharedWarnings: [String] = [], sharedFields: [Field] = []
            func capture(_ key: String) { if let value = observation.node[key] { sharedFields.append(field(value, observation.id + "/" + key)) } }
            for key in ["resourceType", "id", "meta", "code", "status", "subject", "category", "specimen", "method", "performer", "bodySite", "focus", "derivedFrom", "effectiveDateTime", "effectivePeriod", "effectiveTiming", "effectiveInstant"] { capture(key) }
            if let path = person.resourcePath, let patient = archive.resource(at: path) {
                for key in ["resourceType", "name", "identifier"] { if let node = patient.node[key] { sharedFields.append(field(node, path + "/" + key)) } }
            }
            if !statuses.contains(status) { sharedIssues.append("A recognized Observation status is required in the export.") }
            if ["cancelled", "entered-in-error"].contains(status) { sharedIssues.append("The observation is marked " + status + ". It cannot become a reviewed result.") }
            if archive.hasUninterpretedRules(observation) { sharedIssues.append("Unknown modifier extensions or interpretation rules need support before these results can be proposed.") }
            if let focus = observation.node["focus"], focus.elements?.isEmpty != true { sharedIssues.append("This observation has a separate focus. It cannot automatically become the subject patient's result.") }
            if archive.entries.contains(where: { $0.resourcePath == (observation.container ?? observation.id) && $0.requestMethod == "DELETE" }) { sharedIssues.append("This is a deleted entry, not a current result.") }
            if person.resourcePath == nil { sharedWarnings.append("The person has not been established from a local Patient resource. Check the original explicitly.") }
            let effectiveKeys = ["effectiveDateTime", "effectivePeriod", "effectiveTiming", "effectiveInstant"].filter { observation.node[$0] != nil }
            if effectiveKeys.count > 1 { sharedIssues.append("Multiple effective-time forms are supplied. Check the original export.") }
            let effective = effectiveKeys.map { key in key + ": " + archive.json.text(observation.node[key]!) }.joined(separator: "\n")
            var specimen = "", collection = ""
            if let reference = observation.node["specimen"] {
                let resolution = archive.resolve(reference, from: observation, expectedTypes: ["Specimen"])
                links.append(.init(sourcePath: observation.id, fieldPath: observation.id + "/specimen", resolution: resolution, original: field(reference, observation.id + "/specimen")))
                if case .found(let path) = resolution, let sample = archive.resource(at: path) {
                    specimen = concept(sample.node["type"])
                    for key in ["type", "subject", "collection"] { if let node = sample.node[key] { sharedFields.append(field(node, path + "/" + key)) } }
                    if let value = sample.node["collection"] { collection = archive.json.text(value) }
                    if archive.hasUninterpretedRules(sample) { sharedIssues.append("The specimen has unknown interpretation rules.") }
                    if sample.node["subject"] != nil {
                        let samplePerson = subject(sample)
                        sharedIssues += samplePerson.issues.map { "Specimen: " + $0 }
                        if samplePerson.suppliedIdentity && person.suppliedIdentity && samplePerson.key != person.key { sharedIssues.append("The specimen and observation name different patients.") }
                    }
                } else { sharedWarnings.append("The supplied specimen link is unresolved; no specimen or collection time was inferred.") }
            }
            if let performers = observation.node["performer"]?.elements {
                var names: [String] = []
                for (index, performer) in performers.enumerated() {
                    try control.checkCancellation()
                    let resolution = archive.resolve(performer, from: observation)
                    links.append(.init(sourcePath: observation.id, fieldPath: observation.id + "/performer/\(index)", resolution: resolution, original: field(performer, observation.id + "/performer/\(index)")))
                    if case .found(let path) = resolution, let organization = archive.resource(at: path), organization.type == "Organization", let name = organization.node["name"] {
                        sharedFields.append(field(name, path + "/name")); if let text = name.string { names.append(text) }
                    }
                }
                if !names.isEmpty { sharedWarnings.append("Performer organizations are reported separately. Confirm the laboratory during review; a performer is not automatically a laboratory.") }
            } else if observation.node["performer"] != nil {
                sharedIssues.append("Performers must be an array in the export.")
            }
            let reportPaths = reportsByObservation[observation.id] ?? []
            for path in reportPaths {
                guard let report = archive.resource(at: path) else { continue }
                let reportPerson = subject(report)
                sharedIssues += reportPerson.issues.map { "Linked report: " + $0 }
                if reportPerson.resourcePath == nil { sharedWarnings.append("The linked report's patient is not established. Its person wording stays separate from the observation.") }
                if person.suppliedIdentity, reportPerson.suppliedIdentity, person.key != reportPerson.key { sharedIssues.append("A linked report and this observation name different patients.") }
                // Context is retained separately; never copy report status,
                // specimen, performer or time into the Observation's fields.
                for key in ["code", "status", "subject", "effectiveDateTime", "effectivePeriod", "performer", "specimen"] {
                    if let node = report.node[key] { sharedFields.append(field(node, path + "/" + key)) }
                }
                if archive.hasUninterpretedRules(report) { sharedIssues.append("A linked report has unknown interpretation rules.") }
                if ["cancelled", "entered-in-error"].contains(report.node["status"]?.string ?? "") { sharedWarnings.append("A linked report is marked " + report.node["status"]!.string! + ". The observation's own status is shown separately.") }
            }
            var ancestors = [observation.id], visited = Set<String>(), capturedLinks = Set<String>()
            while let target = ancestors.popLast() {
                try control.checkCancellation(); guard visited.insert(target).inserted else { continue }
                for link in incoming[target] ?? [] {
                    if capturedLinks.insert(link.fieldPath).inserted { sharedFields.append(link.original) }
                    ancestors.append(link.sourcePath)
                }
            }
            let components: [LiteralJSON.Node]
            if let node = observation.node["component"] {
                if let array = node.elements { components = array }
                else { components = []; sharedIssues.append("The component field is not an array.") }
            } else { components = [] }
            let ownValues = observation.node.members?.filter { $0.name.hasPrefix("value") } ?? []
            if !ownValues.isEmpty, let parentCoding = observation.node["code"]?["coding"]?.elements {
                let overlaps = components.contains { component in
                    component["code"]?["coding"]?.elements?.contains { b in parentCoding.contains { a in
                        guard let ac = a["code"]?.string, let bc = b["code"]?.string, exact(ac, bc) else { return false }
                        return exact(a["system"]?.string ?? "", b["system"]?.string ?? "")
                    } } ?? false
                }
                if overlaps { sharedIssues.append("The panel and component repeat a code while the panel also supplies a value.") }
            }
            let hasOwnRow = !ownValues.isEmpty || observation.node["dataAbsentReason"] != nil || (components.isEmpty && observation.node["hasMember"] == nil)
            if !hasOwnRow { panels.append(observation.id) }
            let nodes: [(LiteralJSON.Node, Int?)] = (hasOwnRow ? [(observation.node, nil)] : []) + components.enumerated().map { ($0.element, Optional($0.offset)) }
            for (node, component) in nodes {
                try control.checkCancellation(); guard rows.count < Self.maxResults else { throw Failure.results }
                let path = component.map { observation.id + "/component/\($0)" } ?? observation.id
                var issues = sharedIssues, warnings = sharedWarnings, fields = sharedFields
                if node.members == nil { issues.append("This component is not a structured result.") }
                if component != nil {
                    let retained = Set(["code", "interpretation", "referenceRange", "dataAbsentReason"]).union(valueKeys)
                    omitted[path] = node.members?.map(\.name).filter { !retained.contains($0) } ?? []
                }
                let values = node.members?.filter { $0.name.hasPrefix("value") } ?? []
                if values.count > 1 { issues.append("Multiple result-value forms are supplied for one result.") }
                if values.contains(where: { !valueKeys.contains($0.name) }) { issues.append("This result-value form is not supported by the R4 importer.") }
                if !values.isEmpty && node["dataAbsentReason"] != nil { issues.append("A result value and a missing-value reason conflict.") }
                for key in ["code", "interpretation", "referenceRange", "dataAbsentReason"] + values.map(\.name) {
                    if let value = node[key] {
                        let item = field(value, path + "/" + key)
                        if !fields.contains(where: { $0.path == item.path }) { fields.append(item) }
                    }
                }
                let test = concept(node["code"])
                if test.isEmpty { issues.append("The result needs a reported test name or code.") }
                var result = "", unit = "", kind = "missing", scalar: String?
                if let value = values.first, valueKeys.contains(value.name) {
                    kind = value.name
                    switch value.name {
                    case "valueQuantity":
                        if value.value.members == nil { issues.append("The quantity is not a structured value.") }
                        if let number = value.value["value"] {
                            if let literal = number.number { result = literal; if value.value["comparator"] == nil { scalar = literal } }
                            else { issues.append("The quantity value must be a JSON number.") }
                        } else { warnings.append("No quantity value is reported.") }
                        if let comparator = value.value["comparator"] {
                            if let mark = comparator.string, ["<", "<=", ">=", ">"].contains(mark) { if !result.isEmpty { result = mark + result } }
                            else { issues.append("The quantity comparator is unsupported or invalid.") }
                        }
                        unit = value.value["unit"]?.string ?? ""
                        for key in ["unit", "system", "code"] { if let token = value.value[key], token.string == nil { issues.append("The quantity's " + key + " has the wrong JSON type.") } }
                        if value.value["code"] != nil && value.value["system"]?.string == nil { issues.append("The coded unit has no defining system.") }
                        if result.isEmpty { result = "No quantity value reported" }
                    case "valueString", "valueTime", "valueDateTime":
                        if let text = value.value.string { result = text } else { issues.append("The declared text/time result has the wrong JSON type.") }
                    case "valueInteger":
                        if let literal = value.value.number, literal.range(of: #"^-?(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil, let integer = Int64(literal), (-2_147_483_648...2_147_483_647).contains(integer) { result = literal; scalar = literal }
                        else { issues.append("The declared integer result is not an integer token.") }
                    case "valueBoolean":
                        if case .boolean(let flag) = value.value.value { result = flag ? "true" : "false" } else { issues.append("The declared boolean result has the wrong JSON type.") }
                    case "valueCodeableConcept":
                        result = concept(value.value)
                        if result.isEmpty { issues.append("The coded result has no readable text or code.") }
                    default:
                        if value.value.members != nil { result = archive.json.text(value.value) }
                        else { issues.append("The declared structured result has the wrong JSON type.") }
                        warnings.append("Structured result retained as literal JSON. No scalar value was calculated.")
                    }
                } else if let absent = node["dataAbsentReason"] {
                    if absent.members == nil { issues.append("The missing-value reason must be a structured coded concept.") }
                    kind = "dataAbsentReason"; result = "No value reported" + (concept(absent).isEmpty ? "" : ": " + concept(absent))
                    warnings.append("The missing-value label is supplied by Lumen; the original reason is retained separately.")
                } else { result = "No value reported"; warnings.append("The resource supplies no result value. No measurement was inferred.") }
                if let ranges = node["referenceRange"], ranges.elements == nil { issues.append("Reference ranges must be an array in the export.") }
                if let flags = node["interpretation"], flags.elements == nil { issues.append("Interpretations must be an array in the export.") }
                let ref = node["referenceRange"].map { archive.json.text($0) } ?? ""
                let flags = node["interpretation"]?.elements?.map { concept($0) }.filter { !$0.isEmpty }.joined(separator: "; ") ?? ""
                let rowBytes = fields.reduce(0) { $0 + $1.path.utf8.count + $1.token.utf8.count }
                if fields.count > 64 || rowBytes > 32_000 { issues.append("This result's complete source context exceeds the retained-field limit. Export fewer linked contexts, or exclude this result.") }
                preparedBytes += rowBytes
                guard preparedBytes <= Self.maxPreparedBytes else { throw Failure.content }
                rows.append(.init(id: path, resourcePath: observation.id, componentIndex: component, subject: person, valueKind: kind, originalScalarToken: scalar, test: test, result: result, unit: unit, reference: ref, flag: flags, status: status, method: concept(observation.node["method"]), specimen: specimen, laboratory: "", effectiveWording: effective, collectionWording: collection, fields: fields, reportPaths: reportPaths, issues: Array(Set(issues)).sorted(), warnings: Array(Set(warnings)).sorted()))
            }
        }
        results = rows
        let fullFields = Set(rows.flatMap { $0.fields.map(\.path) })
        for resource in archive.resources {
            omitted[resource.id] = resource.node.members?.map(\.name).filter { !fullFields.contains(resource.id + "/" + $0) } ?? []
        }
        coverage = .init(entries: archive.entries.count, resources: archive.resources.count, resourceTypes: Dictionary(grouping: archive.resources, by: \.type).mapValues(\.count), resultRows: rows.count, panelsWithoutOwnValue: panels, requestResponseOnly: archive.entries.filter { $0.resourcePath == nil }.map(\.path), deletedEntries: archive.entries.filter { $0.requestMethod == "DELETE" }.map(\.path), links: links, hasNextPage: archive.hasNextPage, omittedResourceFields: omitted)
        try control.checkCancellation()
    }
}
