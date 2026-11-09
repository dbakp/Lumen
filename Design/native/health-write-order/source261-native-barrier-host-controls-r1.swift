// Appended to the exact extracted native helper in a temporary host-only control.
// These synthetic files exercise transport validation, never app recovery.
let controlState = ["session": UUID().uuidString, "capture": UUID().uuidString, "phase": "ready", "selected": ""]
var checks: [[String: Any]] = []
let manager = FileManager.default
func control(_ label: String, phase: String = "pre-recover", state: [String: String] = controlState,
             kind: String = "json", shouldAccept: Bool = false,
             change: ((inout [String: Any]) -> Void)? = nil) throws {
    let barrier = RetainedRecoveryBackendBarrier()
    let stem = "Lumen-retained-backend-" + barrier.runID.lowercased() + "-" + phase
    let marker = manager.temporaryDirectory.appendingPathComponent(stem + "-marker.json")
    let ack = manager.temporaryDirectory.appendingPathComponent(stem + "-ack.json")
    let peer = ack.appendingPathExtension("synthetic-peer")
    let completed = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        defer { completed.signal() }
        let end = Date().addingTimeInterval(2)
        while !manager.fileExists(atPath: marker.path) && Date() < end { Thread.sleep(forTimeInterval: 0.005) }
        guard let bytes = try? Data(contentsOf: marker),
              let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let binding = value["binding"] as? [String: String] else { return }
        var row = binding.reduce(into: [String: Any]()) { $0[$1.key] = $1.value }
        row["markerSHA256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        row["snapshotSHA256"] = String(repeating: "a", count: 64); change?(&row)
        guard var raw = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        if kind == "duplicate" { raw.insert(contentsOf: Data("\"runID\":\"duplicate\",".utf8), at: 1) }
        if kind == "whitespace" { raw.append(32) }
        if kind == "oversize" { raw = Data(repeating: 65, count: 8193) }
        do {
            switch kind {
            case "missing": return
            case "symlink": try raw.write(to: peer, options: .withoutOverwriting); try manager.createSymbolicLink(at: ack, withDestinationURL: peer)
            case "hardlink": try raw.write(to: peer, options: .withoutOverwriting); try manager.linkItem(at: peer, to: ack)
            case "fifo": guard mkfifo(ack.path, mode_t(0o600)) == 0 else { return }
            default:
                let staging = ack.appendingPathExtension("synthetic-staging")
                try raw.write(to: staging, options: .withoutOverwriting); try manager.moveItem(at: staging, to: ack)
            }
        } catch { return }
    }
    var accepted = false, message = ""
    do {
        try barrier.wait(phase: phase, state: state, location: "review-ready",
                         image: ["attachmentName": "synthetic", "bytes": 1, "sha256": String(repeating: "b", count: 64)],
                         timeout: kind == "missing" ? 0.1 : 1.5)
        accepted = true
    } catch { message = error.localizedDescription }
    guard completed.wait(timeout: .now() + 3) == .success, accepted == shouldAccept else {
        throw NSError(domain: "SyntheticNativeBarrierControls", code: 1, userInfo: [NSLocalizedDescriptionKey: label + " wrong actual result"])
    }
    if !accepted && !["symlink", "hardlink", "fifo", "oversize", "missing"].contains(kind) {
        guard let event = barrier.events.last, let attempt = event["ackAttempt"] as? [String: Any],
              let actual = attempt["raw"] as? [String: Any],
              let encoded = actual["base64"] as? String, let raw = Data(base64Encoded: encoded),
              raw == (try? Data(contentsOf: ack)) else { throw NSError(domain: "SyntheticNativeBarrierControls", code: 2) }
    }
    checks.append(["case": label, "accepted": accepted, "error": message, "events": barrier.events])
    for file in [marker, ack, peer, ack.appendingPathExtension("synthetic-staging")] {
        if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey])) != nil { try manager.removeItem(at: file) }
    }
}
try control("exact canonical binding", shouldAccept: true)
for field in ["runID", "runnerPID", "case", "phase", "nonce", "sessionID", "captureID", "selected", "location", "markerSHA256"] {
    try control("wrong " + field, change: { $0[field] = "wrong" })
}
try control("numeric snapshot type", change: { $0["snapshotSHA256"] = 1 })
try control("bad snapshot digest", change: { $0["snapshotSHA256"] = "g" })
for kind in ["duplicate", "whitespace", "symlink", "hardlink", "fifo", "oversize", "missing"] { try control(kind, kind: kind) }
// A later phase must fail before publishing a marker or waiting for any ack.
let wrongOrder = RetainedRecoveryBackendBarrier()
var rejected = false
do { try wrongOrder.wait(phase: "post-success", state: controlState, location: "review-success", image: [:], timeout: 0.1) }
catch { rejected = true }
guard rejected && wrongOrder.events.isEmpty else { fatalError("Out-of-order phase accepted") }
checks.append(["case": "out-of-order phase before marker", "accepted": false])
let data = try JSONSerialization.data(withJSONObject: ["status": "PASS actual extracted native barrier host file controls", "checks": checks], options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
