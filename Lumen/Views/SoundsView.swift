import SwiftUI

// MARK: - Sleep sounds (generated on-device, with a fade-out timer)

public struct SoundsView: View {
    @StateObject private var engine = SoundEngine.shared
    public init() {}

    var current: SoundTrack? { SoundTrack.all.first { $0.id == engine.playingId && engine.isPlaying } }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Steady sound masks noise and helps your mind settle. Pick one and set a timer — it fades out gently.")
                    .font(.body).foregroundStyle(Theme.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(SoundTrack.all) { t in
                        let playing = engine.playingId == t.id && engine.isPlaying
                        Button { engine.toggle(t); haptic() } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    Image(systemName: t.icon).font(.title3).foregroundStyle(playing ? .black : Theme.calm)
                                    Spacer()
                                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.footnote).foregroundStyle(playing ? .black : Theme.tertiary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(.headline).foregroundStyle(playing ? .black : Theme.text)
                                    Text(t.subtitle).font(.footnote).foregroundStyle(playing ? .black.opacity(0.6) : Theme.secondary).lineLimit(1)
                                }
                            }
                            .padding(16)
                            .background(playing ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if current != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupLabel("Sleep timer")
                        HStack(spacing: 10) {
                            ForEach([15, 30, 60], id: \.self) { m in
                                Button("\(m) min") { engine.startSleepTimer(minutes: m); haptic(.light) }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(engine.sleepTimerMinutes == m ? Color.white : Theme.surfaceRaised, in: Capsule())
                                    .foregroundStyle(engine.sleepTimerMinutes == m ? .black : .white)
                            }
                            Button { engine.stop() } label: { Image(systemName: "stop.fill") }
                                .frame(width: 44, height: 44).background(Theme.surfaceRaised, in: Circle()).foregroundStyle(.white)
                                .accessibilityLabel("Stop")
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 40)
        }
        .lumenScreen(Theme.calm)
        .navigationTitle("Sleep sounds")
    }
}
