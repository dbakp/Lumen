import Foundation

/// Display parts retain every original Unicode scalar and UTF-8 byte. A very
/// large combining sequence cannot bypass the reader's per-part byte bound.
enum FHIRSourceReading {
    static func pages(_ text: String, maxScalars: Int = 2000, maxBytes: Int = 8000) -> [String] {
        precondition(maxScalars > 0 && maxBytes >= 4)
        var pages: [String] = [], part = String.UnicodeScalarView(), scalars = 0, bytes = 0
        for scalar in text.unicodeScalars {
            let width = scalar.value <= 0x7f ? 1 : scalar.value <= 0x7ff ? 2 : scalar.value <= 0xffff ? 3 : 4
            if scalars >= maxScalars || bytes + width > maxBytes {
                pages.append(String(part)); part = String.UnicodeScalarView(); scalars = 0; bytes = 0
            }
            part.append(scalar); scalars += 1; bytes += width
        }
        if !part.isEmpty || pages.isEmpty { pages.append(String(part)) }
        return pages
    }
}

/// Literal selected source material, not an original-file archive or signature.
public struct FHIRSourceField: Codable, Sendable, Equatable {
    public let path: String
    public let token: String
    public let byteStart: Int
    public let byteEnd: Int
    var isBounded: Bool {
        path.hasPrefix("/") && LabReport.bounded(path, limit: 1000, required: true, multiline: false) &&
        byteStart >= 0 && byteEnd > byteStart && byteEnd <= LiteralJSON.maxBytes &&
        token.utf8.count == byteEnd - byteStart && token.utf8.count <= 32_000
    }
    var sourceText: String { path + ":\n" + token }
}

