import SwiftUI

/// A capsule segmented control: the colourway switch in leaf detail, Sleep / Focus in Rest (spec §7.3).
///
/// The track is white 6%; the selected segment sits on a `surface2` thumb with a top-lit hairline that slides
/// over `gentle` (instantly under Reduce Motion). Segments share one width, that of the widest label.
/// Changing the selection plays the `.selection` haptic.
///
/// ```swift
/// SegmentedCapsule(selection: $colourway, options: [.pressed, .summer, .autumn]) { $0.title }
/// SegmentedCapsule(selection: $mode, options: RestMode.allCases, size: .regular, fillsWidth: true) { $0.title }
/// ```
public struct SegmentedCapsule<Value: Hashable>: View {
    nonisolated public enum Size: Sendable, Hashable {
        /// 32pt with 13pt labels (leaf detail).
        case compact
        /// 36pt with 15pt labels (Rest's mode switch).
        case regular

        var height: CGFloat {
            switch self {
            case .compact: 32
            case .regular: 36
            }
        }

        @MainActor var font: Font {
            switch self {
            case .compact: MapleFont.tileName
            case .regular: MapleFont.contextEmphasis
            }
        }
    }

    @Environment(\.theme) private var theme
    @Binding private var selection: Value
    private let options: [Value]
    private let size: Size
    private let fillsWidth: Bool
    private let title: (Value) -> String

    /// - Parameters:
    ///   - fillsWidth: Stretch to the offered width instead of hugging the labels.
    ///   - title: The label for each option, in sentence case.
    public init(
        selection: Binding<Value>, options: [Value], size: Size = .compact, fillsWidth: Bool = false,
        title: @escaping (Value) -> String
    ) {
        self._selection = selection
        self.options = options
        self.size = size
        self.fillsWidth = fillsWidth
        self.title = title
    }

    public var body: some View {
        let selectedIndex = options.firstIndex(of: selection) ?? 0
        EqualWidthRow(fillsWidth: fillsWidth) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(SegmentedCapsuleMetrics.inset)
        .frame(minHeight: size.height)
        .background {
            Capsule(style: .continuous).fill(theme.colors.chipSmallFill)
        }
        .background {
            GeometryReader { proxy in
                let width = SegmentedCapsuleMetrics.thumbWidth(total: proxy.size.width, count: options.count)
                let capsule = Capsule(style: .continuous)
                capsule.fill(theme.colors.surface2)
                    .overlay { capsule.strokeBorder(theme.topLitHairline(theme.selectedHairline), lineWidth: 1) }
                    .frame(width: width, height: max(0, proxy.size.height - 2 * SegmentedCapsuleMetrics.inset))
                    .offset(
                        x: SegmentedCapsuleMetrics.thumbOffset(index: selectedIndex, thumbWidth: width),
                        y: SegmentedCapsuleMetrics.inset
                    )
            }
            .mapleAnimation(theme.motion.gentle, value: selectedIndex)
        }
        // The visual control is 32–36pt; keep a 44pt hit area.
        .padding(.vertical, (theme.spacing.minimumHitTarget - size.height) / 2)
        .contentShape(Rectangle())
        .sensoryFeedback(.selection, trigger: selection)
        // Like the system segmented control: labels grow up to AX1, then the Large Content Viewer takes over.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(title(option))
                .font(size.font)
                .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .mapleAnimation(theme.motion.gentle, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Thumb geometry for `SegmentedCapsule`, kept pure for testing.
nonisolated enum SegmentedCapsuleMetrics {
    /// The gap between the track's edge and the thumb.
    static let inset: CGFloat = 2

    static func thumbWidth(total: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(0, (total - 2 * inset) / CGFloat(count))
    }

    static func thumbOffset(index: Int, thumbWidth: CGFloat) -> CGFloat {
        inset + CGFloat(max(0, index)) * thumbWidth
    }
}

/// Lays children out in a row of equal widths: the widest child's ideal width, or the offered width shared
/// equally when `fillsWidth` is set (or when the ideal row would not fit).
private struct EqualWidthRow: Layout {
    var fillsWidth: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let ideal = idealCellWidth(subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let idealWidth = ideal * CGFloat(subviews.count)
        guard let offered = proposal.width, offered.isFinite else {
            return CGSize(width: idealWidth, height: height)
        }
        return CGSize(width: fillsWidth ? offered : min(idealWidth, offered), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * width, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }

    private func idealCellWidth(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
}
