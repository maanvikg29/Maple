import SwiftUI
import MapleCore
import MapleDesign

/// The leaf line's words, and whether they say a leaf has opened (and so carry the bud).
nonisolated struct LeafLineWords: Equatable, Sendable {
    let line: RunningSessionModel.Line
    let opened: Bool
}

/// The leaf line (§4.3, §5.4, §5.8): "Field maple" in the primary colour, "· 17m to go" in the secondary; once a leaf
/// has opened, "Field maple is yours · it opens after this session" after the amber bud, which marks an earned leaf.
/// The running session and the receipt draw it alike, so the line doesn't change look as the receipt takes over.
struct LeafLineRow: View {
    @Environment(\.theme) private var theme
    /// The bud keeps to the line's text size.
    @ScaledMetric(relativeTo: .subheadline) private var budSide: CGFloat = 18

    let words: LeafLineWords

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
            if words.opened {
                BudGlyph(waiting: true, glow: .still)
                    .frame(width: budSide, height: budSide)
                    // Beside the first line, its base a little below the text's baseline, when the line wraps.
                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.78 }
            }
            Text(text)
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textPrimary)
        }
    }

    private var text: AttributedString {
        var text = AttributedString(words.line.lead)
        if let trail = words.line.trail {
            var rest = AttributedString(" \(trail)")
            rest.foregroundColor = theme.colors.textSecondary
            text.append(rest)
        }
        return text
    }
}
