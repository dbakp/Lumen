import SwiftUI

// MARK: - Sleep history: every night, editable

public struct SleepLogView: View {
    @EnvironmentObject var store: SleepStore
    @State private var editing: SleepEpisode?

    public init() {}

    var byMonth: [(month: Date, nights: [SleepEpisode])] {
        let cal = Calendar.current
        let g = Dictionary(grouping: store.episodes) { cal.date(from: cal.dateComponents([.year, .month], from: $0.wakeTime)) ?? $0.wakeTime }
        return g.map { ($0.key, $0.value.sorted { $0.wakeTime > $1.wakeTime }) }.sorted { $0.month > $1.month }
    }

    public var body: some View {
        List {
            if store.episodes.count >= 3 {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            stat(SleepFormat.durationHM(store.avg7), "7-night average")
                            Spacer()
                            stat("±\(Int(store.consistency / 60)) min", "Wake-time consistency")
                        }
                        DebtHistoryChart(need: store.profile.sleepNeed, episodes: store.episodes).frame(height: 140)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Theme.surface)
                }
            }
            if store.episodes.isEmpty {
                ContentUnavailableView("No nights yet", systemImage: "moon.zzz", description: Text("Nights from Apple Health appear here automatically. Tap + to add one."))
                    .listRowBackground(Color.clear)
            }
            ForEach(byMonth, id: \.month) { group in
                Section(group.month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(group.nights) { ep in
                        Button { editing = ep } label: { row(ep) }
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                Button("Delete", role: .destructive) { store.deleteEpisode(ep) }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AuroraBackground(Theme.sleep))
        .navigationTitle("Sleep history")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { AppRouter.shared.show(.sleepLog) } label: { Image(systemName: "plus") }.accessibilityLabel("Add a night")
            }
        }
        .sheet(item: $editing) { ep in EditSleepSheet(episode: ep) }
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Theme.text)
            Text(l).font(.footnote).foregroundStyle(Theme.secondary)
        }
    }

    func row(_ ep: SleepEpisode) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ep.wakeTime.formatted(.dateTime.weekday(.wide).day().month())).font(.body).foregroundStyle(Theme.text)
                Text("\(SleepFormat.time(ep.bedtime)) – \(SleepFormat.time(ep.wakeTime))\(ep.source == .manual ? " · added by you" : "")")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(SleepFormat.durationHM(ep.duration)).font(.body.monospacedDigit())
                .foregroundStyle(ep.duration >= store.profile.sleepNeed - 1800 ? Theme.text : Theme.food)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add / edit a night

public struct LogSleepSheet: View {
    @EnvironmentObject var store: SleepStore
    @Environment(\.dismiss) var dismiss
    @State private var bedtime = Date()
    @State private var wake = Date()
    @State private var didSetDefaults = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                let dur = max(0, wake.timeIntervalSince(bedtime))
                VStack(alignment: .leading, spacing: 4) {
                    Text(SleepFormat.durationHM(dur)).font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.text)
                    Text(impact(dur)).font(.subheadline).foregroundStyle(Theme.secondary)
                }
                VStack(spacing: 0) {
                    DatePicker("Went to bed", selection: $bedtime, displayedComponents: [.date, .hourAndMinute]).padding(.vertical, 10)
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    DatePicker("Woke up", selection: $wake, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).padding(.vertical, 10)
                }
                .padding(.horizontal, 16).surface()
                Spacer()
                Button("Save night") {
                    store.logEpisode(bedtime: bedtime, wakeTime: wake)
                    dismiss()
                    AppRouter.shared.confirm("Night saved")
                }
                .buttonStyle(LumenPrimaryButtonStyle())
                .disabled(wake <= bedtime)
            }
            .padding(Theme.gutter)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add a night").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                // Default to "last night": wake at your goal this morning (or now, if earlier).
                guard !didSetDefaults else { return }
                didSetDefaults = true
                wake = min(store.wakeGoalToday, Date())
                bedtime = wake.addingTimeInterval(-store.profile.sleepNeed - 15 * 60)
            }
        }
        .presentationDetents([.medium, .large])
        .tint(.white)
    }

    func impact(_ dur: TimeInterval) -> String {
        let need = store.profile.sleepNeed
        if dur >= need { return "Enough to cover your need" }
        if dur >= need - 3600 { return "Close to your need" }
        return "About \(SleepFormat.durationHM(need - dur)) less than you need"
    }
}

public struct EditSleepSheet: View {
    @EnvironmentObject var store: SleepStore
    @Environment(\.dismiss) var dismiss
    @State var episode: SleepEpisode

    public init(episode: SleepEpisode) { _episode = State(initialValue: episode) }
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 0) {
                    DatePicker("Went to bed", selection: $episode.bedtime, displayedComponents: [.date, .hourAndMinute]).padding(.vertical, 10)
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    DatePicker("Woke up", selection: $episode.wakeTime, displayedComponents: [.date, .hourAndMinute]).padding(.vertical, 10)
                }
                .padding(.horizontal, 16).surface()
                Button("Delete night", role: .destructive) { store.deleteEpisode(episode); dismiss() }
                    .foregroundStyle(Theme.move)
                Spacer()
                Button("Save changes") {
                    episode.asleepSeconds = nil // times were edited by hand
                    store.updateEpisode(episode); dismiss()
                }
                .buttonStyle(LumenPrimaryButtonStyle())
            }
            .padding(Theme.gutter)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Edit night").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .tint(.white)
    }
}

struct StatChip: View {
    let title: String; let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            Text(title.capitalized).font(.caption).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10).surface(14)
    }
}
