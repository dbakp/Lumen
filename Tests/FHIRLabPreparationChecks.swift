import Foundation

enum FHIRLabPreparationChecks {
    static func run() throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: " + name) }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { print("PASS: " + name) }
        }
        func prepare(_ text: String) throws -> FHIRLabPreparation {
            try .init(archive: FHIRResourceArchive(data: Data(text.utf8), filename: "Synthetic clinical.json"))
        }
        func observation(_ fields: String, status: String = "final") throws -> FHIRLabPreparation {
            try prepare(#"{"resourceType":"Observation","status":""# + status + #"","code":{"text":"Synthetic test"},"# + fields + "}")
        }
        let data = ##"""
        {"resourceType":"Bundle","type":"collection","entry":[
        {"fullUrl":"https://a.example/fhir/DiagnosticReport/d","resource":{"resourceType":"DiagnosticReport","id":"d","status":"final","code":{"text":"Synthetic panel report"},"subject":{"reference":"Patient/p"},"effectiveDateTime":"2026-01-01","performer":[{"display":"Not the observation laboratory"}],"result":[{"reference":"Observation/panel"}]}},
        {"fullUrl":"https://a.example/fhir/Observation/panel","resource":{"resourceType":"Observation","id":"panel","status":"final","code":{"text":"Synthetic panel"},"subject":{"reference":"Patient/p"},"hasMember":[{"reference":"Observation/o"},{"reference":"Observation/o"},{"reference":"Observation/panel"}]}},
        {"fullUrl":"https://a.example/fhir/Observation/o","resource":{"resourceType":"Observation","id":"o","status":"preliminary","code":{"coding":[{"system":"http://loinc.org","code":"718-7","display":"Hemoglobin"}]},"subject":{"reference":"Patient/p"},"specimen":{"reference":"Specimen/s"},"performer":[{"reference":"Organization/org"}],"effectiveDateTime":"2026-10-30T23:40:00-05:00","method":{"text":"Synthetic assay"},"valueQuantity":{"value":12.00,"unit":"g/dL","system":"http://unitsofmeasure.org","code":"g/dL"},"interpretation":[{"text":"H"}],"referenceRange":[{"low":{"value":10.0,"unit":"g/dL"},"high":{"value":15.0,"unit":"g/dL"},"text":"Reported reference"},{"text":"Alternate reference","appliesTo":[{"text":"Original group"}]}],"note":[{"text":"Not retained automatically"}]}},
        {"fullUrl":"https://a.example/fhir/Patient/p","resource":{"resourceType":"Patient","id":"p","name":[{"given":["Synthetic"],"family":"Person"}]}},
        {"fullUrl":"https://a.example/fhir/Specimen/s","resource":{"resourceType":"Specimen","id":"s","type":{"text":"Serum"},"subject":{"reference":"Patient/p"},"collection":{"collectedDateTime":"2026-10-29T09:00:00Z"}}},
        {"fullUrl":"https://a.example/fhir/Organization/org","resource":{"resourceType":"Organization","id":"org","name":"Synthetic responsible organization"}},
        {"fullUrl":"https://a.example/fhir/Patient/other","resource":{"resourceType":"Patient","id":"other","name":[{"text":"Synthetic Person"}],"address":[{"text":"Other person's unselected address"}]}},
        {"fullUrl":"https://a.example/fhir/Observation/standalone","resource":{"resourceType":"Observation","id":"standalone","status":"final","code":{"text":"Unknown-person coded result"},"valueCodeableConcept":{"text":"12.00"}}}
        ]}
        """##
        let prepared = try prepare(data), quantity = prepared.results[0], coded = prepared.results[1]
        check(prepared.coverage.entries == 8 && prepared.coverage.resources == 8 && prepared.results.count == 2 && prepared.coverage.panelsWithoutOwnValue == ["/entry/1/resource"], "FHIR panels and entry counts stay separate from actual result rows")
        check(quantity.reportPaths == ["/entry/0/resource"] && quantity.test == "Hemoglobin" && quantity.result == "12.00" && quantity.originalScalarToken == "12.00", "linked panel traversal preserves one result and its exact numeric token despite cycles/repeated edges")
        check(quantity.status == "preliminary" && quantity.method == "Synthetic assay" && quantity.specimen == "Serum", "component/report relationships do not replace direct Observation status, method or specimen")
        check(quantity.laboratory.isEmpty && quantity.warnings.contains(where: { $0.contains("not automatically a laboratory") }), "a performer organization is retained separately rather than asserted to be a laboratory")
        check(quantity.effectiveWording.contains("2026-10-30T23:40:00-05:00") && quantity.collectionWording.contains("2026-10-29T09:00:00Z") && !quantity.effectiveWording.contains("2026-01-01"), "effective, specimen collection and report times retain their separate source roles")
        check(quantity.reference.contains("appliesTo") && quantity.reference.contains("Alternate reference") && quantity.flag == "H", "every reference-range representation and the reported interpretation remain literal")
        check(quantity.issues.isEmpty && quantity.allowsNumericInterpretation && !coded.allowsNumericInterpretation && coded.result == "12.00", "a numeric-looking coded result does not inherit the quantity's scalar eligibility")
        check(quantity.subject.resourcePath == "/entry/3/resource" && quantity.subject.key != coded.subject.key && coded.subject.resourcePath == nil, "a missing observation person stays unknown even when a linked report supplies one")
        check(!quantity.sourceText.contains("Other person's unselected address") && !quantity.sourceText.contains("Not retained automatically"), "unselected-person fields and additional notes do not enter proposed selected source text")
        check(prepared.coverage.omittedResourceFields["/entry/2/resource"]?.contains("note") == true && prepared.coverage.omittedResourceFields["/entry/6/resource"]?.contains("address") == true, "coverage identifies extra fields not retained in full across result and non-result resources")
        check(quantity.fields.allSatisfy { $0.token == String(decoding: prepared.archive.json.source[$0.byteStart..<$0.byteEnd], as: UTF8.self) }, "each prepared source field keeps its actual original byte interval and token")
        let captured = prepared.capturedSource(for: quantity.id)!, codedCapture = prepared.capturedSource(for: coded.id)!
        check(captured.isValid && captured.originalScalarToken == "12.00" && captured.permitsScalar && !codedCapture.permitsScalar, "captured immutable FHIR metadata retains original declared scalar eligibility separately from numeric-looking codes")
        let capturedData = try JSONEncoder().encode(captured), decodedCapture = try JSONDecoder().decode(FHIRResultSource.self, from: capturedData)
        check(decodedCapture == captured && decodedCapture.permitsScalar && String(decoding: capturedData, as: UTF8.self).contains("facts") == false, "FHIR metadata round trips without trusting or serializing cached validation flags")
        check(captured.matchesSource(in: "Prefix\n" + captured.sourceText + "\nSuffix") && !captured.matchesSource(in: captured.sourceText.replacingOccurrences(of: "12.00", with: "12.0")), "retained source matching requires exact original token spelling despite equivalent numeric values")
        var forged = try JSONSerialization.jsonObject(with: capturedData) as! [String: Any]
        forged["valueKind"] = "valueCodeableConcept"; forged["facts"] = ["status":"final", "scalar":"999", "codingContext":"forged", "eventIdentity":"forged"]
        let forgedCapture = try JSONDecoder().decode(FHIRResultSource.self, from: JSONSerialization.data(withJSONObject: forged))
        check(!forgedCapture.isValid && !forgedCapture.permitsScalar, "forged serialized cached facts cannot authorize a mismatched FHIR source value kind")
        let otherVersion = FHIRResultSource(inputSHA256: String(repeating: "b", count: 64), resourcePath: captured.resourcePath, fullURL: captured.fullURL, resourceVersion: "other-version", componentIndex: nil, valueKind: captured.valueKind, fields: captured.fields)
        check(otherVersion.isValid && otherVersion.eventIdentity == captured.eventIdentity, "different files and versions of one known Observation URI do not manufacture independent events")
        let receipt = FHIRLabImportOrigin(version: 1, filename: prepared.archive.filename, sha256: prepared.archive.sha256, readAt: prepared.archive.readAt, inputEntries: 8, inputResources: 8, proposedResults: 2, selectedPaths: [quantity.id], subjectKey: quantity.subject.key, subjectLabel: quantity.subject.label, hasNextPage: false, unresolvedLinks: 0, omittedFields: 2)
        check(receipt.isValid && receipt.referenceText.contains("not the original file layout") && receipt.referenceText.contains(prepared.archive.sha256), "a record-owned FHIR receipt describes selected fields without claiming the original file is archived")
        check(try JSONDecoder().decode(FHIRLabImportOrigin.self, from: JSONEncoder().encode(receipt)) == receipt, "the retained FHIR receipt has a compatible coded round trip independent of lab rows")
        check(quantity.anchor?.path == "/entry/2/resource/valueQuantity" && quantity.anchor?.token.contains("12.00") == true && coded.anchor?.path == "/entry/7/resource/valueCodeableConcept", "a result anchor points to its own value while complete related provenance remains separate")
        check(quantity.fields.contains { $0.path == "/entry/0/resource/result/0" } && quantity.fields.contains { $0.path == "/entry/1/resource/hasMember/0" }, "report-to-panel-to-result relationship fields remain traceable without copying sibling values")
        let components = try observation(#""referenceRange":[{"text":"Parent range must not leak"}],"component":[{"code":{"text":"Component A"},"valueQuantity":{"value":0.00,"unit":"mg/L"}},{"code":{"text":"Component B"},"valueString":"Not detected","referenceRange":[{"text":"Own reference"}]}]"#)
        check(components.results.count == 2 && components.results[0].componentIndex == 0 && components.results[0].result == "0.00" && components.results[0].reference.isEmpty && components.results[1].reference.contains("Own reference"), "components retain their own values and ranges without inheriting the parent range")
        check(components.results.allSatisfy { $0.reportPaths.isEmpty && $0.subject.resourcePath == nil }, "standalone components do not invent a report or resolved patient")
        let firstComponent = components.capturedSource(for: components.results[0].id)!, secondComponent = components.capturedSource(for: components.results[1].id)!
        check(firstComponent.eventIdentity == secondComponent.eventIdentity && firstComponent.resultIdentity != secondComponent.resultIdentity, "component results remain individually identifiable while belonging to one original event")
        check(!FHIRResultSource.validResultPath("/component/01") && !FHIRResultSource.validResultPath("/component/+1") && !FHIRResultSource.validResourcePath("/entry/1024/resource"), "retained original paths use canonical bounded array indices")
        var tooManyFields = try JSONSerialization.jsonObject(with: capturedData) as! [String: Any]
        tooManyFields["fields"] = Array(repeating: (tooManyFields["fields"] as! [[String:Any]])[0], count: 65)
        rejects("FHIR provenance decoding stops before accepting oversized captured-field arrays") { _ = try JSONDecoder().decode(FHIRResultSource.self, from: JSONSerialization.data(withJSONObject: tooManyFields)) }
        for comparator in ["<", "<=", ">=", ">"] {
            let value = try observation(#""valueQuantity":{"value":1.2300e-9,"unit":"mg/L","comparator":""# + comparator + #""}"#).results[0]
            check(value.result == comparator + "1.2300e-9" && !value.allowsNumericInterpretation, "FHIR quantity comparator \(comparator) is never dropped to create an unqualified scalar")
        }
        let codeUnit = try observation(#""valueQuantity":{"value":0,"system":"http://unitsofmeasure.org","code":"mg/dL"}"#).results[0]
        check(codeUnit.unit.isEmpty && codeUnit.sourceText.contains("mg/dL"), "a coded unit is preserved without pretending a missing display unit was reported")
        let boolean = try observation(#""valueBoolean":false"#).results[0]
        check(boolean.result == "false" && !boolean.allowsNumericInterpretation, "FHIR boolean false remains literal rather than zero")
        for (key, literal) in [("valueRange", #"{"low":{"value":1.0},"high":{"value":2.0}}"#), ("valueRatio", #"{"numerator":{"value":1},"denominator":{"value":3}}"#), ("valueSampledData", #"{"origin":{"value":0},"period":1,"dimensions":1,"data":"1 2 E"}"#), ("valuePeriod", #"{"start":"2026-10","end":"2026-11"}"#)] {
            let value = try observation("\"" + key + "\":" + literal).results[0]
            check(value.result == literal && !value.allowsNumericInterpretation && value.issues.isEmpty, "\(key) stays structured and no scalar is calculated")
        }
        let absent = try observation(#""dataAbsentReason":{"text":"Not performed"}"#).results[0]
        check(absent.valueKind == "dataAbsentReason" && absent.result == "No value reported: Not performed" && !absent.allowsNumericInterpretation, "missing-value reasons remain explicit with a labelled generated missing-value phrase")
        let missingQuantity = try observation(#""valueQuantity":{"unit":"mg/L","comparator":"<"}"#).results[0]
        check(missingQuantity.result == "No quantity value reported" && !missingQuantity.allowsNumericInterpretation, "a comparator without a quantity does not become a fabricated result")
        for fields in [#""valueQuantity":{"value":"12.00"}"#, #""valueQuantity":{"value":1,"comparator":"="}"#, #""valueQuantity":{"value":1,"unit":7}"#, #""valueQuantity":{"value":1,"code":"mg/L"}"#, #""valueString":"12","valueInteger":12"#, #""valueInteger":2147483648"#, #""valueInteger":1.5"#, #""valueBoolean":0"#, #""valueQuantity":{"value":1},"dataAbsentReason":{"text":"missing"}"#, #""valueAttachment":{"data":"AA=="}"#, #""valueString":"x","referenceRange":{}"#, #""valueString":"x","interpretation":{}"#, #""valueString":"x","focus":[{"reference":"Patient/fetus"}]"#] {
            check(!(try observation(fields).results[0].issues.isEmpty), "conflicting or mistyped FHIR result remains visible and blocked: \(fields)")
        }
        for status in ["cancelled", "entered-in-error", "INVALID"] {
            let value = try observation(#""valueInteger":1"#, status: status).results[0]
            check(!value.issues.isEmpty && !value.allowsNumericInterpretation, "FHIR \(status) cannot silently become an active numeric result")
        }
        for status in ["registered", "unknown"] {
            let value = try observation(#""valueInteger":1"#, status: status).results[0]
            check(value.issues.isEmpty && !value.allowsNumericInterpretation, "FHIR \(status) remains literal with its supplied status")
        }
        let otherPatient = try prepare(data.replacingOccurrences(of: #""subject":{"reference":"Patient/p"},"collection""#, with: #""subject":{"reference":"Patient/other"},"collection""#))
        check(otherPatient.results[0].issues.contains(where: { $0.contains("specimen and observation") }), "conflicting specimen and observation patients block automatic result preparation")
        let otherReport = try prepare(data.replacingOccurrences(of: #""subject":{"reference":"Patient/p"},"effectiveDateTime":"2026-01-01""#, with: #""subject":{"reference":"Patient/other"},"effectiveDateTime":"2026-01-01""#))
        check(otherReport.results[0].issues.contains(where: { $0.contains("linked report and this observation") }), "conflicting report and observation patients stay visible instead of inheriting report identity")
        let overlap = try prepare(#"{"resourceType":"Observation","status":"final","code":{"coding":[{"system":"urn:test","code":"same"}]},"valueInteger":1,"component":[{"code":{"coding":[{"system":"urn:test","code":"same"}]},"valueInteger":2}]}"#)
        check(overlap.results.count == 2 && overlap.results.allSatisfy { $0.issues.contains(where: { $0.contains("panel and component") }) }, "a forbidden same-code panel value blocks both rows rather than retaining one as independent")
        let deleted = try prepare(#"{"resourceType":"Bundle","type":"history","entry":[{"request":{"method":"DELETE"},"response":{"status":"204"},"resource":{"resourceType":"Observation","status":"final","code":{"text":"Deleted value"},"valueInteger":1}}]}"#)
        check(deleted.coverage.deletedEntries.count == 1 && deleted.results[0].issues.contains(where: { $0.contains("deleted entry") }), "a deletion entry carrying a payload does not become a current measurement")
        let unresolved = try prepare(#"{"resourceType":"DiagnosticReport","id":"report","status":"final","code":{"text":"Unresolved report"},"result":[{"reference":"https://outside.example/Observation/missing"}]}"#)
        check(unresolved.results.isEmpty && unresolved.coverage.links.count == 1 && unresolved.coverage.links[0].resolution == .missing, "an unresolved report result stays in coverage even when no measurement can be prepared")
        let cancelled = BackupOperationControl(); cancelled.cancel()
        rejects("cancellation rejects the complete FHIR preparation rather than publishing partial rows") { _ = try FHIRLabPreparation(archive: prepared.archive, control: cancelled) }
        let missingPeople = try prepare(#"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"https://a.example/fhir/Observation/a","resource":{"resourceType":"Observation","status":"final","code":{"text":"A"},"subject":{"reference":"Patient/p"},"valueInteger":1}},{"fullUrl":"https://b.example/fhir/Observation/b","resource":{"resourceType":"Observation","status":"final","code":{"text":"B"},"subject":{"reference":"Patient/p"},"valueInteger":2}}]}"#)
        check(missingPeople.results[0].subject.key != missingPeople.results[1].subject.key, "unresolved same short patient IDs on different REST bases are never merged")
        let displayOnly = try prepare(#"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"urn:synthetic:a","resource":{"resourceType":"Observation","status":"final","code":{"text":"A"},"subject":{"display":"Same person label"},"valueInteger":1}},{"fullUrl":"urn:synthetic:b","resource":{"resourceType":"Observation","status":"final","code":{"text":"B"},"subject":{"display":"Same person label"},"valueInteger":2}}]}"#)
        check(displayOnly.results[0].subject.key != displayOnly.results[1].subject.key, "equal unresolved display names do not become one person group")
        let versions = try prepare(#"{"resourceType":"Bundle","type":"history","entry":[{"fullUrl":"https://a.example/fhir/Observation/o","resource":{"resourceType":"Observation","status":"final","code":{"text":"A"},"subject":{"reference":"Patient/p/_history/1"},"valueInteger":1}},{"fullUrl":"https://a.example/fhir/Observation/p","resource":{"resourceType":"Observation","status":"final","code":{"text":"B"},"subject":{"reference":"Patient/p/_history/2"},"valueInteger":2}},{"fullUrl":"https://a.example/fhir/Patient/p","resource":{"resourceType":"Patient","meta":{"versionId":"1"}}},{"fullUrl":"https://a.example/fhir/Patient/p","resource":{"resourceType":"Patient","meta":{"versionId":"2"}}}]}"#)
        check(versions.results[0].subject.key == versions.results[1].subject.key && versions.results[0].subject.resourcePath != versions.results[1].subject.resourcePath, "resolved versions of one Patient retain their source versions without inventing different people")
        let typedGroup = try observation(#""subject":{"reference":"urn:synthetic:group","type":"Group"},"valueInteger":1"#).results[0]
        check(typedGroup.issues.contains(where: { $0.contains("declared as another resource type") }), "a known Group subject cannot become a patient merely because its resource is absent")
        let unresolvedConflict = try prepare(#"{"resourceType":"Bundle","type":"collection","entry":[{"fullUrl":"https://a.example/fhir/DiagnosticReport/d","resource":{"resourceType":"DiagnosticReport","status":"final","code":{"text":"Report"},"subject":{"reference":"Patient/a"},"result":[{"reference":"Observation/o"}]}},{"fullUrl":"https://a.example/fhir/Observation/o","resource":{"resourceType":"Observation","status":"final","code":{"text":"Result"},"subject":{"reference":"Patient/b"},"valueInteger":1}}]}"#)
        check(unresolvedConflict.results[0].issues.contains(where: { $0.contains("linked report and this observation") }), "conflicting explicit report/observation person references block preparation even when Patient resources are absent")
        let parentAliases = try prepare(##"{"resourceType":"Patient","identifier":[{"system":"urn:synthetic:person","value":"A"}],"contained":[{"resourceType":"Observation","id":"a","status":"final","code":{"text":"A"},"subject":{"reference":"#"},"valueInteger":1},{"resourceType":"Observation","id":"b","status":"final","code":{"text":"B"},"subject":{"identifier":{"system":"urn:synthetic:person","value":"A"}},"valueInteger":2}]}"##)
        check(parentAliases.results[0].subject.key == parentAliases.results[1].subject.key && parentAliases.results[0].subject.resourcePath == "", "contained-parent and logical references to the same local Patient keep one identity even without a fullUrl")
        func rejectsPreparation(_ text: String, expected: FHIRLabPreparation.Failure, _ name: String) {
            do { _ = try prepare(text); preconditionFailure(name) }
            catch let error as FHIRLabPreparation.Failure { precondition(error == expected, name); print("PASS: " + name) }
            catch { preconditionFailure(name + ": unexpected error \(error)") }
        }
        let part = #"{"code":{"text":"Synthetic component"},"valueInteger":1}"#
        let atLimit = try observation(#""component":["# + Array(repeating: part, count: 1024).joined(separator: ",") + "]")
        check(atLimit.results.count == 1024 && atLimit.results.last?.componentIndex == 1023, "every proposal at the complete FHIR result limit remains reachable")
        rejectsPreparation(#"{"resourceType":"Observation","status":"final","code":{"text":"Panel"},"component":["# + Array(repeating: part, count: 1025).joined(separator: ",") + "]}", expected: .results, "exceeding the result limit rejects complete preparation rather than publishing a prefix")
        let resultRefs = (0..<900).map { #"{"reference":"urn:synthetic:o"# + String($0) + #""}"# }.joined(separator: ",")
        let reports = (0..<10).map { #"{"fullUrl":"urn:synthetic:r"# + String($0) + #"","resource":{"resourceType":"DiagnosticReport","status":"final","code":{"text":"Report"},"result":["# + resultRefs + "]}}" }
        let manyObservations = (0..<900).map { #"{"fullUrl":"urn:synthetic:o"# + String($0) + #"","resource":{"resourceType":"Observation","status":"final","code":{"text":"Result"},"valueInteger":1}}"# }
        rejectsPreparation(#"{"resourceType":"Bundle","type":"collection","entry":["# + (reports + manyObservations).joined(separator: ",") + "]}", expected: .relationships, "dense report relationships have an independent whole-preparation bound")
        let expanded = #"{"resourceType":"Observation","status":"final","code":{"text":"Panel"},"meta":{"source":""# + String(repeating: "x", count: 100_000) + #""},"component":["# + Array(repeating: part, count: 100).joined(separator: ",") + "]}"
        rejectsPreparation(expanded, expected: .content, "source-context expansion is bounded independently of the small input file")
    }
}
