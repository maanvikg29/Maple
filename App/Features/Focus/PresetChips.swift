import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The start screen's preset chips (F1 design §4.5, §5.1, §5.13, §5.17): one per preset, then "+" for a new preset
/// while there is room for one (at most 6). A chip sets the session to its preset and the preset's length.
///
/// - At default sizes the chips sit in one centred row, which scrolls sideways once it can't fit (more than 5
///   presets). At accessibility sizes they wrap with `ChipFlow`, and "+" reads "New preset".
/// - A chip shows its preset's name only, and the dial's numeral shows the length. VoiceOver reads "Study, 50 minutes".
/// - "+" opens the preset editor for a new preset (`FocusTabSheet.preset(nil)`). Holding a chip for half a second edits
///   its preset (`editsPresetOnHold`), as does VoiceOver's "Edit preset" action; a tap still only selects it. The lift
///   that ends a hold doesn't also select the chip (`ChipHoldGate`), so opening the editor leaves a turned dial, a
///   notice and the plain-timer offer as they were.
struct PresetChips: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(FocusTabState.self) private var tab
    @Environment(PresetStore.self) private var presets
    @State private var gate = ChipHoldGate()

    /// The preset the start screen shows.
    let selectedID: UUID?
    let select: (FocusPreset) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ChipFlow(spacing: theme.spacing.xs, lineSpacing: 0, alignment: .center) { chips }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.spacing.xs) { chips }
                    ScrollView(.horizontal) {
                        HStack(spacing: theme.spacing.xs) { chips }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        // Any lift has come by the time the editor closes, so a tap after it always selects.
        .onChange(of: tab.sheet == nil) { _, closed in
            if closed { gate.editorClosed() }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(presets.presets) { preset in
            Chip(preset.name, isSelected: preset.id == selectedID) {
                if gate.tap(preset.id) { select(preset) }
            }
            .accessibilityLabel(FocusStartLines.chipLabel(preset, locale: locale))
            .editsPresetOnHold { byHold in
                if byHold { gate.held(preset.id) }
                tab.sheet = .preset(preset.id)
            }
        }
        if presets.canAdd {
            Chip(FocusStartLines.addChipTitle(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize), isSelected: false) {
                tab.sheet = .preset(nil)
            }
            .frame(minWidth: theme.spacing.minimumHitTarget)
            .accessibilityLabel(FocusCopy.newPreset)
        }
    }
}
