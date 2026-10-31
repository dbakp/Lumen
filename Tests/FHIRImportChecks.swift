import Foundation

enum FHIRImportChecks {
    static func run() throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: " + name) }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { print("PASS: " + name) }
        }
        func json(_ text: String) throws -> LiteralJSON.Document { try LiteralJSON.parse(Data(text.utf8)) }
        func archive(_ text: String) throws -> FHIRResourceArchive { try FHIRResourceArchive(data: Data(text.utf8), filename: "Synthetic FHIR.json") }
        func ref(_ text: String) throws -> LiteralJSON.Node { try json(text).root }
        let spelling = #"{ "valueQuantity" : {"value":1.2300e-9,"unit":"\u00b5g/L"}, "zero":-0.00, "flag":false, "empty":null }"#
        let source = try json(spelling)
        let quantity = source.root["valueQuantity"]!
        check(quantity["value"]?.number == "1.2300e-9" && source.text(quantity["value"]!) == "1.2300e-9", "structured JSON keeps the exact decimal/exponent token without floating point")
        check(quantity["unit"]?.string == "µg/L" && source.text(quantity["unit"]!) == #""\u00b5g/L""#, "structured JSON retains the original escaped source separately from its decoded value")
        check(source.root["zero"]?.number == "-0.00" && source.root["flag"]?.number == nil && source.root["empty"]?.number == nil, "negative zero stays literal and booleans/null never become numeric results")
        check(source.text(quantity) == #"{"value":1.2300e-9,"unit":"\u00b5g/L"}"#, "nested source ranges preserve original member order and whitespace")
        let bom = try LiteralJSON.parse(Data([239,187,191]) + Data(spelling.utf8))
        check(bom.root.bytes.lowerBound == 3 && bom.text(bom.root) == spelling, "a UTF-8 BOM keeps correct original byte offsets and source text")
        let sliced = try LiteralJSON.parse(Data(("prefix" + spelling).utf8).dropFirst(6))
        check(sliced.text(sliced.root) == spelling && sliced.source.startIndex == 0, "a sliced input buffer keeps file-relative byte ranges without indexing before its start")
        rejects("repeated decoded JSON fields are rejected including escaped aliases") { _ = try json(#"{"value":1,"\u0076alue":2}"#) }
        let unicode = try json("{\"é\":1,\"e\u{301}\":2}")
        check(unicode.root.members?.count == 2 && unicode.root["é"]?.number == "1" && unicode.root["e\u{301}"]?.number == "2", "byte-distinct Unicode JSON names are not merged by canonical String equality")
        for text in ["", "[1,]", "{\"a\":1,}", "{}{}", "[01]", "[+1]", "[1.]", "[.5]", "[NaN]", "[Infinity]", "[0x10]", "[1e]", "[truefalse]", "[nullx]", #""\q""#, #""\uD800""#, "\"unescaped\tcontrol\"", "//comment\n{}"] {
            rejects("strict structured JSON rejects malformed syntax \(text.debugDescription)") { _ = try json(text) }
        }
        rejects("structured JSON rejects invalid UTF-8") { _ = try LiteralJSON.parse(Data([34,255,34])) }
        rejects("structured JSON refuses input above its byte limit") { _ = try LiteralJSON.parse(Data(repeating: 32, count: LiteralJSON.maxBytes + 1)) }
        _ = try json(String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64))
        print("PASS: structured JSON accepts its documented nesting boundary")
        rejects("structured JSON rejects deeper nesting rather than overflowing recursion") { _ = try json(String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)) }
        rejects("structured JSON bounds its node count independently of file size") { _ = try json("[" + String(repeating: "0,", count: 100_000) + "0]") }
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("structured JSON cancellation stops before returning a partial document") { _ = try LiteralJSON.parse(Data(spelling.utf8), control: cancelled) }

        let bundle = try archive(##"""
        {"resourceType":"Bundle","type":"collection","entry":[
        {"fullUrl":"https://a.example/fhir/DiagnosticReport/d","resource":{"resourceType":"DiagnosticReport","id":"d","subject":{"reference":"Patient/p"},"result":[{"reference":"Observation/o"}]}},
        {"fullUrl":"https://a.example/fhir/Observation/o","resource":{"resourceType":"Observation","id":"o","valueQuantity":{"value":12.00}}},
        {"fullUrl":"https://b.example/fhir/Observation/o","resource":{"resourceType":"Observation","id":"o","valueQuantity":{"value":99.00}}},
        {"fullUrl":"https://a.example/fhir/Patient/p","resource":{"resourceType":"Patient","id":"p","identifier":[{"system":"urn:synthetic:person","value":"A"}]}},
        {"fullUrl":"https://b.example/fhir/Patient/p","resource":{"resourceType":"Patient","id":"p","identifier":[{"system":"urn:synthetic:person","value":"B"}]}},
        {"fullUrl":"urn:uuid:synthetic-observation","resource":{"resourceType":"Observation","id":"urn-observation"}}
        ]}
        """##)
        let report = bundle.resource(at: "/entry/0/resource")!, observation = bundle.resource(at: "/entry/1/resource")!, urn = bundle.resource(at: "/entry/5/resource")!
        check(bundle.resources.count == 6 && bundle.entries.count == 6 && bundle.sha256.count == 64, "FHIR inventory retains every resource and full input identity")
        check(bundle.resolve(report.node["result"]!.elements![0], from: report, expectedTypes: ["Observation"]) == .found(observation.id), "relative FHIR references use the containing entry's REST service base rather than a global short ID")
        check(bundle.resolve(report.node["subject"]!, from: report, expectedTypes: ["Patient"]) == .found("/entry/3/resource"), "same patient ID on another server does not change the resolved source person")
        check(observation.node["subject"] == nil, "an observation missing its own subject remains unknown despite a linked report subject")
        check(bundle.resolve(try ref(#"{"reference":"Observation/o"}"#), from: urn) == .unsupported, "a URN entry never invents a REST base for a relative reference")
        check(bundle.resolve(try ref(#"{"reference":"urn:uuid:synthetic-observation"}"#), from: report) == .found(urn.id), "absolute URN references resolve only through an exact local fullUrl")
        check(bundle.resolve(try ref(#"{"reference":"https://outside.example/Observation/o"}"#), from: report) == .missing, "an external unresolved reference stays missing and is never fetched")
        check(bundle.resolve(try ref(#"{"display":"Same display name"}"#), from: report) == .unsupported, "a display-only subject reference never establishes identity")
        check(bundle.resolve(try ref(#"{"identifier":{"system":"urn:synthetic:person","value":"B"}}"#), from: report, expectedTypes: ["Patient"]) == .found("/entry/4/resource"), "logical references use an exact system and identifier pair")
        check(bundle.resolve(try ref(#"{"identifier":{"value":"B"}}"#), from: report) == .unsupported, "an identifier without its system is not guessed across issuers")
        check(bundle.resolve(try ref(#"{"reference":"Patient/p","type":"Observation"}"#), from: report) == .wrongType("/entry/3/resource"), "a declared reference type conflict is visible rather than accepted")
        check(bundle.resolve(try ref(#"{"reference":"Patient/p","type":"http://hl7.org/fhir/StructureDefinition/Patient"}"#), from: report) == .found("/entry/3/resource"), "standard FHIR type URIs retain their resource-type check")
        check(bundle.resolve(try ref(#"{"reference":"Patient?identifier=A"}"#), from: report) == .unsupported, "conditional transaction references are not simulated by substring matching")

        let history = try archive(##"""
        {"resourceType":"Bundle","type":"history","link":[{"relation":"next","url":"https://outside.example/next"}],"entry":[
        {"fullUrl":"https://a.example/fhir/Observation/o","resource":{"resourceType":"Observation","id":"o","meta":{"versionId":"1"},"valueString":"earlier"}},
        {"fullUrl":"https://a.example/fhir/Observation/o","resource":{"resourceType":"Observation","id":"o","meta":{"versionId":"2"},"valueString":"later"}},
        {"request":{"method":"DELETE","url":"Observation/deleted"},"response":{"status":"204"}}
        ]}
        """##)
        let old = history.resources[0]
        check(history.hasNextPage && history.entries.count == 3 && history.entries[2].requestMethod == "DELETE" && history.entries[2].resourcePath == nil, "FHIR pagination and deletion-only entries stay in the coverage inventory")
        check(history.resolve(try ref(#"{"reference":"Observation/o"}"#), from: old) == .ambiguous(["/entry/0/resource", "/entry/1/resource"]), "multiple resource versions leave an unversioned reference ambiguous")
        check(history.resolve(try ref(#"{"reference":"Observation/o/_history/2"}"#), from: old) == .found("/entry/1/resource"), "relative version-specific references match exact meta.versionId")
        check(history.resolve(try ref(#"{"reference":"https://a.example/fhir/Observation/o/_history/1"}"#), from: old) == .found(old.id), "absolute version-specific references preserve the requested older version")
        check(history.resolve(try ref(#"{"reference":"Observation/o/_history/3"}"#), from: old) == .missing, "a missing requested version never falls back to a different version")
        let duplicate = try archive(#"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"urn:uuid:same","resource":{"resourceType":"Patient","identifier":[{"system":"urn:s","value":"p"}]}},{"fullUrl":"urn:uuid:same","resource":{"resourceType":"Patient","identifier":[{"system":"urn:s","value":"p"}]}}]}"#)
        check(duplicate.resolve(try ref(#"{"reference":"urn:uuid:same"}"#), from: duplicate.resources[0]) == .ambiguous(duplicate.resources.map(\.id)), "duplicate fullUrl candidates never silently choose the first")
        check(duplicate.resolve(try ref(#"{"identifier":{"system":"urn:s","value":"p"}}"#), from: duplicate.resources[0]) == .ambiguous(duplicate.resources.map(\.id)), "duplicate issuer/identifier pairs also remain ambiguous")
        let roles = try archive(#"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"urn:synthetic:patient","resource":{"resourceType":"Patient","identifier":[{"system":"urn:synthetic:person","value":"A"}]}},{"fullUrl":"urn:synthetic:practitioner","resource":{"resourceType":"Practitioner","identifier":[{"system":"urn:synthetic:person","value":"A"}]}}]}"#)
        check(roles.resolve(try ref(#"{"type":"Patient","identifier":{"system":"urn:synthetic:person","value":"A"}}"#), from: roles.resources[0]) == .found("/entry/0/resource"), "a declared logical-reference type distinguishes separate Patient and Practitioner roles")
        check(roles.resolve(try ref(#"{"identifier":{"system":"urn:synthetic:person","value":"A"}}"#), from: roles.resources[0]) == .ambiguous(roles.resources.map(\.id)), "an untyped logical identifier shared by multiple resource roles remains ambiguous")
        let entries = String(repeating: #"{"resource":{"resourceType":"Observation"}},"#, count: 1023) + #"{"resource":{"resourceType":"Observation"}}"#
        let atLimit = try archive(#"{"resourceType":"Bundle","type":"collection","entry":["# + entries + "]}")
        check(atLimit.resources.count == 1024 && atLimit.entries.count == 1024, "FHIR inventory retains every entry at the resource limit without a first-N prefix")
        rejects("FHIR inventory rejects more than the complete resource bound") { _ = try archive(#"{"resourceType":"Bundle","type":"collection","entry":["# + entries + #",{"resource":{"resourceType":"Patient"}}]}"#) }
        let containedLimit = String(repeating: #"{"resource":{"resourceType":"Observation"}},"#, count: 1023) + #"{"resource":{"resourceType":"Observation","contained":[{"resourceType":"Patient","id":"p"}]}}"#
        rejects("FHIR resource bound includes contained resources within 1,024 entries") { _ = try archive(#"{"resourceType":"Bundle","type":"collection","entry":["# + containedLimit + "]}") }

        let contained = try archive(##"{"resourceType":"DiagnosticReport","id":"report","contained":[{"resourceType":"Patient","id":"p"},{"resourceType":"Observation","id":"o","subject":{"reference":"#p"}}]}"##)
        let child = contained.resource(at: "/contained/1")!
        check(contained.resolve(child.node["subject"]!, from: child, expectedTypes: ["Patient"]) == .found("/contained/0"), "contained observations resolve sibling contained subjects within their owner only")
        check(contained.resolve(try ref(##"{"reference":"#"}"##), from: child) == .found(""), "a contained parent reference resolves to its actual owning resource")
        check(contained.resolve(try ref(##"{"reference":"#"}"##), from: contained.resources[0]) == .unsupported, "a root resource does not invent a containing parent for an empty fragment")
        check(contained.resolve(try ref(##"{"reference":"#missing"}"##), from: child) == .missing, "a missing contained identity is not replaced by a similar name")
        let scoped = try archive(#"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"urn:uuid:a","resource":{"resourceType":"Observation","contained":[{"resourceType":"Patient","id":"p"}]}},{"fullUrl":"urn:uuid:b","resource":{"resourceType":"Observation","contained":[{"resourceType":"Patient","id":"p"}]}}]}"#)
        check(scoped.resolve(try ref(##"{"reference":"#p"}"##), from: scoped.resources[2]) == .found("/entry/1/resource/contained/0"), "identical contained IDs in different owners remain separate")
        rejects("a nested contained resource is rejected instead of leaking its scope") { _ = try archive(#"{"resourceType":"Observation","contained":[{"resourceType":"Patient","id":"p","contained":[]}] }"#) }
        rejects("a version-specific fullUrl is rejected as invalid resource identity") { _ = try archive(#"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"https://a.example/Observation/o/_history/1","resource":{"resourceType":"Observation"}}]}"#) }
        rejects("a malformed bundle entry is not silently omitted") { _ = try archive(#"{"resourceType":"Bundle","type":"collection","entry":[{}]}"#) }
        rejects("a non-resource JSON table is not mislabelled as FHIR") { _ = try archive(#"[{"test":"A","result":1}]"#) }
        rejects("a cancelled FHIR graph never returns a partial resource inventory") { _ = try FHIRResourceArchive(data: Data(spelling.utf8), filename: "Synthetic.json", control: cancelled) }
        let rules = try archive(#"{"resourceType":"Observation","component":[{"modifierExtension":[{"url":"urn:unknown","valueBoolean":true}]}]}"#)
        check(rules.hasUninterpretedRules(rules.resources[0]) && !bundle.hasUninterpretedRules(observation), "modifier extensions inside result components block interpretation rather than disappearing")
        let implicit = try archive(#"{"resourceType":"Bundle","type":"collection","implicitRules":"urn:unknown","entry":[{"fullUrl":"urn:uuid:o","resource":{"resourceType":"Observation"}}]}"#)
        check(implicit.hasUninterpretedRules(implicit.resources[0]), "bundle-level interpretation rules apply to local proposal eligibility")
    }
}
