import Foundation
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let report = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as! [String: Any]
let cases = report["cases"] as! [[String: Any]]
var results: [[String: Any]] = []
for item in cases {
    let root = URL(fileURLWithPath: item["root"] as! String)
    var files: [[String: String]] = []
    for case let file as URL in FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)! {
        let facts = try FileManager.default.attributesOfItem(atPath: file.path)
        if facts[.type] as? FileAttributeType == .typeRegular {
            let canonicalRoot = root.resolvingSymlinksInPath().path
            let canonicalFile = file.resolvingSymlinksInPath().path
            guard canonicalFile.hasPrefix(canonicalRoot + "/") else { fatalError("outside synthetic root") }
            files.append(["actualEnumeratedPath": file.path,
                          "actualProducerKey": String(file.path.dropFirst(root.path.count + 1)),
                          "canonicalRelative": String(canonicalFile.dropFirst(canonicalRoot.count + 1))])
        }
    }
    results.append(["label": item["label"]!, "rootURLPath": root.path,
                    "canonicalRoot": root.resolvingSymlinksInPath().path, "files": files])
}
try JSONSerialization.data(withJSONObject: ["status": "Read-only actual Foundation path spelling probe", "cases": results], options: [.prettyPrinted, .sortedKeys]).write(to: output)
print("Read-only Foundation path mapping cases", results.count)
