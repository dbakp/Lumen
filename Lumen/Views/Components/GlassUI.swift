import SwiftUI

// MARK: - Lumen design language
// Calm, typographic, dark. Content sits on quiet surfaces; Liquid Glass is reserved
// for the navigation layer (tab bar, toolbars, floating controls) as Apple intends.
// Colour is used for data only — one hue per domain, muted.

public enum Theme {
    public static let bg = Color(red: 0.035, green: 0.035, blue: 0.045)
    public static let surface = Color.white.opacity(0.055)
    public static let surfaceRaised = Color.white.opacity(0.085)
    public static let hairline = Color.white.opacity(0.07)
    public static let text = Color.white
    public static let secondary = Color.white.opacity(0.62)
    public static let tertiary = Color.white.opacity(0.4)

    // Domain hues
    public static let sleep = Color(red: 0.62, green: 0.58, blue: 1.0)
    public static let move = Color(red: 1.0, green: 0.45, blue: 0.40)
    public static let food = Color(red: 1.0, green: 0.72, blue: 0.38)
    public static let heart = Color(red: 1.0, green: 0.42, blue: 0.55)
    public static let water = Color(red: 0.43, green: 0.72, blue: 1.0)
    public static let steps = Color(red: 0.50, green: 0.89, blue: 0.79)
    public static let calm = Color(red: 0.55, green: 0.85, blue: 0.95)

    public static let radius: CGFloat = 22
    public static let gutter: CGFloat = 20

    public static func readiness(_ score: Int?) -> Color {
        guard let score else { return .white.opacity(0.35) }
        return score >= 80 ? steps : score >= 65 ? calm : score >= 50 ? food : move
    }
}

/// Screen background: near-black with one soft glow in the section's hue.
public struct AuroraBackground: View {
    var hue: Color
    public init(_ hue: Color = Theme.calm) { self.hue = hue }
    public var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [hue.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: -0.1), startRadius: 10, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

public extension View {
    /// Quiet content surface (kept under its old name so every screen adopts it).
    func liquidGlass(cornerRadius: CGFloat = Theme.radius, tintOpacity: Double = 0.14) -> some View {
        self.background(Color.white.opacity(0.03 + tintOpacity * 0.18), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
    }

    func surface(_ radius: CGFloat = Theme.radius) -> some View {
        self.background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
    }

    func cardPadding() -> some View { self.padding(18) }

    /// Standard screen chrome: background + hidden scroll indicators.
    func lumenScreen(_ hue: Color = Theme.calm) -> some View {
        self.scrollIndicators(.hidden).background(AuroraBackground(hue))
    }
}

public struct GlassCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardPadding()
            .surface()
    }
}

/// Section title: quiet, sentence case, optional trailing action.
public struct SectionHeader: View {
    let title: String
    let subtitle: String?
    public init(_ title: String, subtitle: String? = nil, systemImage: String = "") {
        self.title = title; self.subtitle = subtitle
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).foregroundStyle(Theme.text)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small label above a group of content, outside cards.
public struct GroupLabel: View {
    let text: String
    var action: (title: String, run: () -> Void)?
    public init(_ text: String, action: (title: String, run: () -> Void)? = nil) { self.text = text; self.action = action }
    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            Spacer()
            if let action {
                Button(action.title, action: action.run).font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.top, 8)
    }
}

public func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Color helpers

public extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: Double
        if h.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        } else {
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
