import SwiftUI

/// A large, readable number, optionally with units at half size ("1h 20m").
/// Grows with Dynamic Type (capped), rolls when it changes, and reads as one element in VoiceOver.
public struct StatNumber: View {
    public enum Size: Sendable {
        /// Home's one hero numeral (64pt, max 88).
        case hero
        /// The wellbeing score (48pt, max 72).
        case score
        /// Totals such as the herbarium count (34pt).
        case stat
        /// The Profile sheet's totals row (28pt).
        case total
        /// Inline numbers in rows (17pt).
        case inline
    }

    /// A piece of the number: digits in the numeral style, units smaller and secondary.
    public struct Part: Sendable, Hashable {
        public let text: String
        public let isUnit: Bool

        public static func value(_ text: String) -> Part { Part(text: text, isUnit: false) }
        public static func unit(_ text: String) -> Part { Part(text: text, isUnit: true) }
    }

    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 48
    @ScaledMetric(relativeTo: .title) private var statSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var totalSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var inlineSize: CGFloat = 17

    private let parts: [Part]
    private let size: Size
    private let accessibilityText: String?

    /// - Parameter accessibilityText: Full spoken form, e.g. "One hour twenty minutes".
    public init(_ parts: [Part], size: Size = .hero, accessibilityText: String? = nil) {
        self.parts = parts
        self.size = size
        self.accessibilityText = accessibilityText
    }

    public init(_ value: String, size: Size = .hero, accessibilityText: String? = nil) {
        self.init([.value(value)], size: size, accessibilityText: accessibilityText)
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part.text)
                    .font(part.isUnit ? MapleFont.numeralUnit(size: numeralSize / 2) : MapleFont.numeral(size: numeralSize))
                    .tracking(part.isUnit || size != .hero ? 0 : -1.5)
                    .foregroundStyle(part.isUnit ? theme.colors.textSecondary : theme.colors.textPrimary)
                    .contentTransition(.numericText())
                    // A word space between a unit and the next value: "1h 20m".
                    .padding(.leading, Self.startsNewGroup(parts, at: index) ? numeralSize * 0.14 : 0)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .mapleAnimation(theme.motion.gentle, value: parts)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? parts.map(\.text).joined())
    }

    private var numeralSize: CGFloat {
        switch size {
        case .hero: min(heroSize, 88)
        case .score: min(scoreSize, 72)
        case .stat: statSize
        case .total: totalSize
        case .inline: inlineSize
        }
    }

    /// Whether the part at `index` is a value that follows a unit, and so needs a word space before it.
    nonisolated static func startsNewGroup(_ parts: [Part], at index: Int) -> Bool {
        index > 0 && parts.indices.contains(index) && !parts[index].isUnit && parts[index - 1].isUnit
    }
}
