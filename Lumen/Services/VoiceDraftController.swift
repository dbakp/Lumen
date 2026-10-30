import Foundation
import AVFoundation
import Speech
import UIKit

@available(iOS 26, *)
@MainActor
final class VoiceDraftController: ObservableObject {
    static let shared = VoiceDraftController()
    enum Phase { case checking, ready, needsDownload, downloading, authorizing, recording, finishing, reviewing, unavailable }
    struct Language: Identifiable { let id: String; let name: String }
    @Published private(set) var phase: Phase = .checking
    @Published private(set) var languages: [Language] = []
    @Published private(set) var languageID = ""
    @Published private(set) var liveText = ""
    @Published var text = "" { didSet { if oldValue != text { checked = false } } }
    @Published var checked = false
    @Published private(set) var notice: String?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var downloadProgress: Progress?
    @Published private(set) var soundsPaused = false
    private var transcript = VoiceTranscript()
    private var identity: UUID?
    private var work: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var resource: VoiceSpeechResource?
    private var driver: VoiceSpeechDriver?
    private var capturedThisAttempt = false
    private var fixtureStarts = 0
    private var began = 0.0
    private var finishingDeadline = 0.0
    private var observers: [NSObjectProtocol] = []
    var busy: Bool { [.checking, .downloading, .authorizing, .recording, .finishing].contains(phase) }
    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var validText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && VoiceTranscript.accepts(text) }
    var fixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-voice-fixture")
        #else
        false
        #endif
    }
    private init() {}

    func open(language: String? = nil) {
        close()
        let oldCleanup = cleanup, id = UUID(); identity = id
        phase = .checking; text = ""; liveText = ""; transcript = .init(); checked = false
        notice = nil; elapsed = 0; downloadProgress = nil; soundsPaused = false; fixtureStarts = 0
        work = Task {
            await oldCleanup?.value
            guard identity == id, !Task.isCancelled else { return }
            if fixture {
                languages = [.init(id: "en-US", name: "English (United States)")]; languageID = "en-US"; phase = .ready; work = nil; return
            }
            // Reservations are per app. No earlier voice worker is active here;
            // release any Lumen reservation left by an interrupted previous launch.
            for locale in await AssetInventory.reservedLocales {
                guard identity == id, !Task.isCancelled else { return }
                _ = await AssetInventory.release(reservedLocale: locale)
            }
            let locales = await VoiceSpeechResource.locales()
            guard identity == id, !Task.isCancelled else { return }
            languages = locales.map { .init(id: $0.identifier(.bcp47), name: Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let preferred = language ?? UserDefaults.standard.string(forKey: "lumen.voice.language") ?? Locale.preferredLanguages.first ?? Locale.current.identifier
            do {
                let selected = try await VoiceSpeechResource.make(locale: Locale(identifier: preferred))
                guard identity == id, !Task.isCancelled else { return }
                resource = selected; languageID = selected.locale.identifier(.bcp47)
                if !languages.contains(where: { $0.id == languageID }) { languages.append(.init(id: languageID, name: Locale.current.localizedString(forIdentifier: languageID) ?? languageID)) }
                let status = await selected.status()
                guard identity == id, !Task.isCancelled else { return }
                switch status {
                case .installed: phase = .ready
                case .supported, .downloading: phase = .needsDownload
                default: phase = .unavailable; notice = VoiceCaptureError.unavailable.localizedDescription
                }
                guard identity == id else { return }
                UserDefaults.standard.set(languageID, forKey: "lumen.voice.language")
            } catch { if identity == id { phase = .unavailable; notice = VoiceCaptureError.unavailable.localizedDescription } }
            if identity == id { work = nil }
        }
    }
    func download() {
        guard phase == .needsDownload, let id = identity, let resource else { return }
        phase = .downloading; notice = nil
        work = Task {
            do {
                if let request = try await resource.installation() {
                    guard identity == id, !Task.isCancelled else { throw CancellationError() }
                    downloadProgress = request.progress
                    try await request.downloadAndInstall()
                }
                try Task.checkCancellation(); guard identity == id else { throw CancellationError() }
                let status = await resource.status()
                try Task.checkCancellation(); guard identity == id else { throw CancellationError() }
                guard status == .installed else { throw VoiceCaptureError.unavailable }
                phase = .ready; notice = "Language is ready. Tap Start recording when you're ready."
            } catch {
                if identity == id { phase = .needsDownload; notice = "The language isn't ready yet. iOS may retry a shared download. Try again later, choose another language or type your message." }
            }
            if identity == id { downloadProgress = nil; work = nil }
        }
    }
    func start() {
        guard [.ready, .reviewing, .unavailable].contains(phase), let id = identity else { return }
        phase = .authorizing; notice = nil; capturedThisAttempt = false
        work = Task {
            if fixture { await runFixture(id: id); return }
            var failure: String?
            do {
                let resource: VoiceSpeechResource
                if let existing = self.resource { resource = existing }
                else { resource = try await VoiceSpeechResource.make(locale: Locale(identifier: languageID)) }
                try Task.checkCancellation(); guard identity == id else { throw CancellationError() }
                self.resource = resource
                let status = await resource.status()
                try Task.checkCancellation(); guard identity == id else { throw CancellationError() }
                guard status == .installed else {
                    if identity == id { phase = .needsDownload; work = nil }
                    return
                }
                let allowed = await AVAudioApplication.requestRecordPermission()
                try Task.checkCancellation(); guard identity == id else { throw CancellationError() }
                guard allowed else { throw VoiceCaptureError.microphone }
                for _ in 0..<20 where UIApplication.shared.applicationState != .active {
                    try await Task.sleep(for: .milliseconds(50))
                }
                try Task.checkCancellation(); guard identity == id else { throw CancellationError() }
                guard UIApplication.shared.applicationState == .active else { throw VoiceCaptureError.inactive }
                let driver = VoiceSpeechDriver(resource: resource); self.driver = driver
                installAudioObservers(id: id)
                try await driver.run(started: { [weak self] in
                    self?.soundsPaused = driver.pausedSounds
                    self?.recordingBegan(id: id)
                }, receive: { start, duration, value, final in
                    guard self.identity == id else { return false }
                    let accepted = self.transcript.receive(start: start, duration: duration, text: value, final: final)
                    self.liveText = self.transcript.text
                    return accepted
                })
            } catch {
                if error is CancellationError { failure = VoiceCaptureError.timedOut.localizedDescription }
                else { failure = (error as? VoiceCaptureError)?.localizedDescription ?? "Voice input stopped. Review any text captured, or try again." }
            }
            removeAudioObservers()
            if let resource = self.resource { await resource.release() }
            if identity == id {
                soundsPaused = driver?.pausedSounds ?? soundsPaused
                self.resource = nil; driver = nil; work = nil
                finish(id: id, message: failure)
            }
        }
    }
    private func recordingBegan(id: UUID) {
        guard identity == id else { return }
        capturedThisAttempt = true
        transcript = .init(); liveText = ""; text = ""; checked = false
        began = ProcessInfo.processInfo.systemUptime; elapsed = 0; phase = .recording
        clock?.cancel()
        clock = Task {
            while !Task.isCancelled, identity == id {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, identity == id else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if phase == .recording {
                    elapsed = now - began
                    if elapsed >= 180 { stop(message: "Recording stopped at three minutes. Review the text before using it.") }
                } else if phase == .finishing, now >= finishingDeadline {
                    notice = VoiceCaptureError.timedOut.localizedDescription; driver?.cancel(); work?.cancel(); return
                }
            }
        }
    }
    func stop(message: String? = nil) {
        guard phase == .recording else { return }
        phase = .finishing; finishingDeadline = ProcessInfo.processInfo.systemUptime + 5
        if let message { notice = message }
        driver?.stop()
    }
    func interrupted() {
        if phase == .recording { stop(message: VoiceCaptureError.interrupted.localizedDescription) }
        else if phase == .authorizing, driver != nil { driver?.cancel(); work?.cancel() }
    }
    func leftForeground(background: Bool) {
        if phase == .recording { stop(message: "Recording stopped when you left Lumen. Check the text before using it.") }
        else if background, phase == .authorizing { driver?.cancel(); work?.cancel() }
    }
    private func finish(id: UUID, message: String? = nil) {
        guard identity == id else { return }
        clock?.cancel(); clock = nil
        if let message { notice = message }
        if capturedThisAttempt { text = transcript.text }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phase = .unavailable
            if notice == nil { notice = "No words were captured. Try again or type your message." }
        } else {
            phase = .reviewing
            if transcript.hasUnfinishedWords && notice == nil { notice = "Some words may still be unfinished. Check the text before using it." }
        }
    }
    func close() {
        identity = nil; driver?.cancel(); downloadProgress?.cancel(); work?.cancel(); clock?.cancel()
        removeAudioObservers()
        let old = work, prior = cleanup, resource = resource
        work = nil; driver = nil; self.resource = nil; clock = nil; downloadProgress = nil
        cleanup = Task { await prior?.value; await old?.value; await resource?.release() }
        text = ""; liveText = ""; transcript = .init(); checked = false
    }
    private func installAudioObservers(id: UUID) {
        removeAudioObservers()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard self?.identity == id else { return }; self?.interrupted() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  raw != AVAudioSession.RouteChangeReason.categoryChange.rawValue else { return }
            Task { @MainActor in guard self?.identity == id else { return }; self?.interrupted() }
        })
    }
    private func removeAudioObservers() { for token in observers { NotificationCenter.default.removeObserver(token) }; observers = [] }

    private func runFixture(id: UUID) async {
        #if DEBUG && targetEnvironment(simulator)
        if fixtureStarts > 0, ProcessInfo.processInfo.arguments.contains("-voice-fixture-fail-restart") {
            finish(id: id, message: VoiceCaptureError.setup.localizedDescription); work = nil; return
        }
        fixtureStarts += 1
        recordingBegan(id: id)
        do {
            try await Task.sleep(for: .milliseconds(350))
            guard identity == id else { return }
            _ = transcript.receive(start: 0, duration: 2, text: "I drank 300 ml", final: false); liveText = transcript.text
            while identity == id, phase == .recording { try await Task.sleep(for: .milliseconds(100)) }
            guard identity == id, !Task.isCancelled else { return }
            _ = transcript.receive(start: 0, duration: 2, text: "I drank 350 ml of water.\n", final: true); liveText = transcript.text
            finish(id: id); work = nil
        } catch { if identity == id { finish(id: id); work = nil } }
        #endif
    }
}
