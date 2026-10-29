// Turns the design skill's lossless frames into a portable MP4 using macOS AVFoundation.
import Foundation
import AVFoundation
import CoreGraphics
import ImageIO

@main struct DesignMovie {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("Usage: design-movie <frame-directory> <output.mp4>") }
        let folder = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
        let frames = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" && $0.lastPathComponent != "seam.png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let first = frames.first, let source = CGImageSourceCreateWithURL(first as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("No PNG frames") }
        let width = image.width, height = image.height
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        for (index, url) in frames.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            try autoreleasepool {
                guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(s, 0, nil) else { fatalError("Invalid frame") }
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
                guard let buffer else { fatalError("Could not allocate video buffer") }
                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { fatalError("Could not draw frame") }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 12)) else { throw writer.error! }
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        print("Created \(output.lastPathComponent): \(frames.count) frames, 12 fps")
    }
}
