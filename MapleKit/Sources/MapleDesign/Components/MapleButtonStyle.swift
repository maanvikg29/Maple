import SwiftUI

/// Maple's key-action button: full width, bordered and glowing like a card. Not amber; amber is for rewards.
public struct MapleButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, secondary }

    private let kind: Kind

    public init(_ kind: Kind = .primary) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind)
    }

    private struct StyledButton: View {
        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let kind: Kind

        var body: some View {
            configuration.label
                .font(MapleFont.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, theme.spacing.md)
                .modifier(Surface(kind: kind, pressed: configuration.isPressed))
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .mapleAnimation(theme.motion.gentle, value: configuration.isPressed)
        }
    }

    private struct Surface: ViewModifier {
        @Environment(\.theme) private var theme
        let kind: Kind
        let pressed: Bool

        func body(content: Content) -> some View {
            switch kind {
            case .primary:
                content.glowSurface(
                    cornerRadius: theme.radius.control,
                    fill: pressed ? theme.colors.surface : theme.colors.surfaceRaised
                )
            case .secondary:
                content.background(
                    RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                        .strokeBorder(theme.colors.borderSoft, lineWidth: theme.glow.borderWidth)
                )
            }
        }
    }
}

extension ButtonStyle where Self == MapleButtonStyle {
    public static var maple: MapleButtonStyle { MapleButtonStyle(.primary) }
    public static var mapleSecondary: MapleButtonStyle { MapleButtonStyle(.secondary) }
}
