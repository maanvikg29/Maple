import SwiftUI

/// The standard Maple container: navy surface, thin white-to-blue border, faint outer glow.
public struct GlowCard<Content: View>: View {
    @Environment(\.theme) private var theme
    private let padding: CGFloat?
    private let content: Content

    public init(padding: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding ?? theme.spacing.lg)
            .glowSurface(cornerRadius: theme.radius.card)
    }
}

extension View {
    /// Gives any view Maple's bordered, softly glowing surface treatment.
    public func glowSurface(cornerRadius: CGFloat, fill: Color? = nil) -> some View {
        modifier(GlowSurface(cornerRadius: cornerRadius, fill: fill))
    }
}

private struct GlowSurface: ViewModifier {
    @Environment(\.theme) private var theme
    let cornerRadius: CGFloat
    let fill: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(fill ?? theme.colors.surface, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [theme.colors.borderHighlight, theme.colors.borderSoft],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: theme.glow.borderWidth
                )
            }
            .shadow(color: theme.colors.glow, radius: theme.glow.radius, y: theme.glow.y)
    }
}
