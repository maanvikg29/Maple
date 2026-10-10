import SwiftUI

/// How much a container lifts off the black (spec §6.5). Black does the work: most things are Level 0.
nonisolated public enum SurfaceLevel: Sendable, Hashable, CaseIterable {
    /// No fill, no edge. The default: Home's first screen, section headers, specimen rows on black.
    case level0
    /// `surface1` fill with a 1pt inner hairline lit from the top. No glow, no shadow. Tiles, cards, rows.
    case level1
    /// `surface1` fill, 1pt `borderHighlight` → `borderSoft` edge and the `glowLevel2` glow. Share card only.
    case level2
}

extension View {
    /// Places the view on a Maple surface: the replacement for cards with glows.
    ///
    /// ```swift
    /// StatusTile().padding(20).surface(.level1, radius: theme.radius.largeTile)
    /// ```
    ///
    /// - Parameters:
    ///   - radius: A token from `Theme.Radius` (20, 28 or 40); corners are always continuous.
    ///   - pressed: Level 1 only: the pressed fill (`surface2`), for tiles that act as buttons.
    public func surface(_ level: SurfaceLevel, radius: CGFloat, pressed: Bool = false) -> some View {
        modifier(SurfaceModifier(level: level, radius: radius, pressed: pressed))
    }
}

private struct SurfaceModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let level: SurfaceLevel
    let radius: CGFloat
    let pressed: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch level {
        case .level0:
            content
        case .level1:
            content
                .background {
                    shape.fill(pressed ? theme.colors.surface2 : theme.colors.surface1)
                }
                .overlay {
                    shape.strokeBorder(theme.topLitHairline, lineWidth: theme.elevation.hairlineWidth)
                        .allowsHitTesting(false)
                }
        case .level2:
            content
                .background {
                    shape.fill(theme.colors.surface1)
                        .shadow(color: theme.colors.glowLevel2, radius: theme.elevation.level2GlowRadius)
                }
                .overlay {
                    shape.strokeBorder(theme.edgeGradient, lineWidth: theme.elevation.hairlineWidth)
                        .allowsHitTesting(false)
                }
        }
    }
}

extension Theme {
    /// The Level-1 inner stroke: `hairlineTop` fading to clear at `elevation.hairlineFade` of the height.
    var topLitHairline: LinearGradient {
        topLitHairline(colors.hairlineTop)
    }

    /// A top-lit inner stroke in `color`, fading to clear at `elevation.hairlineFade` of the height.
    /// Selected chips and segment thumbs use it at white 14%.
    func topLitHairline(_ color: Color) -> LinearGradient {
        LinearGradient(
            stops: [.init(color: color, location: 0), .init(color: color.opacity(0), location: elevation.hairlineFade)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// The Level-2 and glass edge: `borderHighlight` at the top to `borderSoft` at the bottom.
    var edgeGradient: LinearGradient {
        LinearGradient(colors: [colors.borderHighlight, colors.borderSoft], startPoint: .top, endPoint: .bottom)
    }

    /// The hairline on selected chips and segment thumbs (spec §7.3): white 14%, 6 points above `hairlineTop`,
    /// so it rises with it under Increase Contrast (8% → 24% gives 30%).
    var selectedHairline: Color {
        .white.opacity(max(0.14, colors.hairlineTop.opacityValue + 0.06))
    }
}

extension Color {
    /// The colour's own opacity (0...1), for tokens derived from other tokens.
    var opacityValue: Double {
        Double(resolve(in: EnvironmentValues()).opacity)
    }
}
