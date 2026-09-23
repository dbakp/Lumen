import SwiftUI

// MARK: - Coach: a calm conversation with someone who knows your data.

public struct CoachView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @StateObject private var coach = ChatCoachService.shared
    @ObservedObject private var ai = AIService.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    public init() {}

    let suggestions: [(String, String)] = [
        ("sun.max", "How should I approach today?"),
        ("fork.knife", "What should I eat for dinner?"),
        ("figure.run", "Should I work out hard today?"),
        ("moon", "Why do I feel tired?"),
    ]

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if health.chat.isEmpty { intro } else {
                        ForEach(health.chat) { ChatBubble(msg: $0).id($0.id) }
                        if coach.isTyping { TypingBubble() }
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: health.chat.count) { _, _ in withAnimation(.spring(response: 0.45)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: coach.isTyping) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .lumenScreen(Theme.calm)
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !health.chat.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New conversation", systemImage: "square.and.pencil") { health.chat = []; health.persist() }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
    }

    var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hi\(sleep.profile.name.isEmpty ? "" : " \(sleep.profile.name)"), what's on your mind?")
                    .font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text)
                Text("Ask about sleep, training, food or energy. I use your data to give answers that fit you.")
                    .font(.body).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 20)
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
                }
            }
            Label(ai.brain.label, systemImage: ai.brain.isAI ? "lock.shield" : "cpu")
                .font(.footnote).foregroundStyle(Theme.tertiary)
        }
    }

    var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $draft, prompt: Text("Message your coach").foregroundStyle(Theme.tertiary), axis: .vertical)
                .focused($focused).lineLimit(1...5)
                .accessibilityIdentifier("coachInput")
                .padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(.white)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .onChange(of: draft) { _, v in
                    // Multi-line field: the keyboard's Send key inserts a newline — treat it as send.
                    if v.hasSuffix("\n") { send(String(v.dropLast())) }
                }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up").font(.headline.weight(.bold))
                    .foregroundStyle(canSend ? .black : Theme.tertiary)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.white : Theme.surfaceRaised, in: Circle())
            }
            .disabled(!canSend)
            .padding(.trailing, 6).padding(.bottom, 6)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("coachSend")
        }
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
        .padding(.horizontal, 16).padding(.bottom, 8).padding(.top, 6)
        .background(Theme.bg)
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !coach.isTyping }

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
            if isUser { Spacer(minLength: 48) }
            Text(LocalizedStringKey(msg.text))
                .font(.body).lineSpacing(3)
                .foregroundStyle(isUser ? .black : Theme.text)
                .padding(.horizontal, isUser ? 16 : 0).padding(.vertical, isUser ? 11 : 4)
                .background(isUser ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .textSelection(.enabled)
                .accessibilityIdentifier(isUser ? "userMessage" : "coachMessage")
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
