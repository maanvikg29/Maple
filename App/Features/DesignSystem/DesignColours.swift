#if DEBUG
import SwiftUI
import MapleCore
import MapleDesign

/// One colour token: its name, the live value from the theme and its one job (spec §6.1).
private struct Swatch: Identifiable {
    var id: String { name }
    let name: String
    let color: Color
    let role: String
}

private struct SwatchGroup: Identifiable {
    var id: String { title }
    let title: String
    let swatches: [Swatch]
}

/// Every colour in the current theme (Increase Contrast shows its overrides), two to a row, with the hex value read
/// back from the token itself so the page can never drift from `Tokens.swift`.
struct DesignColours: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    DesignGroupLabel(group.title)
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: theme.spacing.gutter, alignment: .top),
                                  GridItem(.flexible(), spacing: theme.spacing.gutter, alignment: .top)],
                        alignment: .leading, spacing: theme.spacing.md
                    ) {
                        ForEach(group.swatches) { SwatchCell(swatch: $0) }
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.bottom, theme.spacing.lg)
    }

    private var groups: [SwatchGroup] {
        let c = theme.colors
        let s = c.scene
        return [
            SwatchGroup(title: "Surfaces and text", swatches: [
                Swatch(name: "background", color: c.background, role: "Every screen"),
                Swatch(name: "surface1", color: c.surface1, role: "Level-1 tiles and rows"),
                Swatch(name: "surface2", color: c.surface2, role: "Sheets, selected chips, avatar, pressed Level 1"),
                Swatch(name: "textPrimary", color: c.textPrimary, role: "Primary text"),
                Swatch(name: "textSecondary", color: c.textSecondary, role: "Secondary text"),
                Swatch(name: "textTertiary", color: c.textTertiary, role: "Decorative only, never text"),
            ]),
            SwatchGroup(title: "Lines and borders", swatches: [
                Swatch(name: "hairlineTop", color: c.hairlineTop, role: "Level-1 top-lit stroke"),
                Swatch(name: "divider", color: c.divider, role: "Row separators"),
                Swatch(name: "track", color: c.track, role: "Progress tracks"),
                Swatch(name: "skeletonStroke", color: c.skeletonStroke, role: "Locked leaf outline"),
                Swatch(name: "skeletonVein", color: c.skeletonVein, role: "Locked leaf veins"),
                Swatch(name: "borderHighlight", color: c.borderHighlight, role: "Level 2 and glass, top"),
                Swatch(name: "borderSoft", color: c.borderSoft, role: "Level 2 and glass, bottom"),
                Swatch(name: "glowLevel2", color: c.glowLevel2, role: "Share card glow only"),
            ]),
            SwatchGroup(title: "Reward", swatches: [
                Swatch(name: "reward", color: c.reward, role: "Reward only: streak, waiting bud, owned bar"),
                Swatch(name: "rewardHalo", color: c.rewardHalo, role: "Reward only: new-leaf halo"),
            ]),
            SwatchGroup(title: "Primary capsule", swatches: [
                Swatch(name: "primaryFillTop", color: c.primaryFillTop, role: "Fill, top"),
                Swatch(name: "primaryFillBottom", color: c.primaryFillBottom, role: "Fill, bottom"),
                Swatch(name: "primaryFillTopDim", color: c.primaryFillTopDim, role: "Evening fill, top"),
                Swatch(name: "primaryFillBottomDim", color: c.primaryFillBottomDim, role: "Evening fill, bottom"),
                Swatch(name: "primaryLabel", color: c.primaryLabel, role: "Label, 11:1 on the fill"),
                Swatch(name: "primaryBorderTop", color: c.primaryBorderTop, role: "Border, top"),
                Swatch(name: "primaryBorderBottom", color: c.primaryBorderBottom, role: "Border, bottom"),
                Swatch(name: "primaryGlow", color: c.primaryGlow, role: "Glow, r 20"),
                Swatch(name: "primaryDisabledFill", color: c.primaryDisabledFill, role: "Disabled fill"),
            ]),
            SwatchGroup(title: "Glass, chips and buds", swatches: [
                Swatch(name: "glassTint", color: c.glassTint, role: "Glass capsules and circles"),
                Swatch(name: "chipFill", color: c.chipFill, role: "Unselected chips"),
                Swatch(name: "chipSmallFill", color: c.chipSmallFill, role: "Tier and small chips"),
                Swatch(name: "budNeutral", color: c.budNeutral, role: "Locked buds"),
            ]),
            SwatchGroup(title: "Season tints", swatches: Season.allCases.map { season in
                Swatch(name: "seasonTint.\(season.rawValue)", color: c.seasonTint(season), role: "The one accent in \(season.rawValue)")
            }),
            SwatchGroup(title: "Scene", swatches: [
                Swatch(name: "skyNight", color: s.skyNight, role: "Night sky"),
                Swatch(name: "skyNavy", color: s.skyNavy, role: "Morning and day sky, top"),
                Swatch(name: "skyDay", color: s.skyDay, role: "Day sky, middle"),
                Swatch(name: "skyDeep", color: s.skyDeep, role: "Night sky, lower"),
                Swatch(name: "dawnWash", color: s.dawnWash, role: "Morning horizon wash"),
                Swatch(name: "dawnPool", color: s.dawnPool, role: "Morning light pool"),
                Swatch(name: "moonlight", color: s.moonlight, role: "Moonlight pools"),
                Swatch(name: "moonDisc", color: s.moonDisc, role: "The moon"),
                Swatch(name: "ground", color: s.ground, role: "Ground mound"),
                Swatch(name: "groundRim", color: s.groundRim, role: "Ground crest"),
                Swatch(name: "barkLight", color: s.barkLight, role: "Bark, moonlit side"),
                Swatch(name: "barkDark", color: s.barkDark, role: "Bark, shaded side"),
                Swatch(name: "barkTip", color: s.barkTip, role: "Thin tips"),
                Swatch(name: "barkRim", color: s.barkRim, role: "Moon-facing bark edge"),
                Swatch(name: "contactShadow", color: s.contactShadow, role: "The only shadow"),
                Swatch(name: "samara", color: s.samara, role: "Autumn seeds"),
                Swatch(name: "firefly", color: s.firefly, role: "Summer evenings"),
                Swatch(name: "pollen", color: s.pollen, role: "Spring motes"),
                Swatch(name: "cotyledon", color: s.cotyledon, role: "The onboarding sprout"),
            ]),
        ]
    }
}

private struct SwatchCell: View {
    @Environment(\.theme) private var theme
    let swatch: Swatch

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            Circle()
                .fill(swatch.color)
                .overlay { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(swatch.name)
                    .font(MapleFont.tileName)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(DesignHex.describe(swatch.color))
                    .font(MapleFont.tileMeta)
                    .foregroundStyle(theme.colors.textSecondary)
                Text(swatch.role)
                    .font(MapleFont.tileMeta)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "#E8A35C", or "#E8A35C · 30%" for a translucent token, read back from the resolved colour.
enum DesignHex {
    static func describe(_ color: Color) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        let hex = String(format: "#%02X%02X%02X", channel(resolved.linearRed), channel(resolved.linearGreen),
                         channel(resolved.linearBlue))
        let opacity = Int((Double(resolved.opacity) * 100).rounded())
        return opacity >= 100 ? hex : "\(hex) · \(opacity)%"
    }

    /// A linear sRGB channel as an 8-bit gamma-encoded value.
    private static func channel(_ linear: Float) -> Int {
        let value = Double(min(max(linear, 0), 1))
        let encoded = value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
        return Int((encoded * 255).rounded())
    }
}
#endif
