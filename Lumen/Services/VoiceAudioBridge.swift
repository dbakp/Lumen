import Foundation
import AVFoundation

/// A tap's buffer may be reused by AVAudioEngine. Only owned copies cross queues.
final class VoiceAudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(copying source: AVAudioPCMBuffer) throws {
        guard source.frameLength > 0, source.frameLength <= 65_536,
              source.format.channelCount > 0, source.format.channelCount <= 8,
              let owned = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { throw VoiceAudioError.format }
        owned.frameLength = source.frameLength
        let original = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(owned.mutableAudioBufferList)
        guard original.count == destination.count else { throw VoiceAudioError.format }
        for index in original.indices {
            let count = Int(original[index].mDataByteSize)
            guard count <= Int(destination[index].mDataByteSize), let from = original[index].mData, let to = destination[index].mData else { throw VoiceAudioError.format }
            memcpy(to, from, count)
        }
        buffer = owned
    }
}

enum VoiceAudioError: Error { case format, overrun, conversion }

/// Used by the actual microphone path and generated-PCM verification, without files.
final class VoicePCMConverter {
    private let target: AVAudioFormat
    private let converter: AVAudioConverter?
    init(source: AVAudioFormat, target: AVAudioFormat) throws {
        guard source.sampleRate.isFinite, target.sampleRate.isFinite,
              (8_000...192_000).contains(source.sampleRate), (8_000...192_000).contains(target.sampleRate),
              (1...8).contains(source.channelCount), (1...8).contains(target.channelCount) else { throw VoiceAudioError.format }
        self.target = target
        if source == target { converter = nil }
        else {
            guard let value = AVAudioConverter(from: source, to: target) else { throw VoiceAudioError.conversion }
            converter = value
        }
    }
    func convert(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        guard let converter else { return source }
        let ratio = target.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio)) + 256
        guard capacity <= 1_000_000, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw VoiceAudioError.format }
        var supplied = false, error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return source
        }
        guard status != .error, error == nil else { throw VoiceAudioError.conversion }
        return output.frameLength > 0 ? output : nil
    }
    func flush() throws -> [AVAudioPCMBuffer] {
        guard let converter else { return [] }
        var result: [AVAudioPCMBuffer] = []
        for _ in 0..<16 {
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else { throw VoiceAudioError.format }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in state.pointee = .endOfStream; return nil }
            guard status != .error, error == nil else { throw VoiceAudioError.conversion }
            if output.frameLength > 0 { result.append(output) }
            if status == .endOfStream || output.frameLength == 0 { return result }
        }
        throw VoiceAudioError.conversion
    }
}
