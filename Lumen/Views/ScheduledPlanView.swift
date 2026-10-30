import SwiftUI

struct ScheduledPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthStore
    @ObservedObject private var ai = AIService.shared
    @State private var goal = ""
    @State private var start = Date()
    @State private var weeks = 2
    @State private var proposal: ScheduledPlanDraft?
    @State private var savedID: String?
    @State private var working = false
    @State private var error: String?
    @State private var discard = false
    @State private var generationID: UUID?
    @State private var generation: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    private var request: ScheduledPlanRequest { .init(goal: goal, startDay: PlanDay.string(start), weeks: weeks) }
    private var hasDraft: Bool { savedID == nil && (!goal.isEmpty || proposal != nil || working || weeks != 2 || PlanDay.string(start) != PlanDay.string(Date())) }
    private var fixture: String? {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-scheduledPlanUITestFixture"), args.indices.contains(index + 1) { return args[index + 1] }
        #endif
        return nil
    }
    var body: some View {
        NavigationStack {
            Group {
                if let savedID {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text("Plan saved.").font(.largeTitle.bold()).fontWidth(.expanded)
                        Text("Your dated steps are in Library and Your next steps. You can edit them as your plans change.").foregroundStyle(Theme.secondary)
                        NavigationLink { DocumentDetailView(documentID: savedID) } label: {
                            Text("View saved plan").multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 20)
                        }.buttonStyle(LumenPrimaryButtonStyle())
                        Button { dismiss() } label: { Text("Done").padding(.horizontal, 24).padding(.vertical, 12) }
                            .buttonStyle(LumenTonalButtonStyle()).accessibilityIdentifier("finishScheduledPlan")
                    }.padding(Theme.gutter).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if proposal != nil {
                    ScheduledPlanReview(draft: Binding(get: { proposal! }, set: { proposal = $0 }), onSaved: { savedID = $0 }, onRevise: { proposal = nil })
                } else { setup }
            }
            .background(Theme.bg).navigationTitle(savedID == nil ? "Make a plan" : "Saved plan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { if hasDraft { discard = true } else { stop(); dismiss() } }.accessibilityIdentifier("closeScheduledPlan")
            } }
        }.tint(Theme.accent)
            .background(SheetDismissGuard(hasEdits: hasDraft) { discard = true })
            .alert("Discard this plan draft?", isPresented: $discard) {
                Button("Keep planning", role: .cancel) {}
                Button("Discard draft", role: .destructive) { stop(); dismiss() }
            } message: { Text("Your goal and unsaved steps will be discarded. Saved plans stay in Library.") }
            .onDisappear { stop() }
    }
    private var setup: some View {
        Form {
            Section {
                Text("Make room\nfor a routine.").font(.largeTitle.bold()).fontWidth(.expanded).foregroundStyle(Theme.text)
                Text("Choose a timeframe, then review the steps before adding them to your agenda.").foregroundStyle(Theme.secondary)
            }.listRowBackground(Color.clear)
            Section("Your goal") {
                if !goal.isEmpty { Text(verbatim: goal).lineLimit(3).accessibilityIdentifier("scheduledPlanGoalPreview") }
                NavigationLink(goal.isEmpty ? "Add a goal" : "Edit goal") {
                    PlanDraftTextEditor(text: $goal, title: "Your goal", limit: 2000, identifier: "scheduledPlanGoal")
                }.accessibilityIdentifier("editScheduledPlanGoal")
            }.disabled(working)
            Section("Timeframe") {
                DatePicker("Start date", selection: $start, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date).accessibilityIdentifier("scheduledPlanStart")
                Picker("Duration", selection: $weeks) {
                    ForEach([1, 2, 4, 8], id: \.self) { Text("\($0) \($0 == 1 ? "week" : "weeks")").tag($0) }
                }.accessibilityIdentifier("scheduledPlanWeeks")
                if let end = request.lastDay.flatMap({ PlanDay.date($0) }) {
                    Text("Through " + end.formatted(date: .complete, time: .omitted)).font(.footnote).foregroundStyle(Theme.secondary)
                }
            }.disabled(working)
            Section {
                if let fixture { Text("Simulated plan. No AI request.").font(.subheadline.bold()).foregroundStyle(Theme.accent).accessibilityIdentifier("scheduledPlanFixture"); Text(fixture == "invalid" ? "Invalid-reply fixture" : "Synthetic schedule fixture").font(.caption).foregroundStyle(Theme.secondary) }
                else { Text(ai.brain.label).font(.headline) }
                if working {
                    ProgressView("Preparing your draft")
                    Button("Stop preparing") { stop(); error = "Preparation stopped. Your goal and timeframe are still here." }.accessibilityIdentifier("stopScheduledPlan")
                } else {
                    Button("Prepare draft") { prepare() }.fontWeight(.semibold).disabled(!request.isValid || (!ai.brain.isAI && fixture == nil)).accessibilityIdentifier("prepareScheduledPlan")
                }
            } footer: {
                Text(ai.brain.isAI ? "Your goal and health summary go to this provider, including source wording kept with confirmed logs. Personal context follows your sharing choice. Library excerpts and other chat history stay out of this request. Nothing is saved yet." : "No AI provider is available. You can choose the planning template below, or configure a provider in Settings.").foregroundStyle(Theme.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(Theme.text).accessibilityIdentifier("scheduledPlanError") } }
            Section {
                Button("Use a planning template") {
                    guard ready() else { return }
                    do { proposal = try ScheduledPlanDraft.template(request: request); error = nil } catch { self.error = error.localizedDescription }
                }.disabled(!request.isValid || working).accessibilityIdentifier("useScheduledPlanTemplate")
            } footer: { Text("Three repeated planning prompts per week, prepared on this iPhone. The template doesn't use health data or tailor steps to your goal.").foregroundStyle(Theme.secondary) }
            if !goal.isEmpty && !request.isValid { Section { Text("Shorten the goal to fit within 2,000 characters, and choose a supported date and duration.").font(.footnote).foregroundStyle(Theme.secondary) } }
        }.scrollContentBackground(.hidden)
    }
    private func ready() -> Bool {
        guard request.isValid else { return false }
        if let urgent = ChatCoachService.urgentResponse(for: goal) { error = urgent; return false }
        return true
    }
    private func prepare() {
        guard !working, ready() else { return }
        let selected = ai.brain, input = request, synthetic = fixture
        let personal = CompanionStore.shared.personalContext.assistantText
        let context = CompanionStore.shared.context(health: health) + "\n" + CoachingEngine.contextPrompt(metrics: health.metrics, readiness: health.readiness, goals: health.goals, workoutsToday: health.workoutsToday, estimatedSleepDebt: health.assistantSleepDebt)
        guard context.utf8.count <= 64_000 else { error = "The health summary is too large for this request. You can use and edit the planning template."; return }
        let ticket = UUID(); generationID = ticket; working = true; error = nil
        timeout = Task {
            do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
            guard generationID == ticket else { return }
            stop(); error = "Preparation took too long. Your goal is still here. Try again, or use the planning template."
        }
        generation = Task {
            let response: String?
            var source = selected.label
            #if DEBUG && targetEnvironment(simulator)
            if let synthetic {
                do { try await Task.sleep(nanoseconds: synthetic == "delayed" ? 8_000_000_000 : 250_000_000) } catch { return }
                source = "Simulated plan · no AI request"
                if synthetic == "invalid" { response = "An incomplete synthetic reply" }
                else {
                    let steps = (0..<input.weeks).flatMap { week in [(1, "Choose a small step that fits your week"), (7, "Review your routine and adjust if needed")].map { ["day": week * 7 + $0.0, "title": $0.1] as [String: Any] } }
                    let object: [String: Any] = ["version": 1, "title": "A steady routine", "reason": "Synthetic planning text for interface verification. No provider or health inference.", "steps": steps]
                    response = String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)
                }
            } else { response = await ai.scheduledPlan(request: input, context: context, using: selected) }
            #else
            response = await ai.scheduledPlan(request: input, context: context, using: selected)
            #endif
            guard !Task.isCancelled, generationID == ticket else { return }
            timeout?.cancel(); timeout = nil; generationID = nil; working = false; generation = nil
            guard personal == CompanionStore.shared.personalContext.assistantText else { error = "Your personal context changed while preparing. Prepare again to use your current sharing choice and text."; return }
            guard let response else { error = "The provider couldn't prepare a draft. Your goal is still here. Try again, or use the planning template."; return }
            do { proposal = try ScheduledPlanDraft.parse(response, request: input, source: source) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func stop() {
        generationID = nil; generation?.cancel(); generation = nil; timeout?.cancel(); timeout = nil; working = false
    }
}

private struct ScheduledPlanReview: View {
    @Binding var draft: ScheduledPlanDraft
    var onSaved: (String) -> Void
    var onRevise: () -> Void
    @State private var acknowledged = false
    @State private var saving = false
    @State private var error: String?
    @State private var revise = false
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                Text(verbatim: draft.title).font(.largeTitle.bold()).fontWidth(.expanded).foregroundStyle(Theme.text)
                Text("\(draft.request.weeks) \(draft.request.weeks == 1 ? "week" : "weeks") · \(draft.actions.count) dated steps").font(.headline).foregroundStyle(Theme.accent).accessibilityIdentifier("scheduledPlanCount")
                Text(draft.source).font(.footnote).foregroundStyle(Theme.secondary)
                Text("Nothing is saved yet. Open a step to edit its wording or date; swipe to remove it.").foregroundStyle(Theme.secondary)
            }.listRowBackground(Color.clear)
            Section("Plan details") {
                NavigationLink("Edit title") { PlanDraftTextEditor(text: $draft.title, title: "Plan title", limit: 120, identifier: "scheduledPlanTitle") }
                Text(verbatim: draft.reason).font(.subheadline)
                NavigationLink("Edit description") { PlanDraftTextEditor(text: $draft.reason, title: "Plan description", limit: 2000, identifier: "scheduledPlanReason") }
                DisclosureGroup("Your original goal") { Text(verbatim: draft.request.goal) }
            }
            ForEach(0..<draft.request.weeks, id: \.self) { week in
                Section("Week \(week + 1)") {
                    let actions = draft.actions.filter { ($0.day - 1) / 7 == week }.sorted { $0.day < $1.day }
                    if actions.isEmpty { Text("No steps in this week").foregroundStyle(Theme.secondary) }
                    ForEach(actions) { action in
                        NavigationLink {
                            PlanActionEditor(action: Binding(get: { draft.actions.first { $0.id == action.id } ?? action }, set: { value in
                                if let index = draft.actions.firstIndex(where: { $0.id == action.id }), draft.actions[index] != value {
                                    acknowledged = false; error = nil; draft.actions[index] = value
                                }
                            }), request: draft.request)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: action.title.isEmpty ? "Add step wording" : action.title).foregroundStyle(Theme.text)
                                if let day = PlanDay.adding(action.day - 1, to: draft.request.startDay).flatMap({ PlanDay.date($0) }) { Text(day.formatted(date: .complete, time: .omitted)).font(.caption).foregroundStyle(Theme.secondary) }
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("scheduledPlanAction-\(action.id)")
                    }.onDelete { indices in
                        let ids = Set(indices.map { actions[$0].id }); draft.actions.removeAll { ids.contains($0.id) }
                    }
                }.id("plan-week-\(week)")
            }
            Section {
                Button("Add a step", systemImage: "plus") { draft.actions.append(.init(day: 1, title: "")) }.disabled(draft.actions.count >= 56)
            }
            Section {
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("I checked the steps and dates")
                        Toggle("I checked the steps and dates", isOn: $acknowledged).labelsHidden().accessibilityIdentifier("acknowledgeScheduledPlan")
                    }
                } else { Toggle("I checked the steps and dates", isOn: $acknowledged).accessibilityIdentifier("acknowledgeScheduledPlan") }
                Text("Saving adds this plan to Library and its unfinished steps to Your next steps. Steps stay in Lumen. Assistant sharing starts off.").font(.footnote).foregroundStyle(Theme.secondary)
                if !draft.isValid { Text(ScheduledPlanError.review.localizedDescription).font(.footnote).foregroundStyle(Theme.secondary) }
                if let error { Text(error).foregroundStyle(Theme.text) }
                Button("Save plan") {
                    guard !saving else { return }; saving = true
                    do { let document = try draft.document(acknowledged: acknowledged); try CompanionStore.shared.saveChecked(document); onSaved(document.id) }
                    catch { self.error = "The plan wasn't saved. Your draft is still here; try again." }
                    saving = false
                }.fontWeight(.semibold).disabled(!acknowledged || !draft.isValid || saving).accessibilityIdentifier("saveScheduledPlan")
            }.id("plan-confirm")
            Section { Button("Change goal or timeframe") { revise = true } }
        }.scrollContentBackground(.hidden).accessibilityIdentifier("scheduledPlanReview")
            .onChange(of: draft) { _, _ in acknowledged = false; error = nil }
            .alert("Replace these draft steps?", isPresented: $revise) {
                Button("Keep these steps", role: .cancel) {}
                Button("Change setup", role: .destructive) { onRevise() }
            } message: { Text("Your goal and timeframe stay. These unsaved steps will be discarded so you can prepare a new draft.") }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Weeks", systemImage: "calendar") {
                        ForEach(0..<draft.request.weeks, id: \.self) { week in
                            Button("Week \(week + 1)") { proxy.scrollTo("plan-week-\(week)", anchor: .top) }
                        }
                        Button("Before saving") { proxy.scrollTo("plan-confirm", anchor: .top) }
                    }.accessibilityLabel("Jump to week")
                }
            }
        }
    }
}

