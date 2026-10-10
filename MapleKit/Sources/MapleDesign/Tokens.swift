import SwiftUI
import MapleCore

// Every visual decision in Maple lives in this file (design spec §6, docs/design/spec.md).
// Views read the current `Theme` from the environment (`@Environment(\.theme)`), so a future theme
// only has to supply a different value.
//
// Ground rules the tokens encode:
// - Black does the work. Containers never glow; light comes from content (the tree, leaves, the moon).
// - Amber (`reward`) means "you earned something" and appears only in the places listed in spec §1.3.
// - The season tint is the only other accent.

public struct Theme: Sendable {
    public var colors: Colors
    public var spacing: Spacing
    public var radius: Radius
    public var motion: Motion
    /// Surface levels and the caps on every content glow (spec §6.5).
    public var elevation = Elevation()

    public init(colors: Colors, spacing: Spacing = Spacing(), radius: Radius = Radius(), motion: Motion = Motion()) {
        self.colors = colors
        self.spacing = spacing
        self.radius = radius
        self.motion = motion
    }

    public static let maple = Theme(colors: .maple)
    /// Used when the system's Increase Contrast setting is on.
    public static let mapleIncreasedContrast = Theme(colors: .mapleIncreasedContrast)
}

// MARK: - Colours

extension Theme {
    public struct Colors: Sendable {
        public var background: Color
        /// Level-1 tiles.
        public var surface1: Color
        /// Sheets, selected chips and segment thumbs, the avatar disc, pressed Level 1, glass fallback.
        public var surface2: Color
        public var textPrimary: Color
        public var textSecondary: Color
        /// Decorative strokes and ticks only. Never text.
        public var textTertiary: Color
        /// Level-1 top-lit inner stroke: this colour fading to clear at 40% of the height.
        public var hairlineTop: Color
        public var divider: Color
        public var track: Color
        public var skeletonStroke: Color
        public var skeletonVein: Color
        public var borderHighlight: Color
        public var borderSoft: Color
        /// Level 2 (share card) only.
        public var glowLevel2: Color
        /// Amber. Reward whitelist only (spec §1.3).
        public var reward: Color
        public var rewardHalo: Color
        public var primaryFillTop: Color
        public var primaryFillBottom: Color
        public var primaryFillTopDim: Color
        public var primaryFillBottomDim: Color
        public var primaryLabel: Color
        public var primaryBorderTop: Color
        public var primaryBorderBottom: Color
        public var primaryGlow: Color
        public var primaryDisabledFill: Color
        public var glassTint: Color
        public var chipFill: Color
        public var chipSmallFill: Color
        public var budNeutral: Color
        public var seasonTints: SeasonTints
        public var scene: SceneColors

        /// The accent for the current season: progress hairlines, the header's season word, insight highlights.
        public func seasonTint(_ season: Season) -> Color {
            seasonTints.color(for: season)
        }
    }

    public struct SeasonTints: Sendable {
        public var spring: Color
        public var summer: Color
        public var autumn: Color
        public var winter: Color

        public func color(for season: Season) -> Color {
            switch season {
            case .spring: spring
            case .summer: summer
            case .autumn: autumn
            case .winter: winter
            }
        }
    }

    /// Colours used only by the tree scene (spec §4.4).
    public struct SceneColors: Sendable {
        public var skyNight: Color
        public var skyNavy: Color
        public var skyDay: Color
        public var skyDeep: Color
        public var dawnWash: Color
        public var dawnPool: Color
        public var moonlight: Color
        public var moonDisc: Color
        public var ground: Color
        public var groundRim: Color
        public var barkLight: Color
        public var barkDark: Color
        public var barkTip: Color
        public var barkRim: Color
        public var contactShadow: Color
        public var samara: Color
        public var firefly: Color
        public var pollen: Color
        public var cotyledon: Color
    }
}

