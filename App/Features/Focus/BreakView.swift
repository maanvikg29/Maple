import SwiftUI
import MapleCore
import MapleDesign

/// The break (F1 design §5.5): "Break · apps stay locked" over the session's title; the dial switched to the break,
/// one rest mark per 10 seconds going out one by one under the cool bloom, with "4m" over "left of your break"; one
/// thing to do away from the phone; "The break counts. Back to studying at 14:28."; "Back to studying"; and the
/// session's own way out. `RunningSessionView` draws it once a second while the break runs. Apps stay locked and the
/// break counts (O5). The break doesn't dim: it is short, and the member is away from the phone.
struct BreakView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: BreakScreenModel
    /// "Back to studying" is on its way to the store: a second tap does nothing.
    let isEndingBreak: Bool
    let onMinimise: () -> Void
    let onBackToStudying: () -> Void
    let onEndPath: () -> Void
    /// Where Magic Tap moves VoiceOver: the first control (§4.9).
    let controlsFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        SessionScreen(title: FocusCopy.BreakTime.header, subtitle: model.subtitle, onMinimise: onMinimise) { diameter in
            MinuteDial(
                frame: .breakTime(BreakDialLayout(breakSeconds: model.breakSeconds), left: model.secondsLeft),
                diameter: diameter, theme: theme
            ) {
                DialCentre(leaf: nil, numeral: DialCentre.numeralParts(model.remaining), caption: FocusCopy.BreakTime.caption,
                           diameter: diameter)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(model.spoken))
        } lines: {
            if dynamicTypeSize.isAccessibilitySize {
                // The dial's centre stops growing at xxLarge, so the time is repeated where it can grow (§5.17).
                Text(model.timeLine)
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityHidden(true)
            }
            Text(model.suggestion)
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textPrimary)
                .contentTransition(.opacity)
                .mapleAnimation(theme.motion.gentle, value: model.suggestion)
            Text(model.backLine)
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
        } controls: {
            Button(FocusCopy.BreakTime.backToStudying, action: onBackToStudying)
                .buttonStyle(.glassCapsule)
                .disabled(isEndingBreak)
                .accessibilityFocused(controlsFocused)
            TextLink(model.endPath.title, chevron: false, action: onEndPath)
        }
    }
}
