import MapleCore
import SwiftUI

/// A filter chip: a 32pt capsule with a 13pt SF Rounded semibold label (spec §7.3). Unselected chips sit on
/// `chipFill`; the selected one on `surface2` with a white top hairline. Each tap plays the `.selection` haptic.
///
/// ```swift
/// Chip("Earned", count: 23, isSelected: filter == .earned) { filter = .earned }
/// ```
public struct Chip: View {
    @Environment(\.theme) private var theme
    @State private var taps = 0

    private let title: String
    private let count: Int?
    private let isSelected: Bool
    private let action: () -> Void

    /// - Parameter count: Shown after the title in the secondary colour ("Earned 23").
    public init(_ title: String, count: Int? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                if let count {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .font(MapleFont.tileName)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(ChipStyle(isSelected: isSelected))
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct ChipBody: View {
    @Environment(\.theme) private var theme
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    var body: some View {
        let capsule = Capsule(style: .continuous)
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background {
                if isSelected {
                    capsule.fill(theme.colors.surface2)
                        .overlay { capsule.strokeBorder(theme.topLitHairline(theme.selectedHairline), lineWidth: 1) }
                } else {
                    capsule.fill(theme.colors.chipFill)
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .mapleAnimation(theme.motion.press, value: configuration.isPressed)
            .mapleAnimation(theme.motion.gentle, value: isSelected)
    }
}

/// A small label chip: tier, approximate drawing, region (spec §7.3). A 22pt capsule with 11pt SF Rounded
/// medium text on `chipSmallFill`; the approximate style has no fill and a dashed white 30% edge.
///
/// ```swift
/// SmallChip(tier: .common)
/// if let chip = SmallChip(approximate: species.confidence) { chip }   // "≈ Approximate drawing" / "≈ Uncharted"
/// ```
public struct SmallChip: View {
    nonisolated public enum Style: Sendable, Hashable {
        case filled
        /// No fill, 1pt dashed border at white 30%, dash (3, 2). For approximate drawings only.
        case approximate
    }

    @Environment(\.theme) private var theme
    private let title: String
    private let style: Style
    private let spokenLabel: String?

    /// - Parameter accessibilityLabel: What VoiceOver says instead of `title`.
    public init(_ title: String, style: Style = .filled, accessibilityLabel: String? = nil) {
        self.title = title
        self.style = style
        self.spokenLabel = accessibilityLabel
    }

    /// The neutral tier chip ("Common"). Tiers are never coloured or ranked against other people.
    public init(tier: RewardTier) {
        self.init(tier.displayName, accessibilityLabel: "\(tier.displayName) tier")
    }

    /// "≈ Approximate drawing" or "≈ Uncharted" for an approximate drawing; nil for a documented one.
    public init?(approximate confidence: LeafSpecies.Confidence) {
        guard let title = confidence.approximateChipTitle else { return nil }
        self.init(title, style: .approximate, accessibilityLabel: confidence.approximateSpokenLabel)
    }

    public var body: some View {
        let capsule = Capsule(style: .continuous)
        Text(title)
            .font(MapleFont.micro)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(1)
            // Squeezed (only ever by a very large text size) it shrinks a little before it truncates.
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minHeight: 22)
            .background {
                switch style {
                case .filled:
                    capsule.fill(theme.colors.chipSmallFill)
                case .approximate:
                    capsule.strokeBorder(
                        approximateBorder,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel ?? title)
    }

    /// White 30%, raised with the other borders under Increase Contrast (`borderHighlight` 22% → 40%).
    private var approximateBorder: Color {
        .white.opacity(max(0.30, theme.colors.borderHighlight.opacityValue + 0.05))
    }
}

extension LeafSpecies.Confidence {
    /// The chip on detail, the reveal and share cards (spec §5.2); nil for a documented drawing.
    nonisolated public var approximateChipTitle: String? {
        switch self {
        case .documented: nil
        case .inferred: "≈ Approximate drawing"
        case .placeholder: "≈ Uncharted"
        }
    }

    /// What VoiceOver says for an approximate drawing (spec §5.2); nil for a documented one.
    nonisolated public var approximateSpokenLabel: String? {
        switch self {
        case .documented: nil
        case .inferred: "Approximate drawing."
        case .placeholder: "Uncharted, placeholder drawing."
        }
    }

    /// The Accuracy row in leaf detail (spec §5.2); nil for a documented drawing.
    nonisolated public var accuracyNote: String? {
        switch self {
        case .documented: nil
        case .inferred: "Approximate. Drawn from the typical leaf of its series; this species is little studied."
        case .placeholder: "Uncharted. Only its native range is confirmed; this drawing is a placeholder."
        }
    }
}

/// Lays chips out in rows that wrap, like words: the tier and approximate chips under a leaf's name, region
/// chips in the specimen label, filter chips at large text sizes. A chip wider than a whole row gets the row.
///
/// ```swift
/// ChipFlow(alignment: .center) {
///     SmallChip(tier: progress.tier)
///     if let chip = SmallChip(approximate: species.confidence) { chip }
/// }
/// ```
public struct ChipFlow: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat
    public var alignment: HorizontalAlignment

    /// - Parameters:
    ///   - spacing: Between chips in a row (8, as in leaf detail).
    ///   - lineSpacing: Between rows.
    ///   - alignment: `.leading` or `.center`; each row is aligned on its own.
    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8, alignment: HorizontalAlignment = .leading) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.alignment = alignment
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = ChipFlowRows(sizes: sizes, maxWidth: proposal.width ?? .infinity, spacing: spacing, lineSpacing: lineSpacing)
        return rows.size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = ChipFlowRows(sizes: sizes, maxWidth: bounds.width, spacing: spacing, lineSpacing: lineSpacing)
        for row in rows.rows {
            let slack = bounds.width - row.width
            let inset: CGFloat = switch alignment {
            case .center: slack / 2
            case .trailing: slack
            default: 0
            }
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + inset + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }
}

/// Row breaking for `ChipFlow`, kept pure for testing.
nonisolated struct ChipFlowRows {
    struct Item {
        var index: Int
        var x: CGFloat
        var size: CGSize
    }

    struct Row {
        var items: [Item] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private(set) var rows: [Row] = []

    init(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat, lineSpacing: CGFloat) {
        var row = Row()
        var y: CGFloat = 0
        for (index, ideal) in sizes.enumerated() {
            // A chip wider than the row gets the row.
            let size = CGSize(width: min(ideal.width, maxWidth), height: ideal.height)
            let x = row.items.isEmpty ? 0 : row.width + spacing
            if !row.items.isEmpty, x + size.width > maxWidth {
                rows.append(row)
                y += row.height + lineSpacing
                row = Row(y: y)
                row.items.append(Item(index: index, x: 0, size: size))
                row.width = size.width
                row.height = size.height
            } else {
                row.items.append(Item(index: index, x: x, size: size))
                row.width = x + size.width
                row.height = max(row.height, size.height)
            }
        }
        if !row.items.isEmpty { rows.append(row) }
    }

    var size: CGSize {
        CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
}
