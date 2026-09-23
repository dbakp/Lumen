import SwiftUI

// MARK: - Shared components (one visual vocabulary across the app)

/// Primary action: white capsule, black label. One per screen.
public struct LumenPrimaryButtonStyle: ButtonStyle {
    var fill: Color
    public init(colors: [Color]? = nil) { fill = colors?.first ?? .white }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Secondary action: quiet surface capsule.
public struct LumenTonalButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.surfaceRaised, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

public struct LumenSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondary.opacity(configuration.isPressed ? 0.5 : 1))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Thin progress ring with a rounded cap.
public struct ThinRing: View {
    let progress: Double
    let color: Color
    var width: CGFloat
    public init(progress: Double, color: Color, width: CGFloat = 10) { self.progress = progress; self.color = color; self.width = width }
    public var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: width)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .opacity(progress > 0.005 ? 1 : 0)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.9, dampingFraction: 0.85), value: progress)
        }
    }
}

/// Slim horizontal progress bar.
public struct Bar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 6
    public init(_ progress: Double, color: Color, height: CGFloat = 6) { self.progress = progress; self.color = color; self.height = height }
    public var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                Capsule().fill(color).frame(width: max(height, g.size.width * min(1, max(0, progress))))
                    .animation(.spring(response: 0.7), value: progress)
            }
        }
        .frame(height: height)
    }
}

/// Compact metric tile: label, big value, caption. Tappable when wrapped in a link.
public struct StatTile: View {
    let label: String
    let value: String
    let caption: String
    let color: Color
    var progress: Double?
    public init(_ label: String, value: String, caption: String, color: Color, progress: Double? = nil) {
        self.label = label; self.value = value; self.caption = caption; self.color = color; self.progress = progress
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let progress { Bar(progress, color: color, height: 4) }
            Text(caption).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surface()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityElement(children: .combine)
    }
}

/// List row with optional leading symbol, value and chevron.
public struct LumenRow: View {
    let icon: String?
    let color: Color
    let title: String
    let subtitle: String?
    let value: String?
    var chevron: Bool
    public init(_ title: String, subtitle: String? = nil, value: String? = nil, icon: String? = nil, color: Color = .white, chevron: Bool = true) {
        self.title = title; self.subtitle = subtitle; self.value = value; self.icon = icon; self.color = color; self.chevron = chevron
    }
    public var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(systemName: icon).font(.body.weight(.medium)).foregroundStyle(color).frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(Theme.text)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(.body.monospacedDigit()).foregroundStyle(Theme.secondary) }
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary) }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Groups rows in one surface with hairline separators.
public struct RowGroup<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .surface()
    }
}

public struct RowDivider: View {
    public init() {}
    public var body: some View { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 40) }
}

/// Selectable card row used in onboarding and pickers.
public struct ChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String?
    let selected: Bool
    let action: () -> Void
    public init(icon: String, title: String, subtitle: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.selected = selected; self.action = action
    }
    public var body: some View {
        Button {
            haptic(.light); action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(selected ? .black : .white.opacity(0.8)).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(selected ? .black : .white)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(selected ? .black.opacity(0.6) : Theme.secondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(selected ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
            .animation(.easeOut(duration: 0.18), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Empty state with a single clear next step.
public struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    public init(icon: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.message = message; self.actionTitle = actionTitle; self.action = action
    }
    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .regular)).foregroundStyle(Theme.secondary)
                .padding(.bottom, 4)
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Text(message).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 20)
        .surface()
    }
}

/// Soft breathing glow used on hero moments (onboarding, lock screen).
public struct LumenOrb: View {
    @State private var phase = false
    var size: CGFloat
    public init(size: CGFloat = 180) { self.size = size }
    public var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.calm.opacity(0.55), Theme.sleep.opacity(0.25), .clear], center: .center, startRadius: 2, endRadius: size / 2))
                .scaleEffect(phase ? 1.06 : 0.94)
                .blur(radius: 10)
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.12, height: size * 0.12)
                .blur(radius: 2)
                .shadow(color: .white.opacity(0.8), radius: 12)
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { phase.toggle() } }
        .accessibilityHidden(true)
    }
}
