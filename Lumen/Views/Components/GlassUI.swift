import SwiftUI

// MARK: - Lumen design language
// Calm, typographic, dark. Content sits on quiet surfaces; Liquid Glass is reserved
// for the navigation layer (tab bar, toolbars, floating controls) as Apple intends.
// Colour is used for data only — one hue per domain, muted.

public enum Theme {
    public static let bg = Color("Ground")
    public static let surface = Color("Raised")
    public static let surfaceRaised = Color("Raised2")
    public static let hairline = Color("Rule")
    public static let text = Color("Ink")
    public static let secondary = Color("Ink2")
    public static let tertiary = Color("Ink3")
    public static let accent = Color("ActionTeal")
    public static let onAccent = Color("OnAccent")
    public static let sleep = Color(hex: "395B9A")
    public static let move = Color(hex: "B04B31")
    public static let food = Color(hex: "8A631E")
    public static let heart = Color(hex: "A33755")
    public static let water = Color(hex: "176992")
    public static let steps = Color(hex: "24755A")
    public static let calm = accent

    public static let radius: CGFloat = 22
    public static let gutter: CGFloat = 24

    public static func readiness(_ score: Int?) -> Color {
        guard let score else { return tertiary }
        return score >= 80 ? steps : score >= 65 ? calm : score >= 50 ? food : move
    }
}

/// Screen background: near-black with one soft glow in the section's hue.
public struct AuroraBackground: View {
    var hue: Color
    public init(_ hue: Color = Theme.calm) { self.hue = hue }
    public var body: some View {
        Theme.bg
        .ignoresSafeArea()
    }
}

public extension View {
    /// Quiet content surface (kept under its old name so every screen adopts it).
    func liquidGlass(cornerRadius: CGFloat = Theme.radius, tintOpacity: Double = 0.14) -> some View {
        self.background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
    }

    func surface(_ radius: CGFloat = Theme.radius) -> some View {
        self.background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
    }

    func cardPadding() -> some View { self.padding(18) }

    /// Standard screen chrome: background + hidden scroll indicators.
    func lumenScreen(_ hue: Color = Theme.calm) -> some View {
        self.scrollIndicators(.hidden).foregroundStyle(Theme.text).background(AuroraBackground(hue))
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
