import SwiftUI
import Charts

struct LabHistoryView: View {
    @ObservedObject private var companion = CompanionStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: LabHistory.Selection?
    @State private var recordIDs: [String] = []
    @State private var choosingRecords = false
    @State private var personChecked = false
    @State private var groupID: String?
    @State private var groupQuery = ""
    @State private var groupPage = 0
    @State private var resultPage = 0
    @State private var style: LabHistory.DecimalStyle?
    @State private var pair: [String] = []
    @State private var detail: LabHistory.Point?
    @State private var comparison: LabHistoryComparisonDraft?
    @State private var limitDates = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var selectedPlotDay: Date?
    @State private var onlyDay: String?
    @State private var status: String?
    @State private var refreshing = false
    @State private var refreshControl: BackupOperationControl?
    @State private var refreshJob: Task<Void, Never>?
    @State private var generation = UUID()
    private let pageSize = 20
    private let utc = TimeZone(secondsFromGMT: 0)!
    private var picking: Bool { selection == nil || choosingRecords }
    private var group: LabHistory.Group? { selection?.groups.first { $0.id == groupID } }
    var body: some View {
        Group {
            if picking {
                LabHistoryRecordPicker(selected: recordIDs, notice: status, onCancel: selection == nil ? nil : { choosingRecords = false }) { result in
                    selection = result; recordIDs = result.records.map(\.id); personChecked = true; choosingRecords = false; groupID = nil; groupQuery = ""; groupPage = 0; pair = []; style = nil; status = nil
                }
            } else if refreshing { checking }
            else if let selection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let status { Text(status).foregroundStyle(Theme.secondary).accessibilityIdentifier("labHistorySourceStatus") }
                        if let group { series(group, selection: selection) }
                        else { groups(selection) }
                    }.padding(Theme.gutter).padding(.bottom, 24)
                }.lumenScreen()
            }
        }.navigationTitle("Lab history").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !picking { ToolbarItem(placement: .topBarTrailing) { Button("Choose records") { choosingRecords = true }.accessibilityIdentifier("historyChooseRecords") } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !picking && !refreshing && !pair.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if pair.count == 1 { Text("1 of 2 selected").font(.headline).accessibilityIdentifier("historyComparisonSelectionState") }
                        Button("Clear selected results") { pair = [] }.frame(minHeight: 44).foregroundStyle(Theme.accent).accessibilityIdentifier("historyClearComparedResults")
                        if pair.count == 2 { Button("Compare 2 results") { openComparison() }.buttonStyle(LumenPrimaryButtonStyle()).disabled(!personChecked).accessibilityIdentifier("compareLabHistoryResults") }
                    }.padding(.horizontal, Theme.gutter).padding(.vertical, 8).background(.bar)
                }
            }
            .sheet(item: $detail) { point in NavigationStack { ScrollView { LabCapturedResultView(point: point, label: "Captured result", expandedSource: true).padding(Theme.gutter) }.lumenScreen().navigationTitle("Reported result").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } } } }
            .sheet(item: $comparison) { LabComparisonReviewSheet(draft: $0) }
            .onReceive(companion.$documents.dropFirst()) { documents in if selection != nil && !choosingRecords { refresh(documents) } }
            .onAppear { if selection != nil && !choosingRecords { refresh(companion.documents) } }
            .onDisappear { generation = UUID(); refreshControl?.cancel(); refreshJob?.cancel(); refreshing = false }
            .onChange(of: groupQuery) { _, _ in groupPage = 0 }
            .onChange(of: style) { _, _ in selectedPlotDay = nil }
            .onChange(of: limitDates) { _, _ in selectedPlotDay = nil }
            .onChange(of: start) { _, _ in selectedPlotDay = nil }
            .onChange(of: end) { _, _ in selectedPlotDay = nil }
    }
    private var checking: some View {
        VStack(alignment: .leading, spacing: 24) { LabHistoryHeading(text: "Checking\nsaved sources."); ProgressView("Refreshing local history"); Spacer() }.padding(Theme.gutter).lumenScreen()
    }
    @ViewBuilder private func groups(_ selection: LabHistory.Selection) -> some View {
        LabHistoryHeading(text: "Results, with\ntheir sources.")
        Text("\(selection.records.count) selected \(selection.records.count == 1 ? "record" : "records") · \(selection.points.count.formatted()) saved \(selection.points.count == 1 ? "result" : "results")").foregroundStyle(Theme.secondary).accessibilityIdentifier("labHistoryPreparedCount")
        sources(selection)
        if !personChecked { Button("Check the intended person") { choosingRecords = true }.buttonStyle(LumenTonalButtonStyle()) }
        Text("Choose a test and recorded context.").font(.headline)
        TextField("Find a test name", text: $groupQuery).textFieldStyle(.roundedBorder).accessibilityIdentifier("labHistoryTestSearch")
        let filtered = selection.groups.filter { groupQuery.isEmpty || $0.exemplar.test.localizedCaseInsensitiveContains(groupQuery) }
        let page = min(groupPage, max(0, (filtered.count - 1) / pageSize))
        if filtered.isEmpty { Text("No matching test names.") }
        ForEach(Array(filtered.dropFirst(page * pageSize).prefix(pageSize))) { item in
            VStack(alignment: .leading, spacing: 12) {
                Button { choose(item) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.exemplar.test).font(.headline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        Text(item.exemplar.unit.isEmpty ? "Unit not recorded" : item.exemplar.unit).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(item.exemplar.laboratory.isEmpty ? "Laboratory not recorded" : item.exemplar.laboratory).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("\(item.points.count.formatted()) \(item.points.count == 1 ? "result" : "results") · View history").font(.subheadline).foregroundStyle(Theme.accent)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("history-group-" + item.id)
                DisclosureGroup("Recorded context") { LabHistoryContext(observation: item.exemplar) }
                Divider()
            }
        }
        LabHistoryPager(page: page, count: filtered.count, size: pageSize) { groupPage = $0 }
    }
    private func sources(_ selection: LabHistory.Selection) -> some View {
        DisclosureGroup("Chosen records and person labels") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(selection.records) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.title.isEmpty ? "Untitled record" : record.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text(record.personLabel).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        NavigationLink("Open record") { DocumentDetailView(documentID: record.id) }.frame(minHeight: 44).foregroundStyle(Theme.accent)
                    }
                }
            }.padding(.top, 12)
        }
    }
    @ViewBuilder private func series(_ group: LabHistory.Group, selection: LabHistory.Selection) -> some View {
        Button { groupID = nil; onlyDay = nil } label: { Label("All tests", systemImage: "chevron.left").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityIdentifier("historyAllTests")
        LabHistoryHeading(text: group.exemplar.test)
        Text(group.exemplar.unit.isEmpty ? "Unit not recorded" : "Reported unit: " + group.exemplar.unit).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        Text(group.exemplar.laboratory.isEmpty ? "Laboratory not recorded" : group.exemplar.laboratory).font(.headline).fixedSize(horizontal: false, vertical: true)
        DisclosureGroup("Recorded context") { LabHistoryContext(observation: group.exemplar) }
        LabNumberStylePicker(style: $style)
        Text("Choose the decimal mark used in these reports, or keep wording only. Use wording only for numbers with thousands separators.").font(.footnote).foregroundStyle(Theme.secondary)
        if style == .dot || style == .comma { dateControls(group) }
        let plot = plot(group)
        ForEach(Array(plot.blockers.enumerated()), id: \.offset) { _, blocker in Text(blocker.message).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
        if !plot.points.isEmpty { numericPlot(plot) }
        else if plot.blockers.isEmpty { Text("No numeric points in this window. Reported wording remains in the history below.").foregroundStyle(Theme.secondary) }
        if style == .dot || style == .comma { Text("\(plot.points.count.formatted()) of \(plot.numericDatedCount.formatted()) numeric \(plot.numericDatedCount == 1 ? "result" : "results") with collection days plotted. \(plot.omitted.count.formatted()) other \(plot.omitted.count == 1 ? "result is" : "results are") kept as wording or without a date.").font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("labHistoryPlotCoverage") }
        ForEach(plot.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
        Text("Matching recorded labels do not establish clinical comparability. Use each original report's reference wording.").font(.footnote).foregroundStyle(Theme.secondary)
        Divider()
        Text("Reported history").font(.title2.bold())
        Text("Select 2 results to compare. Missing collection days stay unknown.").foregroundStyle(Theme.secondary).accessibilityIdentifier("historySelectionGuidance")
        if let onlyDay { Text("Showing collection day " + onlyDay).font(.headline); Button("Show all results") { self.onlyDay = nil; resultPage = 0 }.frame(minHeight: 44) }
        let rows = group.points.filter { onlyDay == nil || $0.collectionDay == onlyDay }
        let page = min(resultPage, max(0, (rows.count - 1) / pageSize))
        ForEach(Array(rows.dropFirst(page * pageSize).prefix(pageSize))) { point in resultRow(point, plot: plot) }
        LabHistoryPager(page: page, count: rows.count, size: pageSize) { resultPage = $0 }
        sources(selection)
    }
    private func choose(_ group: LabHistory.Group) {
        groupID = group.id; style = nil; onlyDay = nil; selectedPlotDay = nil; resultPage = 0; limitDates = false
        let days = group.points.compactMap(\.collectionDay).sorted()
        if let first = days.first, let last = days.last { start = PlanDay.date(first, timeZone: utc)!; end = PlanDay.date(last, timeZone: utc)! }
    }
    @ViewBuilder private func dateControls(_ group: LabHistory.Group) -> some View {
        LabHistoryToggle(title: "Limit plotted dates", value: $limitDates, identifier: "labHistoryLimitDates").disabled(!group.points.contains { $0.collectionDay != nil })
        if limitDates {
            VStack(alignment: .leading, spacing: 16) {
                Text("First collection day").font(.subheadline)
                DatePicker("First collection day", selection: $start, displayedComponents: .date).labelsHidden().accessibilityIdentifier("historyFirstDay")
                Text("Last collection day").font(.subheadline)
                DatePicker("Last collection day", selection: $end, displayedComponents: .date).labelsHidden().accessibilityIdentifier("historyLastDay")
            }.environment(\.timeZone, utc).environment(\.calendar, PlanDay.calendar(utc))
        }
    }
    private func plot(_ group: LabHistory.Group) -> LabHistory.Plot {
        let first = PlanDay.string(start, timeZone: utc), last = PlanDay.string(end, timeZone: utc)
        if limitDates && first > last { return .init(points: [], numericDatedCount: 0, omitted: [], blockers: [.range], warnings: []) }
        return LabHistory.plot(group, style: style, personChecked: personChecked, days: limitDates ? first...last : nil)
    }
    private func numericPlot(_ plot: LabHistory.Plot) -> some View {
        let ticks = chartDateTicks(plot)
        return VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(plot.points) { value in
                    PointMark(x: .value("Collection day", value.day), y: .value("Reported number", value.number.plotValue)).foregroundStyle(Theme.accent).symbolSize(50)
                        .accessibilityLabel(value.point.collectionDay ?? "Collection day unknown").accessibilityValue(value.point.observation.result + " " + value.point.observation.unit)
                }
                if let selected = nearestDay(plot) { RuleMark(x: .value("Selected collection day", selected)).foregroundStyle(Theme.secondary) }
            }
            .chartXSelection(value: $selectedPlotDay)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in proxy.selectXValue(at: event.location.x) }
            }
            .chartYScale(domain: yDomain(plot))
            .chartXAxis {
                AxisMarks(values: ticks) { value in
                    AxisGridLine(); AxisTick()
                    let first = value.as(Date.self) == ticks.first
                    AxisValueLabel(anchor: ticks.count == 1 ? .top : (first ? .topLeading : .topTrailing), collisionResolution: .disabled) {
                        if let date = value.as(Date.self) {
                            Text(chartDay(date)).fixedSize(horizontal: true, vertical: true).multilineTextAlignment(first ? .leading : .trailing).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in AxisGridLine(); AxisTick(); AxisValueLabel { if let number = value.as(Double.self) { Text(chartNumber(number)).foregroundStyle(Theme.secondary) } } } }
            .chartXAxisLabel { Text("Collection day").foregroundStyle(Theme.secondary) }
            .chartYAxisLabel { Text("Result").foregroundStyle(Theme.secondary) }
            .frame(height: typeSize.isAccessibilitySize ? 440 : 240).accessibilityIdentifier("labHistoryNumericPlot")
            Text("Tap the plot to select a collection day.").font(.footnote).foregroundStyle(Theme.secondary)
            if let first = plot.points.map(\.point.collectionDay).compactMap({ $0 }).min(), let last = plot.points.map(\.point.collectionDay).compactMap({ $0 }).max() { Text(first + " to " + last).font(.footnote).foregroundStyle(Theme.secondary) }
            if let selected = nearestDay(plot) {
                let day = PlanDay.string(selected, timeZone: utc), count = plot.points.filter { $0.point.collectionDay == day }.count
                Text("\(day) · \(count) \(count == 1 ? "result" : "results")").font(.headline)
                Button("Show selected day") { onlyDay = day; resultPage = 0 }.frame(minHeight: 44).foregroundStyle(Theme.accent)
                Button("Clear plot selection") { selectedPlotDay = nil }.frame(minHeight: 44).foregroundStyle(Theme.accent)
            }
            Text("Reported values stay literal in the history below.").font(.footnote).foregroundStyle(Theme.secondary)
        }
    }
    private func nearestDay(_ plot: LabHistory.Plot) -> Date? {
        guard let selectedPlotDay, selectedPlotDay.timeIntervalSince1970.isFinite else { return nil }
        return plot.points.min { abs($0.day.timeIntervalSince(selectedPlotDay)) < abs($1.day.timeIntervalSince(selectedPlotDay)) }?.day
    }
    private func yDomain(_ plot: LabHistory.Plot) -> ClosedRange<Double> {
        let values = plot.points.map(\.number.plotValue), low = min(0, values.min() ?? 0), high = max(0, values.max() ?? 0)
        if low == high { return 0...1 }
        let padding = (high - low) * 0.08
        return (low < 0 ? low - padding : 0)...(high > 0 ? high + padding : 0)
    }
    private func chartDay(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.timeZone = utc; formatter.calendar = PlanDay.calendar(utc); formatter.locale = .current
        if typeSize.isAccessibilitySize {
            formatter.setLocalizedDateFormatFromTemplate("d"); let day = formatter.string(from: date)
            formatter.setLocalizedDateFormatFromTemplate("MMM"); return day + "\n" + formatter.string(from: date)
        }
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
    private func chartDateTicks(_ plot: LabHistory.Plot) -> [Date] {
        let days = Set(plot.points.map(\.day)).sorted()
        guard let first = days.first, let last = days.last else { return [] }
        return first == last ? [first] : [first, last]
    }
    private func chartNumber(_ number: Double) -> String {
        var format = FloatingPointFormatStyle<Double>.number.precision(.significantDigits(1...3))
        if abs(number) >= 1_000_000 || (number != 0 && abs(number) < 0.001) { format = format.notation(.scientific) }
        return number.formatted(format)
    }
    private func resultRow(_ point: LabHistory.Point, plot: LabHistory.Plot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(point.collectionDay ?? "Collection day not recorded").font(.headline)
            let preview = LabTable.displayPreview(point.observation.result, maxCharacters: 120)
            Text(preview.text).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("historyValue-" + point.id)
            if preview.truncated { Text("Preview only. Open the full result to read every character.").font(.footnote).foregroundStyle(Theme.secondary) }
            Text(point.record.title.isEmpty ? "Untitled record" : point.record.title).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if let omission = plot.omitted.first(where: { $0.pointID == point.id }), omission.message != LabHistory.NumberIssue.decimalChoice.message && omission.message != LabHistory.NumberIssue.literalOnly.message { Text(omission.message).font(.footnote).foregroundStyle(Theme.secondary) }
            Button("Read result and source") { detail = point }.frame(minHeight: 44).accessibilityIdentifier("history-read-" + point.id)
            Button {
                if pair.contains(point.id) { pair.removeAll { $0 == point.id } }
                else if pair.count < 2 { pair.append(point.id) }
            } label: { Label(pair.contains(point.id) ? "Selected for comparison" : "Select for comparison", systemImage: pair.contains(point.id) ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                .disabled(!pair.contains(point.id) && pair.count == 2).accessibilityIdentifier("history-select-" + point.id)
            Divider()
        }
    }
    private func openComparison() {
        guard let selection, pair.count == 2, personChecked else { return }
        comparison = LabHistoryComparisonDraft(selection: selection, firstID: pair[0], secondID: pair[1], style: style)
    }
    private func refresh(_ documents: [HealthDocument]) {
        guard let previous = selection else { return }
        refreshControl?.cancel(); refreshJob?.cancel()
        let next = BackupOperationControl(), token = UUID(), ids = previous.records.map(\.id)
        refreshControl = next; generation = token; refreshing = true
        refreshJob = Task { @MainActor in
            do {
                let current = try await Task.detached(priority: .userInitiated) { try LabHistory.prepare(recordIDs: ids, documents: documents, control: next) }.value
                try next.checkCancellation(); guard generation == token else { return }
                let same = zip(previous.records, current.records).allSatisfy { $0.id == $1.id && $0.fingerprint == $1.fingerprint && $0.reviewedAt == $1.reviewedAt }
                selection = current
                if !same { personChecked = false; groupID = nil; pair = []; style = nil; status = "Saved lab records changed. Check the intended person and refreshed results again." }
            } catch {
                guard generation == token else { return }
                if !(error is CancellationError) { status = error.localizedDescription; selection = nil; choosingRecords = true; personChecked = false; pair = [] }
            }
            guard generation == token else { return }
            refreshing = false; refreshControl = nil; refreshJob = nil
        }
    }
}

struct LabNumberStylePicker: View {
    @Binding var style: LabHistory.DecimalStyle?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Number interpretation").font(.headline)
            ForEach(LabHistory.DecimalStyle.allCases, id: \.self) { choice in
                Button { style = choice } label: { Label(choice.label, systemImage: style == choice ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityIdentifier("historyDecimal-" + choice.rawValue)
            }
        }
    }
}
