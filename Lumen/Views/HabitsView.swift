import SwiftUI

// MARK: - Daily habits, timed to your body clock

public struct HabitsView: View {
    @EnvironmentObject var store: SleepStore
    public init() {}

    func time(for h: SleepHabit) -> Date? {
        guard let pred = store.prediction else { return nil }
        switch h.anchor {
        case .wakePlus, .fixedClock: return pred.wakeZone.lowerBound.addingTimeInterval(h.offset)
        case .bedtimeMinus: return store.suggestedBedtime.addingTimeInterval(-h.offset)
        }
    }

    var active: [SleepHabit] { store.habits.filter(\.isEnabled).sorted { (time(for: $0) ?? .distantFuture) < (time(for: $1) ?? .distantFuture) } }
    var inactive: [SleepHabit] { store.habits.filter { !$0.isEnabled } }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                let done = active.filter(\.doneToday).count
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(done) of \(active.count) done today").font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                    Bar(Double(done) / Double(max(1, active.count)), color: Theme.steps, height: 6)
                    Text("Small, well-timed habits add up to better sleep. Reminders follow these times.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                RowGroup {
                    ForEach(Array(active.enumerated()), id: \.element.id) { i, h in
                        if i > 0 { RowDivider() }
                        habitRow(h)
                    }
                }
                if !inactive.isEmpty {
                    GroupLabel("More habits")
                    RowGroup {
                        ForEach(Array(inactive.enumerated()), id: \.element.id) { i, h in
                            if i > 0 { RowDivider() }
                            habitRow(h)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 40)
        }
        .lumenScreen(Theme.steps)
        .navigationTitle("Daily habits")
    }

    func habitRow(_ h: SleepHabit) -> some View {
        HStack(spacing: 14) {
            Button {
                store.toggleHabitDone(h.id); haptic(.light)
            } label: {
                Image(systemName: h.doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(h.doneToday ? Theme.steps : Theme.tertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!h.isEnabled)
            .accessibilityLabel(h.doneToday ? "Mark \(h.title) not done" : "Mark \(h.title) done")
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title).font(.body).foregroundStyle(h.isEnabled ? Theme.text : Theme.secondary)
                Text(h.detail).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if h.isEnabled, let t = time(for: h) {
                Text(SleepFormat.time(t)).font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            Toggle("", isOn: Binding(get: { h.isEnabled }, set: { store.setHabitEnabled(h.id, enabled: $0); NotificationManager.shared.reschedule(from: store) }))
                .labelsHidden().tint(Theme.steps).scaleEffect(0.85)
        }
        .padding(.vertical, 10)
    }
}
