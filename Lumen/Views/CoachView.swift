import SwiftUI

// MARK: - Coach: chat + insights. Feels like texting an elite coach who
// actually knows your data — because it does.

public struct CoachView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @StateObject private var coach = ChatCoachService.shared
    @State private var draft = ""
    @State private var suggested: String?
    @FocusState private var focused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if let plan = health.plan {
                            BriefingCard(plan: plan, readiness: health.readiness)
                        }
                        ForEach(health.insights) { InsightCard($0) }
                        Divider().background(.white.opacity(0.1)).padding(.vertical, 4)
                        ForEach(health.chat) { msg in ChatBubble(msg: msg) }
                        if coach.isTyping {
                            HStack {
                                ProgressView().tint(.cyan).scaleEffect(0.8)
                                Text("Coach is thinking…").font(.caption).foregroundStyle(.white.opacity(0.6))
                                Spacer()
                            }
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
                    .onChange(of: health.chat.count) { _, _ in
                        withAnimation(.spring(response: 0.5)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            // Suggestion chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { c in
                        Button(c) { send(c) }
                            .font(.caption.weight(.bold)).foregroundStyle(.cyan)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.cyan.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(.cyan.opacity(0.25), lineWidth: 0.8))
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            // Input bar — liquid glass, always reachable
            HStack(spacing: 10) {
                TextField("Ask your coach…", text: $draft, axis: .vertical)
                    .focused($focused).lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .foregroundStyle(.white)
                    .onSubmit { send(draft) }
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(draft.isEmpty ? .gray : .cyan)
                }.disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || coach.isTyping)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .liquidGlass(cornerRadius: 26, tintOpacity: 0.16)
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .background(AuroraBackground())
        .navigationTitle("Coach").navigationBarTitleDisplayMode(.inline)
    }

    var chips: [String] {
        ["How should I approach today?", "What should I eat tonight?", "Should I train hard?", "Why am I tired?"]
    }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !coach.isTyping else { return }
        draft = ""
        health.chat.append(ChatMessage(role: .user, text: t))
        health.persist()
        Task {
            let answer = await coach.reply(to: t, health: health, sleepDebt: sleep.debt)
            health.chat.append(ChatMessage(role: .coach, text: answer))
            health.persist()
        }
    }
}

struct ChatBubble: View {
    let msg: ChatMessage
    var isUser: Bool { msg.role == .user }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 50) }
            Text(msg.text)
                .font(.subheadline).lineSpacing(3)
                .foregroundStyle(isUser ? .black : .white)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    isUser ? AnyShapeStyle(LinearGradient(colors: [.cyan, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                           : AnyShapeStyle(Color.white.opacity(0.1)),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(isUser ? nil : RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.8))
            if !isUser { Spacer(minLength: 50) }
        }
        .transition(.move(edge: isUser ? .trailing : .leading).combined(with: .opacity))
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: msg.id)
    }
}
