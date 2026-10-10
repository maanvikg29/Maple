import SwiftUI
import MapleDesign

/// Stub entry point so other features can present this screen; replaced by its owner (spec §8.3).
struct ProfileView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Profile")
            .font(MapleFont.screenTitle)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
    }
}
