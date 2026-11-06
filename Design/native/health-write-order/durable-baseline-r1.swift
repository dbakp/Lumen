import Foundation
import Darwin

/// Run as two actual processes against an isolated synthetic folder. Uses the
/// unchanged production queue; neither this harness nor the queue calls HealthKit.
@main struct DurableBaseline {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func save(_ object: [String: String], _ name: String) throws {
            try encoder.encode(object).write(to: root.appendingPathComponent(name), options: .atomic)
        }
        let queue = OrderedHealthWrites()
        if CommandLine.arguments[1] == "prepare" {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try save(["water": "250mL", "meal": "synthetic nutrition", "weight": "75kg"], "local-records.json")
            // HealthStore's real local-commit / task-scheduling boundary has
            // exactly this stop window. No actor yield before process death.
            queue.enqueueSave(.water("synthetic-water"), isCurrent: { true }) {
                try! save(["water": "saved"], "external-water.json")
            }
            queue.enqueueSave(.meal("synthetic-meal"), isCurrent: { true }) {
                try! save(["meal": "saved"], "external-meal.json")
            }
            Task { @MainActor in try! save(["weight": "saved"], "external-weight.json") }
            precondition(queue.pendingRecordCount == 2)
            try save(["pid": String(getpid()), "pendingQueueKeys": "2", "weight": "unstructured Task", "boundary": "local commit before worker actor turn"], "prepare.json")
            _exit(0)
        }
        precondition(CommandLine.arguments[1] == "resume")
        let prepared = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("prepare.json")))
        precondition(prepared["pid"] != String(getpid()))
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent("local-records.json").path))
        precondition(queue.pendingRecordCount == 0)
        for kind in ["water", "meal", "weight"] {
            precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("external-" + kind + ".json").path))
        }
        try save(["pid": String(getpid()), "originalPID": prepared["pid"]!, "status": "defect reproduced", "localRecords": "retained", "pendingQueueKeys": "0", "externalOperations": "0", "scope": "Real process termination and production ordering primitive; synthetic local/adapter files, no HealthKit or HealthStore integration claim"], "resume.json")
        print("PASS: actual new process retains local records and loses all pending external work; pre-repair defect reproduced.")
    }
}
