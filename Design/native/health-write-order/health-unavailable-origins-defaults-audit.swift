import Foundation
import CryptoKit

// Read only the exact isolated synthetic suites recorded by the baseline.
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Supply baseline report and new output path") }
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard !FileManager.default.fileExists(atPath: output.path),
      let report = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as? [String: Any],
      let cases = report["observations"] as? [[String: Any]], cases.count == 5 else { fatalError("Invalid report or existing output") }
func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
var rows: [[String: Any]] = []
var observedSuites = Set<String>()
for item in cases {
    guard let suite = item["suiteName"] as? String,
          suite.hasPrefix("com.dbakp.lumen.synthetic.origin."),
          UUID(uuidString: String(suite.dropFirst("com.dbakp.lumen.synthetic.origin.".count))) != nil,
          observedSuites.insert(suite).inserted,
          let key = item["legacyKey"] as? String, key == "lumen.health.meals.v1",
          let expected = item["legacyAfter"] as? [String: String],
          let defaults = UserDefaults(suiteName: suite) else { fatalError("Refusing unbound suite/key") }
    let domain = defaults.persistentDomain(forName: suite)
    let actual = defaults.object(forKey: key)
    var facts: [String: String]
    if let data = actual as? Data {
        facts = ["storageType": "Data", "kind": "Data", "base64": data.base64EncodedString(), "sha256": digest(data)]
    } else if let string = actual as? String {
        facts = ["storageType": "String", "kind": String(reflecting: type(of: actual!)), "description": string]
    } else if actual == nil {
        facts = ["storageType": "absent", "kind": "absent"]
    } else { fatalError("Unexpected synthetic value type") }
    guard facts["storageType"] == expected["storageType"],
          ["base64", "sha256", "description"].allSatisfy({ facts[$0] == expected[$0] }) else { fatalError("Synthetic persisted value changed") }
    let expectedKeys = facts["storageType"] == "absent" ? [] : [key]
    guard (domain.map { Array($0.keys).sorted() } ?? []) == expectedKeys else { fatalError("Unexpected persistent domain keys") }
    rows.append(["case": item["case"]!, "suiteName": suite, "legacyKey": key,
                 "actualFacts": facts, "persistentDomainPresent": domain != nil,
                 "persistentKeys": domain.map { Array($0.keys).sorted() } ?? [], "typedRawValueMatches": true])
}
let result: [String: Any] = ["status": "PASS read-only independent persisted synthetic suite audit", "reportSHA256": digest(try Data(contentsOf: input)), "auditorSHA256": digest(try Data(contentsOf: URL(fileURLWithPath: args[0]))), "observations": rows, "cleanupPerformed": false, "scope": "Only five validated UUID synthetic suites/key; exact persisted raw values and semantic storage types. Foundation object class is observed separately, not treated as stable storage type. No standard/personal defaults or native UI queried."]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
print("Five persisted synthetic suite identities/keys and typed raw values independently verified")
