import SwiftUI
import MapleDesign

/// Scaffold: replaced by the Home screen from docs/design/spec.md §3.
struct HomeView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Home")
            .font(MapleFont.screenTitle)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
