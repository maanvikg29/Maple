import MapleCore
import SwiftUI

/// The line on the ground under the tree (spec §3.2): "Young maple · 23 of 155 ›". The stage name in footnote
/// secondary, the count in 13pt SF Rounded semibold primary (rolling when it changes), " of 155" secondary and a
/// small chevron. A 44pt-tall button that opens the Herbarium.
public struct TreeCaption: View {
    @Environment(\.theme) private var theme

    private let stage: TreeStage
    private let leaves: Int
    private let total: Int
    private let action: () -> Void

    public init(stage: TreeStage, leaves: Int, total: Int = LeafCatalog.shared.species.count, action: @escaping () -> Void) {
        self.stage = stage
        self.leaves = leaves
        self.total = total
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // One line. At the largest text sizes, where the whole line no longer fits, the stage name gives way
            // (VoiceOver still says it) rather than being cut to "Young m…".
            ViewThatFits(in: .horizontal) {
                line(showsStage: true)
                line(showsStage: false)
            }
            .padding(.horizontal, theme.spacing.sm)
            .frame(minHeight: theme.spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(CaptionPressStyle())
        .mapleAnimation(theme.motion.gentle, value: leaves)
        .accessibilityLabel(HomeSpeech.caption(stage: stage, leaves: leaves, total: total))
        .accessibilityHint("Opens the herbarium.")
    }
}

extension TreeCaption {
    private func line(showsStage: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if showsStage {
                Text("\(stage.displayName) · ")
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Text(leaves, format: .number)
                .font(MapleFont.tileName.monospacedDigit())
                .foregroundStyle(theme.colors.textPrimary)
                .contentTransition(.numericText(value: Double(leaves)))
            Text(" of \(total)")
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.leading, 5)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct CaptionPressStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .mapleAnimation(theme.motion.press, value: configuration.isPressed)
    }
}
