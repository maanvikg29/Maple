import SwiftUI
import MapleCore

// Every visual decision in Maple lives in this file. Views read the current `Theme` from the
// environment (`@Environment(\.theme)`) so a future theme only has to supply a different value.

public struct Theme: Sendable {
    public var colors: Colors
    public var spacing: Spacing
    public var radius: Radius
    public var glow: Glow
    public var motion: Motion

    public init(colors: Colors, spacing: Spacing, radius: Radius, glow: Glow, motion: Motion) {
        self.colors = colors
        self.spacing = spacing
        self.radius = radius
        self.glow = glow
        self.motion = motion
    }

    /// The default theme: dark, calm, low saturation. Amber is reserved for leaves and rewards.
    public static let maple = Theme(
        colors: .maple,
        spacing: Spacing(),
        radius: Radius(),
        glow: Glow(),
        motion: Motion()
    )
}

// MARK: - Colours

extension Theme {
    public struct Colors: Sendable {
        /// Near-black app background.
        public var background: Color
        /// Deep navy, used for the lower half of the background gradient and grouped areas.
        public var backgroundRaised: Color
        /// Navy surface for cards and controls.
        public var surface: Color
        /// Slightly lighter surface for pressed or nested elements.
        public var surfaceRaised: Color
        public var textPrimary: Color
        public var textSecondary: Color
        /// Thin card and button borders: white fading into soft blue.
        public var borderHighlight: Color
        public var borderSoft: Color
        /// The faint outer glow around cards and key buttons.
        public var glow: Color
        /// Maple amber. Leaves and rewards only.
        public var reward: Color
        public var leaves: LeafPalette
    }

    public struct LeafPalette: Sendable {
        public var spring: Color
        public var summer: Color
        public var autumnGold: Color
        public var autumnCrimson: Color
        public var winterFrost: Color

        /// The everyday leaf colour for a season.
        public func color(for season: Season) -> Color {
            switch season {
            case .spring: spring
            case .summer: summer
            case .autumn: autumnGold
            case .winter: winterFrost
            }
        }
    }
}

extension Theme.Colors {
    public static let maple = Theme.Colors(
        background: Color(hex: 0x05070D),
        backgroundRaised: Color(hex: 0x0B1426),
        surface: Color(hex: 0x111D35),
        surfaceRaised: Color(hex: 0x18264A),
        textPrimary: Color(hex: 0xF2F5FA),
        textSecondary: Color(hex: 0x8A96AD),
        borderHighlight: Color(hex: 0xF2F5FA, opacity: 0.22),
        borderSoft: Color(hex: 0x9DB4E6, opacity: 0.10),
        glow: Color(hex: 0x7F9FE0, opacity: 0.16),
        reward: Color(hex: 0xE8A35C),
        leaves: Theme.LeafPalette(
            spring: Color(hex: 0x9CBF86),
            summer: Color(hex: 0x6E9A6B),
            autumnGold: Color(hex: 0xE8A35C),
            autumnCrimson: Color(hex: 0xB65A4E),
            winterFrost: Color(hex: 0xC9DCE8)
        )
    )
}

// MARK: - Layout

extension Theme {
    /// A 4-point spacing scale. Generous by default: calm screens breathe.
    public struct Spacing: Sendable {
        public var xxs: CGFloat = 4
        public var xs: CGFloat = 8
        public var sm: CGFloat = 12
        public var md: CGFloat = 16
        public var lg: CGFloat = 24
        public var xl: CGFloat = 32
        public var xxl: CGFloat = 48
        /// Horizontal margin for screen content.
        public var screen: CGFloat = 20
    }

    public struct Radius: Sendable {
        public var card: CGFloat = 24
        public var control: CGFloat = 16
        public var chip: CGFloat = 12
    }

    /// Low-opacity blur around bordered elements. Subtle, never neon.
    public struct Glow: Sendable {
        public var radius: CGFloat = 18
        public var y: CGFloat = 0
        public var borderWidth: CGFloat = 1
    }
}

// MARK: - Motion

extension Theme {
    /// Slow, sleepy easing. Use through `View.mapleAnimation(_:value:)` so Reduce Motion is respected.
    public struct Motion: Sendable {
        /// Small state changes: selection, toggles.
        public var gentle: Animation = .easeInOut(duration: 0.6)
        /// Screen-level changes: cards appearing, reveals.
        public var calm: Animation = .easeInOut(duration: 1.0)
        /// Ambient loops: breathing glows, the tree's sway.
        public var drift: Animation = .easeInOut(duration: 3.2)
    }
}

// MARK: - Typography

/// Type styles built on Dynamic Type text styles so they scale with the user's settings.
/// SF Rounded is used for headings and numbers; SF Pro for reading text.
public enum MapleFont {
    public static let display = Font.system(.largeTitle, design: .rounded, weight: .semibold)
    public static let title = Font.system(.title2, design: .rounded, weight: .semibold)
    public static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    public static let body = Font.system(.body)
    public static let callout = Font.system(.callout)
    public static let caption = Font.system(.footnote)
    public static let overline = Font.system(.caption, design: .rounded, weight: .semibold)

    /// Large numbers (sleep duration, scores). Scales with Dynamic Type relative to `.largeTitle`.
    public static func stat(size: CGFloat = 52) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry public var theme: Theme = .maple
}

// MARK: - Helpers

extension Color {
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
