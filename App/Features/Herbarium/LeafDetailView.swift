import SwiftUI
import MapleDesign

/// Stub entry point so other features can present this screen; replaced by its owner (spec §5.6).
struct LeafDetailView: View {
    @Environment(\.theme) private var theme
    let speciesID: String

    var body: some View {
        Text("Leaf")
            .font(MapleFont.screenTitle)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
    }
}
