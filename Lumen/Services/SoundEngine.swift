import Foundation
import AVFoundation

// MARK: - Procedural sleep sound engine (no bundled audio needed)

@MainActor
public final class SoundEngine: ObservableObject {
    public static let shared = SoundEngine()
    @Published public var playingId: String?
    @Published public var isPlaying = false
    @Published public var sleepTimerMinutes: Int = 0

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var timer: Timer?
    private var phase: Double = 0
    private var brownLast: Double = 0
    private var kind: SoundTrack.SoundKind = .rain

    public func toggle(_ track: SoundTrack) {
        if playingId == track.id && isPlaying {
            stop()
        } else {
            play(track)
        }
    }

    public func play(_ track: SoundTrack) {
        stopEngine()
        kind = track.kind
        playingId = track.id
        phase = 0; brownLast = 0

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }

        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let kindCopy = kind

        var noiseSeed: UInt32 = 123456789
        func white() -> Double {
            noiseSeed = noiseSeed &* 1664525 &+ 1013904223
            return (Double(noiseSeed >> 8) / Double(UInt32.max >> 8)) * 2 - 1
        }

        var brown: Double = 0
        var lowpass: Double = 0
        var t: Double = 0

        let src = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                t += 1 / 44100.0
                let w = white()
                var sample: Double = 0
                switch kindCopy {
                case .whiteNoise, .fan:
                    // Fan = white + slow amplitude LFO.
                    let lfo = kindCopy == .fan ? (0.75 + 0.25 * sin(2 * .pi * 0.7 * t)) : 1.0
                    lowpass = lowpass * 0.92 + w * 0.08
                    sample = (kindCopy == .fan ? (w * 0.25 + lowpass * 2.2) : w * 0.22) * lfo
                case .pinkNoise:
                    lowpass = lowpass * 0.97 + w * 0.03
                    sample = (w * 0.06 + lowpass * 3.2) * 0.5
                case .brownNoise, .fireplace:
                    brown = (brown + 0.02 * w) / 1.02
                    sample = brown * 3.2
                    if kindCopy == .fireplace {
                        // crackle: sparse random pops
                        if white() > 0.9985 { sample += white() * 0.5 * exp(-fmod(t, 0.09) * 40) }
                    }
                case .rain:
                    lowpass = lowpass * 0.86 + w * 0.14
                    let patter = 0.6 + 0.4 * sin(2 * .pi * 3.1 * t) * sin(2 * .pi * 0.43 * t)
                    sample = (w * 0.10 + lowpass * 1.4) * patter
                case .ocean:
                    let swell = 0.5 + 0.5 * sin(2 * .pi * 0.09 * t)
                    lowpass = lowpass * 0.94 + w * 0.06
                    sample = (w * 0.05 + lowpass * 2.6) * (0.35 + 0.65 * swell)
                case .forest:
                    lowpass = lowpass * 0.96 + w * 0.04
                    let cricket = max(0, sin(2 * .pi * 4200 * t)) * (0.5 + 0.5 * sin(2 * .pi * 6 * t))
                    sample = lowpass * 1.8 + cricket * 0.015
                }
                let s = Float(max(-1, min(1, sample * 0.8)))
                for buf in abl {
                    let ptr = buf.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame * 2] = s
                    if buf.mNumberChannels > 1 { ptr[frame * 2 + 1] = s }
                }
            }
            return noErr
        }

        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.engine = engine
            self.sourceNode = src
            self.isPlaying = true
        } catch {
            self.isPlaying = false
        }
    }

    public func stop() {
        stopEngine()
        playingId = nil
        isPlaying = false
        timer?.invalidate(); timer = nil
        sleepTimerMinutes = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public func startSleepTimer(minutes: Int) {
        sleepTimerMinutes = minutes
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    private func stopEngine() {
        engine?.stop()
        engine = nil
        sourceNode = nil
    }
}