private struct PlanDraftTextEditor: View {
    @Binding var text: String
    let title: String
    let limit: Int
    let identifier: String
    @State private var local: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    init(text: Binding<String>, title: String, limit: Int, identifier: String) {
        _text = text; _local = State(initialValue: text.wrappedValue); self.title = title; self.limit = limit; self.identifier = identifier
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $local).font(.body).foregroundStyle(Theme.text).scrollContentBackground(.hidden).focused($focused).autocorrectionDisabled().accessibilityLabel(title).accessibilityIdentifier(identifier)
            if local.count > limit || local.utf8.count > limit * 4 { Text("Shorten this text to fit within \(limit.formatted()) characters.").font(.footnote).foregroundStyle(Theme.secondary) }
        }.padding(Theme.gutter).background(Theme.bg).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack { Spacer(); Button { text = local; focused = false; dismiss() } label: { Text("Done").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("finishPlanText") }.padding(.horizontal, Theme.gutter).background(.bar)
            }.onChange(of: local) { _, value in text = value }.task { focused = true }
    }
}

private struct PlanActionEditor: View {
    @Binding var action: ScheduledPlanAction
    let request: ScheduledPlanRequest
    @State private var wording: String
    @State private var day: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    init(action: Binding<ScheduledPlanAction>, request: ScheduledPlanRequest) {
        _action = action; _wording = State(initialValue: action.wrappedValue.title); _day = State(initialValue: action.wrappedValue.day); self.request = request
    }
    private var date: Binding<Date> { Binding(get: { PlanDay.date(PlanDay.adding(day - 1, to: request.startDay)!)! }, set: { value in
        let start = PlanDay.date(request.startDay)!, end = PlanDay.date(PlanDay.string(value))!
        day = PlanDay.calendar(.current).dateComponents([.day], from: start, to: end).day! + 1
    }) }
    var body: some View {
        Form {
            if textSize.isAccessibilitySize { Section("Planned date") { datePicker.labelsHidden() } }
            else { Section { datePicker } }
            Section("Step wording") {
                if !wording.isEmpty { Text(verbatim: wording).lineLimit(3) }
                NavigationLink(wording.isEmpty ? "Add step wording" : "Edit full step") {
                    PlanDraftTextEditor(text: $wording, title: "Step wording", limit: 500, identifier: "scheduledActionText")
                }.accessibilityIdentifier("editFullScheduledAction")
            }
        }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Plan step").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { commit(); dismiss() }.accessibilityIdentifier("finishScheduledAction")
            } }
            .onDisappear { commit() }
    }
    private var datePicker: some View {
        DatePicker("Planned date", selection: date, in: PlanDay.date(request.startDay)!...PlanDay.date(request.lastDay!)!, displayedComponents: .date).accessibilityIdentifier("scheduledActionDate")
    }
    private func commit() {
        var value = action; value.day = day; value.title = wording; action = value
    }
}
