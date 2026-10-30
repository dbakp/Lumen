import Foundation
import AVFoundation

enum VoiceDraftChecks {
    static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); print("PASS: " + name) }
        var transcript = VoiceTranscript()
        check(transcript.receive(start: 0, duration: 2, text: "I drank 300 ml", final: false) && transcript.hasUnfinishedWords, "voice hypotheses remain visibly unfinished before recognition finalizes")
        check(transcript.receive(start: 0, duration: 2, text: "I drank 350 ml of water.\n", final: true) && transcript.text == "I drank 350 ml of water.\n" && !transcript.hasUnfinishedWords, "the finalized voice result replaces its earlier numeric hypothesis instead of duplicating it")
        check(transcript.receive(start: 0, duration: 2, text: "I drank 350 ml of water.\n", final: true) && transcript.segments.count == 1, "repeated final speech packets do not repeat a saved phrase")
        check(!transcript.receive(start: 0, duration: 2, text: "I drank 700 ml", final: false) && transcript.text.contains("350"), "a conflicting delayed hypothesis cannot overwrite finalized words")
        check(transcript.receive(start: 2, duration: 1, text: "My shoulder hurts.", final: false) && transcript.text == "I drank 350 ml of water.\nMy shoulder hurts.", "adjacent speech ranges retain their exact content and punctuation in time order")
        let retained = transcript.text
        check(!transcript.receive(start: .nan, duration: 1, text: "bad", final: true) && !transcript.receive(start: 3, duration: -1, text: "bad", final: true) && !transcript.receive(start: 3, duration: 1000, text: "bad", final: true) && transcript.text == retained, "invalid speech time ranges leave the preceding reviewable text intact")
        check(!transcript.receive(start: 3, duration: 1, text: String(repeating: "x", count: 8001), final: true) && transcript.text == retained, "voice transcript length limits reject an entire overlarge packet without silently trimming words")
        let combining = "a" + String(repeating: "\u{301}", count: 17_000)
        check(combining.count == 1 && !VoiceTranscript.accepts(combining), "voice draft UTF-8 bounds also cover pathological single-grapheme text")
        var bounded = VoiceTranscript()
        for i in 0..<2048 { precondition(bounded.receive(start: Double(i) / 10, duration: 0.05, text: "", final: true)) }
        check(!bounded.receive(start: 205, duration: 0.05, text: "", final: true), "empty recognition packets cannot create an unbounded segment list")
        let target = VoiceDraftTarget(conversationID: "original", originalDraft: "My earlier question")
        let combined = try target.adding("I drank 350 ml of water.\n\n", to: target)
        check(combined == "My earlier question\nI drank 350 ml of water." && !combined.hasSuffix("\n"), "reviewed voice text preserves a typed draft and removes the trailing keyboard-send cue")
        let empty = VoiceDraftTarget(conversationID: nil, originalDraft: "")
        let standalone = try empty.adding("Line one\nLine two\n", to: empty)
        check(standalone == "Line one\nLine two", "multiline reviewed voice text stays an unsent draft with internal newlines intact")
        for changed in [VoiceDraftTarget(conversationID: "other", originalDraft: target.originalDraft), VoiceDraftTarget(conversationID: "original", originalDraft: "New typing")] {
            do { _ = try target.adding("voice", to: changed); preconditionFailure("changed voice target accepted") }
            catch { print("PASS: changed conversation or typed draft cannot receive an earlier voice capture") }
        }
        do { _ = try target.adding(" \n ", to: target); preconditionFailure("empty accepted") } catch { print("PASS: empty reviewed voice text cannot replace or append to a message") }
        let full = VoiceDraftTarget(conversationID: nil, originalDraft: String(repeating: "x", count: 7999))
        do { _ = try full.adding("more", to: full); preconditionFailure("combined limit") } catch { print("PASS: combined message limits preserve the original draft when voice text will not fit") }
        check(ComposerDraftEdit.isReturn(previous: "Message", next: "Message\n") && !ComposerDraftEdit.isReturn(previous: "Message", next: "Message\nPasted health text\n"), "composer keyboard Return remains separate from a multiline paste")
        check(!ComposerDraftEdit.isReturn(previous: "", next: "Line one\nLine two\n"), "a complete inserted multiline draft is not interpreted as a keyboard Send event")

        // The actual owned-buffer copy and sample-rate conversion used by the mic.
        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4096)!
        buffer.frameLength = 4096
        for channel in 0..<2 { for frame in 0..<4096 { buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 200 / 48_000) * 0.25) } }
        let copy = try VoiceAudioChunk(copying: buffer)
        let original = copy.buffer.floatChannelData![0][100]
        buffer.floatChannelData![0][100] = 0.9
        check(copy.buffer.floatChannelData![0][100] == original && copy.buffer.floatChannelData![1][100] == original, "audio tap buffers are owned copies before the engine can reuse or mutate them")
        let converter = try VoicePCMConverter(source: sourceFormat, target: targetFormat)
        var frames = 0, energy: Double = 0, formatsCorrect = true
        for _ in 0..<4 {
            if let output = try converter.convert(copy.buffer) {
                formatsCorrect = formatsCorrect && output.format == targetFormat
                frames += Int(output.frameLength)
                for i in 0..<Int(output.frameLength) { let value = output.floatChannelData![0][i]; precondition(value.isFinite); energy += Double(value * value) }
            }
        }
        for output in try converter.flush() { frames += Int(output.frameLength) }
        check(formatsCorrect, "actual voice PCM conversion produces the analyzer's mono 16 kHz format throughout the stream")
        check(abs(Double(frames) - 4 * 4096 / 3) < 64 && energy > 1, "streamed resampling and final drain retain the synthetic audio duration and nonzero finite signal")
        let bypass = try VoicePCMConverter(source: sourceFormat, target: sourceFormat)
        let unchanged = try bypass.convert(copy.buffer)
        check(unchanged === copy.buffer, "already compatible PCM buffers need no extra conversion copy")
    }
}
