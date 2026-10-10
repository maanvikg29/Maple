import SwiftUI

/// The one primary action on a screen: a moonlit capsule (spec §7.3, D11).
///
/// ```swift
/// Button("Start wind-down") { … }
///     .buttonStyle(.moonlight(dimmed: phase.isEvening))
/// ```
///
/// - 52pt minimum height, as wide as it is offered (Home offers the screen minus its 24pt margins), growing
///   with Dynamic Type; the label wraps to two lines at accessibility sizes.
/// - A vertical `primaryFillTop` → `primaryFillBottom` gradient (the dimmed pair in evening and wind-down),
///   a 1pt `primaryBorderTop` → `primaryBorderBottom` edge and the soft `primaryGlow`.
/// - Pressed: 0.98 scale and 6% darker over `press` (no scale under Reduce Motion).
/// - Disabled: a flat `primaryDisabledFill` with a `textSecondary` label, no edge and no glow.
///
/// It is the only bordered-and-glowing element on its screen, so use at most one, and never on the share card.
public struct MoonlightButtonStyle: ButtonStyle {
    /// The quieter fill used in the evening and wind-down phases.
    public var dimmed: Bool

    public init(dimmed: Bool = false) {
        self.dimmed = dimmed
    }

    public func makeBody(configuration: Configuration) -> some View {
        MoonlightButton(configuration: configuration, dimmed: dimmed)
    }
}

extension ButtonStyle where Self == MoonlightButtonStyle {
    /// The primary capsule.
    public static var moonlight: MoonlightButtonStyle { MoonlightButtonStyle() }

    /// The primary capsule; `dimmed` in the evening and wind-down phases.
    public static func moonlight(dimmed: Bool) -> MoonlightButtonStyle {
        MoonlightButtonStyle(dimmed: dimmed)
    }
}

private struct MoonlightButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let configuration: ButtonStyleConfiguration
    let dimmed: Bool

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .font(MapleFont.buttonLabel)
            .foregroundStyle(isEnabled ? theme.colors.primaryLabel : theme.colors.textSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background { background(pressed: pressed) }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .mapleAnimation(theme.motion.press, value: pressed)
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        let capsule = Capsule(style: .continuous)
        let colors = theme.colors
        if isEnabled {
            capsule
                .fill(LinearGradient(
                    colors: dimmed ? [colors.primaryFillTopDim, colors.primaryFillBottomDim]
                        : [colors.primaryFillTop, colors.primaryFillBottom],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay { capsule.fill(.black.opacity(pressed ? 0.06 : 0)) }
                .overlay {
                    capsule.strokeBorder(
                        LinearGradient(colors: [colors.primaryBorderTop, colors.primaryBorderBottom],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: theme.elevation.hairlineWidth
                    )
                }
                .shadow(color: colors.primaryGlow, radius: theme.elevation.primaryGlowRadius)
        } else {
            capsule.fill(colors.primaryDisabledFill)
        }
    }
}
