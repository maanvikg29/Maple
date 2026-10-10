#if DEBUG
import SwiftUI
import MapleCore
import MapleDesign

/// Levels 0, 1 and 2 side by side (spec §6.5).
struct DesignSurfaces: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.gutter) {
            sample(.level0, title: "Level 0", detail: "No fill, no edge. The default.")
            sample(.level1, title: "Level 1", detail: "surface1 and a top-lit hairline.")
            sample(.level2, title: "Level 2", detail: "Edge and glow. Share card only.")
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.bottom, theme.spacing.lg)
    }

    private func sample(_ level: SurfaceLevel, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            Text(title)
                .font(MapleFont.tileName)
                .foregroundStyle(theme.colors.textPrimary)
            Text(detail)
                .font(MapleFont.tileMeta)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(theme.spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .surface(level, radius: theme.radius.tile)
        .overlay {
            if level == .level0 {
                // Level 0 has no edge; a dashed outline only marks the sample's bounds here.
                RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous)
                    .strokeBorder(theme.colors.divider, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }
}

/// The numeral scale and the full type ramp, each with its token and size (spec §6.2).
struct DesignType: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                DesignGroupLabel("Numerals")
                numeral(StatNumber([.value("1"), .unit("h"), .value("20"), .unit("m")], size: .hero), "hero · 64, units 32, max 88")
                numeral(StatNumber("72", size: .score), "score · 48, max 72")
                numeral(StatNumber("23", size: .stat), "stat · 34")
                numeral(StatNumber("14", size: .total), "total · 28 (Profile)")
                numeral(StatNumber("9", size: .inline), "inline · 17")
            }
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                DesignGroupLabel("Ramp")
                ramp("Young maple", MapleFont.screenTitle, "screenTitle · 28 rounded semibold", tracking: -0.3)
                ramp("Red maple", MapleFont.leafTitle, "leafTitle · 28 rounded semibold", tracking: -0.3)
                ramp("Almost there", MapleFont.sectionTitle, "sectionTitle · 20 rounded semibold")
                ramp("Start wind-down", MapleFont.headline, "headline, buttonLabel · 17 rounded semibold")
                ramp("Keep bedtime 14 nights in a row.", MapleFont.body, "body · 17 SF Pro")
                ramp("Autumn", MapleFont.contextEmphasis, "contextEmphasis · 15 rounded semibold", tint: true)
                ramp("until wind-down · bed 23:00", MapleFont.callout, "callout · 15 SF Pro", secondary: true)
                ramp("In bed within 15 minutes of your bedtime.", MapleFont.footnote, "footnote · 13 SF Pro", secondary: true)
                ramp("Paperbark maple", MapleFont.tileName, "tileName · 13 rounded semibold")
                ramp("9 of 14", MapleFont.tileMeta, "tileMeta · 12 SF Pro, monospaced digits", secondary: true)
                ramp("≈ Uncharted", MapleFont.micro, "micro · 11 rounded medium, chips only", secondary: true)
            }
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                DesignGroupLabel("New York italic, scientific names only")
                ramp("Acer rubrum", MapleFont.scientific(.title, weight: .semibold), "scientific(.title) · 28, a title without a common name")
                ramp("Acer rubrum", MapleFont.scientific(.body), "scientific(.body) · 17", secondary: true)
                ramp("Acer rubrum", MapleFont.scientific(.subheadline), "scientific(.subheadline) · 15", secondary: true)
                ramp("Acer rubrum", MapleFont.scientific(.footnote), "scientific(.footnote) · 13")
            }
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.bottom, theme.spacing.lg)
    }

    private func numeral(_ number: StatNumber, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            number
            DesignCaption(caption)
        }
    }

    private func ramp(
        _ sample: String, _ font: Font, _ caption: String, tracking: CGFloat = 0, secondary: Bool = false,
        tint: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sample)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(tint ? theme.colors.seasonTint(season)
                    : secondary ? theme.colors.textSecondary : theme.colors.textPrimary)
            DesignCaption(caption)
        }
    }
}
#endif
