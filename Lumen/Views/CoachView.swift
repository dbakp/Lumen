import SwiftUI

// MARK: - Coach: a calm conversation with someone who knows your data.

public struct CoachView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @StateObject private var coach = ChatCoachService.shared
    @ObservedObject private var ai = AIService.shared
    @State private var draft = ""
    @State private var saveError: String?
    @State private var conversationFailure: String?
    @State private var conversationFailureTitle = "Couldn’t save conversation"
    @State private var voiceTarget: VoiceDraftTarget?
    @State private var keyboardSubmission: VoiceDraftTarget?
    @State private var historyPresented = false
    @State private var logSelection: HealthLogSelection?
    @State private var planning = false
    @State private var isSending = false
    @State private var responseTask: Task<Void, Never>?
    @ObservedObject private var companion = CompanionStore.shared
    @FocusState private var focused: Bool

    public init() {}

    let suggestions: [(String, String)] = [
        ("sun.max", "Make a flexible plan for today"),
        ("fork.knife", "What should I eat for dinner?"),
        ("figure.run", "Should I work out hard today?"),
        ("bandage", "Help me understand my symptom log"),
    ]

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ConversationStorageStatus().environmentObject(health)
                    ForEach(health.pendingConversationReplies.filter { $0.owner.conversationID != health.activeConversationID }) { pending in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A reply in another conversation hasn't been saved.").font(.footnote)
                            Button("Open conversation") { changeConversation { try await health.selectConversation(pending.owner.conversationID) } }
                                .frame(minHeight: 44).disabled(health.isConversationSaving)
                        }.id(pending.id)
                    }
                    #if DEBUG && targetEnvironment(simulator)
                    if SemanticSearchService.usesLocalReplyTest { Text("Local model test · no generative provider request").font(.footnote).foregroundStyle(Theme.secondary) }
                    #endif
                    if health.conversationReady, health.chat.isEmpty { intro }
                    else if health.conversationReady {
                        ForEach(health.chat) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                ChatBubble(msg: message).id(message.id)
                                if message.role == .user, let conversationID = health.activeConversationID {
                                    Button("Review health entries", systemImage: "square.and.pencil") { focused = false; logSelection = HealthLogSelection(conversationID: conversationID, message: message) }.font(.footnote).frame(minHeight: 44).disabled(isSending || coach.isTyping || message.text.count > 8000)
                                    if message.text.count > 8000 { Text("Use a message under 8,000 characters to prepare health entries.").font(.caption).foregroundStyle(Theme.secondary) }
                                }
                                if message.role == .coach {
                                    Text(message.provider ?? "Provider not recorded").font(.caption).foregroundStyle(Theme.secondary).accessibilityIdentifier("savedReplyProvider-" + message.id)
                                    PersonalReplyContextNote(message: message, current: .included(companion.personalContext))
                                    if let context = message.recordContext, context.mode != .guide {
                                        RecordSourcesView(context: context)
                                    } else if message.recordContext == nil {
                                        Text("Sources weren’t recorded for this reply. It isn’t included with new questions.").font(.caption).foregroundStyle(Theme.secondary)
                                    }
                                    if message.recordContext == nil || message.personalContext?.allowsHistory(current: .included(companion.personalContext)) != true {
                                        Button("Quote in new question", systemImage: "quote.bubble") { draft = RecordRetrieval.quotedQuestion(from: message); focused = true }
                                            .font(.footnote).frame(minHeight: 44).disabled(isSending)
                                            .accessibilityIdentifier("quoteReply-" + message.id)
                                    }
                                    if let saved = companion.documents.first(where: { $0.messageID == message.id }) {
                                        NavigationLink {
                                            DocumentDetailView(documentID: saved.id)
                                        } label: {
                                            Label(saved.kind == .plan ? "View saved plan" : "View saved document", systemImage: "bookmark.fill")
                                        }.font(.footnote).frame(minHeight: 44)
                                    } else {
                                        Button("Save to Library", systemImage: "bookmark") {
                                            do {
                                                try companion.saveChecked(RecordRetrieval.savedDocument(from: message, history: health.chat))
                                                AppRouter.shared.confirm("Saved to Library")
                                            } catch { saveError = "The reply wasn't saved. Try again." }
                                        }.font(.footnote).frame(minHeight: 44)
                                        .accessibilityIdentifier("saveReplyToLibrary-" + message.id)
                                    }
                                }
                            }
                        }
                        if coach.isTyping { TypingBubble() }
                    }
                    ForEach(health.pendingConversationReplies) { pending in
                        if pending.owner.conversationID == health.activeConversationID {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Reply not saved", systemImage: "exclamationmark.circle").font(.headline).accessibilityIdentifier("unsavedConversationReply")
                                ChatBubble(msg: pending.message)
                                Text(pending.message.provider ?? "Provider not recorded").font(.caption).foregroundStyle(Theme.secondary).accessibilityIdentifier("pendingReplyProvider")
                                PersonalReplyContextNote(message: pending.message, current: .included(companion.personalContext), pending: true)
                                if let context = pending.message.recordContext, context.mode != .guide { RecordSourcesView(context: context) }
                                Text("Keep Lumen open until this reply is saved. Retry saves it without another request.").font(.footnote).foregroundStyle(Theme.secondary)
                                Button("Retry save", systemImage: "arrow.clockwise") { retryReply(pending.id) }
                                    .frame(minHeight: 44).disabled(health.isConversationSaving || isSending)
                                    .accessibilityIdentifier("retryConversationReply")
                            }
                        }
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: health.chat.count) { _, _ in scrollToRecoveryOrBottom(proxy) }
            .onChange(of: coach.isTyping) { _, _ in scrollToRecoveryOrBottom(proxy) }
            .onChange(of: health.pendingConversationReplies.map(\.id)) { _, _ in scrollToRecoveryOrBottom(proxy) }
            .onChange(of: conversationFailure) { _, failure in
                if failure == nil { scrollToRecoveryOrBottom(proxy) }
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .lumenScreen(Theme.calm)
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { historyPresented = true } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("Conversation history")
            }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Make a multiweek plan", systemImage: "calendar.badge.plus") { focused = false; planning = true }
                        if !health.chat.isEmpty { Button("New conversation", systemImage: "square.and.pencil") { changeConversation { try await health.newConversation() } }.disabled(health.isConversationSaving || !health.conversationReady) }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Conversation actions")
                }
        }
        .alert("Couldn't save reply", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
        .alert(conversationFailureTitle, isPresented: Binding(get: { conversationFailure != nil }, set: { if !$0 { conversationFailure = nil } })) { Button("OK") { conversationFailure = nil } } message: { Text(conversationFailure ?? "") }
        .sheet(isPresented: Binding(get: { voiceTarget != nil }, set: { if !$0 { voiceTarget = nil } })) {
            if let target = voiceTarget {
                VoiceDraftSheet(target: target) { text in
                    draft = try target.adding(text, to: .init(conversationID: health.activeConversationID, originalDraft: draft))
                }
            }
        }
        .onChange(of: keyboardSubmission) { _, request in
            guard let request else { return }
            keyboardSubmission = nil
            guard request.conversationID == health.activeConversationID,
                  request.originalDraft == draft.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            // Submit after the text-input callback has finished its binding writes.
            send(request.originalDraft)
        }
        .sheet(item: $logSelection) { HealthLogReviewView(selection: $0).environmentObject(health) }
        .sheet(isPresented: $planning) { ScheduledPlanSheet().environmentObject(health) }
        .sheet(isPresented: $historyPresented) { ConversationHistoryView().environmentObject(health) }
    }

    var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Let’s put it\nin context.")
                    .font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text)
                Text("Bring your questions, symptoms and goals. We’ll work from what you have actually recorded.")
                    .font(.body).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 20)
            VStack(alignment: .leading, spacing: 8) {
                Label("Today’s context", systemImage: "checkmark.shield").font(.headline)
                Text(companion.perspective(health: health).evidence.joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.secondary)
                let sharedCount = companion.documents.filter(\.includeInAssistant).count
                Text("\(companion.activeSymptoms.count) ongoing symptom \(companion.activeSymptoms.count == 1 ? "log" : "logs") · \(sharedCount) shared \(sharedCount == 1 ? "record" : "records")")
                    .font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("conversationContextCounts")
                Text("Provider: \(ai.brain.label). Relevant text is selected from shared Library documents for each question, alongside your current health summary.").font(.footnote).foregroundStyle(Theme.secondary)
            }.padding(18).surface()
            VStack(spacing: 10) {
                ForEach(suggestions, id: \.1) { icon, text in
                    Button { send(text) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: icon).foregroundStyle(Theme.calm).frame(width: 24)
                            Text(text).font(.body).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(Theme.tertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 15)
                        .surface(18)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartRequest)
                }
            }
            Button("Make a multiweek plan", systemImage: "calendar.badge.plus") { planning = true }.frame(minHeight: 44).accessibilityIdentifier("startScheduledPlan")
            NavigationLink("Personal context", destination: PersonalContextView()).frame(minHeight: 44)
            Label(ai.brain.label, systemImage: ai.brain.isAI ? "lock.shield" : "cpu")
                .font(.footnote).foregroundStyle(Theme.tertiary)
        }
    }

    var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: Binding(get: { draft }, set: { value in
                let returned = ComposerDraftEdit.isReturn(previous: draft, next: value)
                draft = value
                if returned { requestKeyboardSubmission(String(value.dropLast())) }
            }), prompt: Text("Message your coach").foregroundStyle(Theme.tertiary), axis: .vertical)
                .focused($focused).lineLimit(1...5)
                .accessibilityIdentifier("coachInput")
                .padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(Theme.text)
                .submitLabel(.send)
                .onSubmit { requestKeyboardSubmission(draft) }
            Button {
                focused = false
                voiceTarget = .init(conversationID: health.activeConversationID, originalDraft: draft)
            } label: { Image(systemName: "mic").font(.system(size: 20)).frame(width: 44, height: 44) }
                .disabled(isSending || coach.isTyping || !health.conversationReady || health.isConversationSaving).accessibilityLabel("Speak a message").accessibilityIdentifier("coachVoice")
            if isSending {
                Button { responseTask?.cancel(); AppRouter.shared.confirm("Response stopped") } label: {
                    Image(systemName: "stop.fill").frame(width: 44, height: 44)
                }.accessibilityLabel("Stop response")
            }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up").font(.system(size: 22, weight: .bold))
                    .foregroundStyle(canSend ? Theme.onAccent : Theme.tertiary)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Theme.accent : Theme.surfaceRaised, in: Circle())
            }
            .disabled(!canSend)
            .padding(.trailing, 6).padding(.bottom, 6)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("coachSend")
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
        .padding(.horizontal, 16).padding(.bottom, 8).padding(.top, 6)
        .background(Theme.bg)
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && canStartRequest }
    var canStartRequest: Bool { !coach.isTyping && !isSending && health.conversationReady && !health.isConversationSaving && health.pendingConversationReplies.isEmpty }

    func scrollToRecoveryOrBottom(_ proxy: ScrollViewProxy) {
        if let pending = health.pendingConversationReplies.first(where: { $0.owner.conversationID != health.activeConversationID }) {
            // The recovery row can be inserted in the same update that presents
            // the save alert. Resolve its ID after layout, and again when the
            // alert closes, rather than leaving recovery below a long intro.
            DispatchQueue.main.async {
                guard health.pendingConversationReplies.contains(where: { $0.id == pending.id && $0.owner.conversationID != health.activeConversationID }) else { return }
                withAnimation { proxy.scrollTo(pending.id, anchor: .top) }
            }
        } else { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
    }

    func requestKeyboardSubmission(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, canStartRequest else { return }
        keyboardSubmission = .init(conversationID: health.activeConversationID, originalDraft: value)
    }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, canStartRequest else { return }
        let submittedDraft = draft, target = health.activeConversationID
        isSending = true
        responseTask = Task {
            var replyOwner: ConversationReplyOwner?
            defer {
                if let replyOwner { health.finishConversationReply(replyOwner) }
                isSending = false; responseTask = nil
            }
            do {
                let sent = try await health.sendUserMessageChecked(ChatMessage(role: .user, text: t), expectedConversationID: target)
                replyOwner = sent.owner
                guard let runningTask = responseTask,
                      health.registerConversationReplyCancellation(sent.owner, cancel: { runningTask.cancel() }) else { return }
                if draft == submittedDraft, health.activeConversationID == sent.owner.conversationID {
                    // Clearing a submitted question must never erase separately
                    // entered text while its save was preparing off-thread.
                    if submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines) == t { draft = ""; focused = false }
                }
                guard !Task.isCancelled, health.ownsReply(sent.owner) else { return }
                let answer = await coach.reply(to: t, health: health, sleepDebt: sleep.debt, conversationHistory: sent.history)
                guard !Task.isCancelled, health.ownsReply(sent.owner) else { return }
                let reply = ChatMessage(role: .coach, text: answer, provider: coach.lastReplySource, recordContext: coach.lastRecordContext, personalContext: coach.lastPersonalContext)
                guard let id = health.retainConversationReply(reply, owner: sent.owner,
                    savePlan: coach.lastReplyCanBecomePlan && PlanBuilder.isRequest(t) && ChatCoachService.urgentResponse(for: t) == nil) else { return }
                do { saveReplyPlan(try await health.savePendingConversationReply(id)) }
                catch {
                    if Task.isCancelled { health.discardConversationReply(id) }
                    else if case ConversationSaveError.notReady = error { /* The inline pending reply remains available after the other save. */ }
                    else if health.ownsReply(sent.owner) {
                        conversationFailureTitle = "Couldn’t save reply"
                        conversationFailure = "This reply hasn't been saved. Keep Lumen open and use Retry save below. Your question won't be sent again."
                    }
                }
            } catch is CancellationError {
                // Stop can cancel preparation before a user message is committed.
            } catch {
                if submittedDraft.isEmpty, draft.isEmpty, health.activeConversationID == target { draft = t }
                conversationFailureTitle = "Couldn’t save question"
                if let error = error as? ConversationSaveError { conversationFailure = error.localizedDescription }
                else { conversationFailure = "Your question wasn't saved or sent. Your draft is still available. Try sending again." }
            }
        }
    }

    func changeConversation(_ action: @escaping @MainActor () async throws -> Void) {
        Task { do { try await action() } catch {
            conversationFailureTitle = "Couldn’t change conversation"
            conversationFailure = "The conversation change wasn't saved. Your saved history is unchanged. Try again."
        } }
    }

    func retryReply(_ id: String) {
        Task {
            do { saveReplyPlan(try await health.savePendingConversationReply(id)) }
            catch {
                conversationFailureTitle = "Couldn’t save reply"
                conversationFailure = "This reply still hasn't been saved. Keep Lumen open and try saving again."
            }
        }
    }

    func saveReplyPlan(_ pending: PendingConversationReply) {
        guard pending.savePlan else { return }
        let reply = pending.message
        do {
            try companion.saveChecked(HealthDocument(title: "Plan · \(Date().formatted(date: .abbreviated, time: .omitted))", kind: .plan,
                body: reply.text, steps: PlanBuilder.steps(from: reply.text), source: "Lumen assistant · \(reply.provider ?? "Provider not recorded")",
                messageID: reply.id, recordContext: reply.recordContext))
            AppRouter.shared.confirm("Plan saved to Library")
        } catch { saveError = "The reply is in this conversation, but its plan wasn't saved. Use Save to Library to try again." }
    }
}

struct ChatBubble: View {
    let msg: ChatMessage
    var isUser: Bool { msg.role == .user }
    @ViewBuilder var messageText: some View {
        if isUser {
            FHIRLiteralText(text: msg.text, identifier: "userMessage", lineSpacing: 3, color: Theme.onAccent, fitsContentWidth: true)
        } else if msg.recordContext?.mode == .lookup {
            FHIRLiteralText(text: msg.text, identifier: "coachMessage", lineSpacing: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(LocalizedStringKey(msg.text)).font(.body).lineSpacing(3)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .accessibilityIdentifier("coachMessage")
        }
    }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            messageText
                .padding(.horizontal, isUser ? 16 : 0).padding(.vertical, isUser ? 11 : 4)
                .background(isUser ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if !isUser { Spacer(minLength: 24) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct TypingBubble: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.secondary).frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .padding(.vertical, 8)
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi } }
        .accessibilityLabel("Coach is typing")
    }
}
