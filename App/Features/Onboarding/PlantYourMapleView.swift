import SwiftUI
import MapleDesign

/// Stub entry point so other features can present this screen; replaced by its owner (spec §8.8).
struct PlantYourMapleView: View {
    @Environment(\.theme) private var theme
    /// Called after "Place on your maple"; the app then shows Home.
    var onFinish: () -> Void

    var body: some View {
        Text("Your maple")
            .font(MapleFont.screenTitle)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
    }
}
