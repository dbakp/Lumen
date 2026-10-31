import SwiftUI
import UIKit
import AVFoundation

struct VoiceDraftSheet: View {
    let target: VoiceDraftTarget
    let use: (String) throws -> Void
    var body: some View {
        if #available(iOS 26, *) { VoiceDraftView(target: target, use: use) }
        else { VoiceVersionView() }
    }
}

private struct VoiceVersionView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form { Text("Voice drafts need iOS 26 or later. You can still type a message or use your keyboard's dictation.").foregroundStyle(Theme.secondary) }
                .scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Voice draft")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

@available(iOS 26, *)
private struct VoiceDraftView: View {
    let target: VoiceDraftTarget
    let use: (String) throws -> Void
    @StateObject private var voice = VoiceDraftController.shared
    @State private var discarding = false
    @State private var restarting = false
    @State private var error: String?
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing = false
    private var capturing: Bool { voice.phase == .recording || voice.phase == .finishing }
    private var canUse: Bool { voice.validText && voice.checked }
    private var duration: String { let seconds = max(0, min(180, Int(voice.elapsed))); return String(format: "%d:%02d", seconds / 60, seconds % 60) }

    var body: some View {
        NavigationStack {
            Form {
                header
                if capturing { liveSection }
                else if voice.phase == .reviewing { reviewSection }
                else { setupSection }
                if let notice = voice.notice { Section { Text(notice).foregroundStyle(Theme.secondary).accessibilityIdentifier("voiceNotice") } }
                if voice.soundsPaused { Section { Text("Lumen sleep sounds are paused. You can resume them from Sounds; the existing sleep timer keeps running.").foregroundStyle(Theme.secondary) } }
                if !capturing { Section { Text("Audio and unused voice text aren't saved by Lumen. Recording stops after three minutes or when you leave Lumen.").font(.footnote).foregroundStyle(Theme.secondary) } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Voice draft").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { attemptClose() }.accessibilityIdentifier("cancelVoice") }
            }
            .safeAreaInset(edge: .bottom) { bottomControls }
            .sheet(isPresented: $editing) { VoiceTextEditorSheet(text: voice.text) { voice.text = $0 } }
            .alert("Discard this voice draft?", isPresented: $discarding) {
                Button("Discard draft", role: .destructive) { voice.close(); dismiss() }
                Button("Keep reviewing", role: .cancel) {}
            } message: { Text("This temporary voice text won't be saved.") }
            .alert("Record again?", isPresented: $restarting) {
                Button("Replace voice draft", role: .destructive) { copied = false; voice.start() }
                Button("Keep reviewing", role: .cancel) {}
            } message: { Text("New speech will replace this voice text. Your existing message draft stays in place.") }
            .alert("Couldn't add voice text", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) { error = nil } } message: { Text(error ?? "") }
            .interactiveDismissDisabled(voice.hasText || voice.busy)
            .onAppear { voice.open() }.onDisappear { voice.close() }
            .onChange(of: scenePhase) { _, value in if value != .active { voice.leftForeground(background: value == .background) } }
            .onChange(of: voice.text) { _, _ in copied = false }
        }.tint(Theme.accent)
    }
    private var header: some View {
        Section {
            Text(voice.phase == .reviewing ? "Check your\nwords." : capturing ? "Your words,\nas you speak." : "Speak a\nmessage.").font(.largeTitle.bold()).fontWidth(.expanded)
            Text(voice.phase == .reviewing ? "Check names, numbers and units before adding the text to your message." : "Speech is transcribed on this iPhone. Your chosen assistant receives the message only when you send it.").foregroundStyle(Theme.secondary)
        }.listRowBackground(Color.clear)
    }
    private var liveSection: some View {
        Section {
            Text("Live text").font(.headline)
            Text(voice.liveText.isEmpty ? "Speak when you're ready." : String(voice.liveText.suffix(1200)))
                .foregroundStyle(voice.liveText.isEmpty ? Theme.secondary : Theme.text).accessibilityIdentifier("voiceLiveText")
        } footer: { Text("The latest words appear here. Review the complete text after stopping.").foregroundStyle(Theme.secondary) }
    }
    private var reviewSection: some View {
        Section {
            Text("Voice text").font(.headline)
            Text(verbatim: voice.text).font(.body).textSelection(.enabled).accessibilityIdentifier("voiceReviewText")
            reviewAction("Edit text", icon: "pencil") { editing = true }.accessibilityIdentifier("editVoiceText")
            if !VoiceTranscript.accepts(voice.text) { Text("Shorten this text to 8,000 characters and 32 KB before using it.").foregroundStyle(Theme.destructive) }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    Text("I checked names, numbers and units")
                    Toggle("I checked names, numbers and units", isOn: $voice.checked).labelsHidden().accessibilityIdentifier("voiceChecked")
                }
            } else { Toggle("I checked names, numbers and units", isOn: $voice.checked).accessibilityIdentifier("voiceChecked") }
            reviewAction("Copy text", icon: "doc.on.doc") { UIPasteboard.general.string = voice.text; copied = true }.disabled(!voice.validText).accessibilityIdentifier("copyVoiceText")
            reviewAction("Record again", icon: "mic") { editing = false; restarting = true }.accessibilityIdentifier("recordVoiceAgain")
            if copied { Text("Copied").foregroundStyle(Theme.secondary) }
        } footer: { Text("Use text adds to your unsent draft. It doesn't send a message or save a health entry.").foregroundStyle(Theme.secondary) }
    }
    private func reviewAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if typeSize.isAccessibilitySize { Text(title).frame(maxWidth: .infinity, alignment: .leading) }
            else { Label(title, systemImage: icon) }
        }
    }
    private var setupSection: some View {
        Section {
            if !voice.languages.isEmpty {
                Picker("Speech language", selection: Binding(get: { voice.languageID }, set: { voice.open(language: $0) })) {
                    if voice.languageID.isEmpty { Text("Choose a language").tag("") }
                    ForEach(voice.languages) { language in Text(language.name).tag(language.id) }
                }.disabled(voice.busy).accessibilityIdentifier("voiceLanguage")
            }
            availability
        }
    }
    @ViewBuilder private var availability: some View {
        switch voice.phase {
        case .checking: HStack { ProgressView(); Text("Checking on-device speech").foregroundStyle(Theme.secondary) }
        case .needsDownload:
            Text("This language needs a download.").font(.headline)
            Text("iOS manages the shared speech language and its storage. Downloading uses a network connection; your audio stays on this device.").foregroundStyle(Theme.secondary)
            Button("Download language", systemImage: "arrow.down.circle") { voice.download() }.accessibilityIdentifier("downloadVoiceLanguage")
        case .downloading: downloadState
        case .authorizing: HStack { ProgressView(); Text("Preparing microphone").foregroundStyle(Theme.secondary) }
        case .ready:
            Label("On-device speech is ready", systemImage: "iphone").foregroundStyle(Theme.secondary)
            Button("Start recording", systemImage: "mic.fill") { voice.start() }.fontWeight(.semibold).accessibilityIdentifier("startVoice")
        case .unavailable:
            Label("Voice input unavailable", systemImage: "mic.slash").font(.headline).accessibilityIdentifier("voiceUnavailable")
            Button("Check again", systemImage: "arrow.clockwise") { voice.open(language: voice.languageID.isEmpty ? nil : voice.languageID) }.accessibilityIdentifier("retryVoiceAvailability")
            if AVAudioApplication.shared.recordPermission == .denied {
                Button("Open Settings", systemImage: "gearshape") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
        default: EmptyView()
        }
    }
    private var downloadState: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            VStack(alignment: .leading, spacing: 10) {
                Text("Preparing speech language").font(.headline)
                if let progress = voice.downloadProgress, progress.totalUnitCount > 0 { ProgressView(value: progress.fractionCompleted) }
                else { ProgressView() }
                Text("You can close this screen. iOS may finish a shared language download.").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }
    @ViewBuilder private var bottomControls: some View {
        if capturing || voice.phase == .reviewing || voice.fixture {
            VStack(alignment: .leading, spacing: 10) {
                #if DEBUG && targetEnvironment(simulator)
                if voice.fixture { Text("Simulated speech. No microphone.").font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("voiceFixture") }
                #endif
                if capturing {
                    Text((voice.phase == .recording ? "Recording · " : "Finishing transcription · ") + duration).font(.headline.monospacedDigit()).foregroundStyle(Theme.secondary).accessibilityIdentifier("voiceRecordingState")
                    if voice.phase == .recording { primary("Stop recording", enabled: true, id: "stopVoice") { voice.stop() } }
                    else { ProgressView().accessibilityLabel("Finishing the captured speech") }
                } else if voice.phase == .reviewing {
                    primary("Use text", enabled: canUse, id: "useVoiceText") {
                        do { try use(voice.text); voice.close(); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }.padding(.horizontal, Theme.gutter).padding(.vertical, 10).background(.regularMaterial).accessibilityElement(children: .contain).accessibilityIdentifier("voiceControls")
        }
    }
    private func primary(_ title: String, enabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(.headline).foregroundStyle(enabled ? Theme.onAccent : Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: 56).background(enabled ? Theme.accent : Theme.surfaceRaised, in: Capsule())
            .disabled(!enabled).accessibilityIdentifier(id)
    }
    private func attemptClose() {
        editing = false
        if voice.phase == .recording { voice.stop() }
        if voice.hasText || voice.phase == .finishing { discarding = true }
        else { voice.close(); dismiss() }
    }
}


private struct VoiceTextEditorSheet: View {
    let original: String
    let save: (String) -> Void
    @State private var text: String
    @State private var discarding = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    init(text: String, save: @escaping (String) -> Void) {
        original = text; self.save = save; _text = State(initialValue: text)
    }
    private var valid: Bool { VoiceTranscript.accepts(text) && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text).focused($focused).scrollContentBackground(.hidden).font(.body).foregroundStyle(Theme.text).autocorrectionDisabled()
                    .accessibilityIdentifier("voiceDraftText")
                if !valid { Text("Use 1–8,000 characters and at most 32 KB.").font(.footnote).foregroundStyle(Theme.secondary) }
            }.padding(Theme.gutter).background(Theme.bg)
                .navigationTitle("Edit voice text").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if text != original { discarding = true } else { dismiss() } }.accessibilityIdentifier("cancelVoiceEdit") }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { save(text); dismiss() }.disabled(!valid).accessibilityIdentifier("saveVoiceEdit") }
                }
                .alert("Discard your text changes?", isPresented: $discarding) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) {}
                } message: { Text("Your earlier voice text will stay in place.") }
                .interactiveDismissDisabled(text != original)
                .task { focused = true }
        }.tint(Theme.accent)
    }
}
