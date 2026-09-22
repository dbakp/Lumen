import SwiftUI

// MARK: - Sleep sounds (procedural engine + timer)

public struct SoundsView: View {
    @StateObject private var engine = SoundEngine.shared
    @State private var showTimer = false

    public init() {}

    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Fall asleep faster", subtitle: "Procedural audio — no downloads", systemImage: "speaker.wave.2.fill")
                        Text("Mask noise, cue your wind-down. Sound fades with an optional sleep timer.")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SoundTrack.all) { t in
                        SoundCard(track: t, isPlaying: engine.playingId == t.id && engine.isPlaying) {
                            engine.toggle(t); haptic()
                        }
                    }
                }
                // Now playing bar
                if let current = SoundTrack.all.first(where: { $0.id == engine.playingId }), engine.isPlaying {
                    GlassCard {
                        HStack {
                            Image(systemName: current.icon).foregroundStyle(.cyan)
                            VStack(alignment: .leading) {
                                Text(current.title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                Text(engine.sleepTimerMinutes > 0 ? "Timer \(engine.sleepTimerMinutes)m" : "Playing").font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Button("Timer") { showTimer = true }.font(.caption.weight(.bold)).tint(.cyan).buttonStyle(.bordered)
                            Button { engine.stop() } label: { Image(systemName: "stop.fill") }.tint(.pink).buttonStyle(.bordered)
                        }
                    }
                    .confirmationDialog("Sleep timer", isPresented: $showTimer, titleVisibility: .visible) {
                        Button("15 min") { engine.startSleepTimer(minutes: 15) }
                        Button("30 min") { engine.startSleepTimer(minutes: 30) }
                        Button("60 min") { engine.startSleepTimer(minutes: 60) }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .navigationTitle("Sounds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SoundCard: View {
    let track: SoundTrack
    let isPlaying: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: track.icon).font(.title2)
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                    Spacer()
                    if isPlaying {
                        Image(systemName: "waveform").foregroundStyle(.cyan)
                            .symbolEffect(.variableColor.iterative)
                    }
                }
                Text(track.title).font(.headline).foregroundStyle(.white)
                Text(track.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                HStack {
                    Text(isPlaying ? "Pause" : "Play").font(.caption.weight(.bold))
                    Spacer()
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title3)
                }
                .foregroundStyle(.cyan)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(hex: track.gradient[0]), Color(hex: track.gradient[1])], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(isPlaying ? 0.5 : 0.15), lineWidth: isPlaying ? 1.5 : 0.8))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }
}
