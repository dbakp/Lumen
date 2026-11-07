import Foundation
import AVFoundation
import ImageIO
import CryptoKit

// Inspect actual native recording cadence and optionally extract uncropped
// original-sized frames at explicit video times. No wall-clock alignment is
// inferred from recorder acknowledgement or from requested frame times.
// Usage: swift scripts/inspect-verification-video.swift input.mp4 output-dir [times.json]
let args = CommandLine.arguments
guard args.count == 3 || args.count == 4 else { fatalError("Supply input, owned output directory and optional JSON array of video seconds") }
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2], isDirectory: true)
guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Refusing to overwrite an inspection") }
func hash(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    var value = SHA256()
    while let bytes = try handle.read(upToCount: 65_536), !bytes.isEmpty { value.update(data: bytes) }
    return value.finalize().map { String(format: "%02x", $0) }.joined()
}
let asset = AVURLAsset(url: input)
let duration = try await asset.load(.duration)
guard let track = try await asset.loadTracks(withMediaType: .video).first else { fatalError("No video track") }
let size = try await track.load(.naturalSize)
let rate = try await track.load(.nominalFrameRate)
let reader = try AVAssetReader(asset: asset)
let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
guard reader.canAdd(trackOutput) else { fatalError("Cannot inspect video samples") }
reader.add(trackOutput)
guard reader.startReading() else { throw reader.error ?? NSError(domain: "VideoInspection", code: 1) }
var sampleTimes: [Double] = []
while let sample = trackOutput.copyNextSampleBuffer() {
    sampleTimes.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
}
guard reader.status == .completed else { throw reader.error ?? NSError(domain: "VideoInspection", code: 2) }
let ordered = sampleTimes.sorted()
let deltas = zip(ordered.dropFirst(), ordered).map(-)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
var frames: [[String: Any]] = []
if args.count == 4 {
    let times = try JSONDecoder().decode([Double].self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
    guard times.count <= 80, Set(times).count == times.count,
          times.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < duration.seconds }) else { fatalError("At most80unique finite in-range frame times") }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    for (index, seconds) in times.enumerated() {
        let value = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60_000))
        let destinationURL = output.appendingPathComponent(String(format: "frame-%03d.png", index))
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, "public.png" as CFString, 1, nil) else { fatalError("Cannot create frame") }
        CGImageDestinationAddImage(destination, value.image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save frame") }
        frames.append(["file": destinationURL.lastPathComponent, "requestedVideoSeconds": seconds,
                       "actualVideoSeconds": value.actualTime.seconds, "width": value.image.width,
                       "height": value.image.height, "sha256": try hash(destinationURL)])
    }
}
let report: [String: Any] = [
    "scope": "Actual compressed sample presentation timestamps and optional uncropped native frames; no visual motion or wall-clock alignment acceptance inferred",
    "recording": input.path, "recordingSHA256": try hash(input),
    "recordingBytes": try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
    "durationSeconds": duration.seconds, "naturalWidth": size.width, "naturalHeight": size.height,
    "nominalFrameRate": rate, "compressedSamples": sampleTimes.count,
    "presentationTimesSeconds": ordered, "minimumPresentationDeltaSeconds": deltas.min() ?? 0,
    "maximumPresentationDeltaSeconds": deltas.max() ?? 0,
    "extractorSHA256": try hash(URL(fileURLWithPath: args[0])), "frames": frames
]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("video-provenance.json"))
print("Inspected \(sampleTimes.count) compressed samples; extracted \(frames.count) native frames")
