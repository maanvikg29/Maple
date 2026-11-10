import MapleCore
import SwiftUI

extension Theme {
    /// The minute-marks dial's colours (F1 design §4.2), gold for the centre leaf and the finish (F1-18), and the
    /// bloom behind the dial. Views read `theme.dial`; `Theme.mapleIncreasedContrast` carries the table's Increase
    /// Contrast column.
    ///
    /// Gold (`#F0C24A`, about 43°) is not the reward amber (`#E8A35C`, about 30°). It appears only over counted
    /// time: this session's share of the centre leaf, the opened leaf and the finish. A session that counted
    /// nothing finishes in white.
    public struct Dial: Sendable {
        /// Start-screen preview marks: `textPrimary` at 42% (60% under Increase Contrast).
        public var plan: Color
        /// Time still to come: 16% (30%).
        public var ahead: Color
        /// Passed minutes: 88% (100%).
        public var lit: Color
        /// The current mark is the season tint at this opacity as its minute starts (55%, or 100% under Increase
        /// Contrast)…
        public var currentLow: Double
        /// …and at this one as it ends (100%).
        public var currentHigh: Double
        /// Break time left: `#C9D3E3` at 78% (100%).
        public var rest: Color
        /// Minutes that didn't count, on the receipt, drawn shorter: 9% (22%).
        public var gap: Color
        /// Press-and-hold progress: 100%.
        public var hold: Color
        /// Needs Screen Time: 10% (22%).
        public var off: Color
        /// The brighter gold: this session's counted time in the centre leaf, the opened leaf, and the finish.
        public var gold: Color
        /// The softer gold: the part of the leaf's rung saved before this session.
        public var goldSoft: Color
        /// The light edge at the leaf's fill line.
        public var goldEdge: Color
        /// The opened leaf's dark veins and outline.
        public var goldVein: Color
        /// The season-tint bloom's opacity at its centre.
        public var bloom: Double
        /// The bloom once the leaf has opened: gold at 18%, the tree bloom's cap (spec §6.5).
        public var goldBloom: Color
        /// The cooler bloom of the break and the emergency release.
        public var restBloom: Color

        /// The colour `state` draws in. The current mark is `tint` at its brightness through its minute
        /// (`DialFrame.currentBrightness`, 0.55…1); every other state is its token.
        public func colour(for state: MarkState, tint: Color, brightness: Double) -> Color {
            switch state {
            case .plan: plan
            case .ahead: ahead
            case .lit: lit
            case .current: tint.opacity(currentOpacity(brightness: brightness))
            case .rest: rest
            case .gap: gap
            case .hold: hold
            case .off: off
            }
        }

        /// The current mark's opacity: `currentLow` at brightness 0.55, rising to `currentHigh` at 1.
        public func currentOpacity(brightness: Double) -> Double {
            let value = brightness.isFinite ? brightness : 1
            let through = min(1, max(0, (value - 0.55) / 0.45))
            return currentLow + through * (currentHigh - currentLow)
        }
    }
}

extension Theme.Dial {
    public static let maple: Theme.Dial = {
        let text = Theme.Colors.maple.textPrimary
        return Theme.Dial(
            plan: text.opacity(0.42),
            ahead: text.opacity(0.16),
            lit: text.opacity(0.88),
            currentLow: 0.55,
            currentHigh: 1,
            rest: Color(hex: 0xC9D3E3, opacity: 0.78),
            gap: text.opacity(0.09),
            hold: text,
            off: text.opacity(0.10),
            gold: Color(hex: 0xF0C24A),
            goldSoft: Color(hex: 0xC99A2C, opacity: 0.62),
            goldEdge: Color(hex: 0xFFE8A8, opacity: 0.85),
            goldVein: Color(hex: 0x725811),
            bloom: 0.14,
            goldBloom: Color(hex: 0xF0C24A, opacity: 0.18),
            restBloom: Color(hex: 0xC9D3E3, opacity: 0.12)
        )
    }()

    /// Increase Contrast: §4.2's last column. Gold, its tones and the blooms are unchanged.
    public static let mapleIncreasedContrast: Theme.Dial = {
        let text = Theme.Colors.mapleIncreasedContrast.textPrimary
        var dial = Theme.Dial.maple
        dial.plan = text.opacity(0.60)
        dial.ahead = text.opacity(0.30)
        dial.lit = text
        dial.currentLow = 1
        dial.currentHigh = 1
        dial.rest = Color(hex: 0xC9D3E3)
        dial.gap = text.opacity(0.22)
        dial.hold = text
        dial.off = text.opacity(0.22)
        return dial
    }()
}
