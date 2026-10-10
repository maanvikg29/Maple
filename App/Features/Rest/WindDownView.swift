import SwiftUI
import MapleDesign

/// Stub entry point so other features can present this screen; replaced by its owner (spec §8.1).
struct WindDownView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Wind-down")
            .font(MapleFont.screenTitle)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
    }
}
