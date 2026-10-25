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
/// - "+" opens the preset editor for a new preset (`FocusTabSheet.preset(nil)`). Holding a chip edits its preset: Task
///   15 adds `.editsPresetOnHold { tab.sheet = .preset(preset.id) }` after each preset's `Chip`.
struct PresetChips: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(FocusTabState.self) private var tab
    @Environment(PresetStore.self) private var presets

    /// The preset the start screen shows.
    let selectedID: UUID?
    let select: (FocusPreset) -> Void

    var body: some View {
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

    @ViewBuilder
    private var chips: some View {
        ForEach(presets.presets) { preset in
            Chip(preset.name, isSelected: preset.id == selectedID) { select(preset) }
                .accessibilityLabel(FocusStartLines.chipLabel(preset, locale: locale))
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
