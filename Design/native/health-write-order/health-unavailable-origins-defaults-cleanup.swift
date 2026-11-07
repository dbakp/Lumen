import Foundation
import CryptoKit

// Invoke only after the parent has byte-verified this exact baseline on GitHub.
// Validate all recorded synthetic suites before removing any persistent domain.
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Supply backed-up report and new cleanup output") }
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard !FileManager.default.fileExists(atPath: output.path),
      let report = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as? [String: Any],
      let cases = report["observations"] as? [[String: Any]], cases.count == 5 else { fatalError("Invalid report or existing output") }
let expectedCases: Set<String> = ["missing-current-malformed-legacy", "missing-current-nondata-legacy", "relative-selected-domain-link", "absolute-selected-domain-link", "dangling-selected-domain-link"]
guard Set(cases.compactMap { $0["case"] as? String }) == expectedCases else { fatalError("Unexpected cases") }
var suites: [(String, UserDefaults)] = []
var seen = Set<String>()
for item in cases {
    guard let suite = item["suiteName"] as? String,
          suite.hasPrefix("com.dbakp.lumen.synthetic.origin."),
          UUID(uuidString: String(suite.dropFirst("com.dbakp.lumen.synthetic.origin.".count))) != nil,
          seen.insert(suite).inserted,
          let key = item["legacyKey"] as? String, key == "lumen.health.meals.v1",
          let expected = item["legacyAfter"] as? [String: String],
          let defaults = UserDefaults(suiteName: suite) else { fatalError("Refusing unbound suite") }
    let domain = defaults.persistentDomain(forName: suite) ?? [:]
    if expected["storageType"] == "Data" {
        guard Set(domain.keys) == [key], let data = domain[key] as? Data,
              data.base64EncodedString() == expected["base64"] else { fatalError("Synthetic Data changed") }
    } else if expected["storageType"] == "String" {
        guard Set(domain.keys) == [key], let value = domain[key] as? String,
              value == expected["description"] else { fatalError("Synthetic String changed") }
    } else {
        guard expected["storageType"] == "absent", domain.isEmpty else { fatalError("Unexpected domain content") }
    }
    suites.append((suite, defaults))
}
var rows: [[String: Any]] = []
for (suite, defaults) in suites {
    defaults.removePersistentDomain(forName: suite)
    let synchronized = defaults.synchronize()
    let remainingKeys = defaults.persistentDomain(forName: suite).map { Array($0.keys).sorted() } ?? []
    guard synchronized, remainingKeys.isEmpty else { fatalError("Synthetic domain cleanup incomplete") }
    rows.append(["suiteName": suite, "synchronized": synchronized, "remainingPersistentKeys": remainingKeys])
}
let hash: (Data) -> String = { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
let result: [String: Any] = ["status": "PASS five exact recorded synthetic suite domains empty after removal/readback", "reportSHA256": hash(try Data(contentsOf: input)), "cleanupToolSHA256": hash(try Data(contentsOf: URL(fileURLWithPath: args[0]))), "observations": rows, "scope": "Only validated UUID synthetic domains with exact expected contents; no standard/personal defaults or filesystem sweep."]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
print("Five backed-up synthetic suite domains removed and empty readback verified")
