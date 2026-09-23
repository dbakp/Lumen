import SwiftUI

// MARK: - Habits / Rituals (16 timed nudges)

public struct HabitsView: View {
    @EnvironmentObject var store: SleepStore

    public init() {}

    func fireTime(for h: SleepHabit) -> Date {
        guard let pred = store.prediction else { return Date() }
        switch h.anchor {
        case .wakePlus:
            return pred.wakeZone.lowerBound.addingTimeInterval(h.offset)
        case .bedtimeMinus:
            return store.suggestedBedtime.addingTimeInterval(-h.offset)
        case .fixedClock:
            return pred.wakeZone.lowerBound.addingTimeInterval(h.offset)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader("Today's rituals", subtitle: "Timed to your melatonin window", systemImage: "checklist")
                        Text("\(store.habits.filter { $0.isEnabled && $0.doneToday }.count) of \(store.habits.filter(\.isEnabled).count) complete — consistency compounds.")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                        ProgressView(value: Double(store.habits.filter { $0.isEnabled && $0.doneToday }.count), total: Double(max(1, store.habits.filter(\.isEnabled).count)))
                            .tint(.cyan)
                    }
                }
                ForEach(store.habits) { h in
                    GlassCard {
                        HStack(spacing: 12) {
                            Button {
                                store.toggleHabitDone(h.id); haptic(.light)
                            } label: {
                                Image(systemName: h.doneToday ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(h.doneToday ? .green : .white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .disabled(!h.isEnabled)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.title).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(h.isEnabled ? .white : .white.opacity(0.45))
                                    .strikethrough(h.doneToday)
                                Text(h.detail).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                                Text("~\(SleepFormat.time(fireTime(for: h)))").font(.caption2.weight(.bold)).foregroundStyle(.cyan.opacity(0.9))
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { h.isEnabled },
                                set: { store.setHabitEnabled(h.id, enabled: $0) }
                            ))
                            .labelsHidden().tint(.cyan)
                        }
                    }
                    .opacity(h.isEnabled ? 1 : 0.6)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .navigationTitle("Habits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
