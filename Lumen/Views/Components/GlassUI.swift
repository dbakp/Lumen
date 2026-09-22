import SwiftUI

// MARK: - Liquid Glass design system (iOS 26 glassEffect + graceful fallback)

public struct AuroraBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.09).ignoresSafeArea()
            // Deep aurora blobs.
            RadialGradient(colors: [.indigo.opacity(0.55), .clear], center: .topLeading, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()
            RadialGradient(colors: [.teal.opacity(0.35), .clear], center: .topTrailing, startRadius: 20, endRadius: 560)
                .ignoresSafeArea()
            RadialGradient(colors: [.purple.opacity(0.30), .clear], center: .bottom, startRadius: 40, endRadius: 620)
                .ignoresSafeArea()
            // Starfield shimmer.
            StarsView().opacity(0.5).ignoresSafeArea()
        }
    }
}

private struct StarsView: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                for i in 0..<90 {
                    let x = Double((i * 137) % Int(size.width + 1))
                    let y = Double((i * 251) % Int(size.height + 1))
                    let r: Double = i % 7 == 0 ? 1.6 : 0.8
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.5)))
                }
            }
        }
    }
}

public extension View {
    /// Premium glass card. Uses iOS 26 Liquid Glass when available.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 26, tintOpacity: Double = 0.14) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(.white.opacity(tintOpacity)), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
    }

    func cardPadding() -> some View {
        self.padding(18)
    }
}

public struct GlassCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .cardPadding()
            .liquidGlass()
    }
}

public struct SectionHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    public init(_ title: String, subtitle: String? = nil, systemImage: String = "sparkles") {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage
    }
    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .liquidGlass(cornerRadius: 10, tintOpacity: 0.2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).foregroundStyle(.white)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6)) }
            }
            Spacer()
        }
    }
}

public func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Color helpers

public extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