/// Immutable captured fields. Validation/facts are recomputed on decoding, never
/// trusted from serialized flags, and cached so repeated display does not reparse
/// thousands of source objects on the main actor.
public struct FHIRResultSource: Codable, Sendable, Equatable {
    public let version: Int
    public let inputSHA256: String
    public let resourcePath: String
    public let fullURL: String?
    public let resourceIdentity: String?
    public let resourceVersion: String?
    public let componentIndex: Int?
    public let valueKind: String
    public let fields: [FHIRSourceField]
    private let facts: Facts?
    private struct Facts: Sendable, Equatable {
        let status: String
        let scalar: String?
        let codingContext: String
        let eventIdentity: String
        let normalization: LabNormalization.SourceFacts
    }
    private enum CodingKeys: String, CodingKey {
        case version, inputSHA256, resourcePath, fullURL, resourceIdentity, resourceVersion, componentIndex, valueKind, fields
    }
    public init(version: Int = 1, inputSHA256: String, resourcePath: String, fullURL: String?, resourceIdentity: String? = nil, resourceVersion: String?, componentIndex: Int?, valueKind: String, fields: [FHIRSourceField]) {
        self.version = version; self.inputSHA256 = inputSHA256; self.resourcePath = resourcePath; self.fullURL = fullURL
        self.resourceIdentity = resourceIdentity ?? fullURL
        self.resourceVersion = resourceVersion; self.componentIndex = componentIndex; self.valueKind = valueKind; self.fields = fields
        facts = Self.inspect(version: version, sha: inputSHA256, resourcePath: resourcePath, fullURL: fullURL, identity: resourceIdentity ?? fullURL, resourceVersion: resourceVersion, component: componentIndex, kind: valueKind, fields: fields)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var list = try c.nestedUnkeyedContainer(forKey: .fields), fields: [FHIRSourceField] = []
        while !list.isAtEnd {
            guard fields.count < 64 else { throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Too many captured FHIR fields")) }
            fields.append(try list.decode(FHIRSourceField.self))
        }
        self.init(version: try c.decode(Int.self, forKey: .version), inputSHA256: try c.decode(String.self, forKey: .inputSHA256), resourcePath: try c.decode(String.self, forKey: .resourcePath), fullURL: try c.decodeIfPresent(String.self, forKey: .fullURL), resourceIdentity: try c.decodeIfPresent(String.self, forKey: .resourceIdentity), resourceVersion: try c.decodeIfPresent(String.self, forKey: .resourceVersion), componentIndex: try c.decodeIfPresent(Int.self, forKey: .componentIndex), valueKind: try c.decode(String.self, forKey: .valueKind), fields: fields)
    }
    public var isValid: Bool { facts != nil }
    public var resultPath: String { resourcePath + (componentIndex.map { "/component/\($0)" } ?? "") }
    var originalStatus: String? { facts?.status }
    var originalScalarToken: String? { facts?.scalar }
    var codingContext: String? { facts?.codingContext }
    var normalizationFacts: LabNormalization.SourceFacts? { facts?.normalization }
    /// All components/versions of one observation share an event identity;
    /// different component slots retain separate literal-result identities.
    var eventIdentity: String? { facts?.eventIdentity }
    var resultIdentity: String? { eventIdentity.map { LabHistory.key([$0, componentIndex.map { "component:\($0)" } ?? "own value"]) } }
    var permitsScalar: Bool {
        guard let facts, facts.scalar != nil else { return false }
        return ["preliminary", "final", "amended", "corrected"].contains(facts.status)
    }
    var sourceText: String { "Selected FHIR source fields · " + (resultPath.isEmpty ? "file root" : resultPath) + "\n" + fields.map(\.sourceText).joined(separator: "\n") }
    func matchesSource(in body: String) -> Bool {
        guard isValid, let range = body.range(of: sourceText, options: .literal) else { return false }
        return body[range].utf8.elementsEqual(sourceText.utf8)
    }
    public var referenceText: String {
        "Original FHIR source capture · \(valueKind)\nInput SHA-256: \(inputSHA256)\nResource path: \(resourcePath.isEmpty ? "file root" : resourcePath)\nOriginal fullUrl: \(fullURL ?? "Not supplied")\nResolved local resource identity: \(resourceIdentity ?? "Not established outside this file")\nOriginal resource version: \(resourceVersion ?? "Not supplied")\nComponent index: \(componentIndex.map(String.init) ?? "Not a component")\nOriginal declared status: \(originalStatus ?? "Invalid capture")\nCaptured fields are historical original-file data. Reviewed values can differ; these fields do not establish clinical accuracy or current source state.\n" + sourceText
    }
    static func validSHA(_ text: String) -> Bool { text.count == 64 && text.allSatisfy { $0.isASCII && $0.isHexDigit } }
    static func validResourcePath(_ text: String) -> Bool {
        guard text.range(of: #"^(?:/entry/(?:0|[1-9][0-9]{0,3})/resource)?(?:/contained/(?:0|[1-9][0-9]{0,3}))?$"#, options: .regularExpression) != nil else { return false }
        return text.split(separator: "/").filter { $0.first?.isNumber == true }.allSatisfy { Int($0).map { (0..<1024).contains($0) } == true }
    }
    static func validResultPath(_ text: String) -> Bool {
        if let range = text.range(of: "/component/", options: .backwards) {
            let token = String(text[range.upperBound...])
            guard let index = Int(token), String(index) == token, (0..<1024).contains(index) else { return false }
            return validResourcePath(String(text[..<range.lowerBound]))
        }
        return validResourcePath(text)
    }
    private static func inspect(version: Int, sha: String, resourcePath: String, fullURL: String?, identity: String?, resourceVersion: String?, component: Int?, kind: String, fields: [FHIRSourceField]) -> Facts? {
        let kinds = ["valueQuantity", "valueCodeableConcept", "valueString", "valueBoolean", "valueInteger", "valueRange", "valueRatio", "valueSampledData", "valueTime", "valueDateTime", "valuePeriod", "dataAbsentReason", "missing"]
        guard version == 1, validSHA(sha), validResourcePath(resourcePath), kinds.contains(kind),
              component.map({ (0..<1024).contains($0) }) ?? true,
              fullURL.map({ LabReport.bounded($0, limit: 2000, required: true, multiline: false) && !$0.contains("/_history/") && FHIRResourceArchive.isAbsolute($0) }) ?? true,
              identity.map({ LabReport.bounded($0, limit: 2200, required: true, multiline: false) && FHIRResourceArchive.isAbsolute($0) }) ?? true,
              fullURL.map({ full in identity.map { full.utf8.elementsEqual($0.utf8) } ?? false }) ?? true,
              resourceVersion.map({ $0.range(of: #"^[A-Za-z0-9.-]{1,64}$"#, options: .regularExpression) != nil }) ?? true,
              (1...64).contains(fields.count), fields.allSatisfy(\.isBounded),
              Set(fields.map { Data($0.path.utf8) }).count == fields.count,
              fields.reduce(0, { $0 + $1.path.utf8.count + $1.token.utf8.count }) <= 32_000 else { return nil }
        var nodes: [String: LiteralJSON.Node] = [:]
        for field in fields {
            guard let parsed = try? LiteralJSON.parse(Data(field.token.utf8)) else { return nil }
            nodes[field.path] = parsed.root
        }
        let path = resourcePath + (component.map { "/component/\($0)" } ?? "")
        guard let status = nodes[resourcePath + "/status"]?.string,
              ["registered", "preliminary", "final", "amended", "corrected", "cancelled", "entered-in-error", "unknown"].contains(status),
              let code = nodes[path + "/code"], code.members != nil else { return nil }
        let value = nodes[path + "/" + kind]
        let ownValues = fields.filter { item in
            guard item.path.hasPrefix(path + "/") else { return false }
            let key = item.path.dropFirst(path.utf8.count + 1)
            return key.hasPrefix("value") && !key.contains("/")
        }.map(\.path)
        if kind == "missing" { guard ownValues.isEmpty, nodes[path + "/dataAbsentReason"] == nil else { return nil } }
        else if kind == "dataAbsentReason" { guard ownValues.isEmpty else { return nil } }
        else { guard ownValues == [path + "/" + kind], nodes[path + "/dataAbsentReason"] == nil else { return nil } }
        if kind != "missing" && value == nil { return nil }
        var scalar: String?
        switch kind {
        case "valueQuantity":
            guard let value, value.members != nil else { return nil }
            for key in ["unit", "system", "code"] { if let node = value[key], node.string == nil { return nil } }
            if value["code"] != nil && value["system"]?.string == nil { return nil }
            if let comparator = value["comparator"], comparator.string.map({ ["<", "<=", ">=", ">"].contains($0) }) != true { return nil }
            if let number = value["value"], number.number == nil { return nil }
            if value["comparator"] == nil { scalar = value["value"]?.number }
        case "valueInteger":
            guard let token = value?.number, let integer = Int64(token), token.range(of: #"^-?(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil, (-2_147_483_648...2_147_483_647).contains(integer) else { return nil }
            scalar = token
        case "valueString", "valueTime", "valueDateTime": guard value?.string != nil else { return nil }
        case "valueBoolean": guard let value, case .boolean = value.value else { return nil }
        case "missing": break
        default: guard value?.members != nil else { return nil }
        }
        let codeToken = fields.first { $0.path == path + "/code" }!.token
        let quantity = kind == "valueQuantity" ? value : nil
        let context = LabHistory.key([kind, codeToken, quantity?["system"]?.string ?? "", quantity?["code"]?.string ?? "", fields.first { $0.path == resourcePath + "/method" }?.token ?? "", fields.first { $0.path == resourcePath + "/bodySite" }?.token ?? ""] + fields.filter { $0.path.hasSuffix("/type") }.map(\.token))
        let sourceEvent = identity.map { "uri:" + $0 } ?? ("file:" + sha.lowercased() + ":" + resourcePath)
        let event = LabHistory.key([sourceEvent])
        var codes: [LabTestCode] = [], complete = code.members!.allSatisfy { ["coding", "text", "id"].contains($0.name) }
        if let quantity, quantity.members?.allSatisfy({ ["value", "unit", "system", "code", "comparator", "id"].contains($0.name) }) != true { complete = false }
        if let coding = code["coding"] {
            if let items = coding.elements, items.count <= 64 {
                for item in items {
                    guard let members = item.members, members.allSatisfy({ ["system", "code", "version", "display", "userSelected", "id"].contains($0.name) }) else { complete = false; continue }
                    if item["system"] == nil && item["code"] == nil && item["version"] == nil { continue }
                    guard let system = item["system"]?.string, let code = item["code"]?.string,
                          item["version"].map({ $0.string != nil }) ?? true else { complete = false; continue }
                    let value = LabTestCode(system: system, code: code, version: item["version"]?.string)
                    if value.isValid { if !codes.contains(where: { $0.id == value.id }) { codes.append(value) } }
                    else { complete = false }
                }
            } else { complete = false }
        }
        let clinical = LabHistory.key([fields.first { $0.path == resourcePath + "/method" }?.token ?? "", fields.first { $0.path == resourcePath + "/bodySite" }?.token ?? ""] + fields.filter { $0.path.hasSuffix("/type") }.map(\.token))
        let normalization = LabNormalization.SourceFacts(codes: codes, complete: complete, unitSystem: quantity?["system"]?.string, unitCode: quantity?["code"]?.string, unitDisplay: quantity?["unit"]?.string, clinicalContext: clinical)
        return Facts(status: status, scalar: scalar, codingContext: context, eventIdentity: event, normalization: normalization)
    }
}

/// Record-owned receipt survives removal of every reviewed transcription.
public struct FHIRLabImportOrigin: Codable, Sendable, Equatable {
    public let version: Int
    public let filename: String
    public let sha256: String
    public let readAt: Date
    public let inputEntries: Int
    public let inputResources: Int
    public let proposedResults: Int
    public let selectedPaths: [String]
    public let subjectKey: String
    public let subjectLabel: String
    public let hasNextPage: Bool
    public let unresolvedLinks: Int
    public let omittedFields: Int
    public var isValid: Bool {
        version == 1 && LabReport.bounded(filename, limit: 500, required: true, multiline: false) && !filename.contains("/") && !filename.contains("\\") &&
        FHIRResultSource.validSHA(sha256) && FHIRResultSource.validSHA(subjectKey) && readAt.timeIntervalSince1970.isFinite &&
        (1...1024).contains(inputEntries) && (1...1024).contains(inputResources) && (1...1024).contains(proposedResults) &&
        (1...LabReport.maxObservations).contains(selectedPaths.count) && selectedPaths.count <= proposedResults && Set(selectedPaths).count == selectedPaths.count &&
        selectedPaths.allSatisfy(FHIRResultSource.validResultPath) &&
        LabReport.bounded(subjectLabel, limit: 4000, required: true) && (0...100_000).contains(unresolvedLinks) && (0...100_000).contains(omittedFields)
    }
    public var referenceText: String {
        let entries = inputEntries == 1 ? "entry" : "entries", resources = inputResources == 1 ? "resource" : "resources"
        let results = proposedResults == 1 ? "result proposal" : "result proposals", paths = selectedPaths.count == 1 ? "result path" : "result paths"
        return "Originally reviewed FHIR JSON fields: \(filename)\nInput SHA-256: \(sha256)\nRead: \(ISO8601DateFormatter().string(from: readAt))\nFile inventory: \(inputEntries) \(entries), \(inputResources) \(resources), \(proposedResults) \(results). Original selection: \(selectedPaths.count) \(paths).\nSelected paths:\n\(selectedPaths.map { $0.isEmpty ? "file root" : $0 }.joined(separator: "\n"))\nReviewed person group: \(subjectLabel)\nNext page reported: \(hasNextPage ? "Yes; not downloaded" : "No next-page link supplied")\nUnresolved result links: \(unresolvedLinks). Fields not retained in full: \(omittedFields).\nLumen arranged selected source fields; this is not the original file layout, a complete FHIR record or proof of clinical authorship. Other results and additional fields were not retained. Keep the original file separately."
    }
}
