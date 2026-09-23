import SwiftUI

// MARK: - Premium motion + glass primitives.
// Delight rules: everything animates with spring; numbers count; rings glow;
// press states compress; celebrations are earned, never noisy.

public struct AnimatedNumber: View {
    let value: Double
    let format: String
    public init(_ value: Double, format: String = "%.0f") { self.value = value; self.format = format }
    public var body: some View {
        Text(String(format: format, value))
            .contentTransition(.numericText())
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
    }
}

public struct GlowRing: View {
    let progress: Double // 0-1
    let colors: [Color]
    let lineWidth: CGFloat
    public init(progress: Double, colors: [Color] = [.cyan, .purple], lineWidth: CGFloat = 12) {
        self.progress = progress; self.colors = colors; self.lineWidth = lineWidth
    }
    public var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: colors[0].opacity(0.55), radius: 10)
                .animation(.spring(response: 0.9, dampingFraction: 0.78), value: progress)
        }
    }
}

public struct ReadinessDial: View {
    let score: Int?
    public init(score: Int?) { self.score = score }
    var tint: Color {
        guard let score else { return .white.opacity(0.5) }
        return score >= 85 ? .green : score >= 70 ? .cyan : score >= 55 ? .yellow : .orange
    }
    public var body: some View {
        ZStack {
            GlowRing(progress: Double(score ?? 0)/100, colors: [tint, tint.opacity(0.5)])
            VStack(spacing: 0) {
                if let score {
                    AnimatedNumber(Double(score)).font(.system(size: 46, weight: .bold, design: .rounded)).foregroundStyle(.white)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        .symbolEffect(.pulse)
                        .padding(.bottom, 4)
                }
                Text(score == nil ? "CALIBRATING" : "READINESS").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(1.4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Readiness \($0) out of 100" } ?? "Readiness calibrating")
    }
}

public struct MetricTile: View {
    let icon: String; let tint: Color; let title: String; let value: String; let sub: String
    public init(icon: String, tint: Color, title: String, value: String, sub: String) {
        self.icon = icon; self.tint = tint; self.title = title; self.value = value; self.sub = sub
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint).frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                Text(sub).font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardPadding().liquidGlass(cornerRadius: 20)
    }
}

public struct DataPill: View {
    let live: Bool
    public init(live: Bool) { self.live = live }
    var label: String { live ? "APPLE HEALTH" : "ON-DEVICE" }
    public var body: some View {
        HStack(spacing: 5) {
            Circle().fill(live ? .green : .white.opacity(0.6)).frame(width: 7, height: 7)
                .shadow(color: (live ? Color.green : Color.white).opacity(0.6), radius: 4)
            Text(label)
                .font(.caption2.weight(.bold)).tracking(0.8)
                .foregroundStyle(live ? .green : .white.opacity(0.7))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background((live ? Color.green : Color.white).opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke((live ? Color.green : Color.white).opacity(0.25), lineWidth: 0.8))
    }
}

public struct InsightCard: View {    let insight: Insight
    public init(_ insight: Insight) { self.insight = insight }
    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: insight.tint)).frame(width: 34, height: 34)
                .background(Color(hex: insight.tint).opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text(insight.body).font(.caption).foregroundStyle(.white.opacity(0.7)).lineSpacing(2)
                if let a = insight.action {
                    Text(a + " →").font(.caption.weight(.bold)).foregroundStyle(.cyan).padding(.top, 2)
                }
            }
            Spacer()
        }
        .cardPadding().liquidGlass(cornerRadius: 22)
    }
}

public struct BriefingCard: View {
    let plan: DayPlan
    let readiness: Readiness?
    public init(plan: DayPlan, readiness: Readiness?) { self.plan = plan; self.readiness = readiness }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.cyan)
                Text("COACH BRIEFING").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6)).tracking(1.2)
                Spacer()
                if let r = readiness {
                    Text(r.headline).font(.caption2.weight(.bold)).foregroundStyle(.cyan)
                }
            }
            Text(plan.briefing).font(.headline.weight(.semibold)).foregroundStyle(.white).lineSpacing(3)
            ForEach(plan.bullets, id: \.self) { b in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text(b).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineSpacing(2)
                }
            }
        }
        .cardPadding().liquidGlass(cornerRadius: 26, tintOpacity: 0.18)
    }
}

// Press-compress modifier for tactile premium feel.
public struct Pressable: ViewModifier {
    @State private var pressed = false
    public func body(content: Content) -> some View {
        content.scaleEffect(pressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false })
    }
}
public extension View {
    func pressable() -> some View { modifier(Pressable()) }
    func shimmer() -> some View {
        self.overlay(
            LinearGradient(colors: [.clear, .white.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)
                .rotationEffect(.degrees(20)).blur(radius: 6)
                .modifier(ShimmerLoop())
        ).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
struct ShimmerLoop: ViewModifier {
    @State private var x: CGFloat = -1
    func body(content: Content) -> some View {
        content.offset(x: x * 220).opacity(0.5)
            .onAppear { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { x = 1 } }
    }
}

public struct CelebrateRings: ViewModifier {
    @Binding var trigger: Bool
    public func body(content: Content) -> some View {
        content.sensoryFeedback(.success, trigger: trigger)
    }
}
