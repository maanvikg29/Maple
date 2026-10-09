import SwiftUI

/// A large, readable number with a small label, e.g. "7h 42m · Last night".
/// Grows with Dynamic Type and reads as one element in VoiceOver.
public struct StatNumber: View {
    public enum Size: Sendable {
        /// One number that leads a card.
        case hero
        /// Numbers shown side by side.
        case compact
    }

    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 52
    @ScaledMetric(relativeTo: .title) private var compactSize: CGFloat = 34

    private let value: String
    private let unit: String?
    private let label: String
    private let size: Size

    public init(_ value: String, unit: String? = nil, label: String, size: Size = .hero) {
        self.value = value
        self.unit = unit
        self.label = label
        self.size = size
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xxs) {
                Text(value)
                    .font(MapleFont.stat(size: size == .hero ? heroSize : compactSize))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(MapleFont.headline)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Text(label)
                .font(MapleFont.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
