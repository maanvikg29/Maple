import SwiftUI
import MapleDesign

struct SleepView: View {
    var body: some View {
        FeatureScreen(title: "Sleep") {
            PlaceholderCard(
                symbol: "bed.double",
                title: "Sleep schedule",
                message: "Your bedtime, wake-up and wind-down, for weekdays and weekends.",
                milestone: "M1"
            )
            PlaceholderCard(
                symbol: "waveform",
                title: "Sleep sounds",
                message: "Rain, ocean, white, pink and brown noise. Mix your own blend with a fade-out timer.",
                milestone: "M2"
            )
            PlaceholderCard(
                symbol: "hand.raised",
                title: "Bedtime blocking",
                message: "Quietly blocks the apps you choose from wind-down until morning.",
                milestone: "M3"
            )
        }
    }
}

#Preview {
    NavigationStack { SleepView() }
        .preferredColorScheme(.dark)
}
