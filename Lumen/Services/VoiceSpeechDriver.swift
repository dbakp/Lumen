import Foundation
import Speech
import AVFoundation
import UIKit

@available(iOS 26, *)
@MainActor
final class VoiceSpeechResource {
    enum Module {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)
        var value: any SpeechModule {
            switch self { case .speech(let x): return x; case .dictation(let x): return x }
        }
    }
    let module: Module
    let locale: Locale
    private var reserved = false
    init(module: Module, locale: Locale) { self.module = module; self.locale = locale }
    static func locales() async -> [Locale] {
        let speech = SpeechTranscriber.isAvailable ? await SpeechTranscriber.supportedLocales : []
        let dictation = await DictationTranscriber.supportedLocales
        return Dictionary((speech + dictation).map { ($0.identifier(.bcp47), $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.identifier < $1.identifier }
    }
    static func make(locale: Locale) async throws -> VoiceSpeechResource {
        if SpeechTranscriber.isAvailable, let selected = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .init(module: .speech(SpeechTranscriber(locale: selected, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])), locale: selected)
        }
        if let selected = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .init(module: .dictation(DictationTranscriber(locale: selected, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [.volatileResults], attributeOptions: [])), locale: selected)
        }
        throw VoiceCaptureError.unavailable
    }
    func status() async -> AssetInventory.Status { await AssetInventory.status(forModules: [module.value]) }
    func reserve() async throws {
        if !reserved { _ = try await AssetInventory.reserve(locale: locale); reserved = true }
    }
    func release() async {
        if reserved { reserved = false; _ = await AssetInventory.release(reservedLocale: locale) }
    }
    /// This is called only after the separate Download language decision.
    func installation() async throws -> AssetInstallationRequest? {
        try await reserve()
        return try await AssetInventory.assetInstallationRequest(supporting: [module.value])
    }
}

enum VoiceCaptureError: LocalizedError {
    case unavailable, microphone, setup, transcript, interrupted, timedOut, inactive
    var errorDescription: String? {
        switch self {
        case .unavailable: return "On-device speech isn't available for this language on this device. Choose another language or type your message."
        case .microphone: return "Microphone access is off. Allow it in Settings to record a voice draft."
        case .setup: return "Voice input couldn't start. Check your microphone and audio connection, then try again."
        case .transcript: return "Voice stopped before all words could be checked. Review the text captured so far, or try again."
        case .interrupted: return "Recording stopped when the audio connection changed. Review the text before using it."
        case .timedOut: return "Some words didn't finish transcribing. Check the text captured so far."
        case .inactive: return "Voice input didn't start because Lumen left the foreground. Return and start recording when you're ready."
        }
    }
}

@available(iOS 26, *)
@MainActor
final class VoiceSpeechDriver {
    typealias Receiver = @MainActor (Double, Double, String, Bool) -> Bool
    private let resource: VoiceSpeechResource
    private let engine = AVAudioEngine()
    private var raw: AsyncThrowingStream<VoiceAudioChunk, Error>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var installedTap = false
    private var sessionActive = false
    private var cancelled = false
    private(set) var pausedSounds = false
    init(resource: VoiceSpeechResource) { self.resource = resource }

