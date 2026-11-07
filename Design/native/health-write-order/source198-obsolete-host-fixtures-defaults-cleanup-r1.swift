import Foundation
let source = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2])
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as! [String: Any]
let suites = manifest["suites"] as! [[String: Any]]
var outcomes: [[String: Any]] = [], completed = false
func raw(_ value: Any) -> (String, Data)? {
    if let data = value as? Data { return ("Data", data) }
    if let text = value as? String {
        var bytes = Data()
        for unit in text.utf16 { bytes.append(UInt8(truncatingIfNeeded: unit)); bytes.append(UInt8(unit >> 8)) }
        return ("StringUTF16LE", bytes)
    }
    return nil
}
enum Failure: Error { case preflight, cleanup }
defer {
    let result: [String: Any] = ["status": completed ? "PASS exact34knownsyntheticdomains removed/readback" : "FAILED preflight or partialcleanup; inspect outcomes", "domains": outcomes, "scope": "Only recorded known UUID synthetic persistent domains; no standard/app/global defaults or cache clearing."]
    do { try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output) }
    catch { print("Cleanup report failed", String(reflecting: error)) }
}
// Validate every domain before removing any of them.
for row in suites {
    let suite = row["suite"] as! String, expected = row["expected"] as! [String: [String: String]]
    guard suite.hasPrefix("com.dbakp.lumen.synthetic.legacy-"), let defaults = UserDefaults(suiteName: suite),
          let current = defaults.persistentDomain(forName: suite), Set(current.keys) == Set(expected.keys) else { throw Failure.preflight }
    for (key, observation) in expected {
        guard ["lumen.health.meals.v1", "lumen.health.workouts.v1", "lumen.health.goals.v1"].contains(key),
              let value = current[key], let actual = raw(value), actual.0 == observation["type"],
              actual.1 == Data(base64Encoded: observation["base64"]!) else { throw Failure.preflight }
    }
}
for row in suites {
    let suite = row["suite"] as! String
    guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.cleanup }
    defaults.removePersistentDomain(forName: suite)
    let sync = defaults.synchronize(), keys = (defaults.persistentDomain(forName: suite) ?? [:]).keys.sorted()
    outcomes.append(["suite": suite, "synchronized": sync, "keysAfter": keys])
    guard sync && keys.isEmpty else { throw Failure.cleanup }
}
completed = true
print("PASS removed/readback", outcomes.count, "known synthetic domains")
