import Foundation
import AVFoundation
import ImageIO
import CryptoKit

// Read exact native test-recording frames without downloading a media runtime.
// Usage: swift scripts/extract-verification-frames.swift recording.mp4 output-dir [seconds-from-end ...]
let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fatalError("Supply a recording and an owned output directory") }
let input = URL(fileURLWithPath: arguments[1]), output = URL(fileURLWithPath: arguments[2], isDirectory: true)
let offsets = arguments.dropFirst(3).compactMap(Double.init)
let requestedOffsets = offsets.isEmpty ? [2.0] : offsets
func fingerprint(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
    var digest = SHA256()
    while let data = try file.read(upToCount: 65_536), !data.isEmpty { digest.update(data: data) }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
}
let asset = AVURLAsset(url: input), duration = try await asset.load(.duration)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var frames: [[String: Any]] = []
for offset in requestedOffsets {
    guard offset >= 0 && offset < duration.seconds else { fatalError("Offset outside recording") }
    let time = CMTime(seconds: duration.seconds - offset, preferredTimescale: 600)
    let frame = try await generator.image(at: time)
    let file = output.appendingPathComponent("recording-offset-\(offset).png")
    guard !FileManager.default.fileExists(atPath: file.path),
          let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { fatalError("Refusing to replace a frame or unable to create it") }
    CGImageDestinationAddImage(destination, frame.image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Frame could not be saved") }
    frames.append(["file": file.lastPathComponent, "requestedSeconds": time.seconds,
                   "actualSeconds": frame.actualTime.seconds, "width": frame.image.width, "height": frame.image.height,
                   "sha256": try fingerprint(file)])
}
let provenance: [String: Any] = ["scope": "Uncropped native recording frames; AVFoundation preferred track orientation, original pixel dimensions. No image generation or content editing.",
    "recording": input.lastPathComponent, "recordingSHA256": try fingerprint(input), "durationSeconds": duration.seconds,
    "extractorSHA256": try fingerprint(URL(fileURLWithPath: arguments[0])), "frames": frames]
try JSONSerialization.data(withJSONObject: provenance, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("frame-provenance.json"), options: .atomic)
print("Extracted \(frames.count) native frame(s)")