    func run(started: @MainActor () -> Void, receive: @escaping Receiver) async throws {
        try Task.checkCancellation()
        guard await resource.status() == .installed else { throw VoiceCaptureError.unavailable }
        try Task.checkCancellation(); guard !cancelled else { throw CancellationError() }
        try await resource.reserve()
        if Task.isCancelled || cancelled { await resource.release(); throw CancellationError() }
        var conversionTask: Task<Void, Error>?
        var resultTask: Task<Void, Error>?
        var inputBuilder: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
        let session = AVAudioSession.sharedInstance()
        do {
            pausedSounds = SoundEngine.shared.isPlaying
            SoundEngine.shared.pauseForVoice()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try session.setActive(true); sessionActive = true
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0,
                  let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [resource.module.value], considering: format) else { throw VoiceCaptureError.setup }
            let analyzer = SpeechAnalyzer(modules: [resource.module.value], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
            self.analyzer = analyzer
            try await analyzer.prepareToAnalyze(in: target)
            try Task.checkCancellation(); guard !cancelled else { throw CancellationError() }
            let (audio, builder) = AsyncThrowingStream<VoiceAudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(16))
            raw = builder
            let (converted, inputs) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(16))
            inputBuilder = inputs
            let converter = try VoicePCMConverter(source: format, target: target)
            let conversion = Task.detached(priority: .userInitiated) {
                do {
                    func emit(_ buffer: AVAudioPCMBuffer) throws {
                        if case .dropped = inputs.yield(AnalyzerInput(buffer: buffer)) { throw VoiceAudioError.overrun }
                    }
                    for try await chunk in audio {
                        try Task.checkCancellation()
                        if let buffer = try converter.convert(chunk.buffer) { try emit(buffer) }
                    }
                    for buffer in try converter.flush() { try emit(buffer) }
                    inputs.finish()
                } catch { inputs.finish(throwing: error); throw error }
            }
            conversionTask = conversion
            let results = Task { @MainActor in
                switch resource.module {
                case .speech(let module):
                    for try await item in module.results {
                        try Task.checkCancellation()
                        guard receive(item.range.start.seconds, item.range.duration.seconds, String(item.text.characters), item.isFinal) else { throw VoiceCaptureError.transcript }
                    }
                case .dictation(let module):
                    for try await item in module.results {
                        try Task.checkCancellation()
                        guard receive(item.range.start.seconds, item.range.duration.seconds, String(item.text.characters), item.isFinal) else { throw VoiceCaptureError.transcript }
                    }
                }
            }
            resultTask = results
            guard UIApplication.shared.applicationState == .active else { throw VoiceCaptureError.inactive }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                do {
                    let chunk = try VoiceAudioChunk(copying: buffer)
                    if case .dropped = builder.yield(chunk) { builder.finish(throwing: VoiceAudioError.overrun) }
                } catch { builder.finish(throwing: error) }
            }
            installedTap = true
            engine.prepare(); try engine.start(); started()
            do {
                // Race processing against result-stream failures, so an error cannot
                // leave the microphone running until the recording time limit.
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let last = try await analyzer.analyzeSequence(converted)
                        builder.finish()
                        if let last { try await analyzer.finalizeAndFinish(through: last) }
                        else { await analyzer.cancelAndFinishNow() }
                        _ = try await conversion.value
                    }
                    group.addTask { _ = try await results.value }
                    do { while try await group.next() != nil {} }
                    catch {
                        stopAudio()
                        conversion.cancel(); results.cancel(); builder.finish(throwing: error); inputs.finish(throwing: error)
                        await analyzer.cancelAndFinishNow(); group.cancelAll(); throw error
                    }
                }
            } catch {
                conversion.cancel(); results.cancel(); builder.finish(throwing: error); inputs.finish(throwing: error)
                await analyzer.cancelAndFinishNow()
                _ = await conversion.result; _ = await results.result
                throw error
            }
            stopAudio()
            await resource.release()
        } catch {
            stopAudio(); raw?.finish(throwing: error); inputBuilder?.finish(throwing: error)
            conversionTask?.cancel(); resultTask?.cancel()
            if let analyzer { await analyzer.cancelAndFinishNow() }
            _ = await conversionTask?.result; _ = await resultTask?.result
            await resource.release()
            throw error
        }
    }
    /// Ending the input stops the microphone before final recognition is awaited.
    func stop() { stopAudio(); raw?.finish() }
    func cancel() {
        cancelled = true; stopAudio(); raw?.finish(throwing: CancellationError())
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    }
    private func stopAudio() {
        if installedTap { engine.inputNode.removeTap(onBus: 0); installedTap = false }
        engine.stop(); engine.reset()
        if sessionActive {
            sessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
