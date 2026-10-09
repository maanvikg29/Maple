import SwiftUI
import MapleCore
import MapleDesign

@main
struct MapleApp: App {
    var body: some Scene {
        WindowGroup {
            ThemedRoot()
        }
    }
}

/// Picks the theme for the system contrast setting and the season for the member's hemisphere.
private struct ThemedRoot: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RootView()
            .environment(\.theme, contrast == .increased ? .mapleIncreasedContrast : .maple)
            .environment(\.season, Season(for: .now, hemisphere: .current))
            .preferredColorScheme(.dark)
    }
}
