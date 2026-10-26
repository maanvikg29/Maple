import SwiftUI
import MapleCore
import MapleDesign

/// The Focus tab's sheets (`FocusTabState.sheet`, F1 design §5.9, §5.13–§5.16), shown by `FocusView`. Each sheet sets
/// its own detents and `surface2` background (spec §2.3). Task 15 builds the Blocking sheet, the preset editor and
/// intention entry; until then they are placeholders.
struct FocusTabSheetContent: View {
    @Environment(\.theme) private var theme
    let sheet: FocusTabSheet

    var body: some View {
        switch sheet {
        case .saved:
            SavedTodaySheet()
        case .streak:
            StreakSheet()
        case .blocking, .preset, .intention:
            FocusPlaceholder(sheet.title)
                .presentationDetents([.medium])
                .presentationBackground(theme.colors.surface2)
        }
    }
}
