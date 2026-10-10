import MapleCore
import SwiftUI

/// A filter choice in the Filter sheet (spec §5.4): a 32pt capsule with a 13pt SF Rounded semibold label, and for
/// autumn colours a 10pt dot before the name. Colours are always named, so crimson and scarlet never depend on
/// colour alone (spec §9).
///
/// The sheet sits on `surface2`, where `Chip`'s selected thumb (also `surface2`) would vanish, so a chosen filter
/// is lit instead: a white 14% fill with the top-lit hairline and the label in `textPrimary`. Each tap plays the
/// `.selection` haptic.
///
/// ```swift
/// FilterChip("Europe", isSelected: filters.regions.contains(.europe)) { toggle(.europe) }
/// FilterChip(LeafSpecies.AutumnColor.scarlet.displayName, dot: .scarlet, isSelected: …) { … }
/// ```
public struct FilterChip: View {
    @Environment(\.theme) private var theme
    @State private var taps = 0

    private let title: String
    private let dot: LeafColor?
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, dot: LeafColor? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.dot = dot
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: 6) {
                if let dot {
                    Circle()
                        .fill(Color(dot))
                        .frame(width: 10, height: 10)
                }
                Text(title)
                    .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
            }
            .font(MapleFont.tileName)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(FilterChipStyle(isSelected: isSelected, hasDot: dot != nil))
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FilterChipStyle: ButtonStyle {
    let isSelected: Bool
    let hasDot: Bool

    func makeBody(configuration: Configuration) -> some View {
        FilterChipBody(configuration: configuration, isSelected: isSelected, hasDot: hasDot)
    }
}

private struct FilterChipBody: View {
    @Environment(\.theme) private var theme
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let hasDot: Bool

    var body: some View {
        let capsule = Capsule(style: .continuous)
        configuration.label
            .padding(.leading, hasDot ? 12 : 14)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background {
                if isSelected {
                    capsule.fill(.white.opacity(0.14))
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
