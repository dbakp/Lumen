import SwiftUI

// MARK: - Shared buttons, chips and empty states

public struct LumenPrimaryButtonStyle: ButtonStyle {
    var colors: [Color] = [Color(red: 0.36, green: 0.86, blue: 0.98), Color(red: 0.55, green: 0.45, blue: 1.0)]
    public init(colors: [Color]? = nil) { if let colors { self.colors = colors } }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: Capsule())
            .shadow(color: colors[0].opacity(configuration.isPressed ? 0.2 : 0.45), radius: configuration.isPressed ? 6 : 18, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public struct LumenSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.75))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Selectable card row used across onboarding and settings.
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
                Image(systemName: icon).font(.title3)
                    .foregroundStyle(selected ? .cyan : .white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background((selected ? Color.cyan : .white).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.leading) }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? .cyan : .white.opacity(0.3))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(14)
            .liquidGlass(cornerRadius: 20, tintOpacity: selected ? 0.22 : 0.08)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? Color.cyan.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Friendly empty state with a single clear next step.
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
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 30, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom))
                .frame(width: 64, height: 64)
                .liquidGlass(cornerRadius: 32, tintOpacity: 0.15)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.18), in: Capsule())
                    .foregroundStyle(.cyan)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22).padding(.horizontal, 16)
        .liquidGlass()
    }
}

/// Soft glowing orb used on hero screens.
public struct LumenOrb: View {
    @State private var phase = false
    var size: CGFloat
    public init(size: CGFloat = 180) { self.size = size }
    public var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.cyan.opacity(0.9), .purple.opacity(0.6), .clear], center: .center, startRadius: 4, endRadius: size / 2))
                .blur(radius: 18)
                .scaleEffect(phase ? 1.08 : 0.92)
            Circle()
                .fill(AngularGradient(colors: [.cyan, .purple, .pink, .cyan], center: .center))
                .frame(width: size * 0.42, height: size * 0.42)
                .blur(radius: 6)
                .rotationEffect(.degrees(phase ? 360 : 0))
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: size * 0.16, height: size * 0.16)
                .blur(radius: 3)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { phase.toggle() }
        }
        .accessibilityHidden(true)
    }
}