extension Theme.Colors {
    public static let maple = Theme.Colors(
        background: Color(hex: 0x05070D),
        surface1: Color(hex: 0x0C1527),
        surface2: Color(hex: 0x111D35),
        textPrimary: Color(hex: 0xF2F5FA),
        textSecondary: Color(hex: 0x8A96AD),
        textTertiary: Color(hex: 0x5A6680),
        hairlineTop: .white.opacity(0.08),
        divider: .white.opacity(0.06),
        track: .white.opacity(0.08),
        skeletonStroke: Color(hex: 0x8A96AD, opacity: 0.35),
        skeletonVein: .white.opacity(0.10),
        borderHighlight: .white.opacity(0.22),
        borderSoft: Color(hex: 0x9DB4E6, opacity: 0.10),
        glowLevel2: Color(hex: 0x7F9FE0, opacity: 0.08),
        reward: Color(hex: 0xE8A35C),
        rewardHalo: Color(hex: 0xE8A35C, opacity: 0.30),
        primaryFillTop: Color(hex: 0xE2E8F2),
        primaryFillBottom: Color(hex: 0xB4C0D6),
        primaryFillTopDim: Color(hex: 0xCBD3E2),
        primaryFillBottomDim: Color(hex: 0xA2AEC6),
        primaryLabel: Color(hex: 0x05070D),
        primaryBorderTop: .white.opacity(0.45),
        primaryBorderBottom: Color(hex: 0x9DB4E6, opacity: 0.20),
        primaryGlow: Color(hex: 0x9DB4E6, opacity: 0.10),
        primaryDisabledFill: .white.opacity(0.12),
        glassTint: Color(hex: 0x0B1426, opacity: 0.30),
        chipFill: .white.opacity(0.05),
        chipSmallFill: .white.opacity(0.06),
        budNeutral: Color(hex: 0xC9D3E3, opacity: 0.45),
        seasonTints: Theme.SeasonTints(
            spring: Color(hex: 0xBFD8A6),
            summer: Color(hex: 0x9CC3A4),
            autumn: Color(hex: 0xE3A49E),
            winter: Color(hex: 0xC9DDEE)
        ),
        scene: Theme.SceneColors(
            skyNight: Color(hex: 0x05070D),
            skyNavy: Color(hex: 0x0B1426),
            skyDay: Color(hex: 0x111D35),
            skyDeep: Color(hex: 0x080D19),
            dawnWash: Color(hex: 0x3B2F3F, opacity: 0.10),
            dawnPool: Color(hex: 0xF2E6D8, opacity: 0.05),
            moonlight: Color(hex: 0xAFC3E8),
            moonDisc: Color(hex: 0xE9EEF7, opacity: 0.55),
            ground: Color(hex: 0x070B14),
            groundRim: Color(hex: 0x9DB4E6, opacity: 0.14),
            barkLight: Color(hex: 0x2A3348),
            barkDark: Color(hex: 0x121826),
            barkTip: Color(hex: 0x3A4663),
            barkRim: Color(hex: 0xA9BEE3, opacity: 0.25),
            contactShadow: .black.opacity(0.55),
            samara: Color(hex: 0xB89A72, opacity: 0.55),
            firefly: Color(hex: 0xD9E6A8, opacity: 0.35),
            pollen: Color(hex: 0xE8F0C0, opacity: 0.12),
            cotyledon: Color(hex: 0x6E8F6A, opacity: 0.70)
        )
    )

    /// Increase Contrast overrides (spec §6.1).
    public static let mapleIncreasedContrast: Theme.Colors = {
        var colors = Theme.Colors.maple
        colors.textSecondary = Color(hex: 0xA3AEC2)
        colors.hairlineTop = .white.opacity(0.24)
        colors.divider = .white.opacity(0.16)
        colors.track = .white.opacity(0.16)
        colors.skeletonStroke = Color(hex: 0x8A96AD, opacity: 0.55)
        colors.borderHighlight = .white.opacity(0.40)
        colors.borderSoft = Color(hex: 0x9DB4E6, opacity: 0.25)
        return colors
    }()
}

// MARK: - Layout

extension Theme {
    /// A 4-point scale. Spacing is never uniform: heroes get air, rows sit 12 apart, groups 32 apart.
    public struct Spacing: Sendable {
        public var xxs: CGFloat = 4
        public var xs: CGFloat = 8
        public var sm: CGFloat = 12
        public var md: CGFloat = 16
        public var lg: CGFloat = 24
        public var xl: CGFloat = 32
        public var xxl: CGFloat = 40
        public var xxxl: CGFloat = 48
        public var hero: CGFloat = 56

        public var homeMargin: CGFloat = 24
        public var gridMargin: CGFloat = 16
        public var listMargin: CGFloat = 20
        public var row: CGFloat = 56
        public var labelRow: CGFloat = 48
        public var gutter: CGFloat = 10
        public var rowGap: CGFloat = 12
        public var groupGap: CGFloat = 32
        public var sectionGap: CGFloat = 24
        public var minimumHitTarget: CGFloat = 44

        public init() {}
    }

