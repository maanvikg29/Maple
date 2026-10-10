import SwiftUI
import MapleDesign

/// Stub entry point so other features can present this screen; replaced by its owner (spec §5.8).
struct RevealFlow: View {
    @Environment(\.theme) private var theme
    /// Open this waiting leaf first; nil opens the queue in unlock order.
    var startingWith: String? = nil

    var body: some View {
        Text("Reveal")
            .font(MapleFont.screenTitle)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
    }
}
