import SwiftUI

// The syrup van's theme (syrup van design §10): the screens the van reaches take its warm, hand-drawn look instead of
// the night sky's. The colours are the concept picture's own, as `VanPalette` samples them: its peach sky behind
// everything, cream plates with the picture's thick dark-brown outline, dark-brown words, and the gold of home's
// "Set the timer" button for the one primary action.

extension Theme {
    public static let van: Theme = {
        var theme = Theme(colors: .van)
        theme.look = .van
        theme.dial = .van
        // The picture's outlines are thick: every plate, tile and capsule gets one.
        theme.elevation.hairlineWidth = 2.5
        theme.elevation.primaryGlowRadius = 0
        return theme
    }()

    /// Increase Contrast: the secondary words darker, the dividers and tracks stronger.
    public static let vanIncreasedContrast: Theme = {
        var theme = Theme.van
        theme.colors.textSecondary = Color(hex: 0x5A3522)
        theme.colors.divider = Color(hex: 0x3A1C0E, opacity: 0.3)
        theme.colors.track = Color(hex: 0x3A1C0E, opacity: 0.25)
        theme.colors.skeletonStroke = Color(hex: 0x3A1C0E, opacity: 0.55)
        theme.dial = .vanIncreasedContrast
        return theme
    }()
}

extension Theme.Colors {
    /// The van picture's colours.
    public static let van: Theme.Colors = {
        let outline = Color(hex: 0x3A1C0E)
        let gold = Color(hex: 0xEDA04F)
        let syrup = Color(hex: 0xC9662A)
        var colors = Theme.Colors.maple
        colors.background = Color(hex: 0xFFDDC2)
        colors.surface1 = Color(hex: 0xFCEBD3)
        colors.surface2 = Color(hex: 0xF8E1B7)
        colors.textPrimary = outline
        colors.textSecondary = Color(hex: 0x76503A)
        colors.textTertiary = Color(hex: 0xA88468)
        // A plate's outline: solid, as the picture draws them (`Theme.look`).
        colors.hairlineTop = outline
        colors.divider = outline.opacity(0.16)
        colors.track = outline.opacity(0.14)
        colors.skeletonStroke = outline.opacity(0.4)
        colors.skeletonVein = outline.opacity(0.12)
        colors.borderHighlight = outline
        colors.borderSoft = outline
        colors.glowLevel2 = .clear
        colors.reward = syrup
        colors.rewardHalo = syrup.opacity(0.3)
        colors.primaryFillTop = Color(hex: 0xF6C16A)
        colors.primaryFillBottom = gold
        colors.primaryFillTopDim = Color(hex: 0xF6C16A)
        colors.primaryFillBottomDim = gold
        colors.primaryLabel = outline
        colors.primaryBorderTop = outline
        colors.primaryBorderBottom = outline
        colors.primaryGlow = .clear
        colors.primaryDisabledFill = outline.opacity(0.12)
        colors.glassTint = Color(hex: 0xF8E1B7)
        colors.chipFill = outline.opacity(0.06)
        colors.chipSmallFill = outline.opacity(0.08)
        colors.budNeutral = outline.opacity(0.35)
        // A bud's bark is the maple's trunk in the picture.
        colors.scene.barkLight = Color(hex: 0x9A603C)
        colors.scene.barkDark = Color(hex: 0x6E3D24)
        colors.scene.barkTip = Color(hex: 0xAE6E44)
        colors.scene.barkRim = Color(hex: 0xF2B98A, opacity: 0.45)
        // Accents dark enough to read on the cream: the picture's grass, its syrup, a sky blue.
        colors.seasonTints = Theme.SeasonTints(
            spring: Color(hex: 0x6F8F3A),
            summer: Color(hex: 0x4F8A5B),
            autumn: syrup,
            winter: Color(hex: 0x5B7FA6)
        )
        return colors
    }()
}

extension Theme.Dial {
    /// The receipt's and the session's dial on the van's cream: the picture's outline colour where the night's was white,
    /// and a deeper gold, so it reads on light.
    public static let van: Theme.Dial = {
        let text = Theme.Colors.van.textPrimary
        let gold = Color(hex: 0xE0A43A)
        let rest = Color(hex: 0x7F93A8)
        return Theme.Dial(
            plan: text.opacity(0.42),
            ahead: text.opacity(0.16),
            lit: text.opacity(0.88),
            currentLow: 0.55,
            currentHigh: 1,
            rest: rest,
            gap: text.opacity(0.09),
            hold: text,
            off: text.opacity(0.10),
            gold: gold,
            goldSoft: Color(hex: 0xC99A2C, opacity: 0.62),
            goldEdge: Color(hex: 0xFFE8A8, opacity: 0.85),
            goldVein: Color(hex: 0x725811),
            bloom: 0.10,
            goldBloom: gold.opacity(0.18),
            restBloom: rest.opacity(0.12)
        )
    }()

    public static let vanIncreasedContrast: Theme.Dial = {
        let text = Theme.Colors.van.textPrimary
        var dial = Theme.Dial.van
        dial.plan = text.opacity(0.60)
        dial.ahead = text.opacity(0.30)
        dial.lit = text
        dial.currentLow = 1
        dial.gap = text.opacity(0.22)
        dial.off = text.opacity(0.22)
        return dial
    }()
}
