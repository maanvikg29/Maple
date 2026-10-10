import MapleCore
import SwiftUI

/// Home's one number and its one line (spec §3.2): the hero numeral ("1h 20m", "07:00") and a caption of seven
/// words or fewer 4pt below ("until wind-down · bed 23:00"). Centred; one VoiceOver element that reads the pair
/// with full units ("1 hour, 20 minutes until wind-down. Bed at 23:00.").
///
/// ```swift
/// let state = collection.nowState(at: now)
/// NowBlock(numeral: state.numeral.parts, caption: state.caption, spoken: state.spoken)
/// ```
public struct NowBlock: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let numeral: [NumeralPart]
    private let caption: String
    private let spoken: String

    public init(numeral: [NumeralPart], caption: String, spoken: String) {
        self.numeral = numeral
        self.caption = caption
        self.spoken = spoken
    }

    public var body: some View {
        VStack(spacing: HomeLayout.captionGap) {
            StatNumber(numeral.map { $0.isUnit ? .unit($0.text) : .value($0.text) }, size: .hero)
            Text(caption)
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                // One line; at accessibility sizes it wraps (spec §9) rather than truncate: the longest caption
                // ("wind-down tonight · bed 11:00 PM") needs three lines at the largest size.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.9)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .mapleAnimation(theme.motion.gentle, value: caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
