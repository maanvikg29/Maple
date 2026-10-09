import SwiftUI
import MapleDesign

/// Scaffold: replaced by the Rest tab from docs/design/spec.md §8.1.
struct RestView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Rest")
            .font(MapleFont.screenTitle)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
