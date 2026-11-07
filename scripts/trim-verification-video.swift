import Foundation
import AVFoundation
import CryptoKit

// Retain declared verification intervals without changing their pixel size or
// requesting a new video encoding. Exported container/timing can differ: keep
// actual duration and source provenance, and review decoded frames separately.
// Usage: swift scripts/trim-verification-video.swift input.mp4 plan.json output-dir
struct Window: Decodable { let name: String; let startSeconds: Double; let endSeconds: Double }
let args = CommandLine.arguments
guard args.count == 4 else { fatalError("Supply recording, declared windows and owned output directory") }
let source = URL(fileURLWithPath: args[1]), plan = URL(fileURLWithPath: args[2])
let output = URL(fileURLWithPath: args[3], isDirectory: true)
guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Refusing to overwrite clip output") }
func fingerprint(_ url: URL) throws -> String {
    let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
    var hash = SHA256()
    while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty { hash.update(data: bytes) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
let windows = try JSONDecoder().decode([Window].self, from: Data(contentsOf: plan))
let asset = AVURLAsset(url: source), duration = try await asset.load(.duration)
guard duration.seconds.isFinite, !windows.isEmpty, windows.count <= 6,
      Set(windows.map(\.name)).count == windows.count else { fatalError("Invalid window plan") }
for window in windows {
    guard !window.name.isEmpty, window.name.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil,
          window.startSeconds.isFinite, window.endSeconds.isFinite,
          window.startSeconds >= 0, window.startSeconds < window.endSeconds,
          window.endSeconds <= duration.seconds else { fatalError("Invalid or out-of-range interval") }
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
var clips: [[String: Any]] = []
for window in windows {
    guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { fatalError("Passthrough export unavailable") }
    exporter.timeRange = CMTimeRange(start: CMTime(seconds: window.startSeconds, preferredTimescale: 60_000),
        duration: CMTime(seconds: window.endSeconds - window.startSeconds, preferredTimescale: 60_000))
    let file = output.appendingPathComponent(window.name + ".mov")
    try await exporter.export(to: file, as: .mov)
    let clipAsset = AVURLAsset(url: file), actualDuration = try await clipAsset.load(.duration)
    guard actualDuration.seconds.isFinite, let track = try await clipAsset.loadTracks(withMediaType: .video).first else { fatalError("Invalid exported clip") }
    let size = try await track.load(.naturalSize)
    clips.append(["file": file.lastPathComponent, "sourceStartSeconds": window.startSeconds,
        "sourceEndSeconds": window.endSeconds, "actualClipDurationSeconds": actualDuration.seconds,
        "width": size.width, "height": size.height, "sha256": try fingerprint(file),
        "bytes": try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0])
}
let report: [String: Any] = ["scope": "Declared source intervals exported with AVFoundation passthrough; no visual motion acceptance or exact wall-clock alignment inferred",
    "sourceRecording": source.path, "sourceSHA256": try fingerprint(source), "sourceDurationSeconds": duration.seconds,
    "planSHA256": try fingerprint(plan), "extractorSHA256": try fingerprint(URL(fileURLWithPath: args[0])), "clips": clips]
guard JSONSerialization.isValidJSONObject(report) else { fatalError("Invalid clip provenance JSON") }
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("clip-provenance.json"))
print("Retained \(clips.count) declared passthrough intervals")