    /// All rounded rectangles use `style: .continuous`. Buttons and chips are capsules; icon buttons are circles.
    public struct Radius: Sendable {
        public var tile: CGFloat = 20
        public var largeTile: CGFloat = 28
        public var shareCard: CGFloat = 40

        public init() {}
    }

    /// Elevation and glow (spec §6.5). Containers never cast shadows: Level 1 is a fill and a top-lit
    /// hairline, and only the Level-2 share-card frame and the primary capsule glow. Light otherwise comes
    /// from content, within these caps.
    public struct Elevation: Sendable {
        /// Width of the Level-1 inner hairline and of every Level-2 / glass border.
        public var hairlineWidth: CGFloat = 1
        /// The Level-1 hairline fades from `hairlineTop` to clear at this fraction of the height.
        public var hairlineFade: CGFloat = 0.4
        /// `glowLevel2` blur radius (share-card frame only).
        public var level2GlowRadius: CGFloat = 24
        /// `primaryGlow` blur radius (the primary capsule).
        public var primaryGlowRadius: CGFloat = 20

        // Content glow caps, as opacities.
        public var treeBloomCap: Double = 0.18
        public var tileLeafBloomCap: Double = 0.18
        public var detailLeafBloomCap: Double = 0.22
        public var revealAmberBloomCap: Double = 0.30
        public var waitingBudCoreCap: Double = 0.60
        public var primaryGlowCap: Double = 0.10

        public init() {}
    }
}

// MARK: - Motion

extension Theme {
    /// Sleepy motion. Nothing moves faster than `gentle` except press feedback; no spring overshoot.
    /// Use through `View.mapleAnimation(_:value:)` so Reduce Motion is respected.
    public struct Motion: Sendable {
        /// Press feedback, the only fast motion.
        public var press: Animation = .easeOut(duration: 0.2)
        /// Selection, numeric text, crossfades, Reduce Motion substitutes.
        public var gentle: Animation = .easeInOut(duration: 0.6)
        /// Sections appearing, sheet content.
        public var calm: Animation = .easeInOut(duration: 1.0)
        /// Sky and vitality interpolation.
        public var drift: Animation = .easeInOut(duration: 3.2)
        /// Bud opening and leaf unfurl.
        public var reveal: Animation = .timingCurve(0.2, 0, 0, 1, duration: 1.6)
        /// New rosettes and growth easing in on the tree.
        public var graft: Animation = .easeInOut(duration: 1.6)

        // Ambient loop periods, in seconds.
        public var swayPeriod: Double = 8
        public var swayPeriodNight: Double = 10
        public var breathePeriod: Double = 10
        public var budPulsePeriod: Double = 4
        public var loadingPulsePeriod: Double = 1.6

        public init() {}
    }
}

// MARK: - Typography

/// Type styles built on Dynamic Type text styles. SF Rounded for headings and numbers, SF Pro for reading,
/// New York italic for scientific names only. Sentence case everywhere; no tracked capitals.
public enum MapleFont {
    public static let screenTitle = Font.system(.title, design: .rounded, weight: .semibold)
    public static let leafTitle = Font.system(.title, design: .rounded, weight: .semibold)
    public static let sectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    public static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    public static let buttonLabel = Font.system(.headline, design: .rounded, weight: .semibold)
    public static let body = Font.system(.body)
    public static let contextEmphasis = Font.system(.subheadline, design: .rounded, weight: .semibold)
    public static let callout = Font.system(.subheadline)
    public static let footnote = Font.system(.footnote)
    public static let tileName = Font.system(.footnote, design: .rounded, weight: .semibold)
    public static let tileMeta = Font.system(.caption).monospacedDigit()
    /// Minimum size: chips and the "≈" mark only.
    public static let micro = Font.system(.caption2, design: .rounded, weight: .medium)

    /// New York italic, for scientific names and species notes.
    public static func scientific(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        Font.system(style, design: .serif, weight: weight).italic()
    }

    /// Large numerals. Pass a size from `@ScaledMetric` so they follow Dynamic Type.
    public static func numeral(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// Units next to a hero numeral ("h", "m"): half size, medium weight.
    public static func numeralUnit(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry public var theme: Theme = .maple
    /// The real-world season the UI is tinted for. Set once at the root.
    @Entry public var season: Season = .autumn
}

// MARK: - Helpers

extension Color {
    /// A catalogue colour (e.g. a leaf's fill) as a SwiftUI colour.
    public init(_ leafColor: LeafColor, opacity: Double = 1) {
        self.init(hex: leafColor.rgb, opacity: opacity)
    }

    /// Creates a colour from a 0xRRGGBB literal.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
