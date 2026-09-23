import SwiftUI

// MARK: - Sleep journal: history, stats, log/edit

public struct SleepLogView: View {
    @EnvironmentObject var store: SleepStore
    @State private var showAdd = false
    @State private var editing: SleepEpisode?
    @State private var showAll = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("14-night picture", subtitle: "Need \(SleepFormat.durationHM(store.profile.sleepNeed)) · Avg 7n \(SleepFormat.durationHM(store.avg7))", systemImage: "chart.bar.fill")
                        DebtHistoryChart(need: store.profile.sleepNeed, episodes: store.episodes)
                        HStack {
                            StatChip(title: "Avg", value: SleepFormat.durationHM(store.avg7))
                            StatChip(title: "Debt", value: SleepFormat.debtString(store.debt))
                            StatChip(title: "Wake ±", value: "±\(Int(store.consistency/60))m")
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            SectionHeader("Nights", subtitle: "\(store.episodes.count) tracked", systemImage: "moon.fill")
                            Spacer()
                            Button { showAdd = true } label: {
                                Image(systemName: "plus").font(.headline.weight(.bold))
                                    .frame(width: 34, height: 34).liquidGlass(cornerRadius: 12)
                                    .foregroundStyle(.white)
                            }
                        }
                        if store.episodes.isEmpty {
                            Text("No nights yet. Tap + to log one, or connect Apple Health in Settings.")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.6)).padding(.vertical, 8)
                        }
                        ForEach(store.episodes.suffix(showAll ? 400 : 14).reversed()) { ep in
                            Button { editing = ep } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dateTitle(ep.wakeTime)).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        Text("\(SleepFormat.time(ep.bedtime)) → \(SleepFormat.time(ep.wakeTime)) · \(ep.source.label)")
                                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                                    }
                                    Spacer()
                                    Text(SleepFormat.durationHM(ep.duration))
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(ep.duration >= store.profile.sleepNeed - 30*60 ? .green : .orange)
                                }
                                .padding(.vertical, 7)
                                if ep.hasStages { SleepStagesBar(episode: ep).padding(.bottom, 6) }
                                Divider().background(.white.opacity(0.08))
                            }
                            .buttonStyle(.plain)
                        }
                        if store.episodes.count > 14 {
                            Button(showAll ? "Show recent" : "Show all \(store.episodes.count) nights") { withAnimation { showAll.toggle() } }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.cyan).padding(.top, 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .navigationTitle("Sleep journal")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) { LogSleepSheet() }
        .sheet(item: $editing) { ep in EditSleepSheet(episode: ep) }
    }

    func dateTitle(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Last night" }
        if Calendar.current.isDateInYesterday(d) { return "Night before" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }
}

struct StatChip: View {
    let title: String; let value: String
    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(0.8)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 14, tintOpacity: 0.1)
    }
}

// MARK: - Log / Edit sheets

public struct LogSleepSheet: View {
    @EnvironmentObject var store: SleepStore
    @Environment(\.dismiss) var dismiss
    @State private var bedtime: Date = Date()
    @State private var wake: Date = Date()
    @State private var didSetDefaults = false

    public init() {}
    public var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                VStack(spacing: 16) {
                    GlassCard {
                        VStack(spacing: 12) {
                            DatePicker("Bedtime", selection: $bedtime, displayedComponents: [.date, .hourAndMinute])
                            Divider().background(.white.opacity(0.12))
                            DatePicker("Wake time", selection: $wake, displayedComponents: [.date, .hourAndMinute])
                        }.colorScheme(.dark)
                    }
                    let dur = max(0, wake.timeIntervalSince(bedtime))
                    Text("That is \(SleepFormat.durationHM(dur)) — \(impact(dur))")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                    Button {
                        store.logEpisode(bedtime: bedtime, wakeTime: wake)
                        haptic()
                        dismiss()
                    } label: {
                        Text("Save night").font(.headline.weight(.bold)).frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    .disabled(wake <= bedtime)
                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("Log sleep").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Default to "last night": wake at your goal this morning (or now, if earlier),
                // bedtime one sleep-need before that.
                guard !didSetDefaults else { return }
                didSetDefaults = true
                let goal = store.wakeGoalToday
                wake = min(goal, Date())
                bedtime = wake.addingTimeInterval(-store.profile.sleepNeed - 15 * 60)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    func impact(_ dur: TimeInterval) -> String {
        let need = store.profile.sleepNeed
        if dur >= need { return "repays debt" }
        if dur >= need - 3600 { return "near your need" }
        return "adds ~\(SleepFormat.hours(need - dur)) to debt"
    }
}

public struct EditSleepSheet: View {
    @EnvironmentObject var store: SleepStore
    @Environment(\.dismiss) var dismiss
    @State var episode: SleepEpisode

    public init(episode: SleepEpisode) { _episode = State(initialValue: episode) }
    public var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                VStack(spacing: 16) {
                    GlassCard {
                        VStack(spacing: 12) {
                            DatePicker("Bedtime", selection: $episode.bedtime, displayedComponents: [.date, .hourAndMinute])
                            Divider().background(.white.opacity(0.12))
                            DatePicker("Wake time", selection: $episode.wakeTime, displayedComponents: [.date, .hourAndMinute])
                        }.colorScheme(.dark)
                    }
                    Button {
                        store.updateEpisode(episode); haptic(); dismiss()
                    } label: {
                        Text("Save changes").font(.headline.weight(.bold)).frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    Button(role: .destructive) {
                        store.deleteEpisode(episode); dismiss()
                    } label: {
                        Text("Delete night").frame(maxWidth: .infinity)
                    }
                    Spacer()
                }.padding(18)
            }
            .navigationTitle("Edit night").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
